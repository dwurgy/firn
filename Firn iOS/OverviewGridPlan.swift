import UIKit

// Where everything in the grid sits, worked out in one place: the runs of
// loose cards (and folded groups), and each open group as a section of its
// own, its name line on top and its tabs in columns on its glass card
// (step 3 of "Plan: the drag polish", docs/IOS-PLAN.md). The collection
// view lays out from it (`GridPlanLayout`), and the overview reads the same
// measures to find a card that's out of view (`TabOverview.gridSpot`).

/// A section of the grid, as the collection view's data source names it.
enum GridSectionID: Hashable, Sendable {
    /// A run of loose cards, keyed by the open group just before it.
    case loose(after: UUID?)
    /// An open group.
    case group(UUID)
}

/// What a cell of the grid is.
enum GridCellKind {
    /// A tab's card, loose or in an open group.
    case card
    /// A folded group, one card's size among the loose cards.
    case folder
    /// An open group's name line.
    case line
}

struct GridPlan: Equatable {
    struct Section: Equatable {
        /// The open group this is, or nil for a run of cards.
        let group: UUID?
        /// A run's key: the open group just before it.
        let after: UUID?
        /// A run's cards, or a group's tabs (not its name line).
        var ids: [UUID]

        var id: GridSectionID { group.map { .group($0) } ?? .loose(after: after) }
        /// The cells, in order: a group's name line (the group's own id)
        /// comes first.
        var items: [UUID] { group.map { [$0] + ids } ?? ids }
    }

    let sections: [Section]
    /// Every cell's frame, by section, in `Section.items`' order.
    let frames: [[CGRect]]
    /// Each open group's glass card (nil for a run).
    let cards: [CGRect?]
    let height: CGFloat

    @MainActor init(sections: [Section], width: CGFloat, columns: Int, cardHeight: CGFloat, groupCardHeight: CGFloat) {
        self.sections = sections
        let columns = max(columns, 1)
        let count = CGFloat(columns)
        let column = max((width - OverviewGridMetrics.spacing * (count - 1)) / count, 1)
        let tile = max((width - 2 * GroupCard.side - GroupCard.columnGap * (count - 1)) / count, 1)
        var frames: [[CGRect]] = []
        var cards: [CGRect?] = []
        var y: CGFloat = 0
        for (index, section) in sections.enumerated() {
            if index > 0 {
                // Safari's room around an open group: 16pt under it, 10pt
                // over it under a row of titles (`GroupCard`).
                if sections[index - 1].group != nil {
                    y += GroupCard.gapBelow
                } else {
                    y += section.group != nil ? GroupCard.gapAbove : OverviewGridMetrics.rowSpacing
                }
            }
            if section.group != nil {
                let height = Self.groupHeight(tabs: section.ids.count, columns: columns,
                                              groupCardHeight: groupCardHeight)
                var cells = [CGRect(x: 0, y: y, width: width, height: GroupCard.headerHeight)]
                for place in section.ids.indices {
                    cells.append(CGRect(x: GroupCard.side + CGFloat(place % columns) * (tile + GroupCard.columnGap),
                                        y: y + GroupCard.headerHeight
                                            + CGFloat(place / columns) * (groupCardHeight + GroupCard.rowGap),
                                        width: tile, height: groupCardHeight))
                }
                frames.append(cells)
                cards.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height
            } else {
                frames.append(section.ids.indices.map { place in
                    CGRect(x: CGFloat(place % columns) * (column + OverviewGridMetrics.spacing),
                           y: y + CGFloat(place / columns) * (cardHeight + OverviewGridMetrics.rowSpacing),
                           width: column, height: cardHeight)
                })
                cards.append(nil)
                let rows = CGFloat((section.ids.count + columns - 1) / columns)
                y += rows * cardHeight + max(rows - 1, 0) * OverviewGridMetrics.rowSpacing
            }
        }
        // A group at the end keeps a little room under it, as before.
        if sections.last?.group != nil { y += GroupCard.gapBelow - 12 }
        self.frames = frames
        self.cards = cards
        height = y
    }

    /// An open group's glass card, from its name line down to under its
    /// last row of titles.
    @MainActor static func groupHeight(tabs: Int, columns: Int, groupCardHeight: CGFloat) -> CGFloat {
        let rows = CGFloat((tabs + max(columns, 1) - 1) / max(columns, 1))
        return GroupCard.headerHeight + rows * groupCardHeight + max(rows - 1, 0) * GroupCard.rowGap
            + GroupCard.bottom
    }

    /// A cell's frame, in the grid's own space.
    func frame(of id: UUID) -> CGRect? {
        for (s, section) in sections.enumerated() {
            if let place = section.items.firstIndex(of: id) { return frames[s][place] }
        }
        return nil
    }
}

/// The collection view's layout: the plan's frames, nothing of its own.
final class GridPlanLayout: UICollectionViewLayout {
    var sections: [GridPlan.Section] = []
    var columns = 2
    var cardHeight: CGFloat = 1
    var groupCardHeight: CGFloat = 1
    private(set) var plan: GridPlan?

    override func prepare() {
        super.prepare()
        plan = GridPlan(sections: sections, width: collectionView?.bounds.width ?? 0, columns: columns,
                        cardHeight: cardHeight, groupCardHeight: groupCardHeight)
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: plan?.height ?? 0)
    }

    override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let plan, path.section < plan.frames.count, path.item < plan.frames[path.section].count else {
            return nil
        }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
        attributes.frame = plan.frames[path.section][path.item]
        return attributes
    }

    /// An open group's glass card: a view of its own behind the group's
    /// cells, so iOS lifting the name line (its menu, its drag) leaves the
    /// card where it is.
    static let cardKind = "group-card"

    override func layoutAttributesForSupplementaryView(ofKind kind: String, at path: IndexPath)
        -> UICollectionViewLayoutAttributes? {
        guard kind == Self.cardKind, let plan, path.section < plan.cards.count,
              let frame = plan.cards[path.section] else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: path)
        attributes.frame = frame
        attributes.zIndex = -1
        return attributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let plan else { return nil }
        var found: [UICollectionViewLayoutAttributes] = []
        for (s, frames) in plan.frames.enumerated() {
            for (place, frame) in frames.enumerated() where frame.intersects(rect) {
                if let attributes = layoutAttributesForItem(at: IndexPath(item: place, section: s)) {
                    found.append(attributes)
                }
            }
            if let card = plan.cards[s], card.intersects(rect),
               let attributes = layoutAttributesForSupplementaryView(ofKind: Self.cardKind,
                                                                     at: IndexPath(item: 0, section: s)) {
                found.append(attributes)
            }
        }
        return found
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

/// An open group's glass card in the grid (`GridPlanLayout.cardKind`),
/// drawn by the overview. Never touched: the cells over it are.
final class GridGroupCardView: UICollectionReusableView {
    private var content: (UIView & UIContentView)?

    /// Hidden at once when its group was picked up by its name line.
    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1
    }

    func show(_ configuration: some UIContentConfiguration) {
        isUserInteractionEnabled = false
        clipsToBounds = false
        if let content {
            content.configuration = configuration
            return
        }
        let view = configuration.makeContentView()
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
        content = view
    }
}
