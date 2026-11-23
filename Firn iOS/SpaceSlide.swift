import FirnCore
import SwiftUI

/// A sideways swipe on the overview's space name, shared by everything that
/// moves with it (David, 2026-11-23: the next space arrives under the
/// finger, as the next tab does on the address bar): the name's pills
/// (`OverviewBar`), the two spaces' tabs sliding side by side
/// (`SlidesWithSpace`), and the backdrop's color (`SpaceWash`).
///
/// The coming space is drawn by the overview's own code, from a read-only
/// copy of the tab list with that space in front (`BrowserStore.peek`), so
/// it is laid out exactly as the real one will be; nothing is shown,
/// woken, or loaded until the swipe lands. An object of its own, read only
/// by the small pieces that move, so following the finger doesn't run the
/// overview and its whole list again (as `Landing` and `Hold`).
@MainActor @Observable
final class SpaceSlide {
    /// How far the swipe has gone, as the pill's: 0 at rest, toward 1 as
    /// the finger moves right (the space before comes in from the left),
    /// toward -1 the other way.
    var progress: CGFloat = 0
    /// The space a swipe is heading for.
    var coming: Space?
    /// The spaces to either side, each drawn from its copy of the tab
    /// list, waiting a screen away. Made as a finger comes down on the
    /// name, before it moves, so they're laid out by the time they show
    /// (made as the swipe began, their first frames were still finding
    /// their size and scroll; the Simulator's recording, 2026-11-23).
    var peeks: [Peek] = []
    /// The real overview's size, for the copies' first layout.
    @ObservationIgnored var size: CGSize = .zero

    struct Peek: Identifiable {
        let space: Space
        let store: BrowserStore
        /// Which side it comes in from: 1 the left (the space before),
        /// -1 the right.
        let side: CGFloat
        /// Where its cards and list are, for its scroll at the swap.
        let spots = OverviewSpots()
        var id: UUID { space.id }
    }

    /// The coming space's copy, if it has one.
    var comingPeek: Peek? { peeks.first { $0.id == coming?.id } }
    /// The swipe has landed and the space has changed: the copy stands
    /// still in the middle for a few frames while the real list, unseen,
    /// takes the new space's tabs and scroll; then they swap in one frame.
    var settling = false
    /// The copy's own landing: shown and at rest, always.
    @ObservationIgnored let peekLanding: Landing = {
        let landing = Landing()
        landing.shown = true
        landing.arrival = 1
        landing.listIn = 1
        landing.forward = 1
        landing.focus = 1
        return landing
    }()

    /// How much of the coming space's color the backdrop shows.
    var mix: Double {
        guard coming != nil else { return 0 }
        return settling ? 1 : Double(min(abs(progress), 1))
    }

    func clear() {
        if coming != nil { coming = nil }
        if !peeks.isEmpty { peeks = [] }
        if settling { settling = false }
    }
}

/// The overview's list riding a swipe between spaces: the space on screen
/// slides off with the finger, and the coming one (`coming`, the copy) in
/// beside it, a screen's width apart, as two pages do. A transform only:
/// nothing is laid out again as it moves.
struct SlidesWithSpace: ViewModifier {
    let slide: SpaceSlide
    /// Set on a copy: the space it draws, and the side it waits on (1 the
    /// left, -1 the right). Nil on the real list.
    var copyOf: UUID?
    var side: CGFloat = 0
    /// A copy stays unseen for its first few frames, while its list finds
    /// its cards' sizes and its scroll: a flick that began the moment the
    /// finger touched showed those frames, cards in the wrong places (the
    /// Simulator's recording, 2026-11-23). A finger that rests on the name
    /// first, as most do, never meets the wait. On the list's contents, as
    /// every fade of them is: around the scroll view, a fade cut the cards
    /// under the bar on David's iPhone (`TabOverview`).
    var laidOut = true
    /// The overview's width.
    let width: CGFloat

    func body(content: Content) -> some View {
        let p = slide.progress
        // A copy waits a screen away on its side, wherever the finger is.
        let x = slide.settling ? 0 : (p - side) * width
        // Landed: only the coming space's copy shows, until the swap.
        let seen = laidOut && (slide.settling ? (copyOf != nil && copyOf == slide.coming?.id) : true)
        content
            .offset(x: x)
            .opacity(seen ? 1 : 0)
    }
}

/// The coming space's tabs, under the real list (they never overlap: one
/// slides off as the other slides in) and over the backdrop. Read here, so
/// a swipe starting runs only this, not the overview.
struct SpacePeekLayer: View {
    let slide: SpaceSlide
    let pictures: PagePictures
    let screenMiddle: CGPoint?

    var body: some View {
        ForEach(slide.peeks) { peek in
            TabOverview(store: peek.store, pictures: pictures, spots: peek.spots, landing: slide.peekLanding,
                        canvas: OverviewCanvas(), screenMiddle: screenMiddle,
                        actions: OverviewActions(open: { _ in }, done: {}, newTab: {}, key: []),
                        peeking: slide, peekSide: peek.side)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
