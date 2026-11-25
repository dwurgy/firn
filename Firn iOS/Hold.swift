import FirnCore
import SwiftUI

/// What a pull on the bar (and every glide of the page's picture) moves
/// (2i step 4, `docs/IOS-PLAN.md`). `BrowserScreen` owns one and sets
/// these through its own properties of the same names, which skip a value
/// that hasn't changed; only the small views below read them, so a finger
/// moving runs the picture, the held page, and the bar's fade, not the
/// whole screen with its bar and sheets (the SwiftUI template on David's
/// iPhone, 2026-11-14: a held pull ran `BrowserScreen` and everything in it
/// every frame, 263 of its 347 runs set off by the pull's drag).
@MainActor @Observable
final class Hold {
    /// A pull under way: where the finger came down, and the page's picture
    /// being taken for it.
    struct Pull {
        let id = UUID()
        let tab: FirnCore.Tab
        let start: CGPoint
        let picture: Task<UIImage?, Never>?
        var translation: CGSize = .zero
        /// Started sideways: the page slides at full size between tabs,
        /// and never shrinks.
        var sideways = false
    }

    /// A tab beside the one held: -1 just before it in the list (on the
    /// left), 1 just after it.
    struct Neighbor: Identifiable {
        let id: UUID
        let tab: FirnCore.Tab
        var image: UIImage?
        var place: Int
        /// The strip under the clock while it's beside: its picture's top
        /// edge, else the page's own color (none while asleep or loading,
        /// when it's still black).
        var top: CGColor?
        /// Where it's drawn while set, rather than by its place: where it
        /// was as another tab was picked, so it glides on from there.
        var pinned: CGRect? = nil
    }

    // Each is described where `BrowserScreen` passes it through.
    var standIn: UIImage?
    var livePull = false
    var standInTop: CGColor?
    var stripOpacity: Double = 1
    var standInFade: Double = 1
    var standInTab: FirnCore.Tab?
    var box: CGRect = .zero
    var boxRadius: CGFloat = 0
    /// How much of the strip under the clock rides on top of the flying
    /// page, 1 on the page and 0 in its card: the page is the whole screen
    /// from a close's first frame to an open's last, as Safari's.
    var band: CGFloat = 0
    /// Into a tile the strip fades early, before the tile forms.
    var bandFade: Double = 1
    var boxSkip: CGFloat = 0
    /// A let-go's flight into its card, and how far through its time it is
    /// (0 to 1, at an even pace): while set, the page's picture and its
    /// strip are placed by the flight, not by `box`.
    var flight: Flight?
    var flightTime: CGFloat = 0
    var tileCrop: (from: CGRect, to: CGSize)?
    var pull: Pull?
    var neighbors: [Neighbor] = []
    var neighborsOpacity: Double = 1
    var neighborsIn: CGFloat = 1
    var neighborsPeek = false
    /// This pull has been past the point where the grid comes in behind
    /// the page: the tabs beside it have left and don't come back.
    @ObservationIgnored var neighborsLeft = false
    var heldShift: CGFloat = 0
    var swiping = false
    var newTabReach: CGFloat = 0
    var newTabShift: CGFloat = 0
    var newTabGive: CGFloat = 0
    /// The page's own frame on screen, to aim the glide from.
    var pageFrame: CGRect = .zero
    /// Moves a page pulled up toward the finger's place (`Follower`).
    @ObservationIgnored let follower = Follower()
    /// Runs a let-go's flight (`FlightClock`).
    @ObservationIgnored let flightClock = FlightClock()

    /// The screen's own corners, for the flying page. iOS has no public
    /// way to ask, so: iPhones with a home bar about 55pt (47 to 62 across
    /// models), iPads 18pt, a square screen none. Only the first and last
    /// frames sit on the real corners, which hide a small mismatch.
    static func screenRadius(topInset: CGFloat) -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad { return 18 }
        return topInset > 24 ? 55 : 0
    }

    /// How much of a peeking tab shows at the screen's edge.
    static let peek: CGFloat = 20
    /// The least room between a peeking tab and the held page.
    static let peekBuffer: CGFloat = 24

    /// What a pull moves: the picture once it's here, the live page below
    /// the status bar until then (the same size: the picture leaves the
    /// strip out too).
    func pulledSize(topInset: CGFloat) -> CGSize? {
        if let size = standIn?.size { return size }
        guard livePull, pageFrame.width > 0 else { return nil }
        return CGSize(width: pageFrame.width, height: max(pageFrame.height - topInset, 1))
    }

    /// The gap between the held page and the ones beside it: a little
    /// narrower as they shrink.
    func gap(_ box: CGRect) -> CGFloat {
        // Nearly touching at full size, as Safari's pages slide.
        10 + 6 * box.width / max(pageFrame.width, 1)
    }

    /// How far the held page goes sideways with the finger. Swiped toward
    /// a side with no tab, it gives a little and comes back.
    func sidewaysShift(_ pull: Pull) -> CGFloat {
        var dx = pull.translation.width
        if pull.sideways, !neighbors.contains(where: { $0.place == (dx > 0 ? -1 : 1) }) { dx *= 0.3 }
        return dx
    }

    /// Where a tab beside the held one sits: the held box, moved over.
    func neighborBox(_ place: Int) -> CGRect {
        guard neighborsPeek else { return box.offsetBy(dx: CGFloat(place) * (box.width + gap(box)), dy: 0) }
        // At the screen's edge, a little bigger than the held page, and
        // moved as far sideways as it has been.
        let screen = pageFrame.width
        let grown = box.insetBy(dx: -box.width * 0.02, dy: -box.height * 0.02)
        let shift = pull.map(sidewaysShift) ?? heldShift
        var x = place > 0 ? screen - Self.peek + shift : Self.peek + shift - grown.width
        // Never touching the held page, nor under it: a page held off to
        // one side pushes that side's tab out (David, 2026-11-11).
        x = place > 0 ? max(x, box.maxX + Self.peekBuffer) : min(x, box.minX - Self.peekBuffer - grown.width)
        return CGRect(x: x, y: grown.minY, width: grown.width, height: grown.height)
    }

    /// Sideways, the page on screen and the one coming in share the bar's
    /// gap, each with its own pill (`BarSlide`). Measured as on letting go
    /// (`BrowserScreen.neighborChosen`), so the split carries straight on as
    /// the tab beside becomes the one held. Toward a side with no tab, the
    /// pill stays whole. Reads `swiping` first, so a pull up never makes
    /// its reader run again.
    var barSlide: BarSlide? {
        guard swiping, !neighborsPeek, standIn != nil || livePull else { return nil }
        let spacing = box.width + gap(box)
        guard spacing > 1 else { return nil }
        let t = (box.midX - pageFrame.midX) / spacing
        let coming = t > 0 ? -1 : 1
        guard t != 0, neighbors.contains(where: { $0.place == coming }) else { return BarSlide(progress: 0) }
        return BarSlide(progress: t)
    }
}

/// The clock a let-go's flight runs on: Firn's own display link, already
/// ticking while the finger is down, so the flight's first frame is the
/// very next one. As a SwiftUI animation the flight began about 50ms after
/// the let-go (SwiftUI's own frames took that long to start, traced with
/// the cable, 2026-11-22), and the page sat still until then, then leapt.
@MainActor
final class FlightClock: NSObject {
    private var link: CADisplayLink?
    private var began: CFTimeInterval?
    private var length: CFTimeInterval = 0
    private var step: ((CGFloat) -> Void)?
    private var idleSince: CFTimeInterval = 0
    /// Ticking with no flight, it stops by itself after this long.
    private static let longestIdle: CFTimeInterval = 8

    /// Ticking from now on, ready for a flight.
    func warm() {
        idleSince = CACurrentMediaTime()
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// A landing of `length` seconds from now: `step` gets the seconds
    /// since, on every frame, the last one exactly `length`.
    func run(for length: CFTimeInterval, step: @escaping (CGFloat) -> Void) {
        warm()
        self.length = length
        self.step = step
        began = CACurrentMediaTime()
    }

    /// No flight any more; still ticking, for the next one.
    func rest() {
        guard began != nil else { return }
        began = nil
        step = nil
        idleSince = CACurrentMediaTime()
    }

    func stop() {
        link?.invalidate()
        link = nil
        began = nil
        step = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let began, let step else {
            if CACurrentMediaTime() - idleSince > Self.longestIdle { stop() }
            return
        }
        // Where the frame being made will be shown.
        let time = min(max(link.targetTimestamp - began, 0), length)
        if time >= length { stop() }
        step(CGFloat(time))
    }
}

/// A page pulled up follows the finger on a short spring, not rigidly, as
/// Safari's (David's recordings, 2026-11-20: Firn's page was at 81% in its
/// first frame, Safari's eases in). The page can't move until the grab's
/// own work is done, and the finger travels on meanwhile; tied to the
/// finger, the first frame drew the page where the finger already was. Now
/// it starts where the page rests and closes on the finger's place, which
/// `aim` keeps up to date, a step every frame of the screen.
///
/// The spring is worked out exactly for each step, and a step never counts
/// for more than a thirtieth of a second: after a frame that came late the
/// page carries on from where it was, without a jump. The link rests once
/// the page has caught up with a finger held still.
@MainActor
final class Follower: NSObject {
    /// How quickly the page closes on the finger (s): it trails a moving
    /// finger by about a third of this. Short, so only the grab changes;
    /// how far Safari's trails is still to be matched.
    static let response = 0.12

    private(set) var running = false
    private var place: [CGFloat] = [0, 0, 0, 0]
    private var speed: [CGFloat] = [0, 0, 0, 0]
    private var target: [CGFloat] = [0, 0, 0, 0]
    private var step: ((CGRect) -> Void)?
    private var link: CADisplayLink?
    private var last: CFTimeInterval?

    /// The page is at `box`, still; `step` places it from now on.
    func start(at box: CGRect, step: @escaping (CGRect) -> Void) {
        stop()
        place = Self.parts(box)
        target = place
        speed = [0, 0, 0, 0]
        self.step = step
        running = true
    }

    /// Where the finger would have the page now.
    func aim(_ box: CGRect) {
        guard running else { return }
        target = Self.parts(box)
        guard link == nil, target != place else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        last = nil
    }

    /// Someone else places the page from here on.
    func stop() {
        rest()
        running = false
        step = nil
    }

    private func rest() {
        link?.invalidate()
        link = nil
        last = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = CGFloat(min(last.map { link.timestamp - $0 } ?? link.duration, 1.0 / 30))
        last = link.timestamp
        let omega = 2 * CGFloat.pi / CGFloat(Self.response)
        let fall = exp(-omega * dt)
        var caught = true
        for i in 0..<4 {
            // A fully damped spring, from where it is at its own speed.
            let apart = place[i] - target[i]
            let pace = speed[i] + omega * apart
            place[i] = target[i] + (apart + pace * dt) * fall
            speed[i] = (pace - omega * (apart + pace * dt)) * fall
            if abs(place[i] - target[i]) > 0.2 || abs(speed[i]) > 8 { caught = false }
        }
        if caught {
            place = target
            speed = [0, 0, 0, 0]
            rest()
        }
        step?(CGRect(x: place[0], y: place[1], width: place[2], height: place[3]))
    }

    private static func parts(_ box: CGRect) -> [CGFloat] {
        [box.minX, box.minY, box.width, box.height]
    }
}

/// A page let go on a spring that carries the finger, as Safari's (the
/// held-page plan's step 3, `docs/IOS-PLAN.md`; David's recording,
/// 2026-11-20): its middle (across and up), its width, and its shape each
/// on the same spring, which doesn't bounce by itself, each started at its
/// own speed. So a page let go from still eases in, and a flicked one
/// shrinks faster at first (never past its card), rises a little above it, and
/// keeps the finger's sideways drift before it swings back.
///
/// Worked out from the spring's own formula for a point in time, and
/// played by a plain clock of fixed length (`Hold.flightTime`), not run as
/// a SwiftUI spring: a spring reports done before it has landed, and the
/// swap with the card jumped the last points. The little that's left near
/// the end is eased away, so the page is exactly on its card as the clock
/// ends, and the landing's other clocks can keep a fixed time.
struct Flight: Equatable {
    var from: CGRect
    var to: CGRect
    /// The middle's speed across and down, and the width's, in points a
    /// second.
    var velocity: CGVector = .zero
    var widthVelocity: CGFloat = 0
    /// What rides along, from the let-go to the card, on the same spring
    /// from still: the corners, how much of the page's top is left out,
    /// and the strip under the clock (gone in a card).
    var radius: ClosedPair = .init(0, 0)
    var skip: ClosedPair = .init(0, 0)
    var band: CGFloat = 0
    /// Opening: the strip's end, and the timing curve it all runs on in
    /// place of the spring.
    var bandTo: CGFloat = 0
    var curve: Curve? = nil

    struct ClosedPair: Equatable {
        var from: CGFloat
        var to: CGFloat
        init(_ from: CGFloat, _ to: CGFloat) { self.from = from; self.to = to }
    }

    /// Safari's spring: let go from still, halfway at about 0.11s, 90% at
    /// 0.25s, and at rest by about 0.4s (measured: 0.115s, 0.24s, 0.38s).
    static let response = 0.4
    /// The clock's length: the spring is within 1.5% by then.
    static let duration = 0.44
    /// From this share of the time on, what's left is eased to nothing.
    static let closes: CGFloat = 0.6
    /// The fastest the width may start toward its card, as a share of the
    /// speed at which it would just pass it. Safari's hardest flick (David's
    /// recording, 2026-11-22, frame by frame): the page off the screen's
    /// right edge and back, its size halfway to the card's 3 frames after
    /// the let-go, 60% at 4, about 90% at 9, never smaller than its card.
    /// That's this spring started at 0.88 of that speed. At 2.7 (a guess
    /// from one recording, 2026-11-20) Firn's page was card-sized in 4 or 5
    /// frames, then slid back at that size for 12 more: two moves.
    static let mostCarry: CGFloat = 0.88
    /// The fastest finger that counts, in points a second.
    static let fastest: CGFloat = 5000

    /// A page at `from`, let go at the finger's `velocity`, bound for `to`.
    /// `shrink` is how much of its width the held page loses for each point
    /// the finger rises.
    init(from: CGRect, to: CGRect, finger velocity: CGSize, shrink: CGFloat,
         radius: ClosedPair, skip: ClosedPair, band: CGFloat) {
        self.from = from
        self.to = to
        self.radius = radius
        self.skip = skip
        self.band = band
        let limit = Self.fastest
        let vx = min(max(velocity.width, -limit), limit)
        let vy = min(max(velocity.height, -limit), limit)
        self.velocity = CGVector(dx: vx, dy: vy)
        // The width keeps shrinking (or growing) as the finger left it,
        // but never so fast that it passes its card.
        let omega = 2 * .pi / Self.response
        let most = Self.mostCarry * omega * max(abs(from.width - to.width), to.width * 0.2)
        widthVelocity = min(max(vy * shrink, -most), most)
    }

    /// A page opening from its card, on a timing curve, from still: the
    /// same glide as SwiftUI's `timingCurve`, worked out here so it can run
    /// on Firn's own clock (`FlightClock`). `band` grows to `bandTo`.
    init(from: CGRect, to: CGRect, curve: Curve, radius: ClosedPair, skip: ClosedPair,
         band: CGFloat, bandTo: CGFloat) {
        self.from = from
        self.to = to
        self.curve = curve
        self.radius = radius
        self.skip = skip
        self.band = band
        self.bandTo = bandTo
    }

    /// A cubic timing curve from (0, 0) to (1, 1), as `Animation.timingCurve`.
    struct Curve: Equatable {
        var x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat

        /// SwiftUI's `easeOut`.
        static let easeOut = Curve(x1: 0, y1: 0, x2: 0.58, y2: 1)

        /// How far along at `seconds` into a run of `length` seconds.
        func value(at seconds: CGFloat, of length: CGFloat) -> CGFloat {
            length > 0 ? value(at: min(max(seconds / length, 0), 1)) : 1
        }

        /// How far along, 0 to 1, at `time` of the way through (0 to 1).
        func value(at time: CGFloat) -> CGFloat {
            guard time > 0 else { return 0 }
            guard time < 1 else { return 1 }
            func at(_ s: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
                let r = 1 - s
                return 3 * r * r * s * a + 3 * r * s * s * b + s * s * s
            }
            // The curve's own parameter at this time, by halving.
            var low: CGFloat = 0, high: CGFloat = 1
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if at(mid, x1, x2) < time { low = mid } else { high = mid }
            }
            return at((low + high) / 2, y1, y2)
        }
    }

    /// How much is left of the way, let go from still: 1 to 0.
    private func left(at time: CGFloat) -> CGFloat {
        if let curve { return 1 - curve.value(at: time) }
        let time = min(max(time, 0), 1)
        let t = time * Self.duration
        let omega = 2 * .pi / Self.response
        let close = min(max((time - Self.closes) / (1 - Self.closes), 0), 1)
        return (1 + omega * t) * exp(-omega * t) * (1 - close * close * (3 - 2 * close))
    }

    func radius(at time: CGFloat) -> CGFloat { radius.to + (radius.from - radius.to) * left(at: time) }
    func skip(at time: CGFloat) -> CGFloat { skip.to + (skip.from - skip.to) * left(at: time) }
    func band(at time: CGFloat) -> CGFloat { bandTo + (band - bandTo) * left(at: time) }

    /// Where the page is, `time` of the way through the clock (0 to 1).
    func box(at time: CGFloat) -> CGRect {
        let time = min(max(time, 0), 1)
        guard time < 1, from.width > 0, to.width > 0 else { return to }
        if curve != nil {
            // Each side on the curve, as SwiftUI moves a rectangle.
            let left = left(at: time)
            return CGRect(x: to.minX + (from.minX - to.minX) * left, y: to.minY + (from.minY - to.minY) * left,
                          width: to.width + (from.width - to.width) * left,
                          height: to.height + (from.height - to.height) * left)
        }
        let t = time * Self.duration
        let omega = 2 * .pi / Self.response
        let fall = exp(-omega * t)
        let close = min(max((time - Self.closes) / (1 - Self.closes), 0), 1)
        let left = 1 - close * close * (3 - 2 * close)
        // A fully damped spring: how far from its end a value is, having
        // started `apart` from it at `speed`.
        func away(_ apart: CGFloat, _ speed: CGFloat) -> CGFloat {
            (apart + (speed + omega * apart) * t) * fall * left
        }
        let midX = to.midX + away(from.midX - to.midX, velocity.dx)
        let midY = to.midY + away(from.midY - to.midY, velocity.dy)
        let width = max(to.width + away(from.width - to.width, widthVelocity), to.width * 0.5)
        let shape = to.height / to.width + away(from.height / from.width - to.height / to.width, 0)
        let height = width * shape
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
}

// MARK: - The pieces that read the hold

/// The page's picture standing in for the page as it glides (step 3b), with
/// the tabs beside it, its strip under the clock, the card's ring and line,
/// and the set-down's shadow. Nothing while no picture (or held live page)
/// is up.
struct StandInLayer: View {
    let hold: Hold
    let landing: Landing
    let store: BrowserStore
    let pictures: PagePictures

    /// The tile a landing page forms into (`CardGlide.face`): only while
    /// landing in one (`tileCrop` is set only then).
    private var tileFace: ((CGFloat) -> AnyView)? {
        guard hold.tileCrop != nil, let tab = hold.standInTab, tab.place == .basecamp else { return nil }
        let space = store.activeSpace.color
        // Opening, the tile tapped is already the tab on screen; the face
        // shows the ring only if the tile had it (`heldCard`: the tab on
        // screen before the tap), so the swap with the real tile matches.
        let onScreen = tab.id == (landing.heldCard ?? store.activeTab?.id)
        return { radius in AnyView(BasecampTiles.face(tab, space: space, onScreen: onScreen, cornerRadius: radius)) }
    }

    var body: some View {
        let hold = hold
        if let standInSize = hold.pulledSize(topInset: pictures.topInset), standInSize.width > 0 {
            let box = hold.box
            let boxRadius = hold.boxRadius
            if let standInTop = hold.standInTop {
                // A fill, so a new tab's color fades in rather than snaps.
                Rectangle()
                    .fill(Color(cgColor: standInTop))
                    .frame(height: pictures.topInset)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(hold.stripOpacity * hold.standInFade)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Placed from the screen's top-left corner, in the screen's
            // own points, as the cards report theirs (measured: the
            // layer's own corner isn't the screen's).
            let width = hold.pageFrame.width
            let height = width * standInSize.height / standInSize.width
            GeometryReader { layer in
                let corner = layer.frame(in: .global).origin
                ZStack(alignment: .topLeading) {
                    // Sideways, each page carries its own strip under
                    // the clock, which stays still over them (as in
                    // Safari); behind the pictures, filling their
                    // rounded top corners. The live page brings its own.
                    if hold.swiping {
                        ForEach(hold.neighbors) { neighbor in
                            topBand(neighbor.top, over: neighbor.pinned ?? hold.neighborBox(neighbor.place))
                                .opacity(hold.neighborsOpacity * hold.neighborsIn)
                        }
                        if hold.standIn != nil { topBand(hold.standInTop, over: box) }
                    }
                    // The tabs beside it, the same size, a gap apart.
                    ForEach(hold.neighbors) { neighbor in
                        Group {
                            if let image = neighbor.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .frame(width: width, height: width * image.size.height / max(image.size.width, 1))
                            } else {
                                // Never pictured: a plain page.
                                Color.clear.frame(width: width, height: height)
                            }
                        }
                        .frame(width: width, height: height, alignment: .top)
                        .background(Theme.page)
                        .modifier(CardGlide(width: width, box: neighbor.pinned ?? hold.neighborBox(neighbor.place),
                                            radius: boxRadius))
                        // In from beyond the screen's edge.
                        .offset(x: CGFloat(neighbor.place) * (1 - hold.neighborsIn) * (Hold.peek + 40))
                        .opacity(hold.neighborsOpacity * hold.neighborsIn)
                    }
                    // The set-down's shadow: there only while the page is
                    // lifted above its card, sinking in as it settles.
                    // A tile's comes only with the real tile (`BasecampTiles`):
                    // here it was sized to the whole picture, not the
                    // part shown, and trailed below the landing tile as a
                    // faint tall ghost (David's recording, 2026-11-13).
                    if let standInTab = hold.standInTab, standInTab.place != .basecamp {
                        RoundedRectangle(cornerRadius: boxRadius, style: .continuous)
                            .fill(Theme.page)
                            .frame(width: box.width, height: box.height)
                            .shadow(color: Theme.shadowPageFar, radius: 12, y: 6)
                            .offset(x: box.minX, y: box.minY)
                            .opacity(Double((landing.settle - 1) / (BrowserScreen.settleLift - 1)))
                    }
                    // The strip under the clock, on top of the page: its
                    // rounded top is the page's while it flies (sideways,
                    // `topBand` above).
                    if !hold.swiping, hold.standIn != nil {
                        Color.clear
                            .modifier(BandGlide(box: box, flight: hold.flight, time: hold.flightTime,
                                                radius: boxRadius, band: hold.band,
                                                room: pictures.topInset,
                                                color: hold.standInTop.map { Color(cgColor: $0) } ?? Theme.page))
                            .opacity(hold.bandFade)
                    }
                    Group {
                        if let standIn = hold.standIn { Image(uiImage: standIn).resizable() }
                    }
                    .frame(width: width, height: height)
                    .modifier(CardGlide(width: width, box: box, flight: hold.flight, time: hold.flightTime,
                                        radius: boxRadius, skip: hold.boxSkip,
                                        band: hold.swiping ? 0 : hold.band * CGFloat(hold.bandFade),
                                        cropFrom: hold.tileCrop?.from, cropTo: hold.tileCrop?.to,
                                        face: tileFace))
                    .modifier(ArrivalBand(arrival: hold.standInTab?.place == .basecamp ? landing.tileReveal : 0,
                                          range: BasecampTiles.glideSwap, fadesIn: false))
                }
                // Around the card's middle, so it settles in place.
                .scaleEffect(landing.settle, anchor: UnitPoint(x: box.midX / max(layer.size.width, 1),
                                                               y: box.midY / max(layer.size.height, 1)))
                .offset(x: -corner.x, y: -corner.y)
            }
            .opacity(hold.standInFade)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A page's strip under the clock, riding above its box.
    private func topBand(_ color: CGColor?, over box: CGRect) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: hold.boxRadius, topTrailingRadius: hold.boxRadius, style: .continuous)
            .fill(color.map { Color(cgColor: $0) } ?? Theme.page)
            .frame(width: box.width, height: pictures.topInset + hold.boxRadius)
            .offset(x: box.minX, y: box.minY - pictures.topInset)
    }
}

/// The live page, moved by its layer while a finger holds it (`PageHold`).
struct HeldPage: View {
    let page: any PageController
    let barTop: CGFloat
    /// The bar's top when full and when shrunk (`PageView`).
    let barTopSpan: ClosedRange<CGFloat>?
    let hold: Hold
    let onScroll: (BarScroll) -> Void

    var body: some View {
        // `livePull` first, so the box is read (and followed) only while
        // the live page is the one held.
        let held = hold.livePull ? PageHold(box: hold.box, radius: hold.boxRadius, includesTop: hold.swiping,
                                            topShown: hold.band) : nil
        PageView(page: page, barTop: barTop, barTopSpan: barTopSpan, held: held, onScroll: onScroll)
    }
}

/// Reader's Aa pill, just under the clock at the top right, as in the
/// approved design: only while reading, and gone while the page is
/// pulled, the overview shows, or an address is being typed.
struct ReaderPill: View {
    let store: BrowserStore
    let hold: Hold
    /// A hidden page, or typing.
    let away: Bool
    /// The overview showing counts as away too (read here, not by the screen).
    let landing: Landing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = store.activeTab?.page?.isReading == true && !away && !landing.shown && hold.pull == nil && !hold.swiping
        ZStack {
            if shown {
                // Just under the clock, 16pt in, as in the approved design.
                ReaderTextButton(space: store.activeSpace.color, inset: 10)
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: shown)
    }
}

/// The page's bar, with what moves it read here: the sideways pills, the
/// field's give toward a new tab, and its fade as the overview arrives. So
/// a pull up runs only this, never the bar itself (`content` is made once
/// by `BrowserScreen` and passed through unchanged).
struct BarHost<Content: View>: View {
    let hold: Hold
    let landing: Landing
    let editing: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let shown = landing.arrival < 1 || editing
        content
            .environment(\.barSlide, hold.barSlide)
            .environment(\.barGive, hold.newTabGive)
            // Over the overview, the bar shows only while typing from +.
            // It fades out over the first half of the glide, before the
            // overview's bar fades in, so the two never overlap. During
            // a glide it stays a hair above 0: at 0 iOS lets its glass
            // go, and setting the glass up again froze a frame partway
            // back to the page (David's recording, 2026-11-04).
            // Worked out on every frame (`ArrivalBand`): a plain
            // opacity fades straight from start to end, so both bars
            // faded at once and their words smudged together (David's
            // recording, 2026-11-09).
            // As a tab opens the bar comes back on a clock of its own
            // (`BarReturn`), so this band stands aside.
            .modifier(ArrivalBand(arrival: editing || landing.barLate ? 0 : landing.arrival,
                                  range: 0...0.2, fadesIn: false,
                                  floor: !editing && landing.gliding != nil ? 0.002 : 0))
            .modifier(BarReturn(landing: landing, off: editing))
            .allowsHitTesting(shown)
            .hiddenFromVoiceOver(!shown)
    }
}

/// The bar's drag (a swipe up pulls the page into the overview, sideways
/// slides between tabs), with its own finger-down state: kept here, a
/// finger coming down ran the whole screen (and its bar) again, about 10ms
/// just before every grab's turn (the trace of 2026-11-20).
struct BarPull: ViewModifier {
    /// Only the full bar swipes: the small pill is tap-only.
    let including: GestureMask
    let moved: (DragGesture.Value) -> Void
    let ended: (DragGesture.Value) -> Void
    /// A finger came down on the bar, or left it (before it's a drag).
    var touched: (Bool) -> Void = { _ in }
    /// The finger is off the bar, whether the drag ended or iOS took the
    /// touch away (which `ended` never hears about).
    let stopped: () -> Void
    /// True while a finger is on the bar's drag; iOS resets it when the
    /// drag is cancelled too.
    @GestureState private var dragging = false
    @GestureState private var touching = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged(moved)
                    .onEnded(ended),
                including: including
            )
            .onChange(of: dragging) { _, now in if !now { stopped() } }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($touching) { _, state, _ in state = true },
                including: including
            )
            .onChange(of: touching) { _, now in touched(now) }
    }
}

/// The field's hold for the page menu, with its own finger-down state:
/// kept on the bar, a finger coming down ran the whole bar again, 8 to 12ms
/// just before a grab (the trace of 2026-11-20).
struct FieldHold: ViewModifier {
    typealias Value = SequenceGesture<LongPressGesture, DragGesture>.Value
    let including: GestureMask
    let changed: (Value) -> Void
    let ended: () -> Void
    /// A finger is holding the field (from the touch, before it's a hold).
    let holding: (Bool) -> Void
    @GestureState private var down = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: HoldThenMove.menuHold)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .updating($down) { value, state, _ in
                        if case .first(true) = value { state = true }
                    }
                    .onChanged(changed)
                    .onEnded { _ in ended() },
                including: including
            )
            .onChange(of: down) { _, now in holding(now) }
    }
}

/// While the page is pulled up from the bar (and a moment after), the
/// bar's buttons don't act: the finger lifting over one isn't a tap. Asked
/// only as a button is tapped, so it's a plain box nothing watches: as a
/// watched value it ran the whole bar again at every grab.
@MainActor final class BarQuiet {
    var on = false
}

/// The page's bar coming back as a tab opens, on its own clock, as Safari's
/// does on David's iPhone (his recordings, 2026-11-19, frame by frame):
/// first seen about 0.10s after the page starts to grow, then an even fade
/// of about 0.18s, whole at about 0.28s, once the page's bottom edge has
/// passed under it. Tied to the page's travel instead, it rushed (the page
/// covers most of its way early): nearly whole in three or four frames,
/// and waiting, finished, over the blurred overview before the page reached
/// it. Read here alone, so the fade keeps its own timing whatever else
/// moves in the same moment. A hair above nothing keeps its glass alive.
struct BarReturn: ViewModifier {
    let landing: Landing
    let off: Bool

    /// The wait and the fade, as shares of the opening glide's time (0.50s
    /// for a tab: 0.10s and 0.18s).
    static var wait: Double { 0.2 }
    static var fade: Double { 0.36 }

    func body(content: Content) -> some View {
        content.modifier(Fade(through: landing.barIn, on: landing.barLate && !off))
    }

    /// `through` rests at 0 between openings, so each fade starts from
    /// nothing: a plain opacity would glide from the bar's last look, whole.
    private struct Fade: ViewModifier, Animatable {
        var through: CGFloat
        let on: Bool

        nonisolated var animatableData: CGFloat {
            get { through }
            set { through = newValue }
        }

        func body(content: Content) -> some View {
            content.opacity(on ? max(0.002, Double(min(max(through, 0), 1))) : 1)
        }
    }
}

/// Swiped past the last tab: a frosted + at the edge says a new tab is a
/// let-go away.
struct NewTabHintLayer: View {
    let hold: Hold
    let space: String

    var body: some View {
        NewTabHint(space: space, reach: hold.newTabReach)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            // Just off the screen's edge at rest, sliding in with the
            // finger (trailing-aligned, it starts half its width in).
            .offset(x: hold.newTabShift + BarButton.glassSize)
            // It stays put as the keyboard comes up (it rode up with
            // the bar; David, 2026-11-06).
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The strip under the clock riding on the flying page: as wide as the
/// box, `band` of the strip's room tall, reaching down behind the picture's
/// rounded top corners. Worked out on every frame, as `CardGlide` is, so it
/// stays on the box mid-glide; it fades over its last fifth, so no edge of
/// it shows around a landed card's corners.
private struct BandGlide: ViewModifier, Animatable {
    var box: CGRect
    var flight: Flight? = nil
    var time: CGFloat = 0
    var radius: CGFloat
    var band: CGFloat
    let room: CGFloat
    let color: Color

    nonisolated var animatableData: AnimatablePair<CGRect.AnimatableData, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(box.animatableData, AnimatablePair(radius, AnimatablePair(band, time))) }
        set {
            box.animatableData = newValue.first
            radius = newValue.second.first
            band = newValue.second.second.first
            time = newValue.second.second.second
        }
    }

    func body(content: Content) -> some View {
        let box = flight?.box(at: time) ?? box
        let radius = flight?.radius(at: time) ?? radius
        let band = flight?.band(at: time) ?? band
        let rise = room * min(max(band, 0), 1)
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: max(box.width, 0), height: rise + radius)
            .offset(x: box.minX, y: box.minY - rise)
            .opacity(Double(min(max(band * 5, 0), 1)))
    }
}

/// The page's picture in its box: scaled to the box's width, placed on it,
/// and cut to the box's height with its corners. Transforms and a mask
/// only, so nothing lays out again while it moves.
private struct CardGlide: ViewModifier, Animatable {
    let width: CGFloat
    /// Where the picture is, unless a flight says (`placed`).
    var rest: CGRect
    /// A let-go's flight, and how far through its time it is.
    var flight: Flight? = nil
    var time: CGFloat = 0
    var radius: CGFloat
    /// How much of the page's top the shown part leaves out, in the page's
    /// own points: 0 on the page, the header's depth in a tall card (2j),
    /// so the header slides away as the page becomes its card.
    var skip: CGFloat = 0
    /// How far the strip under the clock has risen above the picture, 0 to
    /// 1 (`BandGlide`): the picture's top corners square off as it does,
    /// since the rounded top is then the strip's. Left round under a whole
    /// strip, a dark-topped page showed the strip's color in both corners,
    /// flying and at rest while its picture waited for the page (David's
    /// recording, 2026-11-23).
    var band: CGFloat = 0
    /// Into a tile: where the glide started, and the tile's size. The
    /// shown part takes the tile's shape over the first 60% of the way, so
    /// the page becomes a tile as it shrinks, rather than flying as a tall
    /// mini page and being cut down at the end (David's recording,
    /// 2026-11-09).
    var cropFrom: CGRect? = nil
    var cropTo: CGSize? = nil
    /// Into a tile: the tile itself, given its corner radius, drawn at the
    /// tile's size. It forms inside the shrinking picture as the picture
    /// fades under it, as an app's icon forms inside a closing app, so the
    /// page has already become the tile when it lands (David, 2026-11-13:
    /// a page slice swapped for an icon in one frame read as a cut).
    var face: ((CGFloat) -> AnyView)? = nil
    /// The part of the way (`travel`) over which the tile forms: from about
    /// 3 times the tile's width to about 1.6 times, then it travels the
    /// rest as the tile. iOS's app close, frame by frame (David's
    /// recording, 2026-11-13): the icon shows from about 3 times its size,
    /// has taken over by about 1.5 times, and flies the last stretch as
    /// the icon. Formed from 2.5 times to just above (0.55 to 0.9), it was
    /// seen as a tile for only a frame or two before landing.
    static let faceForms: ClosedRange<CGFloat> = 0.4...0.82

    // Worked out on every frame, so the shown part, the ring, and the line
    // all agree on the box mid-glide.
    nonisolated var animatableData: AnimatablePair<CGRect.AnimatableData, AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>> {
        get { AnimatablePair(rest.animatableData, AnimatablePair(radius, AnimatablePair(skip, AnimatablePair(time, band)))) }
        set {
            rest.animatableData = newValue.first
            radius = newValue.second.first
            skip = newValue.second.second.first
            time = newValue.second.second.second.first
            band = newValue.second.second.second.second
        }
    }

    init(width: CGFloat, box: CGRect, flight: Flight? = nil, time: CGFloat = 0, radius: CGFloat,
         skip: CGFloat = 0, band: CGFloat = 0, cropFrom: CGRect? = nil, cropTo: CGSize? = nil,
         face: ((CGFloat) -> AnyView)? = nil) {
        self.width = width
        self.rest = box
        self.flight = flight
        self.time = time
        self.radius = radius
        self.skip = skip
        self.band = band
        self.cropFrom = cropFrom
        self.cropTo = cropTo
        self.face = face
    }

    /// The picture's place on this frame.
    private var box: CGRect { flight?.box(at: time) ?? rest }

    /// The shown part's height on screen.
    /// How far the picture has shrunk toward the tile, 0 to 1, by width.
    private var travel: CGFloat {
        guard let cropFrom, let cropTo, cropFrom.width > cropTo.width else { return 0 }
        return min(max((cropFrom.width - box.width) / (cropFrom.width - cropTo.width), 0), 1)
    }

    /// How far the tile has formed, eased at both ends.
    private var formed: CGFloat {
        let range = Self.faceForms
        let t = min(max((travel - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private var shownHeight: CGFloat {
        guard let cropFrom, let cropTo, cropTo.width > 0, cropFrom.width > cropTo.width else { return box.height }
        let eased = 1 - pow(1 - min(travel / 0.6, 1), 2)
        let tileShaped = min(box.width * cropTo.height / cropTo.width, box.height)
        return box.height + (tileShaped - box.height) * eased
    }

    func body(content: Content) -> some View {
        let box = box
        let radius = flight?.radius(at: time) ?? radius
        let skip = flight?.skip(at: time) ?? skip
        let risen = min(max(flight?.band(at: time) ?? band, 0), 1)
        let top = radius * (1 - risen)
        let scale = width > 0 && box.width > 0 ? box.width / width : 1
        let formed = face == nil ? 0 : formed
        content
            .opacity(1 - Double(formed))
            .overlay(alignment: .topLeading) {
                if let face, let cropTo, cropTo.width > 0, box.width > 0, formed > 0 {
                    // Drawn at the tile's own size (its mark stays 24pt
                    // there) and the shown part's shape, then scaled up to
                    // the picture's, so the two shrink as one.
                    let up = width / cropTo.width
                    face(radius * cropTo.width / box.width)
                        .frame(width: cropTo.width, height: shownHeight * cropTo.width / box.width)
                        .scaleEffect(up, anchor: .topLeading)
                        .frame(width: width, height: shownHeight / scale, alignment: .topLeading)
                        .opacity(Double(formed))
                }
            }
            // One shape throughout, so its size and corners glide.
            .mask(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: top / scale, bottomLeadingRadius: radius / scale,
                                       bottomTrailingRadius: radius / scale, topTrailingRadius: top / scale,
                                       style: .continuous)
                    .frame(height: shownHeight / scale)
                    .offset(y: skip)
            }
            // The part below the skip moves up to the box's top.
            .offset(y: -skip)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: box.minX, y: box.minY)
    }
}

/// The frosted + that shows at the right edge as the last tab is swiped
/// past: it fades in and grows a little with the swipe, and fills with the
/// space's color once letting go would start a new tab.
private struct NewTabHint: View {
    let space: String
    let reach: CGFloat

    var body: some View {
        Image(systemName: "plus")
            .font(BarButton.symbolFont)
            .foregroundStyle(reach >= 1 ? Color.white : Theme.ink)
            .frame(width: BarButton.size, height: BarButton.size)
            .padding(2)
            // Filled once it's a let-go away. A solid fill under the glass,
            // not the glass's tint: a tinted glass that moves every frame
            // drew washed out until it stopped (Simulator recording,
            // 2026-11-06).
            .background(Circle().fill(Theme.spaceVivid(space)).opacity(reach >= 1 ? 1 : 0))
            // The bar's glass (frosty, no tint), under the fill.
            .background { FirnGlass(shape: Circle()) }
            .scaleEffect(0.7 + 0.3 * reach)
            .opacity(Double(reach))
            .animation(.smooth(duration: 0.2), value: reach >= 1)
    }
}
