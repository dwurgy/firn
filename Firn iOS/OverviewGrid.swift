import FirnCore
import SwiftUI

/// The tab overview's look: the list (always, in an App Store build), or a
/// grid of cards, a TestFlight experiment (David, 2026-11-16) so testers
/// can compare the two. Kept on the device only (`@AppStorage`): nothing is
/// logged or sent.
enum OverviewLayout: String {
    case list
    case grid

    static let key = "overviewLayout"
}

/// The grid's columns and card height for the list's width: two columns
/// on an iPhone; on an iPad (or an iPhone on its side) as many as fit at
/// about 220pt each, up to five. A card grows with its column so its
/// picture stays portrait: about 250pt on an iPhone.
struct OverviewGridMetrics: Equatable {
    let columns: Int
    let cardHeight: CGFloat

    /// Between columns, and between a card's title and the card below it:
    /// Safari's grid, measured from David's screenshots (2026-11-16).
    static let spacing: CGFloat = 17
    static let rowSpacing: CGFloat = 9
    /// The list's sides.
    static let margin: CGFloat = 16
    private static let minColumn: CGFloat = 220
    private static let maxColumns = 5
    /// The picture's height for its width (portrait, as a phone's page).
    /// Safari's 1.41 (David, 2026-11-16: 1.25 looked stubby beside it).
    private static let pictureShape: CGFloat = 1.41

    /// `width` is the overview's; `height` its view's, so a card on a
    /// phone on its side still fits on screen with room around it.
    init(width: CGFloat, height: CGFloat) {
        let room = max(width - 2 * Self.margin, 1)
        let fit = Int(((room + Self.spacing) / (Self.minColumn + Self.spacing)).rounded(.down))
        columns = min(max(fit, 2), Self.maxColumns)
        let column = (room - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        // The picture is the card (as Safari's), its title under it.
        let picture = column * Self.pictureShape
        var card = picture + OverviewRow.gridTitleHeight
        if height > 0 { card = min(card, max(height * 0.62, OverviewRow.cardHeight)) }
        cardHeight = card.rounded()
    }

    var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columns)
    }
}

/// Loose tabs between groups, laid out as one grid: keyed by the group just
/// before them (nil at the top), so the run keeps its grid as tabs come and
/// go and its cards glide to their new places.
enum OverviewGridRun: Identifiable {
    case tabs(after: UUID?, [(index: Int, tab: FirnCore.Tab)])
    case group(index: Int, TabGroup)

    var id: String {
        switch self {
        case let .tabs(after, _): "tabs-" + (after?.uuidString ?? "top")
        case let .group(_, group): group.id.uuidString
        }
    }

    /// The list's items in runs: loose tabs together, each group alone.
    static func runs(_ items: [TabListItem]) -> [OverviewGridRun] {
        var runs: [OverviewGridRun] = []
        var loose: [(index: Int, tab: FirnCore.Tab)] = []
        var after: UUID?
        for (index, item) in items.enumerated() {
            switch item {
            case let .tab(tab):
                loose.append((index, tab))
            case let .group(group):
                if !loose.isEmpty { runs.append(.tabs(after: after, loose)) }
                loose = []
                runs.append(.group(index: index, group))
                after = group.id
            }
        }
        if !loose.isEmpty { runs.append(.tabs(after: after, loose)) }
        return runs
    }
}

/// A folded group's site icons in the grid, after its chevron: a few of
/// its tabs' icons, so the folder shows what's inside. No count (David,
/// 2026-11-16).
struct GroupIcons: View {
    let tabs: [FirnCore.Tab]

    static let shown = 4
    private static let size: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs.prefix(Self.shown)) { tab in
                SiteIconView(icon: tab.icon, size: Self.size) {
                    LetterMark(site: WebAddress.site(of: tab.url), size: Self.size)
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
