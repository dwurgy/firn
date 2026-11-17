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
final class GridCardCell: UICollectionViewCell {
    override func dragStateDidChange(_ state: UICollectionViewCell.DragState) {
        super.dragStateDidChange(state)
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
        UICollectionViewDropDelegate {
        private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>?
        private var parent: GridCards?
        var columns = 0
        var cardHeight: CGFloat = 0
        /// What the collection view shows: the store's order, or a drop's
        /// before the store catches up.
        private var shown: [UUID] = []
        /// The card iOS's drag carries, until it's down.
        private var carried: UUID?

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
            parent?.held(id, true)
        }

        func collectionView(_ view: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                            animator: (any UIContextMenuInteractionAnimating)?) {
            guard let id = configuration.identifier as? UUID else { return }
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
            if let id = carried { parent?.held(id, false) }
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
            let proposal = UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            // The card stays its own size as it's carried, as Safari's: the
            // one thing SwiftUI's reorder couldn't ask for.
            proposal.prefersFullSizePreview = true
            return proposal
        }

        func collectionView(_ view: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
            guard let item = coordinator.items.first, let from = item.sourceIndexPath,
                  let id = item.dragItem.localObject as? UUID else { return }
            var order = shown
            let to = min(coordinator.destinationIndexPath?.item ?? order.count - 1, order.count - 1)
            order.remove(at: from.item)
            order.insert(id, at: to)
            shown = order
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(order)
            dataSource?.apply(snapshot, animatingDifferences: false)
            coordinator.drop(item.dragItem, toItemAt: IndexPath(item: to, section: 0))
            parent?.move(id, to + 1 < order.count ? order[to + 1] : nil)
        }
    }
}
