import SwiftUI
import UIKit

// TestFlight's grid, step 1 of "Plan: the grid as a UIKit collection view"
// (docs/IOS-PLAN.md): a run of loose cards as a UIKit collection view, so
// iOS's hold menu and iOS's drag are UIKit's own, as Safari's grid most
// likely is. UIKit, not SwiftUI, because SwiftUI's `.reorderable()` shrank
// the dragged card to about half and had no way to ask for full size;
// UIKit's drop proposal does (`prefersFullSizePreview`). Each cell still
// draws Firn's own card (`OverviewRow`, through `UIHostingConfiguration`).
// For now the collection view doesn't scroll: it sits in the overview's
// SwiftUI scroll view, as tall as its cards (step 3 makes it the whole
// overview).

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
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil, event?.type == .touches, !raised { raise() }
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
        UIView.performWithoutAnimation { contentView.alpha = state == .none ? 1 : 0 }
        contentView.layer.removeAnimation(forKey: "opacity")
    }
}

/// Where a grid card is in a swipe to close (`GridCards`): `swiping`, then
/// `easingHome`. Its spot isn't reported until it's home again (`none`).
enum GridSwipe: Equatable {
    case none, swiping, easingHome
}

/// A run of loose cards in the grid, as one UIKit collection view.
struct GridCards: UIViewRepresentable {
    /// The run's tabs, in order.
    let ids: [UUID]
    let columns: Int
    let cardHeight: CGFloat
    /// A card, drawn by the overview as everywhere else.
    let card: (UUID) -> AnyView
    /// The card's hold menu, made as it opens.
    let menu: (UUID) -> [[HoldMenuItem]]
    /// A card held (its menu open, or carried by the drag), so its X hides:
    /// iOS lifts only the picture, as Safari's.
    let held: (UUID, Bool) -> Void
    /// A card let go before another (nil: at the run's end).
    let move: (UUID, UUID?) -> Void
    /// A card's swipe to close moving on.
    let swipe: (UUID, GridSwipe) -> Void
    /// A card swiped off: its tab closes.
    let close: (UUID) -> Void
    /// Whether a cell swipes to close: a folded group's doesn't.
    var swipes: (UUID) -> Bool = { _ in true }
    /// Whether a cell is a folded group, which a carried tab can be put
    /// into (step 4 of "a folded group is one tab's size").
    var isFolder: (UUID) -> Bool = { _ in false }
    /// A tab let go on a folded group: it goes into the group, at its end.
    var join: (UUID, UUID) -> Void = { _, _ in }
    /// A group folding or opening (`GroupGlide`'s token): cards change
    /// grids at once, with no fade or slide of the collection view's own,
    /// since the glide is drawn over the list (`GroupGlideView`).
    var fold: UUID?

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
            guard let source = view.dataSource as? UICollectionViewDiffableDataSource<Int, UUID> else { continue }
            for cell in view.visibleCells {
                guard let path = view.indexPath(for: cell), let id = source.itemIdentifier(for: path) else { continue }
                frames[id] = cell.convert(cell.bounds, to: nil)
            }
        }
        return frames
    }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.layout(columns: columns,
                                                                                   cardHeight: cardHeight))
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
        let coordinator = context.coordinator
        if coordinator.columns != columns || coordinator.cardHeight != cardHeight {
            view.setCollectionViewLayout(Self.layout(columns: columns, cardHeight: cardHeight), animated: false)
        }
        coordinator.update(self, in: view)
    }

    /// As tall as its rows of cards: the overview's scroll view scrolls it.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICollectionView, context: Context) -> CGSize? {
        let rows = (ids.count + columns - 1) / max(columns, 1)
        let height = rows == 0 ? 0 : CGFloat(rows) * cardHeight + CGFloat(rows - 1) * OverviewGridMetrics.rowSpacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    /// The grid's columns, 17pt apart, rows 9pt apart (Safari's).
    private static func layout(columns: Int, cardHeight: CGFloat) -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                                                            heightDimension: .absolute(cardHeight)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                         heightDimension: .absolute(cardHeight)),
                                                       repeatingSubitem: item, count: columns)
        group.interItemSpacing = .fixed(OverviewGridMetrics.spacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = OverviewGridMetrics.rowSpacing
        return UICollectionViewCompositionalLayout(section: section)
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate,
        UICollectionViewDropDelegate, UIGestureRecognizerDelegate {
        private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>?
        private var parent: GridCards?
        var columns = 0
        var cardHeight: CGFloat = 0
        /// What the collection view shows: the store's order, or a drop's
        /// before the store catches up.
        private var shown: [UUID] = []
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
                    guard let self, shown.contains(id) else { return }
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
               let id = dataSource?.itemIdentifier(for: path), parent?.swipes(id) == false { return false }
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
            cell.contentConfiguration = UIHostingConfiguration {
                parent.card(id)
            }.margins(.all, 0)
        }

        func update(_ new: GridCards, in view: UICollectionView) {
            parent = new
            columns = new.columns
            cardHeight = new.cardHeight
            // Cards show what's new (the X hiding, a new title, a picture).
            for path in view.indexPathsForVisibleItems {
                if let cell = view.cellForItem(at: path), let id = dataSource?.itemIdentifier(for: path) {
                    configure(cell, id)
                }
            }
            if new.ids != shown {
                // Another space's cards (none shared with these) take their
                // place at once: animated, UIKit faded the new ones in over
                // a quarter second, a dim flash after a swipe between spaces
                // had already slid them in (David's recording, 2026-11-23).
                let related = !Set(new.ids).isDisjoint(with: shown)
                shown = new.ids
                var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
                snapshot.appendSections([0])
                snapshot.appendItems(new.ids)
                // A card closed: the next slides into its place (0.25s, as
                // the list). A fold or unfold lands at once: its glide is
                // drawn over the list.
                dataSource?.apply(snapshot, animatingDifferences: new.fold == nil && !new.reduceMotion
                                  && view.window != nil && related)
            }
        }

        /// The card's picture, without its title: what iOS lifts, for its
        /// menu and its drag, as Safari's.
        private func picture(_ view: UICollectionView, _ path: IndexPath) -> UIPreviewParameters? {
            guard let cell = view.cellForItem(at: path) else { return nil }
            let bounds = cell.bounds
            let window = CGRect(x: 0, y: 0, width: bounds.width,
                                height: max(bounds.height - OverviewRow.gridTitleHeight, 1))
            let parameters = UIPreviewParameters()
            parameters.visiblePath = UIBezierPath(roundedRect: window, cornerRadius: OverviewRow.gridCornerRadius)
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
            guard swiping == nil, let id = dataSource?.itemIdentifier(for: path) else { return [] }
            lifting = id
            if let cell = view.cellForItem(at: path) {
                let finger = session.location(in: view)
                grabOffset = CGVector(dx: cell.center.x - finger.x, dy: cell.center.y - finger.y)
            } else {
                grabOffset = .zero
            }
            parent?.held(id, true)
            // Firn's own: never to another app (no address handed over).
            let item = UIDragItem(itemProvider: NSItemProvider())
            item.localObject = id
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
            if let carried { parent?.held(carried, true) }
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
            // Let go outside the grid: it stays where it was last moved to.
            if let id = carried { settle(id); parent?.held(id, false) }
            carried = nil
            lifting = nil
            // Every card shown again once the drop has landed: a card hidden
            // while carried stayed invisible once (David, 2026-11-17, not
            // caught on a recording), likely never told its drag had ended.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak view] in
                guard let self, carried == nil, let view else { return }
                for case let cell as GridCardCell in view.visibleCells { cell.contentView.alpha = 1 }
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
            if let id = carried {
                let finger = session.location(in: view)
                let middle = CGPoint(x: finger.x + grabOffset.dx, y: finger.y + grabOffset.dy)
                if !aimAtFolder(carrying: id, middle: middle, in: view),
                   let spot = nearestSpot(to: middle, in: view) {
                    makeRoom(for: id, at: spot, in: view)
                }
            }
            let proposal = UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            // The card stays its own size as it's carried, as Safari's: the
            // one thing SwiftUI's reorder couldn't ask for.
            proposal.prefersFullSizePreview = true
            return proposal
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

        private func makeRoom(for id: UUID, at spot: Int, in view: UICollectionView) {
            guard let from = shown.firstIndex(of: id) else { return }
            let to = min(max(spot, 0), shown.count - 1)
            guard to != from else { return }
            shown.remove(at: from)
            shown.insert(id, at: to)
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(shown)
            let reduce = parent?.reduceMotion ?? false
            let glide = UIViewPropertyAnimator(duration: 0, timingParameters: Self.roomSpring)
            glide.addAnimations { self.dataSource?.apply(snapshot, animatingDifferences: !reduce) }
            glide.startAnimation()
        }

        /// The spot whose middle is nearest a point. A spot changes only
        /// once the carried card's middle passes halfway to the next, so it
        /// can't flip back and forth.
        private func nearestSpot(to point: CGPoint, in view: UICollectionView) -> Int? {
            let layout = view.collectionViewLayout
            return shown.indices.min { a, b in
                let ca = layout.layoutAttributesForItem(at: IndexPath(item: a, section: 0))?.center ?? .zero
                let cb = layout.layoutAttributesForItem(at: IndexPath(item: b, section: 0))?.center ?? .zero
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
            guard let parent, !parent.isFolder(id), let from = shown.firstIndex(of: id) else {
                aim(at: nil, in: view)
                return false
            }
            let layout = view.collectionViewLayout
            for (spot, other) in shown.enumerated() where other != id && parent.isFolder(other) {
                guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: spot, section: 0))?.frame,
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
            guard let path = dataSource?.indexPath(for: id) else { return nil }
            return view.cellForItem(at: path) as? GridCardCell
        }

        func collectionView(_ view: UICollectionView, dropSessionDidExit session: any UIDropSession) {
            aim(at: nil, in: view)
        }

        func collectionView(_ view: UICollectionView, dropSessionDidEnd session: any UIDropSession) {
            aim(at: nil, in: view)
        }

        /// Saves where the carried card now sits, once.
        private func settle(_ id: UUID) {
            guard let at = shown.firstIndex(of: id), shown != parent?.ids else { return }
            parent?.move(id, at + 1 < shown.count ? shown[at + 1] : nil)
        }

        func collectionView(_ view: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first, let id = item.dragItem.localObject as? UUID,
                  let at = shown.firstIndex(of: id) else { return }
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
            coordinator.drop(item.dragItem, toItemAt: IndexPath(item: at, section: 0))
            settle(id)
        }
    }
}
