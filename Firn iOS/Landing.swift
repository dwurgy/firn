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
    /// How much of the overview's list shows (`BrowserScreen.listIn`).
    var listIn: CGFloat = 0
    /// How far the overview has come forward (`ComesForward.through`).
    var forward: CGFloat = 0
    /// How far it has come into focus (`ComesForward.focus`).
    var focus: CGFloat = 0
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
        content.modifier(ArrivalBand(arrival: off ? 0 : landing[keyPath: value], range: range,
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

    func body(content: Content) -> some View {
        let listing = landing.listIn > 0
        content.modifier(ComesForward(through: landing.forward, focus: landing.focus, middle: middle, off: off,
                                      inScroll: inScroll, blurs: listing, scales: scalesWithList ? listing : true))
    }
}

/// The dim over the overview's cards, lifting as the page arrives.
struct LandingDim: View {
    let landing: Landing

    var body: some View {
        Theme.lookoutDim
            .ignoresSafeArea()
            .opacity(1 - landing.arrival)
            .allowsHitTesting(false)
    }
}

/// The overview softened once (`FrozenOverview`), fading out over the sharp
/// list as a tab lands; only while one glides.
struct LandingFrozen: View {
    let landing: Landing
    let image: UIImage
    let middle: CGPoint?

    var body: some View {
        if landing.gliding != nil {
            FrozenOverviewView(image: image)
                .opacity(1 - Double(min(max(landing.focus, 0), 1)))
                .modifier(LandingBand(landing: landing, value: \.listIn, range: 0...1))
                .modifier(LandingForward(landing: landing, middle: middle, off: false))
        }
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
