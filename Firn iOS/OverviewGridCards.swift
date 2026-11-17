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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit != nil, event?.type == .touches, !raised {
            for case let other as GridCardCell in superview?.subviews ?? [] where other !== self {
                other.raised = false
            }
            raised = true
        }
        return hit
    }

    /// The layout sets each cell's depth as it lays out; a raised card
    /// keeps its place on top.
    override func apply(_ attributes: UICollectionViewLayoutAttributes) {
        super.apply(attributes)
        if raised { layer.zPosition = 1 }
    }

    override func dragStateDidChange(_ state: UICollectionViewCell.DragState) {
        super.dragStateDidChange(state)
        // Not forced instant: hidden at once, the card was gone before iOS
        // took the picture it carries, so drags carried nothing (David's
        // recording, 2026-11-17).
        contentView.alpha = state == .none ? 1 : 0
    }
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
        /// iOS's hold menu is showing.
        private var menuShown = false
        /// Watches for a swipe sideways (`swipeStarted`).
        private let sideways = UIPanGestureRecognizer()

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
            sideways.cancelsTouchesInView = false
            sideways.delaysTouchesEnded = false
            sideways.addTarget(self, action: #selector(swipeStarted))
            view.addGestureRecognizer(sideways)
        }

        /// A swipe sideways (to close a card) that starts while iOS is
        /// still pressing the card down for its menu or a drag: iOS's press
        /// is called off. Left running, it held the card in a frame the
        /// size of its picture, so the swiped card was cut off at its old
        /// edge, as if behind an invisible wall, until iOS let go and it
        /// snapped back (David's recordings, 2026-11-17). Once a drag has
        /// begun or the menu is open, a move sideways is theirs.
        @objc private func swipeStarted(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .began, carried == nil, !menuShown, let view = pan.view else { return }
            for other in view.gestureRecognizers ?? [] where other !== pan && other.isEnabled {
                other.isEnabled = false
                other.isEnabled = true
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture === sideways else { return true }
            let speed = sideways.velocity(in: sideways.view)
            return abs(speed.x) > abs(speed.y)
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gesture === sideways || other === sideways
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
            guard let path = paths.first, let id = dataSource?.itemIdentifier(for: path), let parent else { return nil }
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
            guard let id = dataSource?.itemIdentifier(for: path) else { return [] }
            carried = id
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
            // The spot is the card under the finger, found at once: UIKit's
            // own destination waits for the finger to settle, so the carried
            // card sat over its neighbor about 0.4s before it moved, where
            // Safari's moves as the card arrives (David's recording beside
            // Safari's, 2026-11-17). The carried card's own (hidden) cell
            // takes the finger's spot as it moves, so it can't flip back.
            // Between cards nothing moves (UIKit's late guess could pull a
            // card back to a spot already left).
            if let id = carried, let under = view.indexPathForItem(at: session.location(in: view)) {
                makeRoom(for: id, at: under.item, in: view)
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
