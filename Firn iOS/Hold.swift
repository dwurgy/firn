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
                            .modifier(BandGlide(box: box, radius: boxRadius, band: hold.band,
                                                room: pictures.topInset,
                                                color: hold.standInTop.map { Color(cgColor: $0) } ?? Theme.page))
                            .opacity(hold.bandFade)
                    }
                    Group {
                        if let standIn = hold.standIn { Image(uiImage: standIn).resizable() }
                    }
                    .frame(width: width, height: height)
                    .modifier(CardGlide(width: width, box: box, radius: boxRadius, skip: hold.boxSkip,
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
    let hold: Hold
    let onScroll: (BarScroll) -> Void

    var body: some View {
        // `livePull` first, so the box is read (and followed) only while
        // the live page is the one held.
        let held = hold.livePull ? PageHold(box: hold.box, radius: hold.boxRadius, includesTop: hold.swiping,
                                            topShown: hold.band) : nil
        PageView(page: page, barTop: barTop, held: held, onScroll: onScroll)
    }
}

/// Reader's Aa pill, just under the clock at the top right, as in the
/// approved design: only while reading, and gone while the page is
/// pulled, the overview shows, or an address is being typed.
struct ReaderPill: View {
    let store: BrowserStore
    let hold: Hold
    /// The overview, a hidden page, or typing.
    let away: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = store.activeTab?.page?.isReading == true && !away && hold.pull == nil && !hold.swiping
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
            .accessibilityHidden(!shown)
    }
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
    var radius: CGFloat
    var band: CGFloat
    let room: CGFloat
    let color: Color

    nonisolated var animatableData: AnimatablePair<CGRect.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(box.animatableData, AnimatablePair(radius, band)) }
        set { box.animatableData = newValue.first; radius = newValue.second.first; band = newValue.second.second }
    }

    func body(content: Content) -> some View {
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
    var box: CGRect
    var radius: CGFloat
    /// How much of the page's top the shown part leaves out, in the page's
    /// own points: 0 on the page, the header's depth in a tall card (2j),
    /// so the header slides away as the page becomes its card.
    var skip: CGFloat = 0
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
    nonisolated var animatableData: AnimatablePair<CGRect.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(box.animatableData, AnimatablePair(radius, skip)) }
        set { box.animatableData = newValue.first; radius = newValue.second.first; skip = newValue.second.second }
    }

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
                RoundedRectangle(cornerRadius: radius / scale, style: .continuous)
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
