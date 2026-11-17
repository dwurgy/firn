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

/// A grid card's cell. Its own card hides the moment iOS starts lifting it:
/// the lift is a picture taken just before, and on a quick drag the cell
/// left showing under it read as a second copy (David's recording,
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
        // Not forced instant: hidden at once, the card was gone before iOS
        // took the picture it carries, so drags carried nothing (David's
        // recording, 2026-11-17).
        contentView.alpha = state == .none ? 1 : 0
    }
}

/// Where a grid card is in a swipe to close (`GridCards`): while
/// `swiping`, its title and X are gone; `easingHome`, they come back as it
/// settles. Its spot isn't reported until it's home again (`none`).
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
    /// A card's swipe to close moving on (its title and X follow it).
    let swipe: (UUID, GridSwipe) -> Void
    /// A card swiped off: its tab closes.
    let close: (UUID) -> Void
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.layout(columns: columns,
                                                                                   cardHeight: cardHeight))
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.clipsToBounds = false
        view.allowsSelection = false
        view.dragInteractionEnabled = true
        view.reorderingCadence = .fast
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
        /// The card iOS's drag carries, until it's down.
        private var carried: UUID?
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
        private var swiping: (id: UUID, cell: GridCardCell, start: CGFloat, travel: CGFloat)?

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
        // cell's content), eased home by the render server, so SwiftUI
        // runs only as the title and X go and come back.

        /// How much a swiped card grows: Safari's, about 6% (David's
        /// recording, 2026-11-17), over the swipe's first 24pt.
        private static let growth: CGFloat = 0.06
        /// The ease home, shrinking as it goes: a spring with no bounce and
        /// Safari's pace, measured from David's recordings (2026-11-17):
        /// halfway home in about 0.15s, nearly there by 0.4s, a 0.56s
        /// response (stiffness (2π / 0.56)² ≈ 125). Firn's 0.45s animator
        /// got there in half that and read as stiff.
        private static let homeStiffness: CGFloat = 125

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
                swiping = (id, cell, cell.swipe.tx - pan.translation(in: view).x, 0)
                parent?.swipe(id, .swiping)
            case .changed:
                guard var swipe = swiping else { return }
                let dx = swipe.start + pan.translation(in: view).x
                swipe.travel = max(swipe.travel, abs(dx))
                swiping = swipe
                follow(swipe.cell, dx: dx, travel: swipe.travel)
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
        private func follow(_ cell: GridCardCell, dx: CGFloat, travel: CGFloat) {
            let x = dx < 0 ? dx : dx * 0.4
            let grow = parent?.reduceMotion == true ? 1 : 1 + Self.growth * min(1, travel / 24)
            cell.swipe = CGAffineTransform(translationX: x, y: 0).scaledBy(x: grow, y: grow)
        }

        /// Past a third of the card, or a flick left, it slides off and its
        /// tab closes; otherwise it eases home.
        private func letGo(dx: CGFloat, speed: CGFloat) {
            guard let (id, cell, _, _) = swiping else { return }
            swiping = nil
            let far = -dx > cell.bounds.width / 3
            let flick = speed < -700 && dx < -20
            guard far || flick, carried == nil else {
                // The card's own speed: the finger's going left, 40% going right.
                easeHome(id, cell, speed: dx < 0 ? speed : speed * 0.4)
                return
            }
            let close = { [weak self] in
                self?.parent?.swipe(id, .none)
                self?.parent?.close(id)
                // Not closed after all (the overview was busy): back home.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, shown.contains(id) else { return }
                    cell.swipe = .identity
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
            let now = cell.swipe
            // Where the card's right edge would be unmoved, in the window.
            let gone = -(cell.superview?.convert(cell.center, to: nil).x ?? 0) - cell.bounds.width / 2 - 40
            let duration = min(0.25, max(0.12, Double((gone - now.tx) / min(speed, -900))))
            let slide = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                cell.swipe = CGAffineTransform(translationX: gone, y: 0)
                    .scaledBy(x: now.a, y: now.d)
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
            let speed = sideways.velocity(in: sideways.view)
            return abs(speed.x) > abs(speed.y)
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gesture === sideways, touch.phase == .began { touchedAt = touch.timestamp }
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
            cell.contentConfiguration = UIHostingConfiguration { parent.card(id) }.margins(.all, 0)
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
            guard new.ids != shown else { return }
            shown = new.ids
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(new.ids)
            // A card closed: the next slides into its place (0.25s, as the list).
            dataSource?.apply(snapshot, animatingDifferences: !new.reduceMotion && view.window != nil)
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
        /// stay plain, never `.destructive` (iOS's red breaks "never alarm red").
        private static func element(_ item: HoldMenuItem) -> UIMenuElement {
            let image = item.systemImage.flatMap { UIImage(systemName: $0) }
            if !item.children.isEmpty {
                return UIMenu(title: item.title, image: image, children: item.children.map(element))
            }
            let action = item.action
            return UIAction(title: item.title, image: image) { _ in MainActor.assumeIsolated { action() } }
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
            let back = { [weak self] in
                // Carried on by the drag: its X stays hidden until it's down.
                if self?.carried != id { self?.parent?.held(id, false) }
            }
            if let animator { animator.addCompletion(back) } else { back() }
        }

        // MARK: iOS's drag

        func collectionView(_ view: UICollectionView, itemsForBeginning session: any UIDragSession,
                            at path: IndexPath) -> [UIDragItem] {
            // A card being swiped isn't lifted.
            guard swiping == nil, let id = dataSource?.itemIdentifier(for: path) else { return [] }
            carried = id
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
                if let spot = nearestSpot(to: middle, in: view) { makeRoom(for: id, at: spot, in: view) }
            }
            let proposal = UICollectionViewDropProposal(operation: .move, intent: .unspecified)
            // The card stays its own size as it's carried, as Safari's: the
            // one thing SwiftUI's reorder couldn't ask for.
            proposal.prefersFullSizePreview = true
            return proposal
        }

        /// The carried card's place moves to the spot under the finger, the
        /// others gliding aside (0.2s, no bounce, as quick as Safari's; none
        /// with Reduce Motion).
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
            UIViewPropertyAnimator(duration: reduce ? 0 : 0.2, dampingRatio: 1) {
                self.dataSource?.apply(snapshot, animatingDifferences: !reduce)
            }.startAnimation()
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

        /// Saves where the carried card now sits, once.
        private func settle(_ id: UUID) {
            guard let at = shown.firstIndex(of: id), shown != parent?.ids else { return }
            parent?.move(id, at + 1 < shown.count ? shown[at + 1] : nil)
        }

        func collectionView(_ view: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first, let id = item.dragItem.localObject as? UUID,
                  let at = shown.firstIndex(of: id) else { return }
            coordinator.drop(item.dragItem, toItemAt: IndexPath(item: at, section: 0))
            settle(id)
        }
    }
}
