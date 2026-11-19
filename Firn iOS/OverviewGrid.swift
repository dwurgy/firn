import FirnCore
import SwiftUI

/// The grid's columns and card height for the list's width: two columns
/// on an iPhone; on an iPad (or an iPhone on its side) as many as fit at
/// about 220pt each, up to five. A card grows with its column so its
/// picture stays portrait: about 250pt on an iPhone.
struct OverviewGridMetrics: Equatable {
    let columns: Int
    let cardHeight: CGFloat
    /// A card's height inside an open group: its column is narrower there
    /// and its picture keeps its shape, so it's a little shorter, as
    /// Safari's (David's recording, 2026-11-18).
    let groupCardHeight: CGFloat

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
    static let pictureShape: CGFloat = 1.41

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
        let inner = (room - 2 * GroupCard.side - GroupCard.columnGap * CGFloat(columns - 1)) / CGFloat(columns)
        groupCardHeight = min(max(inner, 1) * Self.pictureShape + OverviewRow.gridTitleHeight, card).rounded()
    }

    var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columns)
    }
}

/// One cell in a run of the grid: a loose tab, or a folded group, which
/// takes one tab's place (as Safari's; David, 2026-11-18).
struct GridRunItem: Identifiable {
    let id: UUID
    /// Its place in the space's list.
    let index: Int
    let tab: FirnCore.Tab?
    let group: TabGroup?
}

/// Loose tabs (and folded groups) between open groups, laid out as one
/// grid: keyed by the open group just before them (nil at the top), so the
/// run keeps its grid as tabs come and go and its cards glide to their new
/// places.
enum OverviewGridRun: Identifiable {
    case tabs(after: UUID?, [GridRunItem])
    case group(index: Int, TabGroup)

    var id: String {
        switch self {
        case let .tabs(after, _): "tabs-" + (after?.uuidString ?? "top")
        case let .group(_, group): group.id.uuidString
        }
    }

    /// The list's items in runs: loose tabs together, each open group
    /// alone. A group `inRun` says is a cell sits among the loose tabs.
    @MainActor static func runs(_ items: [TabListItem], inRun: (TabGroup) -> Bool = { _ in false }) -> [OverviewGridRun] {
        var runs: [OverviewGridRun] = []
        var loose: [GridRunItem] = []
        var after: UUID?
        for (index, item) in items.enumerated() {
            switch item {
            case let .tab(tab):
                loose.append(GridRunItem(id: tab.id, index: index, tab: tab, group: nil))
            case let .group(group) where inRun(group):
                loose.append(GridRunItem(id: group.id, index: index, tab: nil, group: group))
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

/// A folded group in the grid: one tab's size (the picture's, nothing
/// under it), on the group's glass, its name at the top and its first
/// tabs as small square pictures, as Safari's (David, 2026-11-18): the
/// squares fill the bottom, and the name sits centered in the room above
/// them (17pt bold, as Safari's), as tab titles are centered. A tap opens it; holding it is iOS's
/// menu and drag, from the grid (`GridCards`).
struct GroupFolder: View {
    let group: TabGroup
    let tabs: [FirnCore.Tab]
    let pictures: PagePictures
    let cardHeight: CGFloat
    let naming: Bool
    let open: () -> Void

    private static let shown = 4
    static let inset: CGFloat = 8
    static let gap: CGFloat = 6
    private static let thumbCorner: CGFloat = 7

    @State private var width: CGFloat = 0
    private var folderSize: CGSize {
        CGSize(width: width, height: max(cardHeight - OverviewRow.gridTitleHeight, 1))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OverviewRow.gridCornerRadius, style: .continuous)
        VStack(spacing: 0) {
            Button(action: open) {
                VStack(spacing: Self.gap) {
                    Group {
                        if naming {
                            NamingDots(color: Theme.ink, size: 5).frame(height: 18)
                        } else {
                            Text(group.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.gap, alignment: .top),
                                        GridItem(.flexible(), spacing: Self.gap, alignment: .top)],
                              spacing: Self.gap) {
                        ForEach(tabs.prefix(Self.shown)) { tab in
                            FolderThumb(tab: tab, pictures: pictures, corner: Self.thumbCorner)
                        }
                        // Empty places keep two rows' room with fewer tabs,
                        // so the name sits at the same height in every folder.
                        ForEach(tabs.count..<max(Self.shown, tabs.count), id: \.self) { _ in
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Self.inset)
                // `minHeight: 0`: at large text sizes the name and two rows
                // can be taller than the cell; without it the folder grows
                // past its cell instead of the top being squeezed.
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .background { FirnGlass(shape: shape) }
                .contentShape(shape)
            }
            .buttonStyle(UndimmedPress())
            .frame(height: folderSize.height)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            Color.clear.frame(height: OverviewRow.gridTitleHeight)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(naming ? "New group, naming" : group.name)
        .accessibilityValue("Folded, \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")")
        .accessibilityHint("Shows the group's tabs")
        .accessibilityAddTraits(.isButton)
    }
}

/// One small page picture in a folded group: square, as Safari's, the
/// page's top below its header.
private struct FolderThumb: View {
    let tab: FirnCore.Tab
    let pictures: PagePictures
    let corner: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .top) {
                if let picture = pictures.cachedImage(for: tab.id), picture.size.width > 0 {
                    GeometryReader { box in
                        let scale = box.size.width / picture.size.width
                        Image(uiImage: picture)
                            .resizable()
                            .frame(width: box.size.width, height: picture.size.height * scale)
                            .offset(y: -pictures.headerDepth(for: tab.id) * scale)
                    }
                } else {
                    SiteIconView(icon: tab.icon, size: 20) {
                        LetterMark(site: WebAddress.site(of: tab.url), size: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.page)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.windowHairline, lineWidth: 1) }
            .task(id: tab.id) {
                if pictures.cachedImage(for: tab.id) == nil { await pictures.loadImage(for: tab.id) }
            }
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
