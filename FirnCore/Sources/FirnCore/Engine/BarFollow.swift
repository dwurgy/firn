import CoreGraphics

/// What your own scrolling says about the address bar on the iPhone, as
/// Safari's on iOS 27 (measured from David's recordings, 2026-11-23,
/// `docs/IOS-PLAN.md`, section 11): the bar first follows the finger a
/// little of the way, then finishes on its own. Scrolling down to read
/// shrinks it to its small pill; scrolling back up, or reaching the page's
/// top, grows it.
public enum BarScroll: Sendable, Equatable {
    /// Shrink the bar, or finish shrinking it.
    case shrink
    /// Grow the bar, or finish growing it.
    case grow
    /// The bar is on its way, following the finger: `lead` of the whole
    /// way so far, from 0 up to where it lets go and finishes on its own.
    case follow(shrink: Bool, lead: CGFloat)
    /// The finger turned back, or let go, before the bar let go: back to
    /// where it was.
    case back
}

/// Works out `BarScroll` from how far the page has scrolled. Only the
/// arithmetic: what counts as your own scrolling is the page view's to say.
public struct BarFollow: Sendable {
    /// One direction's distances, in points of scroll.
    public struct Turn: Sendable {
        /// Scrolled this far, nothing happens: a wobble never moves the bar.
        public var still: CGFloat
        /// Over this much more, the bar follows the finger...
        public var following: CGFloat
        /// ...this share of the whole way, where it lets go.
        public var share: CGFloat
    }

    /// Scrolling down: nothing for 15pt, then a third of the way over 30pt.
    public static let shrinking = Turn(still: 15, following: 30, share: 1.0 / 3)
    /// Scrolling up: nothing for 50pt, then a sixth of the way over 35pt.
    public static let growing = Turn(still: 50, following: 35, share: 1.0 / 6)

    /// The bar is its small pill (or on its way back from it).
    public private(set) var small: Bool
    /// How far the page has scrolled toward the bar's other size.
    private var travel: CGFloat = 0
    public private(set) var following = false

    public init(small: Bool = false) {
        self.small = small
    }

    /// The bar changed size some other way (a tap on the small pill, a new
    /// page). While it follows the finger, the change is its own.
    public mutating func rests(small: Bool) {
        guard !following, small != self.small else { return }
        self.small = small
        travel = 0
    }

    /// The page scrolled by `distance`, down the page being positive.
    public mutating func scrolled(by distance: CGFloat) -> BarScroll? {
        let turn = small ? Self.growing : Self.shrinking
        travel = max(travel + (small ? -distance : distance), 0)
        guard travel > turn.still else {
            // Turned back before the bar let go.
            guard following else { return nil }
            following = false
            return .back
        }
        let along = (travel - turn.still) / turn.following
        if along >= 1 {
            small.toggle()
            travel = 0
            following = false
            return small ? .shrink : .grow
        }
        following = true
        return .follow(shrink: !small, lead: along * turn.share)
    }

    /// Scrolling ended, or no longer counts.
    public mutating func stopped() -> BarScroll? {
        travel = 0
        guard following else { return nil }
        following = false
        return .back
    }

    /// The page is at its top, where the bar is always full.
    public mutating func reachedTop() -> BarScroll? {
        let was = (small, following)
        small = false
        following = false
        travel = 0
        // Following a shrink that never let go: back. Small, or growing: grow.
        if was.0 { return .grow }
        return was.1 ? .back : nil
    }
}
