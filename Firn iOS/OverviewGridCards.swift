import SwiftUI
import UIKit

// The grid's tabs and groups as one UIKit collection view, so iOS's hold
// menu and iOS's drag are UIKit's own, as Safari's grid most likely is
// ("Plan: the grid as a UIKit collection view" and step 3 of "Plan: the
// drag polish", docs/IOS-PLAN.md). UIKit, not SwiftUI, because SwiftUI's
// `.reorderable()` shrank the dragged card to about half and had no way to
// ask for full size; UIKit's drop proposal does (`prefersFullSizePreview`).
// Each cell still draws Firn's own card (`OverviewRow`, through
// `UIHostingConfiguration`). Basecamp's tiles, runs of loose cards and
// folded groups, and each open group, are sections laid out by `GridPlan`.
// For now the collection view doesn't scroll: it sits in the overview's
// SwiftUI scroll view, as tall as everything in it.

/// A grid card's cell. Its own card hides the moment iOS's drag begins
/// (`dragStateDidChange`): iOS carries a picture of it, and on a quick drag
/// the cell left showing under it read as a second copy (David's recording,
/// 2026-11-16).
/// The card last touched sits above the rest, so a card swiped left to
/// close passes over its neighbor, never under it: the collection view
/// otherwise stacks cells in no set order, and a card could slide under the
/// one beside it, then snap in front (David's recording, 2026-11-17).
final class GridCardCell: UICollectionViewCell {
    private var raised = false {
        didSet { layer.zPosition = raised ? 1 : 0 }
    }
    /// Whether a touch raises it: only a card or a folder, which can pass
    /// over its neighbors. A folder tapped open was raised by that tap, and
    /// its cell becomes the group's name line: it comes back down.
    var raises = true {
        didSet { if !raises, raised { raised = false } }
    }
    /// The tab or group it shows, set as it's drawn. The grid finds a
    /// card's cell by this, never by where the cell sits: while cards are
    /// gliding to new places (and sections come and go under a carried
    /// card) a place can still answer with the cell that was there before.
    /// Asked by place, the carried card's cell was now and then another
    /// open group's name line, which was hidden and shown again, flashing
    /// for as long as the drag went on (David's recording, 2026-11-24).
    var item: UUID?
    /// The card the grid's drag is carrying, if one is (`dragStateDidChange`).
    var carried: (() -> UUID?)?
    /// A Basecamp tile let go, until its carried picture has landed: it
    /// stays hidden. UIKit takes its drag for over as the landing starts,
    /// and the tile showed in its place under the picture still coming
    /// down, two of it for a few frames (the Simulator, dark, 2026-11-24).
    var landing = false
    /// The swiped card easing home, so a new swipe can catch it mid-way.
    var settle: UIViewPropertyAnimator?
    /// Where a swipe has moved the card. The cell itself moves, not its
    /// content: UIKit sets the content's frame as SwiftUI redraws the card,
    /// and a frame set over a transform undid the slide (the Simulator,
    /// 2026-11-17). The collection view resets the cell's transform as it
    /// lays out, so `apply` puts it back.
    var swipe: CGAffineTransform = .identity {
        didSet { transform = swipe }
    }

    /// A swiped card's growth, apart from its slide (`swipe`) so each has
    /// its own curve: the growth a quick spring of its own as the swipe
    /// starts, the slide following the finger. On the cell's sublayer
    /// transform, which UIKit's layout never touches.
    ///
    /// A growth always finishes before the shrink starts, as Safari's: let
    /// go of a quick flick and its card still reaches its full size, then
    /// shrinks on the way home. Firn's shrank as the finger lifted, so a
    /// flick only grew 5 to 8% of its 9% (David's recording, 2026-11-18).
    func grow(to scale: CGFloat, stiffness: CGFloat) {
        let target = CATransform3DMakeScale(scale, scale, 1)
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        let now = CACurrentMediaTime()
        let grown = layer.sublayerTransform
        // Still growing toward a larger size: the shrink waits its turn.
        let wait = scale < grown.m11 ? max(0, grownAt + Self.fullGrowth - now) : 0
        layer.removeAnimation(forKey: "shrink")
        if wait == 0 { layer.removeAnimation(forKey: "grow") }
        if scale > 1 { grownAt = now }
        layer.sublayerTransform = target
        let start = wait > 0 ? grown : from
        guard !CATransform3DEqualToTransform(start, target) else { return }
        let spring = CASpringAnimation(keyPath: "sublayerTransform")
        spring.fromValue = NSValue(caTransform3D: start)
        spring.toValue = NSValue(caTransform3D: target)
        spring.mass = 1
        spring.stiffness = stiffness
        spring.damping = 2 * sqrt(stiffness)
        spring.duration = spring.settlingDuration
        if wait > 0 {
            // Added after the growth, so it takes over once it begins; until
            // then the growth carries on (nothing fills in before it).
            spring.beginTime = now + wait
            layer.add(spring, forKey: "shrink")
        } else {
            layer.add(spring, forKey: "grow")
        }
    }
    /// When the last growth began, and how long one takes to be (nearly)
    /// whole: the growth's spring is 97% there by 0.1s.
    private var grownAt: CFTimeInterval = 0
    private static let fullGrowth: CFTimeInterval = 0.1

    /// On top for a swipe, whether or not the finger's first touch raised it.
    func raise() {
        for case let other as GridCardCell in superview?.subviews ?? [] where other !== self {
            other.raised = false
        }
        raised = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        settle?.stopAnimation(true)
        settle = nil
        swipe = .identity
        layer.removeAnimation(forKey: "grow")
        layer.removeAnimation(forKey: "shrink")
        layer.sublayerTransform = CATransform3DIdentity
        contentView.alpha = 1
        contentView.mask = nil
        isUserInteractionEnabled = true
        landing = false
        raised = false
        raises = true
    }

    /// Tidied away (`Tidying`): its picture is gone at once, as the copy
    /// that sinks takes its place, and the title under it fades.
    func sink() {
        isUserInteractionEnabled = false
        let title = UIView(frame: CGRect(x: 0, y: bounds.height - OverviewRow.gridTitleHeight,
                                         width: bounds.width, height: OverviewRow.gridTitleHeight))
        title.backgroundColor = .black
        contentView.mask = title
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) { self.contentView.alpha = 0 }
    }

    /// Not tidied after all.
    func unsink() {
        contentView.mask = nil
        isUserInteractionEnabled = true
        contentView.alpha = 1
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil, event?.type == .touches, !raised, raises { raise() }
        return hit
    }

    /// The layout sets each cell's depth as it lays out; a raised card
    /// keeps its place on top.
    override func apply(_ attributes: UICollectionViewLayoutAttributes) {
        super.apply(attributes)
        if raised { layer.zPosition = 1 }
        transform = swipe
    }

    override func dragStateDidChange(_ state: UICollectionViewCell.DragState) {
        super.dragStateDidChange(state)
        // Hidden only once the drag has begun, and then at once. iOS takes
        // the picture it carries from the card on screen, between the lift
        // and the drag beginning: hidden at once as the lift began, drags
        // carried nothing (David's recording, 2026-11-17); faded from the
        // lift, the picture caught the card part way through its fade, a
        // pale ghost, fainter or stronger by chance (David's recording,
        // 2026-11-23). While it lifts, iOS's picture covers the card.
        guard state != .lifting else { return }
        // Only the carried card's own cell hides. On a quick drag UIKit
        // marks the dragged cell late and by its place, where a neighbor
        // that made room may already sit: it blinked out (a Basecamp tile,
        // the Simulator, 2026-11-24; `hideOnlyCarried` puts right the rest).
        if state != .none, let carried = carried?(), carried != item { return }
        // Its carried picture is still on its way down (`landing`).
        if state == .none, landing { return }
        UIView.performWithoutAnimation { contentView.alpha = state == .none ? 1 : 0 }
        contentView.layer.removeAnimation(forKey: "opacity")
    }
}

/// Where a grid card is in a swipe to close (`GridCards`): `swiping`, then
/// `easingHome`. Its spot isn't reported until it's home again (`none`).
enum GridSwipe: Equatable {
    case none, swiping, easingHome
}

/// The grid's tabs and groups, as one UIKit collection view: runs of loose
/// cards (and folded groups), and each open group a section of its own
/// (`GridPlan`).
struct GridCards: UIViewRepresentable {
    /// The runs and open groups, in order.
    let sections: [GridPlan.Section]
    let columns: Int
    let cardHeight: CGFloat
    /// A card's height inside an open group.
    let groupCardHeight: CGFloat
    /// An open group's glass card, behind its name line and tabs.
    let groupCard: (UUID) -> AnyView
    /// A card, drawn by the overview as everywhere else.
    let card: (UUID) -> AnyView
    /// The card's hold menu, made as it opens.
    let menu: (UUID) -> [[HoldMenuItem]]
    /// A card held (its menu open, or carried by the drag), so its X hides:
    /// iOS lifts only the picture, as Safari's.
    let held: (UUID, Bool) -> Void
    /// A card let go before another (nil: at the end), among an open
    /// group's tabs, or in the run after an open group (nil: the first run).
    let move: (_ id: UUID, _ before: UUID?, _ group: UUID?, _ after: UUID?) -> Void
    /// A card's swipe to close moving on.
    let swipe: (UUID, GridSwipe) -> Void
    /// A card swiped off: its tab closes.
    let close: (UUID) -> Void
    /// What a cell is. Only a card swipes to close; a carried tab can be
    /// put into a folder (step 4 of "a folded group is one tab's size").
    /// A Basecamp tile let go at a new place among the tiles (counted
    /// without it), or a tab let go there: it becomes a tile.
    var moveTile: (UUID, Int) -> Void = { _, _ in }
    /// Whether a tab may become a tile: Basecamp has room, and the tab has
    /// an address to call home.
    var fitsBasecamp: (UUID) -> Bool = { _ in false }
    /// A tab let go over a Basecamp that wouldn't take it.
    var basecampRefused: () -> Void = {}
    var kind: (UUID) -> GridCellKind = { _ in .card }
    /// A tab let go on a folded group: it goes into the group, at its end.
    var join: (UUID, UUID) -> Void = { _, _ in }
    /// A folded group's card, solid, whether or not the group is folded:
    /// what's carried when an open group is moved by its name line.
    var folderPicture: (UUID) -> AnyView = { _ in AnyView(EmptyView()) }
    /// An open group picked up by its name line: it folds at once, with no
    /// glide of its own, and is carried as a folded group is.
    var carry: (UUID) -> Void = { _ in }
    /// That group is down: it opens where it landed.
    var landed: (UUID) -> Void = { _ in }
    /// A group folding or opening (`GroupGlide`'s token): cards change
    /// grids at once, with no fade or slide of the collection view's own,
    /// since the glide is drawn over the list (`GroupGlideView`).
    var fold: UUID?
    /// Cards are going unseen (`Tidying`): nothing glides.
    var still = false

    /// A group's fold and unfold: Safari's, a little over 0.4s with a soft
    /// end, no bounce (David's recording, 2026-11-18).
    static let morphDuration: TimeInterval = 0.42
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Every run's collection view, so a fold can note where each card is.
    @MainActor private static var live = NSHashTable<UICollectionView>.weakObjects()

    /// Each card on screen and its frame in the window, in every run: read
    /// from the cells themselves, so a card scrolled away never counts.
    @MainActor static func framesOnScreen() -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for view in live.allObjects where view.window != nil {
            for case let cell as GridCardCell in view.visibleCells {
                guard let id = cell.item else { continue }
                frames[id] = cell.convert(cell.bounds, to: nil)
            }
        }
        return frames
    }

    /// The cells showing these cards, in every run.
    @MainActor static func cells(_ ids: Set<UUID>) -> [UUID: GridCardCell] {
        var cells: [UUID: GridCardCell] = [:]
        for view in live.allObjects where view.window != nil {
            for case let cell as GridCardCell in view.visibleCells {
                if let id = cell.item, ids.contains(id) { cells[id] = cell }
            }
        }
        return cells
    }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: GridPlanLayout())
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.clipsToBounds = false
        view.allowsSelection = false
        view.dragInteractionEnabled = true
        view.reorderingCadence = .fast
        Self.live.add(view)
        context.coordinator.attach(to: view)
        context.coordinator.update(self, in: view)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.update(self, in: view)
    }

    /// As tall as everything in it: the overview's scroll view scrolls it.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICollectionView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        let plan = GridPlan(sections: sections, width: width, columns: columns, cardHeight: cardHeight,
                            groupCardHeight: groupCardHeight)
        return CGSize(width: width, height: max(plan.height, context.coordinator.floor))
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate,
        UICollectionViewDropDelegate, UIGestureRecognizerDelegate {
        private var dataSource: UICollectionViewDiffableDataSource<GridSectionID, UUID>?
        private var parent: GridCards?
        /// What the collection view shows: the store's order, or a drop's
        /// before the store catches up.
        private var shown: [GridPlan.Section] = []
        /// Where a card sits in `shown`: its section (a run or an open
        /// group) and its place among that section's cards. Never a group's
        /// name line, which is no card.
        private func spot(of id: UUID) -> (section: Int, place: Int)? {
            for (s, section) in shown.enumerated() {
                if let place = section.ids.firstIndex(of: id) { return (s, place) }
            }
            return nil
        }
        /// A card's cell: in an open group, the name line comes first.
        private func path(_ section: Int, _ place: Int, in sections: [GridPlan.Section]) -> IndexPath {
            IndexPath(item: place + (sections[section].group == nil ? 0 : 1), section: section)
        }
        /// An open group carried by its name line (part 3 of step 3): it
        /// folds as its drag begins (`awaiting` until the overview shows it
        /// folded) and opens again once it's down (`reopen`). iOS lifted
        /// only the name line, so the drag is handed a picture of the
        /// group's folder card as it begins (`carryFolder`).
        private var reopen: UUID?
        private var awaiting: UUID?
        /// The grid stays at least this tall while a card is carried. A
        /// group folding as it's picked up (or a tab leaving a row of its
        /// own) makes the list shorter; near the list's end the overview
        /// then scrolled by itself, and everything jumped under the finger
        /// (David's recording, 2026-11-24).
        fileprivate(set) var floor: CGFloat = 0
        /// The drop has saved where the card sits (`settle`), so the drag's
        /// end doesn't save it again.
        private var landed = false
        /// The card iOS's drag carries, until it's down: set only once the
        /// drag has really begun (`dragSessionWillBegin`).
        private var carried: UUID?
        /// The card iOS asked to lift, before its drag begins. iOS asks as
        /// a hold starts; a hold that ends as a menu, or is let go, never
        /// begins a drag and never says it ended. Taken as carried, it
        /// refused every swipe from then on (David, 2026-11-17).
        private var lifting: UUID?
        /// From the finger to the carried card's middle, as it was grabbed.
        private var grabOffset = CGVector.zero
        /// Follows the carried card every frame (`watch`, `followed`).
        private var following: CADisplayLink?
        private weak var followedView: UICollectionView?
        private var followedDrag: (any UIDragSession)?
        /// When the finger last came down, for telling a swipe from a hold.
        private var touchedAt: TimeInterval = 0
        /// How long after the finger comes down a move sideways may still be
        /// a swipe; later, it's iOS's hold and drag (Safari's way). Swiping
        /// there too ran the two together: the card slid, then iOS's drag
        /// lifted it anyway and the swipe snapped back (David's recording,
        /// 2026-11-17).
        private static let swipeWindow: TimeInterval = 0.25
        /// iOS's hold menu is showing.
        private var menuShown = false
        /// The swipe to close (`swiped`).
        private let sideways = UIPanGestureRecognizer()
        /// The card being swiped, until it's let go.
        private var swiping: (id: UUID, cell: GridCardCell, start: CGFloat)?

        func attach(to view: UICollectionView) {
            let cell = UICollectionView.CellRegistration<GridCardCell, UUID> { [weak self] cell, _, id in
                self?.configure(cell, id)
            }
            dataSource = UICollectionViewDiffableDataSource(collectionView: view) { view, path, id in
                view.dequeueConfiguredReusableCell(using: cell, for: path, item: id)
            }
            let card = UICollectionView.SupplementaryRegistration<GridGroupCardView>(
                elementKind: GridPlanLayout.cardKind) { [weak self] view, _, path in
                self?.configure(view, section: path.section)
            }
            dataSource?.supplementaryViewProvider = { view, _, path in
                view.dequeueConfiguredReusableSupplementary(using: card, for: path)
            }
            view.delegate = self
            view.dragDelegate = self
            view.dropDelegate = self
            sideways.delegate = self
            // The card's own button lets go of the touch once the card moves.
            sideways.cancelsTouchesInView = true
            sideways.delaysTouchesEnded = false
            sideways.addTarget(self, action: #selector(swiped))
            view.addGestureRecognizer(sideways)
        }

        // MARK: The swipe to close

        // The swipe to close is UIKit's, on the collection view, beside
        // iOS's press, menu, and drag, so only one of them ever has a card.
        // It was SwiftUI's, inside the card, and the two never knew of each
        // other: caught as iOS began its lift, the swipe slid a card iOS
        // was fading, so it went see-through and seemed to pass under its
        // neighbor (David's recordings, 2026-11-17). Here a swipe that
        // starts calls iOS's press off, a card iOS has lifted or opened a
        // menu on takes no swipe, and a card being swiped gets no menu or
        // drag. The card moves by its layer alone (a transform on the
        // cell's content), eased home by the render server; SwiftUI
        // runs only as its phase changes.

        /// How much a swiped card grows: Safari's, about 9% (516 to 564px
        /// wide in David's recording, 2026-11-17), two thirds there in
        /// 0.03s and all there by about 0.07s, then held (measured frame by
        /// frame; stiffness 650 took 0.17s and read as stiff); it shrinks
        /// slowly on the ease home's soft spring. It followed the finger's
        /// first 24pt before, and read as a stepped resize.
        private static let growth: CGFloat = 1.09
        private static let growStiffness: CGFloat = 3000
        /// Going right (nothing to close that way), the card still follows
        /// almost fully, with a little give further out: Safari's went 97pt
        /// to the right against 112pt to the left (David's recording,
        /// 2026-11-17), where Firn's 40% stopped at 45pt and felt stiff.
        private static let rightGive: CGFloat = 700
        private static func rightward(_ dx: CGFloat) -> CGFloat { dx * rightGive / (dx + rightGive) }
        /// The ease home, shrinking as it goes: a spring with no bounce and
        /// Safari's pace, measured from David's recordings (2026-11-17):
        /// halfway home in about 0.15s, nearly there by 0.4s, a 0.56s
        /// response (stiffness (2π / 0.56)² ≈ 125). Firn's 0.45s animator
        /// got there in half that and read as stiff. A second recording,
        /// tracked frame by frame (2026-11-17), put Safari's a touch
        /// quicker: 66% of the way left at 0.1s, 28% at 0.2s, 9% at 0.3s,
        /// a critically damped spring of about 170.
        private static let homeStiffness: CGFloat = 170

        @objc private func swiped(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view as? UICollectionView else { return }
            switch pan.state {
            case .began:
                guard carried == nil, !menuShown,
                      let path = view.indexPathForItem(at: pan.location(in: view)),
                      let id = dataSource?.itemIdentifier(for: path),
                      let cell = view.cellForItem(at: path) as? GridCardCell else { return }
                // iOS's press for its menu or a drag, called off: left
                // running, it held the card in a frame the size of its
                // picture, cutting the swiped card at its old edge.
                for other in view.gestureRecognizers ?? [] where other !== pan && other.isEnabled {
                    other.isEnabled = false
                    other.isEnabled = true
                }
                // Only cards swipe (`gestureRecognizerShouldBegin`).
                cell.raise()
                // Caught while easing home: it carries on from where it is.
                cell.settle?.stopAnimation(true)
                cell.settle = nil
                cell.swipe = cell.transform
                if parent?.reduceMotion != true { cell.grow(to: Self.growth, stiffness: Self.growStiffness) }
                swiping = (id, cell, cell.swipe.tx - pan.translation(in: view).x)
                parent?.swipe(id, .swiping)
            case .changed:
                guard let swipe = swiping else { return }
                follow(swipe.cell, dx: swipe.start + pan.translation(in: view).x)
            case .ended:
                let dx = (swiping?.start ?? 0) + pan.translation(in: view).x
                letGo(dx: dx, speed: pan.velocity(in: view).x)
            default:
                letGo(dx: 0, speed: 0)
            }
        }

        /// Left, the card stays under the finger; right, it follows with
        /// some give (Safari's). It grows as it starts and stays grown
        /// either way until let go.
        private func follow(_ cell: GridCardCell, dx: CGFloat) {
            cell.swipe = CGAffineTransform(translationX: dx < 0 ? dx : Self.rightward(dx), y: 0)
        }

        /// Past a third of the card, or a flick left, it slides off and its
        /// tab closes; otherwise it eases home.
        private func letGo(dx: CGFloat, speed: CGFloat) {
            guard let (id, cell, _) = swiping else { return }
            swiping = nil
            let far = -dx > cell.bounds.width / 3
            let flick = speed < -700 && dx < -20
            guard far || flick, carried == nil else {
                // The card's own speed: the finger's going left, the give's
                // share of it going right.
                let share = Self.rightGive / (max(dx, 0) + Self.rightGive)
                easeHome(id, cell, speed: dx < 0 ? speed : speed * share * share)
                return
            }
            let close = { [weak self] in
                self?.parent?.swipe(id, .none)
                self?.parent?.close(id)
                // Not closed after all (the overview was busy): back home.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, shown.contains(where: { $0.ids.contains(id) }) else { return }
                    cell.swipe = .identity
                    cell.grow(to: 1, stiffness: Self.homeStiffness)
                    cell.contentView.alpha = 1
                }
            }
            if parent?.reduceMotion == true {
                // A fade where it stands, no slide.
                let fade = UIViewPropertyAnimator(duration: 0.2, curve: .easeOut) { cell.contentView.alpha = 0 }
                fade.addCompletion { _ in close() }
                fade.startAnimation()
                return
            }
            // Off the left edge at the flick's pace, then closed.
            // Where the card's right edge would be unmoved, in the window.
            let gone = -(cell.superview?.convert(cell.center, to: nil).x ?? 0) - cell.bounds.width / 2 - 40
            let duration = min(0.25, max(0.12, Double((gone - cell.swipe.tx) / min(speed, -900))))
            let slide = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                cell.swipe = CGAffineTransform(translationX: gone, y: 0)
            }
            slide.addCompletion { _ in close() }
            slide.startAnimation()
        }

        /// The card eases home and shrinks together, unhurried, its title
        /// and X coming back on the same ease.
        /// It carries the finger's speed as it's let go, as Safari's: a card
        /// thrown outward drifts on a moment before it turns home, rather
        /// than starting from a standstill.
        private func easeHome(_ id: UUID, _ cell: GridCardCell, speed: CGFloat = 0) {
            parent?.swipe(id, .easingHome)
            // UIKit takes the starting speed as a share of the way left to
            // go, per second; capped so a card let go almost home can't fly.
            let away = cell.swipe.tx
            let share = abs(away) > 1 ? min(max(-speed / away, -12), 12) : 0
            let spring = UISpringTimingParameters(mass: 1, stiffness: Self.homeStiffness,
                                                  damping: 2 * sqrt(Self.homeStiffness),
                                                  initialVelocity: CGVector(dx: share, dy: share))
            let home = UIViewPropertyAnimator(duration: 0, timingParameters: spring)
            home.addAnimations { cell.swipe = .identity }
            // Shrinking on the same spring, so it settles as one motion.
            cell.grow(to: 1, stiffness: Self.homeStiffness)
            home.addCompletion { [weak self, weak cell] _ in
                guard let cell, cell.settle === home else { return }
                cell.settle = nil
                self?.parent?.swipe(id, .none)
            }
            cell.settle = home
            home.startAnimation()
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === sideways else { return true }
            // A card iOS has lifted or opened its menu on is theirs, and so
            // is a card held a moment before it moved.
            guard carried == nil, !menuShown,
                  ProcessInfo.processInfo.systemUptime - touchedAt < Self.swipeWindow else { return false }
            if let view = sideways.view as? UICollectionView,
               let path = view.indexPathForItem(at: sideways.location(in: view)),
               let id = dataSource?.itemIdentifier(for: path), parent?.kind(id) != .card { return false }
            let speed = sideways.velocity(in: sideways.view)
            return abs(speed.x) > abs(speed.y)
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gesture === sideways, touch.phase == .began {
                touchedAt = touch.timestamp
                // A new finger with no drag under way: anything left from
                // a hold that never became a drag is let go.
                if let view = gesture.view as? UICollectionView, !view.hasActiveDrag { forgetHold() }
            }
            return true
        }

        /// Alongside iOS's press on the collection view (until it's called
        /// off), and nothing else: once a swipe starts, the card's own tap
        /// fails (or letting go would open the tab), and the overview
        /// doesn't scroll.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard gesture === sideways || other === sideways else { return false }
            let pair = gesture === sideways ? other : gesture
            return pair.view === sideways.view && pair !== (sideways.view as? UIScrollView)?.panGestureRecognizer
        }

        private func configure(_ cell: UICollectionViewCell, _ id: UUID) {
            guard let parent else { return }
            cell.backgroundConfiguration = .clear()
            cell.clipsToBounds = false
            (cell as? GridCardCell)?.item = id
            (cell as? GridCardCell)?.carried = { [weak self] in self?.carried }
            (cell as? GridCardCell)?.raises = parent.kind(id) != .line
            cell.contentConfiguration = UIHostingConfiguration {
                parent.card(id)
            }.margins(.all, 0)
        }

        private func configure(_ card: GridGroupCardView, section: Int) {
            guard let parent, section < shown.count, let group = shown[section].group else { return }
            card.show(UIHostingConfiguration { parent.groupCard(group) }.margins(.all, 0))
        }

        func update(_ new: GridCards, in view: UICollectionView) {
            parent = new
            if let layout = view.collectionViewLayout as? GridPlanLayout,
               layout.columns != new.columns || layout.cardHeight != new.cardHeight
               || layout.groupCardHeight != new.groupCardHeight {
                layout.columns = new.columns
                layout.cardHeight = new.cardHeight
                layout.groupCardHeight = new.groupCardHeight
                layout.invalidateLayout()
            }
            // Not while a card is carried: the drag's own order stands until
            // it's down (a card may be between sections, in a run made for
            // it), and the store's comes with the drop.
            // Except a group picked up by its name line, now folded.
            let folded = awaiting.map { id in !new.sections.contains { $0.group == id } } ?? false
            if folded, let id = awaiting, let section = shown.firstIndex(where: { $0.group == id }) {
                // Its tabs and glass go at once, the cards around closing
                // up: fading, the glass went dark grey on its way out (the
                // Simulator, 2026-11-24).
                view.supplementaryView(forElementKind: GridPlanLayout.cardKind,
                                       at: IndexPath(item: 0, section: section))?.alpha = 0
                for tab in shown[section].ids { cell(for: tab, in: view)?.contentView.alpha = 0 }
            }
            if folded { awaiting = nil }
            if new.sections != shown, (carried == nil && settling == nil) || folded {
                // Another space's cards (none shared with these) take their
                // place at once: animated, UIKit faded the new ones in over
                // a quarter second, a dim flash after a swipe between spaces
                // had already slid them in (David's recording, 2026-11-23).
                let old = Set(shown.flatMap(\.items))
                let related = new.sections.contains { !old.isDisjoint(with: $0.items) }
                // A card closed: the next slides into its place (0.25s, as
                // the list). A fold or unfold lands at once: its glide is
                // drawn over the list.
                show(new.sections, in: view, animated: new.fold == nil && !new.still && !new.reduceMotion
                     && view.window != nil && related)
            }
            // Cards show what's new (the X hiding, a new title, a picture),
            // and a group's cell what it now is (a folder, or its name line).
            // Each by the card it shows (`GridCardCell.item`), not its place.
            for case let cell as GridCardCell in view.visibleCells {
                if let id = cell.item { configure(cell, id) }
            }
            for path in view.indexPathsForVisibleSupplementaryElements(ofKind: GridPlanLayout.cardKind) {
                if let card = view.supplementaryView(forElementKind: GridPlanLayout.cardKind, at: path)
                    as? GridGroupCardView {
                    configure(card, section: path.section)
                }
            }
            // A redrawn cell comes back showing: the carried one hides again.
            hideOnlyCarried(in: view)
        }

        /// The drag carries a picture of the group's folder card from here
        /// on: a solid card drawn for the purpose, since iOS lifted only
        /// the name line. Not the folder's own cell: glass pictured apart
        /// from the screen comes out a flat dark grey (the Simulator), and
        /// a picture of the cell taken a turn after it folded was all but
        /// invisible on David's iPhone (his recording, 2026-11-24).
        private func carryFolder(_ id: UUID, as item: UIDragItem, in view: UICollectionView) {
            guard let parent, let layout = view.collectionViewLayout as? GridPlanLayout else { return }
            let count = CGFloat(max(layout.columns, 1))
            let size = CGSize(width: max((view.bounds.width - OverviewGridMetrics.spacing * (count - 1)) / count, 1),
                              height: layout.cardHeight)
            let dark = view.traitCollection.userInterfaceStyle == .dark
            let renderer = ImageRenderer(content: parent.folderPicture(id)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = view.traitCollection.displayScale
            guard let image = renderer.uiImage else { return }
            let picture = UIImageView(image: image)
            picture.frame = CGRect(origin: .zero, size: size)
            let window = CGRect(x: 0, y: 0, width: size.width,
                                height: max(size.height - OverviewRow.gridTitleHeight, 1))
            folderAsked = false
            let provider: () -> UIDragPreview? = { [weak self] in
                MainActor.assumeIsolated {
                    self?.folderAsked = true
                    let parameters = UIDragPreviewParameters()
                    parameters.visiblePath = UIBezierPath(roundedRect: window,
                                                          cornerRadius: OverviewRow.gridCornerRadius)
                    parameters.backgroundColor = .clear
                    return UIDragPreview(view: picture, parameters: parameters)
                }
            }
            item.previewProvider = provider
            folderPreview = (item, provider)
        }

        /// The folder picture a carried group's drag was handed, while it's
        /// carried, and whether iOS has asked for it yet.
        private var folderPreview: (item: UIDragItem, provider: () -> UIDragPreview?)?
        private var folderAsked = false
        private var folderWait = 0

        /// Handed over again until iOS asks for it: a drag that begins from
        /// the hold menu went on carrying the menu's picture of the name
        /// line, the new one unasked for, for a second or for the whole
        /// drag (the Simulator, 2026-11-24). Every tenth frame of the carry
        /// (`followed`), and as the menu has gone.
        private func carryFolderAgain() {
            guard carried != nil, !folderAsked, let (item, provider) = folderPreview else { return }
            item.previewProvider = provider
        }

        /// The collection view shows these sections; the layout hears first,
        /// since it's asked for the new places as the cells change.
        private func show(_ sections: [GridPlan.Section], in view: UICollectionView, animated: Bool) {
            shown = sections
            (view.collectionViewLayout as? GridPlanLayout)?.sections = sections
            var snapshot = NSDiffableDataSourceSnapshot<GridSectionID, UUID>()
            for section in sections {
                snapshot.appendSections([section.id])
                snapshot.appendItems(section.items, toSection: section.id)
            }
            dataSource?.apply(snapshot, animatingDifferences: animated)
            hideOnlyCarried(in: view)
            DispatchQueue.main.async { [weak self, weak view] in
                if let view { self?.hideOnlyCarried(in: view) }
            }
        }

        /// While a card is carried, its own cell is the only one hidden.
        /// As the carried card changed sections, UIKit took another cell
        /// for the dragged one: the tab left behind in a group vanished
        /// until the drop (the Simulator's recording, 2026-11-24).
        private func hideOnlyCarried(in view: UICollectionView, showing landed: UUID? = nil) {
            if let landed {
                UIView.performWithoutAnimation {
                    cell(for: landed, in: view)?.contentView.alpha = 1
                    cell(for: landed, in: view)?.alpha = 1
                }
            }
            guard let carried else { return }
            UIView.performWithoutAnimation {
                for case let cell as GridCardCell in view.visibleCells where cell.item != revealed {
                    let alpha: CGFloat = cell.item == carried ? 0 : 1
                    if cell.contentView.alpha != alpha { cell.contentView.alpha = alpha }
                    // UIKit's own dim of the cell it takes for the dragged one.
                    if cell.item != carried, cell.alpha != 1 { cell.alpha = 1 }
                }
            }
        }

        /// The card's picture, without its title: what iOS lifts, for its
        /// menu and its drag, as Safari's.
        private func picture(_ view: UICollectionView, _ path: IndexPath) -> UIPreviewParameters? {
            guard let cell = view.cellForItem(at: path) else { return nil }
            let bounds = cell.bounds
            let parameters = UIPreviewParameters()
            let kind = dataSource?.itemIdentifier(for: path).flatMap { parent?.kind($0) }
            if kind == .tile {
                // A Basecamp tile lifts whole.
                parameters.visiblePath = UIBezierPath(roundedRect: bounds, cornerRadius: BasecampTiles.cornerRadius)
            } else if kind == .line {
                // A group's name line lifts whole, rounded as its card.
                parameters.visiblePath = UIBezierPath(roundedRect: bounds,
                                                      cornerRadius: min(GroupCard.cornerRadius, bounds.height / 2))
            } else {
                let window = CGRect(x: 0, y: 0, width: bounds.width,
                                    height: max(bounds.height - OverviewRow.gridTitleHeight, 1))
                parameters.visiblePath = UIBezierPath(roundedRect: window,
                                                      cornerRadius: OverviewRow.gridCornerRadius)
            }
            parameters.backgroundColor = .clear
            return parameters
        }

        // MARK: iOS's hold menu

        func collectionView(_ view: UICollectionView, contextMenuConfigurationForItemsAt paths: [IndexPath],
                            point: CGPoint) -> UIContextMenuConfiguration? {
            // A card being swiped gets no menu.
            guard swiping == nil, let path = paths.first, let id = dataSource?.itemIdentifier(for: path),
                  let parent else { return nil }
            return UIContextMenuConfiguration(identifier: id as NSUUID, previewProvider: nil) { _ in
                UIMenu(children: parent.menu(id).map { section in
                    UIMenu(options: .displayInline, children: section.map(Self.element))
                })
            }
        }

        /// Firn's choices as UIKit's: the same words and symbols. Close rows
        /// in iOS's destructive red, as every app's (David, 2026-11-17).
        private static func element(_ item: HoldMenuItem) -> UIMenuElement {
            let image = item.systemImage.flatMap { UIImage(systemName: $0) }
            if !item.children.isEmpty {
                return UIMenu(title: item.title, image: image, children: item.children.map(element))
            }
            let action = item.action
            return UIAction(title: item.title, image: image, attributes: item.closes ? .destructive : []) { _ in
                MainActor.assumeIsolated { action() }
            }
        }

        func collectionView(_ view: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                            highlightPreviewForItemAt path: IndexPath) -> UITargetedPreview? {
            guard let cell = view.cellForItem(at: path), let parameters = picture(view, path) else { return nil }
            return UITargetedPreview(view: cell, parameters: parameters)
        }

        func collectionView(_ view: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                            dismissalPreviewForItemAt path: IndexPath) -> UITargetedPreview? {
            self.collectionView(view, contextMenuConfiguration: configuration, highlightPreviewForItemAt: path)
        }

        func collectionView(_ view: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration,
                            animator: (any UIContextMenuInteractionAnimating)?) {
            guard let id = configuration.identifier as? UUID else { return }
            menuShown = true
            parent?.held(id, true)
        }

        func collectionView(_ view: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                            animator: (any UIContextMenuInteractionAnimating)?) {
            guard let id = configuration.identifier as? UUID else { return }
            menuShown = false
            let back = { [weak self, weak view] in
                // Carried on by the drag: its X stays hidden until it's down.
                self?.carryFolderAgain()
                guard let self, carried != id, view?.hasActiveDrag != true else { return }
                if lifting == id { lifting = nil }
                parent?.held(id, false)
            }
            if let animator { animator.addCompletion(back) } else { back() }
        }

        // MARK: iOS's drag

        func collectionView(_ view: UICollectionView, itemsForBeginning session: any UIDragSession,
                            at path: IndexPath) -> [UIDragItem] {
            // A card being swiped isn't lifted.
            guard swiping == nil, let id = dataSource?.itemIdentifier(for: path), let parent else { return [] }
            let line = parent.kind(id) == .line
            guard line || spot(of: id) != nil else { return [] }
            lifting = id
            grabbedAt = session.location(in: view).y
            if let cell = view.cellForItem(at: path) {
                let finger = session.location(in: view)
                grabOffset = CGVector(dx: cell.center.x - finger.x, dy: cell.center.y - finger.y)
                carriedSize = parent.kind(id) == .tile ? cell.bounds.size
                    : CGSize(width: cell.bounds.width,
                             height: max(cell.bounds.height - OverviewRow.gridTitleHeight, 1))
            } else {
                grabOffset = .zero
                carriedSize = .zero
            }
            parent.held(id, true)
            // Firn's own: never to another app (no address handed over).
            let item = UIDragItem(itemProvider: NSItemProvider())
            item.localObject = id
            // A name line is carried as its group's folder card, which
            // sits under the finger wherever the line was grabbed.
            if line {
                grabOffset = .zero
                // Its picture for the drag is handed over now, as the hold
                // starts: iOS then takes it as the drag begins. Handed over
                // once the drag had begun, iOS went on carrying the name
                // line, off to one side, until the finger came to rest (the
                // Simulator, 2026-11-24).
                carryFolder(id, as: item, in: view)
            }
            session.localContext = ObjectIdentifier(self)
            return [item]
        }

        func collectionView(_ view: UICollectionView, dragSessionWillBegin session: any UIDragSession) {
            // The card is read from the drag itself, not from `lifting`: on
            // a quick hold and drag, iOS's menu press ends just before the
            // drag begins, and tidying up after it forgot the card being
            // lifted. Nothing was carried then, so no card made room for
            // the whole drag and the card flew back to where it came from
            // (the Simulator's log, 2026-11-23).
            carried = session.items.first?.localObject as? UUID ?? lifting
            lifting = nil
            landed = false
            stay = nil
            refused = false
            floor = view.bounds.height
            if let carried { parent?.held(carried, true) }
            if let carried, parent?.kind(carried) == .line {
                reopen = carried
                awaiting = carried
                parent?.carry(carried)
            }
            watch(session, in: view)
        }

        /// A hold that never became a drag: its card shows its X again, and
        /// swipes are taken again.
        private func forgetHold() {
            if let id = lifting, !menuShown { parent?.held(id, false) }
            if !menuShown { lifting = nil }
            if let id = carried { parent?.held(id, false) }
            carried = nil
        }

        func collectionView(_ view: UICollectionView,
                            dragSessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { true }

        func collectionView(_ view: UICollectionView, dragPreviewParametersForItemAt path: IndexPath) -> UIDragPreviewParameters? {
            dragParameters(view, path)
        }

        func collectionView(_ view: UICollectionView, dropPreviewParametersForItemAt path: IndexPath) -> UIDragPreviewParameters? {
            dragParameters(view, path)
        }

        private func dragParameters(_ view: UICollectionView, _ path: IndexPath) -> UIDragPreviewParameters? {
            guard let picture = picture(view, path) else { return nil }
            let parameters = UIDragPreviewParameters()
            parameters.visiblePath = picture.visiblePath
            parameters.backgroundColor = .clear
            return parameters
        }

        func collectionView(_ view: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
            unwatch()
            // Let go outside the grid: it stays where it was last moved to.
            let down = carried
            if let id = down, !landed { settle(id) }
            if refused { parent?.basecampRefused() }
            refused = false
            carried = nil
            lifting = nil
            // After `carried` is cleared: the overview's redraw then takes
            // the store's order (a group left empty is gone).
            if let id = down { parent?.held(id, false) }
            awaiting = nil
            folderPreview = nil
            // The grid may be its own height again once the group has
            // opened where it landed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak view] in
                guard let self, carried == nil else { return }
                settling = nil
                revealed = nil
                floor = 0
                view?.invalidateIntrinsicContentSize()
            }
            // The group opens once iOS's picture has landed (`performDrop`);
            // let go outside the grid, or if iOS never says it landed, from
            // here.
            DispatchQueue.main.asyncAfter(deadline: .now() + (landing ? 1.2 : 0)) { [weak self] in
                self?.reopenNow()
            }
            // Every card shown again once the drop has landed: a card hidden
            // while carried stayed invisible once (David, 2026-11-17, not
            // caught on a recording), likely never told its drag had ended.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak view] in
                guard let self, carried == nil, let view else { return }
                // A card that has two cells shows only its own: the other is
                // one the grid has done with and not yet taken away. A group
                // carried by its name line left that line's cell behind,
                // hidden, and showing "every cell" brought a scrap of the
                // name back over the opened group for a moment (the
                // Simulator, 2026-11-24).
                let cells = view.visibleCells.compactMap { $0 as? GridCardCell }
                let shared = Dictionary(grouping: cells.compactMap(\.item)) { $0 }.filter { $0.value.count > 1 }
                for cell in cells {
                    if let id = cell.item, shared[id] != nil {
                        let own = dataSource?.indexPath(for: id).flatMap { view.cellForItem(at: $0) }
                        cell.contentView.alpha = own === cell ? 1 : 0
                    } else {
                        cell.contentView.alpha = 1
                    }
                }
            }
        }

        // MARK: Putting it down

        func collectionView(_ view: UICollectionView, canHandle session: any UIDropSession) -> Bool {
            session.localDragSession?.localContext as? ObjectIdentifier == ObjectIdentifier(self)
        }

        func collectionView(_ view: UICollectionView, dropSessionDidUpdate session: any UIDropSession,
                            withDestinationIndexPath path: IndexPath?) -> UICollectionViewDropProposal {
            guard session.localDragSession?.localContext as? ObjectIdentifier == ObjectIdentifier(self) else {
                return UICollectionViewDropProposal(operation: .forbidden)
            }
            // Firn makes room itself (`makeRoom`), not UIKit: UIKit's own
            // room-making ticks a haptic at every spot and again on letting
            // go, with no way to turn it off; Safari's grid only taps once,
            // on the grab (David, 2026-11-17).
            // The spot is the one nearest the carried card's middle, found
            // at once: UIKit's own destination waits for the finger to
            // settle, so the carried card sat over its neighbor about 0.4s
            // before it moved, where Safari's moves as the card arrives
            // (David's recording beside Safari's, 2026-11-17). Its middle,
            // not the finger: a card grabbed near an edge had to go almost
            // a whole card before the finger reached the next, and between
            // cards nothing moved (David, 2026-11-17).
            follow(session.location(in: view), in: view)
            let proposal = UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            // The card stays its own size as it's carried, as Safari's: the
            // one thing SwiftUI's reorder couldn't ask for.
            proposal.prefersFullSizePreview = true
            return proposal
        }

        /// Room is made where the carried card now is, or a folded group
        /// under it is aimed at.
        private func follow(_ finger: CGPoint, in view: UICollectionView) {
            guard let id = carried else { return }
            // A card among the tiles, or a tile among the cards, goes by the
            // finger: a card's middle can be a row or two of tiles from
            // where it's held, a wide tile's half the screen away.
            let foreign = { [self] in
                (spot(of: id).map { shown[$0.section].basecamp } ?? false) != (parent?.kind(id) == .tile)
            }
            let middle = foreign() ? finger
                : CGPoint(x: finger.x + grabOffset.dx, y: finger.y + grabOffset.dy)
            if cross(id, middle: middle, finger: finger, in: view) {
                aim(at: nil, in: view)
                return
            }
            let point = foreign() ? finger : middle
            if !aimAtFolder(carrying: id, middle: middle, in: view),
               let spot = nearestSpot(to: point, in: view) {
                makeRoom(for: id, at: spot, in: view)
            }
        }

        /// Firn asks where the carried card is every frame, itself. The
        /// collection view says where a drag is (`dropSessionDidUpdate`)
        /// only once the finger slows: while it moved, nothing was heard,
        /// so a card sat right over its neighbor for about 0.4s before the
        /// neighbor moved aside, where Safari's move as it arrives (David's
        /// recording of both, 2026-11-24, frame by frame; the Simulator's
        /// log showed the same gap).
        private func watch(_ session: any UIDragSession, in view: UICollectionView) {
            unwatch()
            followedDrag = session
            followedView = view
            let link = CADisplayLink(target: self, selector: #selector(followed))
            link.add(to: .main, forMode: .common)
            following = link
        }

        private func unwatch() {
            following?.invalidate()
            following = nil
            followedDrag = nil
        }

        @objc private func followed() {
            guard let view = followedView, let session = followedDrag, let carried else { return }
            // The carried card's own cell stays hidden: the hold menu going
            // away showed it again, a second folder beside the carried one
            // (the Simulator, 2026-11-24). And every other cell stays shown,
            // every frame: on a quick drag UIKit marks the cell as dragged
            // only after the cards have already made room, by its place, so
            // the neighbor now in that place was dimmed and hidden until
            // the drop (a Basecamp tile, the Simulator's log, 2026-11-24).
            hideOnlyCarried(in: view)
            folderWait += 1
            if folderWait % 10 == 0 { carryFolderAgain() }
            let finger = session.location(in: view)
            // Outside the grid, the cards stay as they are.
            guard view.bounds.insetBy(dx: -40, dy: -40).contains(finger) else { return }
            follow(finger, in: view)
        }

        /// The carried card's place moves to the spot under the finger, the
        /// others gliding aside (`roomSpring`, as quick as Safari's; none
        /// with Reduce Motion).
        /// The glide of cards making room: a spring with no bounce that runs
        /// until it has settled, most of the way in 0.1s and there by about
        /// 0.25s. It was a 0.2s spring animator, which stopped at 0.2s
        /// whether or not its spring had arrived: cards glided 175 of
        /// their 189pt, then jumped the last 14pt in one frame (David's
        /// recording, 2026-11-17; the same in the Simulator, 2026-11-23).
        private static let roomSpring = UISpringTimingParameters(mass: 1, stiffness: 900, damping: 60,
                                                                 initialVelocity: .zero)

        private func makeRoom(for id: UUID, at place: Int, in view: UICollectionView) {
            guard let (section, from) = spot(of: id) else { return }
            let to = min(max(place, 0), shown[section].ids.count - 1)
            guard to != from else { return }
            var sections = shown
            sections[section].ids.remove(at: from)
            sections[section].ids.insert(id, at: to)
            glide(to: sections, in: view)
        }

        private func glide(to sections: [GridPlan.Section], in view: UICollectionView) {
            let reduce = parent?.reduceMotion ?? false
            // The grid grows with the drag's own order (a new row under the
            // last, Basecamp made at the top): the overview sizes it by the
            // store's, and a card let go in a row past the grid's end had
            // no cell until the store caught up, so it popped in late (a
            // tile carried down to a new row, the Simulator, 2026-11-24).
            if let layout = view.collectionViewLayout as? GridPlanLayout {
                let height = GridPlan(sections: sections, width: view.bounds.width, columns: layout.columns,
                                      cardHeight: layout.cardHeight, groupCardHeight: layout.groupCardHeight).height
                if height > floor {
                    floor = height
                    view.invalidateIntrinsicContentSize()
                }
            }
            let glide = UIViewPropertyAnimator(duration: 0, timingParameters: Self.roomSpring)
            glide.addAnimations { self.show(sections, in: view, animated: !reduce) }
            glide.startAnimation()
        }

        // MARK: Into and out of an open group

        /// The carried card changes sections once its middle is somewhere
        /// else: on an open group's glass (a tab only: groups never nest),
        /// or among the loose cards over, under, or between groups. Where
        /// no loose cards are yet (over a first group, between two groups),
        /// a run is made for it; a run it leaves empty goes. A group it
        /// leaves empty keeps its name line until the card is down, since
        /// it may come back. Returns whether it moved.
        ///
        /// A group's glass counts from the middle of its name line down, so
        /// the room between two groups with nothing between them (16pt)
        /// isn't all there is to aim at.
        private func cross(_ id: UUID, middle: CGPoint, finger: CGPoint, in view: UICollectionView) -> Bool {
            guard let layout = view.collectionViewLayout as? GridPlanLayout, let plan = layout.plan,
                  plan.sections == shown, let from = spot(of: id) else { return false }
            // What it was when picked up: a tile stays a tile to the store
            // until it's down among the tabs, a tab a tab.
            let kind = parent?.kind(id)
            let tile = kind == .tile
            let tab = kind == .card || tile
            // An existing section, or a run to make before section `gap`.
            var target: Int?
            var gap = shown.count
            var found = false
            // Basecamp, by the finger (a card's middle can't reach the
            // tiles when it's held near its top): on the tiles to join
            // them, halfway down the room under them to leave. With no
            // tiles yet, a tab carried up to the grid's top makes it.
            var makeBasecamp = false
            let top = shown.firstIndex(where: \.basecamp)
            let among = shown[from.section].basecamp
            let bottom = top.map { plan.frames[$0].map(\.maxY).max() ?? BasecampTiles.tileHeight }
            let over = tab && (bottom.map { finger.y < $0 + (among ? BasecampTiles.below / 2 : 0) }
                ?? (finger.y < 30 && finger.y < grabbedAt - 20))
            refused = false
            if over, among {
                stay = nil
                return false
            } else if over, tile || parent?.fitsBasecamp(id) == true {
                target = top
                makeBasecamp = top == nil
                found = true
            } else if over {
                // A full Basecamp takes nothing: the tiles stay as they are.
                refused = true
                return false
            }
            for (s, card) in plan.cards.enumerated() where !found {
                guard let card, middle.y <= card.maxY else { continue }
                found = true
                if middle.y >= card.minY + GroupCard.headerHeight / 2 {
                    // A folded group over an open one stays where it is.
                    guard tab else { return false }
                    target = s
                } else if s > 0, shown[s - 1].group == nil, !shown[s - 1].basecamp {
                    target = s - 1
                } else if among, tab {
                    // Out of Basecamp over an open group: straight into the
                    // group. A row made for it over the group pushed the
                    // group a card's height down, out from under the
                    // finger (the Simulator, 2026-11-24).
                    target = s
                } else {
                    gap = s
                }
                break
            }
            if !found, let last = shown.indices.last, shown[last].group == nil, !shown[last].basecamp {
                target = last
            }
            guard target != from.section else {
                stay = nil
                return false
            }
            if let stayed = stay {
                // Its section moved out from under it as it crossed: it
                // stays until it's carried a card's height further away.
                let extent = plan.cards[from.section]
                    ?? plan.frames[from.section].reduce(CGRect.null) { $0.union($1) }
                let away = max(extent.minY - middle.y, middle.y - extent.maxY, 0)
                if stayed < 0 || away < stayed {
                    stay = away
                    return false
                }
                if away <= stayed + layout.cardHeight { return false }
                stay = nil
            }

            var sections = shown
            sections[from.section].ids.remove(at: from.place)
            var home = from.section
            var to: Int
            if makeBasecamp {
                sections.insert(GridPlan.Section(group: nil, after: nil, ids: [], basecamp: true), at: 0)
                to = 0
                home += 1
            } else if let target {
                to = target
            } else {
                let after = gap > 0 ? sections[gap - 1].group : nil
                sections.insert(GridPlan.Section(group: nil, after: after, ids: []), at: gap)
                to = gap
                if gap <= home { home += 1 }
            }
            // A Basecamp its last tile leaves keeps its room until the tile
            // is down; one made for a carried tab goes as the tab leaves.
            if sections[home].group == nil, sections[home].ids.isEmpty, !(sections[home].basecamp && tile) {
                sections.remove(at: home)
                if home < to { to -= 1 }
            }
            // Its place there: the one nearest its middle, counting the end.
            sections[to].ids.append(id)
            let trial = GridPlan(sections: sections, width: view.bounds.width, columns: layout.columns,
                                 cardHeight: layout.cardHeight, groupCardHeight: layout.groupCardHeight)
            let near = sections[to].basecamp != tile ? finger : middle
            let place = sections[to].ids.indices.min { a, b in
                let fa = trial.frames[to][path(to, a, in: sections).item]
                let fb = trial.frames[to][path(to, b, in: sections).item]
                return hypot(fa.midX - near.x, fa.midY - near.y) < hypot(fb.midX - near.x, fb.midY - near.y)
            } ?? 0
            sections[to].ids.removeLast()
            sections[to].ids.insert(id, at: place)
            glide(to: sections, in: view)
            stay = -1
            return true
        }

        /// How far the carried card's middle was from its new section just
        /// after it crossed into it (below zero: not yet measured), or nil
        /// once it's inside. Crossing moves the sections themselves: a card
        /// carried down out of a row of its own and onto a group pulls the
        /// group up a whole row, out from under the finger, and by where
        /// its middle then was it had already passed the group and landed
        /// under it (the Simulator, 2026-11-24). So it stays in the section
        /// it crossed into until its middle is inside it (the usual rules
        /// from then on), or has gone a card's height further away.
        private var stay: CGFloat?
        /// The carried tab is over a Basecamp that won't take it (full, or
        /// the tab has no address): let go there, the overview says why.
        private var refused = false
        /// The carried picture's size, as it was lifted: a card's picture
        /// (without its title) or a whole tile.
        private var carriedSize = CGSize.zero
        /// The carried card, once its cell shows again under its picture
        /// still coming down (a tab landing as a tile, a tile as a tab).
        private var revealed: UUID?
        /// A card whose picture is still coming down after it changed
        /// kind: the grid keeps the drag's order until it's down.
        private var settling: UUID?
        /// How far down the grid the finger was as the card was lifted.
        private var grabbedAt: CGFloat = 0

        /// The spot whose middle is nearest a point. A spot changes only
        /// once the carried card's middle passes halfway to the next, so it
        /// can't flip back and forth.
        private func nearestSpot(to point: CGPoint, in view: UICollectionView) -> Int? {
            guard let id = carried, let (section, _) = spot(of: id) else { return nil }
            let layout = view.collectionViewLayout
            return shown[section].ids.indices.min { a, b in
                let ca = layout.layoutAttributesForItem(at: path(section, a, in: shown))?.center ?? .zero
                let cb = layout.layoutAttributesForItem(at: path(section, b, in: shown))?.center ?? .zero
                return hypot(ca.x - point.x, ca.y - point.y) < hypot(cb.x - point.x, cb.y - point.y)
            }
        }

        // MARK: Into a folded group

        /// The folded group a carried tab would go into if let go now.
        private var aimed: UUID?
        /// How much a folded group swells while a tab is over it.
        private static let folderSwell: CGFloat = 1.06

        /// A carried tab over a folded group (never a group over one:
        /// groups don't nest). Its middle half takes the tab, the folder
        /// swelling a little; the quarter on the far side lets the tab pass
        /// it (the two trade places); the near quarter holds still, so the
        /// folder never slips out from under a tab on its way in. Returns
        /// whether the folder decided, so no room is made.
        private func aimAtFolder(carrying id: UUID, middle: CGPoint, in view: UICollectionView) -> Bool {
            guard let parent, parent.kind(id) == .card, let (run, from) = spot(of: id),
                  shown[run].group == nil else {
                aim(at: nil, in: view)
                return false
            }
            let layout = view.collectionViewLayout
            for (spot, other) in shown[run].ids.enumerated() where other != id && parent.kind(other) == .folder {
                guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: spot, section: run))?.frame,
                      frame.contains(middle) else { continue }
                let inner = frame.insetBy(dx: frame.width / 4, dy: frame.height / 4)
                if inner.contains(middle) {
                    aim(at: other, in: view)
                    return true
                }
                aim(at: nil, in: view)
                let past = from < spot ? middle.x > inner.maxX : middle.x < inner.minX
                if past { makeRoom(for: id, at: spot, in: view) }
                return true
            }
            aim(at: nil, in: view)
            return false
        }

        /// The folder a tab is over swells; the one it left settles back.
        private func aim(at folder: UUID?, in view: UICollectionView) {
            guard folder != aimed else { return }
            let reduce = parent?.reduceMotion ?? false
            if let old = aimed, let cell = cell(for: old, in: view) {
                cell.grow(to: 1, stiffness: 300)
            }
            aimed = folder
            if let folder, let cell = cell(for: folder, in: view) {
                cell.grow(to: reduce ? 1 : Self.folderSwell, stiffness: 300)
            }
        }

        private func cell(for id: UUID, in view: UICollectionView) -> GridCardCell? {
            for case let cell as GridCardCell in view.visibleCells where cell.item == id { return cell }
            return nil
        }

        func collectionView(_ view: UICollectionView, dropSessionDidExit session: any UIDropSession) {
            aim(at: nil, in: view)
        }

        func collectionView(_ view: UICollectionView, dropSessionDidEnd session: any UIDropSession) {
            aim(at: nil, in: view)
        }

        /// Saves where the carried card now sits, once.
        private func settle(_ id: UUID) {
            guard let (section, at) = spot(of: id), shown != parent?.sections else { return }
            landed = true
            let ids = shown[section].ids
            if shown[section].basecamp {
                parent?.moveTile(id, at)
                return
            }
            parent?.move(id, at + 1 < ids.count ? ids[at + 1] : nil, shown[section].group, shown[section].after)
        }

        func collectionView(_ view: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
            unwatch()
            guard let item = coordinator.items.first, let id = item.dragItem.localObject as? UUID,
                  let home = dataSource?.indexPath(for: id) else { return }
            if let folder = aimed, let path = dataSource?.indexPath(for: folder),
               let cell = view.cellForItem(at: path) {
                // The carried picture shrinks into the folder's middle, about
                // one of its small pictures' size, as the tab joins.
                let b = cell.bounds
                let rect = CGRect(x: b.midX - b.width * 0.2, y: b.midY - b.height * 0.15,
                                  width: b.width * 0.4, height: b.height * 0.3)
                coordinator.drop(item.dragItem, intoItemAt: path, rect: rect)
                aim(at: nil, in: view)
                carried = nil
                parent?.held(id, false)
                parent?.join(id, folder)
                return
            }
            let wasTile = parent?.kind(id) == .tile
            let isTile = spot(of: id).map { shown[$0.section].basecamp } ?? wasTile
            // A tab's card and a folder land the same way (2026-11-24):
            // landed "to its cell", the card's carried picture came down,
            // faded to an empty place over about 0.3s, and the card popped
            // in half a second later (David's recording). A group carried by
            // its name line did the same, and lands this way too.
            if let spot = view.layoutAttributesForItem(at: home) {
                // A tile lands as the picture it was carried as, then its
                // cell shows at once. Landed "to its cell", iOS turns the
                // carried picture into a picture of the cell on the way
                // down, and the cell is hidden glass: the tile faded away
                // over 0.4s, its place stood empty, then it popped in (the
                // Simulator, 2026-11-24).
                // A tab that lands as a tile, or a tile as a tab, lands the
                // same way, its carried picture shrinking or growing to fit
                // its new place on the way down (a card's picture sits over
                // its title).
                var center = spot.center
                var size = spot.size
                if !isTile {
                    size.height = max(size.height - OverviewRow.gridTitleHeight, 1)
                    center.y = spot.frame.minY + size.height / 2
                }
                var fit = CGAffineTransform.identity
                if wasTile != isTile, carriedSize.width > 0, carriedSize.height > 0 {
                    // A card ends well inside its tile: fitted exactly,
                    // iOS's carried picture (a little larger than the card)
                    // stuck out over and under the tile as it faded.
                    let scale = min(size.width / carriedSize.width, size.height / carriedSize.height)
                        * (isTile ? 0.8 : 1)
                    fit = CGAffineTransform(scaleX: scale, y: scale)
                }
                let target = UIDragPreviewTarget(container: view, center: center, transform: fit)
                cell(for: id, in: view)?.landing = true
                let flight = coordinator.drop(item.dragItem, to: target)
                settle(id)
                if reopen == id { landing = true }
                if wasTile != isTile {
                    // Its new self is there under the picture coming down,
                    // once the overview has drawn it (a turn after the
                    // store's change): the tile at once (glass fading in
                    // goes grey), the card fading in. Waiting for the
                    // picture to land first, a small card sat alone in the
                    // tile's place for a third of a second (the Simulator,
                    // 2026-11-24).
                    // The grid keeps the drag's order until the picture is
                    // down (`settling`; a Basecamp left empty goes only
                    // then): given the store's at once, the list closed up
                    // under the landing and the card showed late.
                    settling = id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                        guard let self, let view, settling == id, let cell = cell(for: id, in: view) else { return }
                        revealed = id
                        cell.alpha = 1
                        if isTile || parent?.reduceMotion == true {
                            UIView.performWithoutAnimation { cell.contentView.alpha = 1 }
                        } else {
                            UIView.animate(withDuration: 0.25) { cell.contentView.alpha = 1 }
                        }
                    }
                }
                flight.addCompletion { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        guard let self, let view else { return }
                        // The group opens only once its carried picture is
                        // down, and a moment after, once iOS has faded that
                        // picture out over the folder.
                        if self.reopen == id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Self.landedPause) { [weak self] in
                                self?.reopenNow()
                            }
                        }
                        for case let cell as GridCardCell in view.visibleCells { cell.landing = false }
                        if self.revealed == id { self.revealed = nil }
                        if self.settling == id {
                            self.settling = nil
                            if let parent = self.parent, parent.sections != self.shown, self.carried == nil {
                                self.show(parent.sections, in: view, animated: !parent.reduceMotion)
                            }
                        }
                        guard self.carried == id else {
                            self.hideOnlyCarried(in: view, showing: id)
                            return
                        }
                        // Shown now, and no longer the carried one, so
                        // nothing hides it again before the drag's end.
                        self.carried = nil
                        self.hideOnlyCarried(in: view, showing: id)
                        self.parent?.held(id, false)
                    }
                }
                return
            }
            // No place in the layout (never seen): iOS lands it, and a group
            // opens as the drag ends.
            coordinator.drop(item.dragItem, toItemAt: home)
            settle(id)
        }

        /// From a carried group's picture being down to the group opening.
        private static let landedPause: TimeInterval = 0.2

        /// iOS's picture of a carried group is on its way down.
        private var landing = false

        /// The carried group opens where it landed, once.
        private func reopenNow() {
            landing = false
            guard let id = reopen else { return }
            reopen = nil
            parent?.landed(id)
        }
    }
}
