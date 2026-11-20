import FirnCore
import SwiftUI

/// The values a swipe up or a tab opening moves (2i step 3,
/// `docs/IOS-PLAN.md`). `BrowserScreen` owns one and sets them; the
/// overview is handed the object, never the values, so a change runs only
/// the few small views that read each one, not `TabOverview` and its whole
/// list (the SwiftUI template on David's iPhone, 2026-11-14: `TabOverview`
/// ran every time `BrowserScreen` did, 347 times in 30s).
///
/// Set them through `BrowserScreen`'s own properties of the same names,
/// which skip a value that hasn't changed (an `@Observable` property tells
/// its readers on every set, where `@State` let an equal value pass).
/// Animations carry through as they did with `@State`: a value set inside
/// `withAnimation` reaches its readers in that animation.
@MainActor @Observable
final class Landing {
    /// The tab whose card (or tile) is hidden while the page's picture
    /// stands in for it.
    var gliding: UUID?
    /// How far a gliding Basecamp tile shows (`BasecampTiles.reveal`).
    var tileReveal: Double = 1
    /// The set-down: 1 at rest (`BrowserScreen.settle`).
    var settle: CGFloat = 1
    /// The tab on screen's title line, faded in after the landing.
    var lineShown = true
    /// The card that keeps its size while another tab grows out of its row.
    var heldCard: UUID?
    /// How far the overview has arrived, 0 to 1 (`BrowserScreen.arrival`).
    var arrival: CGFloat = 0
    /// A tab is opening: the page's bar comes back on a clock of its own
    /// (`BarReturn`), as Safari's does.
    var barLate = false
    /// How far the bar has come back while `barLate`, 0 to 1; 0 at rest.
    var barIn: CGFloat = 0
    /// How much of the overview's list shows (`BrowserScreen.listIn`).
    var listIn: CGFloat = 0
    /// How far the overview has come forward (`ComesForward.through`).
    var forward: CGFloat = 0
    /// How far it has come into focus (`ComesForward.focus`).
    var focus: CGFloat = 0
    /// A page pulled up is held over the overview, until the glide ends
    /// (`BrowserScreen.gliding`): the overview's picture is dimmed and
    /// blurred, ready behind it, and shows as far as `heldIn`.
    var behind = false
    /// How much of the overview's picture shows behind a held page, 0 to
    /// 1. Safari's grid stays out of a hold, only its blurred wallpaper
    /// behind the page, and fades in, very soft, once the page has been
    /// pulled nearly all the way up (David's recording, 2026-11-19, measured:
    /// from the page at 54% of the screen's width, over about 0.7s).
    /// (2026-11-19, a day: there from the grab, a misreading of quick flicks.)
    var heldIn: CGFloat = 0
    /// Whether the page is past that point (`BrowserScreen.followPull`).
    var heldHigh = false
    /// The grid has come in behind the held page on this pull: its picture
    /// is no darker from then to the glide's end (`ComesForward.heldDim`).
    var heldSeen = false
    /// The overview, hidden behind the page, laid out in its settled look
    /// for the moment its picture is taken (`TabOverview.freezeSoon`, step
    /// 1b): behind the page it otherwise waits as a landing starts, its
    /// list out, smaller, and its bar gone. Only the overview's own pieces
    /// read it; the page and its bar don't.
    var posed = false

    /// A swipe up or the tabs button: the overview is about to show.
    func unpose() {
        if posed { posed = false }
    }
}

/// What the overview can ask the screen to do. Always equal while Reduce
/// Motion and VoiceOver stay as they are, so a new set made on each of the
/// screen's runs never makes the overview run again (a bare closure can't
/// be compared, so it never matched). Made again when either changes, since
/// the screen's actions read them.
struct OverviewActions: Equatable {
    let open: @MainActor (FirnCore.Tab) -> Void
    let done: @MainActor () -> Void
    let newTab: @MainActor () -> Void
    /// What the actions read that could change under them.
    let key: [Bool]
    static func == (a: Self, b: Self) -> Bool { a.key == b.key }
}

// MARK: - The pieces that read the landing

/// `ArrivalBand` on one of the landing's values, read here, so only this
/// runs again as it moves. Always fading in. `floor` holds always;
/// `glidingFloor` only while a page glides (a bar's glass kept alive).
/// `off` reads as 0 (the overview's bar while typing).
struct LandingBand: ViewModifier {
    let landing: Landing
    let value: KeyPath<Landing, CGFloat>
    let range: ClosedRange<CGFloat>
    var floor: Double = 0
    var glidingFloor: Double = 0
    var off = false

    func body(content: Content) -> some View {
        let floor = !off && landing.gliding != nil ? max(floor, glidingFloor) : floor
        content.modifier(ArrivalBand(arrival: off ? 0 : landing.posed ? 1 : landing[keyPath: value], range: range,
                                     fadesIn: true, floor: floor))
    }
}

/// `ComesForward` on the landing's values. The blur runs once the list is
/// coming in; `scalesWithList`: the growth too (the list's own contents).
struct LandingForward: ViewModifier {
    let landing: Landing
    let middle: CGPoint?
    let off: Bool
    var scalesWithList = false
    /// `middle` is in the scroll view's own points (`ComesForward.inScroll`).
    var inScroll = false
    /// The overview's picture: dimmed behind a held page too (`Landing.behind`).
    var behindToo = false

    func body(content: Content) -> some View {
        let posed = landing.posed
        let listing = posed || landing.listIn > 0 || (behindToo && landing.behind)
        content.modifier(ComesForward(through: posed ? 1 : landing.forward, focus: posed ? 1 : landing.focus,
                                      middle: middle, off: off,
                                      inScroll: inScroll, blurs: listing, scales: scalesWithList ? listing : true,
                                      held: landing.heldSeen))
    }
}

/// The dim over the overview's cards, lifting as the page arrives.
struct LandingDim: View {
    let landing: Landing

    var body: some View {
        Theme.lookoutDim
            .ignoresSafeArea()
            .opacity(landing.posed ? 0 : 1 - landing.arrival)
            .allowsHitTesting(false)
    }
}

/// The overview's picture (`FrozenOverview`) over the list and bar while a
/// tab glides, pulled into focus. Behind a held page it stays out, as
/// Safari's grid does, until the page is pulled nearly all the way up, where
/// it fades in fully blurred (`Landing.heldIn`); otherwise it's there, in
/// one step, from the let-go, and from the first frame of a close by the
/// tabs button; its blur shrinking to nothing once the page is let go, then
/// the live list takes over. Opening runs it backward. Put in as the glide
/// begins and shown by a step, not by being added later: a view added
/// mid-animation starts at the animation's end.
struct LandingFrozen: View {
    let landing: Landing
    let image: UIImage
    let pad: CGSize
    let middle: CGPoint?

    var body: some View {
        if landing.gliding != nil {
            FrozenOverviewView(image: image, pad: pad, effects: LandingFocusPull(landing: landing)
                .concat(LandingHeldStep(landing: landing))
                .concat(LandingForward(landing: landing, middle: middle, off: false, behindToo: true)))
                .transition(.identity)
        }
    }
}

/// `FocusPull` on the landing's focus, read here alone, so the blur runs on
/// the focus's own curve whatever else moves in the same moment.
struct LandingFocusPull: ViewModifier {
    let landing: Landing

    func body(content: Content) -> some View {
        content.modifier(FocusPull(focus: landing.focus))
    }
}

/// The picture's blur and its hand-over, from how far the overview has come
/// into focus (0 to 1). The blur really shrinks, a focus pull, where the
/// picture blurred once and cross-faded let the sharp list show through a
/// pale haze midway (David's recordings beside Safari's, 2026-11-19).
/// One picture blurred each frame; the live list was about 200 passes.
struct FocusPull: ViewModifier, Animatable {
    var focus: CGFloat
    /// From here on the picture fades out over the live list, while about
    /// 4pt of blur is left: the sharp list coming through the soft picture
    /// over the glide's last third is what reads as clearing evenly to the
    /// last frame (a picture's fine edges, a title's letters, stay soft
    /// under even half a point of blur, so swapped late it was a step).
    /// The picture was taken the last time the overview rested, and its
    /// scroll may be a few points off (`Look.scroll`).
    static let handOver: CGFloat = 0.6
    /// The radius falls as this power of what's left of the focus. To the
    /// eye a blur clears mostly in its last few points: on a plain share the
    /// picture looked as soft as ever for most of the glide, then went sharp
    /// within two or three frames (the step David saw beside Safari's,
    /// 2026-11-19; measured in the Simulator, 2026-11-20: a title's edges
    /// at a quarter of full strength three frames from the end). Squared,
    /// the large radii pass early and the last points get the time.
    static let ease: CGFloat = 2

    nonisolated var animatableData: CGFloat {
        get { focus }
        set { focus = newValue }
    }

    func body(content: Content) -> some View {
        let focus = min(max(focus, 0), 1)
        content
            .blur(radius: FrozenOverview.radius * pow(1 - focus, Self.ease))
            // The square root: the focus eases to its end, so a plain share
            // left the picture nearly gone for the fade's last frames and
            // packed the swap into two or three; this is about even in time.
            .opacity(focus < Self.handOver ? 1 : Double(((1 - focus) / (1 - Self.handOver)).squareRoot()))
    }
}

/// Shown from the moment one of the landing's values reaches `from`, in one
/// step even while that value is animated; `below` until then.
struct LandingStep: ViewModifier {
    let landing: Landing
    let value: KeyPath<Landing, CGFloat>
    let from: CGFloat
    var below: Double = 0
    var off = false

    func body(content: Content) -> some View {
        content.modifier(Step(value: off ? 1 : landing[keyPath: value], from: from, below: below))
    }

    private struct Step: ViewModifier, Animatable {
        var value: CGFloat
        let from: CGFloat
        let below: Double

        nonisolated var animatableData: CGFloat {
            get { value }
            set { value = newValue }
        }

        func body(content: Content) -> some View {
            content.opacity(value >= from ? 1 : below)
        }
    }
}

/// The overview's picture: whole from the moment the list starts to come in
/// (the let-go), and until then as much as a high hold has brought in
/// (`Landing.heldIn`).
struct LandingHeldStep: ViewModifier {
    let landing: Landing

    func body(content: Content) -> some View {
        content.modifier(Step(listIn: landing.listIn, heldIn: landing.heldIn))
    }

    private struct Step: ViewModifier, Animatable {
        var listIn: CGFloat
        var heldIn: CGFloat

        nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
            get { AnimatablePair(listIn, heldIn) }
            set { listIn = newValue.first; heldIn = newValue.second }
        }

        func body(content: Content) -> some View {
            content.opacity(listIn >= 0.0001 ? 1 : Double(min(max(heldIn, 0), 1)))
        }
    }
}

/// The live list and bar wait unseen under the overview's picture while it
/// covers them, and are there, whole, the moment it starts to fade
/// (`FocusPull.handOver`): the picture's soft edges would otherwise show
/// them sharp around a blurred middle. A hair above nothing, so their glass
/// stays alive. `pictured`: there is a picture for this landing.
struct LandingUnderPicture: ViewModifier {
    let landing: Landing
    let pictured: Bool

    func body(content: Content) -> some View {
        content.modifier(LandingStep(landing: landing, value: \.focus, from: FocusPull.handOver,
                                     below: 0.002, off: !pictured || landing.gliding == nil))
    }
}

/// A group's card gathering as the page lands in a card inside it
/// (`ArrivalFade`); `holdsOnScreen`: the tab on screen is in this group.
struct LandingGroupFade: ViewModifier {
    let landing: Landing
    let holdsOnScreen: Bool

    func body(content: Content) -> some View {
        content.modifier(ArrivalFade(arrival: holdsOnScreen && !landing.lineShown ? landing.arrival : 1))
    }
}

/// Tells the overview when it comes to rest (nothing landing, held, or
/// open over it), reading the landing here so the overview's body doesn't.
/// `still`: the overview's own part of being at rest.
struct LandingRest: View {
    let landing: Landing
    let still: Bool
    let rested: () -> Void

    private var atRest: Bool {
        still && landing.gliding == nil && landing.arrival >= 1 && landing.focus >= 1 && landing.heldCard == nil
    }

    var body: some View {
        Color.clear
            .onChange(of: atRest) { _, now in if now { rested() } }
    }
}
