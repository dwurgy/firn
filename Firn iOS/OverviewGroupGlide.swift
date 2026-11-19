import FirnCore
import SwiftUI

// A group folding into its cell or opening out of it, in the grid on
// iOS 27, as Safari's (David's recordings side by side, 2026-11-18): one
// continuous change. The group's glass grows from the folder's shape to
// the open card's; each small picture in the folder is the tab's own card,
// growing to its place, its title beside it at full size from the first
// frame; the folder's big name blurs away as the open group's name line
// comes in; the tabs after the group ride the same curve to their new
// places; and the cards before it in its row stay in front of the glass.
//
// It's drawn once, over the list (`GroupGlideView`), while the real folder,
// the real open group, and the cards that change grids stay hidden under
// it: they swap in at the end, exactly where the drawing stopped. Before,
// the folder's cell was drawn blown up over the open group (its name huge,
// its pictures arriving late), and cards that moved to a new grid showed a
// few frames late, so they lagged behind the group and ran over it.

/// One fold or unfold: where everything starts and ends, in the list's own
/// space (so the list scrolling under it moves it too).
@MainActor struct GroupGlide: @MainActor Equatable {
    let id: UUID
    let token = UUID()
    let opening: Bool
    /// The folded cell's picture (the folder), and the open group's card.
    let cell: CGRect
    let card: CGRect
    /// The group's tabs drawn: the folder's four, and any others in view.
    let tabs: [UUID]
    let columns: Int
    /// A loose card's height (the folder's cell), and a card's in the group.
    let cardHeight: CGFloat
    let tileHeight: CGFloat
    /// Cards (and folders) after the group, which change grids.
    let arrivals: [Arrival]
    /// Cards before the folder in its row: they stay where they are, in
    /// front of the growing glass, as Safari's (David's recording,
    /// 2026-11-18); under the drawing the glass ran over them.
    let stays: [Arrival]
    /// Everything the drawing stands in for, hidden in the list meanwhile.
    let hidden: Set<UUID>

    struct Arrival: Equatable, Identifiable, Sendable {
        let id: UUID
        /// Where it sits with the group folded, and with it open.
        let folded: CGRect
        let open: CGRect
    }

    /// The folder's small pictures: two columns of squares at the bottom,
    /// as `GroupFolder` lays them out. In the cell's own space.
    func mini(_ index: Int) -> CGRect {
        let side = max((cell.width - 2 * GroupFolder.inset - GroupFolder.gap) / 2, 1)
        let top = cell.height - GroupFolder.inset - (2 * side + GroupFolder.gap)
        return CGRect(x: GroupFolder.inset + CGFloat(index % 2) * (side + GroupFolder.gap),
                      y: top + CGFloat(index / 2) * (side + GroupFolder.gap),
                      width: side, height: side)
    }

    /// A tab's tile in the open group, title and all. In the card's space.
    func tile(_ index: Int) -> CGRect {
        let count = CGFloat(max(columns, 1))
        let width = (card.width - 2 * GroupCard.side - GroupCard.columnGap * (count - 1)) / count
        return CGRect(x: GroupCard.side + CGFloat(index % columns) * (width + GroupCard.columnGap),
                      y: GroupCard.headerHeight + CGFloat(index / columns) * (tileHeight + GroupCard.rowGap),
                      width: max(width, 1), height: tileHeight)
    }

    /// The middle of the folder's name, down from the folder's top.
    var nameMiddle: CGFloat {
        (GroupFolder.inset + mini(0).minY - GroupFolder.gap) / 2
    }

    static func == (a: Self, b: Self) -> Bool { a.token == b.token }
}

/// The drawing. `share` runs from 0 (folded) to 1 (open); it's `Animatable`
/// so every frame is laid out on the way, the fades each over their own
/// stretch of it.
struct GroupGlideView<Tile: View, Title: View, Cell: View>: View, @MainActor Animatable {
    let glide: GroupGlide
    var share: CGFloat
    let name: String
    /// A tab's own card at a height, bare or whole.
    let tile: (UUID, CGFloat, Bool) -> Tile
    /// A tab's title line, as under its card.
    let title: (UUID) -> Title
    /// A card or folder that changes grids, as it is in the list.
    let cell: (UUID) -> Cell

    init(glide: GroupGlide, share: CGFloat, name: String,
         @ViewBuilder tile: @escaping (UUID, CGFloat, Bool) -> Tile,
         @ViewBuilder title: @escaping (UUID) -> Title,
         @ViewBuilder cell: @escaping (UUID) -> Cell) {
        self.glide = glide
        self.share = share
        self.name = name
        self.tile = tile
        self.title = title
        self.cell = cell
    }

    var animatableData: CGFloat {
        get { share }
        set { share = newValue }
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t),
               width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
    }
    /// 0 before `from`, 1 after `to`, eased between.
    private static func ramp(_ t: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
        let x = min(max((t - from) / (to - from), 0), 1)
        return x * x * (3 - 2 * x)
    }

    var body: some View {
        let t = min(max(share, 0), 1)
        let frame = Self.mix(glide.cell, glide.card, share)
        let corner = Self.mix(OverviewRow.gridCornerRadius, GroupCard.cornerRadius, t)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        // The X and shadow: early as it opens, gone at once as it folds,
        // as Safari's.
        let bare = glide.opening ? t < 0.2 : t < 0.97
        // The titles: there from the first frame of an opening and gone in
        // the first of a fold, as Safari's.
        let titles = glide.opening ? Self.ramp(t, 0, 0.1) : Self.ramp(t, 0.9, 1)
        ZStack(alignment: .topLeading) {
            ForEach(glide.arrivals) { arrival in
                let spot = Self.mix(arrival.folded, arrival.open, share)
                cell(arrival.id)
                    .frame(width: spot.width, height: spot.height)
                    .offset(x: spot.minX, y: spot.minY)
            }
            // The glass laid out at each size, never scaled or masked: iOS
            // draws no glass inside a mask or a scale until it's over.
            FirnGlass(shape: shape)
                .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                .offset(x: frame.minX, y: frame.minY)
            ZStack(alignment: .topLeading) {
                // A card, then its title: the next row's cards ride over
                // the titles above them until there's room, as Safari's.
                ForEach(Array(glide.tabs.enumerated()), id: \.element) { index, id in
                    card(id, at: index, in: frame, bare: bare)
                    titleLine(id, at: index, in: frame).opacity(titles)
                }
                folderName(t).position(x: frame.width / 2, y: glide.nameMiddle)
                nameLine(t)
            }
            .frame(width: max(frame.width, 1), height: max(frame.height, 1), alignment: .topLeading)
            .clipShape(shape)
            .offset(x: frame.minX, y: frame.minY)
            ForEach(glide.stays) { stay in
                cell(stay.id)
                    .frame(width: stay.open.width, height: stay.open.height)
                    .offset(x: stay.open.minX, y: stay.open.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A tab's card between its small picture in the folder and its place
    /// in the open group: scaled by its width, its picture's height opening
    /// from the folder's square to the card's portrait.
    private func card(_ id: UUID, at index: Int, in frame: CGRect, bare: Bool) -> some View {
        let small = glide.mini(index).offsetBy(dx: glide.cell.minX, dy: glide.cell.minY)
        let whole = glide.tile(index).offsetBy(dx: glide.card.minX, dy: glide.card.minY)
        let title = OverviewRow.gridTitleHeight
        let scale = Self.mix(small.width, whole.width, share) / whole.width
        // The picture's height on screen, then as the card lays it out.
        let picture = Self.mix(small.height, whole.height - title, share)
        let height = picture / max(scale, 0.01) + title
        return tile(id, height, bare)
            .frame(width: whole.width, height: height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: whole.width * scale, height: height * scale, alignment: .topLeading)
            .offset(x: Self.mix(small.minX, whole.minX, share) - frame.minX,
                    y: Self.mix(small.minY, whole.minY, share) - frame.minY)
    }

    /// A tab's title under its card on the way: never scaled, laid out at
    /// its full width and cut off at the card's, as Safari's (the card
    /// alone grows; the words don't).
    private func titleLine(_ id: UUID, at index: Int, in frame: CGRect) -> some View {
        let small = glide.mini(index).offsetBy(dx: glide.cell.minX, dy: glide.cell.minY)
        let whole = glide.tile(index).offsetBy(dx: glide.card.minX, dy: glide.card.minY)
        let height = OverviewRow.gridTitleHeight
        let width = Self.mix(small.width, whole.width, share)
        let top = Self.mix(small.maxY, whole.maxY - height, share)
        return title(id)
            .frame(width: whole.width, height: height, alignment: .top)
            .frame(width: max(width, 1), height: height, alignment: .topLeading)
            .clipped()
            .offset(x: Self.mix(small.minX, whole.minX, share) - frame.minX, y: top - frame.minY)
    }

    /// The folder's name, where the folder has it: it blurs away over the
    /// first part of an opening, and comes back over the last of a fold.
    private func folderName(_ t: CGFloat) -> some View {
        let gone = Self.ramp(t, 0, 0.4)
        return Text(name)
            .font(.headline.weight(.bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: max(glide.cell.width - 2 * GroupFolder.inset - 12, 1))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .opacity(1 - gone)
            .blur(radius: 6 * gone)
    }

    /// The open group's name line (`GroupLine`'s look), coming in over the
    /// second half.
    private func nameLine(_ t: CGFloat) -> some View {
        let there = Self.ramp(t, 0.45, 1)
        return HStack(spacing: 6) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .fixedSize()
            Spacer(minLength: 14)
        }
        .padding(.leading, 14)
        .frame(minHeight: GroupCard.headerHeight)
        .padding(.horizontal, GroupCard.side)
        .frame(width: glide.card.width, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .opacity(there)
        .blur(radius: 6 * (1 - there))
    }
}
