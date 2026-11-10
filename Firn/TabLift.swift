import FirnCore
import SwiftUI

/// A tab lifted off the sidebar. It's drawn over the whole window, not in
/// the list, so it can leave the sidebar. In the sidebar it's the row,
/// kept to the sidebar's column (giving a little toward the pointer); once
/// the pointer is out over a page where it could open in split view, it
/// comes loose as a small picture of its page (as in Dia). Let go in the
/// sidebar, it glides into its slot. It keeps hold of the same spot under
/// the pointer as it changes shape.
struct TabLift {
    let tab: FirnCore.Tab
    /// The row as drawn in the sidebar.
    let row: AnyView
    /// Where the pointer holds it, as a fraction of its width and height.
    let grab: CGPoint
    /// The row's width (its slot's, which narrows inside a group card).
    var width: CGFloat
    /// The row's left edge in the window: its slot's.
    var column: CGFloat
    /// Out over the page: the picture, not the row.
    var isCard = false
    /// The page's picture, once taken; nil for a sleeping page.
    var preview: CGImage?
    /// Let go in the sidebar: the slot it glides into, in the window's space.
    var settle: CGRect?
    /// Settling into a folded group: it fades into the name line.
    var fades = false
    /// Held over a tab to make a group with it: solid, so the tab under it
    /// doesn't show through.
    var solid = false
    /// Settling into a group forming under it: just the row, no backing or
    /// shadow, so it lands on the glass as the row itself.
    var bare = false
    /// Picked up from Basecamp: the tile as drawn there, and where it's
    /// held, in the window's space.
    var tileFace: AnyView?
    var tile: CGRect?
    /// Drawn as the tile (in Basecamp), not the row (over the tab list).
    var isTile = false
    /// How high and low the row's top may go, in the window's space: the
    /// tab list's. Past these it only tugs (`Tug`).
    var reach: ClosedRange<CGFloat>?
}

/// A Basecamp tile dragged out over the tab list (see `WindowModel.tileInList`),
/// or a tab dragged up over Basecamp (`WindowModel.tabInBasecamp`).
struct TileInList: Equatable {
    let tab: FirnCore.Tab
    /// The tab's id, kept here so comparing needs no main actor.
    private let tabID: UUID
    /// Let go: the list settles it into its place.
    var released = false

    @MainActor init(tab: FirnCore.Tab) {
        self.tab = tab
        tabID = tab.id
    }

    static func == (a: Self, b: Self) -> Bool { a.tabID == b.tabID && a.released == b.released }
}

struct TabLiftGhost: View {
    let window: WindowModel

    var body: some View {
        if let lift = window.tabLift {
            ZStack(alignment: .topLeading) {
                lift.row
                    .frame(width: lift.width, height: Theme.rowHeight)
                    .opacity(lift.isCard || lift.isTile ? 0 : 1)
                if let face = lift.tileFace, let tile = lift.tile {
                    face
                        .frame(width: tile.width, height: tile.height)
                        .opacity(lift.isTile && !lift.isCard ? 1 : 0)
                }
                card(lift)
                    // At least the picture's size, so turning from the row
                    // (or tile) uncovers it rather than squeezing it.
                    .frame(minWidth: Theme.liftedCard.width, maxWidth: .infinity,
                           minHeight: Theme.liftedCard.height, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(lift.isCard ? 1 : 0)
            }
            .modifier(LiftPlacement(card: lift.isCard ? 1 : 0, settled: lift.settle == nil ? 0 : 1,
                                    width: lift.width, column: lift.column,
                                    pointer: window.dragPointer, grab: lift.grab, slot: lift.settle,
                                    tile: lift.tile, tileness: lift.isTile ? 1 : 0, reach: lift.reach,
                                    solid: lift.solid ? 1 : 0, bare: lift.bare ? 1 : 0))
            .opacity(lift.fades ? 0 : 1)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The page's picture, from the top; a sleeping page, its icon and title.
    @ViewBuilder private func card(_ lift: TabLift) -> some View {
        if let preview = lift.preview {
            LiftPicture(image: preview)
        } else {
            VStack(spacing: 8) {
                SiteIconView(icon: lift.tab.icon, size: 22) {
                    Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(Theme.muted)
                }
                Text(lift.tab.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            // The card's own size, not the row's it grows from, so it's centered.
            .frame(width: Theme.liftedCard.width, height: Theme.liftedCard.height)
        }
    }
}

/// The page's picture, from the top, filling the card. The ⌃Tab panel's cards too.
struct LiftPicture: View {
    let image: CGImage

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let scale = max(w / CGFloat(max(image.width, 1)), h / CGFloat(max(image.height, 1)))
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                .frame(width: w, height: h, alignment: .top)
                .clipped()
        }
    }
}

/// Where the lifted tab is and what shape it has: the row in the sidebar's
/// column, the picture at the pointer, or the row settling into its slot,
/// and every step between. Worked out from these numbers as they animate,
/// with the pointer read fresh each time, so the pointer moving never
/// interrupts a change of shape.
struct LiftPlacement: ViewModifier, Animatable {
    /// 0 the row, 1 the picture.
    var card: CGFloat
    /// 0 following the pointer, 1 in its slot.
    var settled: CGFloat
    var width: CGFloat
    var column: CGFloat
    let pointer: CGPoint
    let grab: CGPoint
    let slot: CGRect?
    /// A tile's held place, standing in for the row.
    let tile: CGRect?
    /// 0 the row, 1 the tile.
    var tileness: CGFloat
    let reach: ClosedRange<CGFloat>?
    /// 0 the usual backing, 1 fully solid.
    let solid: CGFloat
    /// 0 lifted, 1 just the row (backing and shadow gone).
    var bare: CGFloat

    nonisolated var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>,
                                                   AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(AnimatablePair(card, settled), tileness),
                           AnimatablePair(AnimatablePair(width, column), bare))
        }
        set {
            card = newValue.first.first.first
            settled = newValue.first.first.second
            tileness = newValue.first.second
            width = newValue.second.first.first
            column = newValue.second.first.second
            bare = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        // The row keeps to its column, giving at most 8pt toward the pointer,
        // as if about to come loose.
        let pull = pointer.x - (column + grab.x * width)
        var top = pointer.y - grab.y * Theme.rowHeight
        if let reach { top = Tug.held(top, reach.lowerBound, reach.upperBound) }
        var row = CGRect(x: column + 8 * CGFloat(tanh(Double(pull) / 60)),
                         y: top, width: width, height: Theme.rowHeight)
        if let slot { row = Self.mix(row, slot, settled) }
        if let tile { row = Self.mix(row, tile, tileness) }
        let size = Theme.liftedCard
        let picture = CGRect(x: pointer.x - grab.x * size.width, y: pointer.y - grab.y * size.height,
                             width: size.width, height: size.height)
        let frame = Self.mix(row, picture, card)
        let corner = Theme.tabRadius + (Theme.tileRadius - Theme.tabRadius) * (tile == nil ? 0 : tileness)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let lift = card
        return content
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .background {
                ZStack {
                    shape.fill(Theme.frame).opacity(solid)
                    LiftBacking(shape: shape)
                }
                .opacity(1 - bare)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.frost, lineWidth: 1).opacity(lift) }
            .shadow(color: Theme.shadowPageFar.opacity(1 - bare), radius: 8 + 6 * lift, y: 3 + 3 * lift)
            .offset(x: frame.minX, y: frame.minY)
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ amount: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * amount, y: a.minY + (b.minY - a.minY) * amount,
               width: a.width + (b.width - a.width) * amount, height: a.height + (b.height - a.height) * amount)
    }
}
