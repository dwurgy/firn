import FirnCore
import SwiftUI

/// The page on screen, floating in the frame. With no tab open, a calm
/// empty page. In split view, two pages side by side, with a gap between
/// them that can be dragged (double-click evens them) and a thin frost ring
/// on the page in use; pressing the other page moves it there, and the
/// address bar and buttons follow. Picking a page for a split, the page
/// takes the left half beside an empty one. One layout for all three, so
/// the left page never changes places between them (swapping whole layouts
/// left the old one stuck over the new split).
struct PageArea: View {
    let store: BrowserStore
    let window: WindowModel
    @State private var startFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = store.activeTab
        let split = active.flatMap { store.split(of: $0) }
        let pair = split.map { store.tabs(in: $0) } ?? []
        let drop = window.pageDrop
        // Picking a split's page, or a tab dragged over one page, shows
        // halves, as a new split has.
        let fraction = split?.leftFraction ?? (window.isPickingSplit || drop != nil ? 0.5 : nil)
        GeometryReader { proxy in
            let room = max(proxy.size.width - Theme.pageInset, 1)
            let leftWidth = fraction.map { room * $0 } ?? proxy.size.width
            let rightX = leftWidth + Theme.pageInset
            // Each page keeps its place in a ZStack, by its tab, so it glides
            // from one half to the other instead of being made again.
            ZStack(alignment: .topLeading) {
                ForEach(slots(active: active, pair: pair, drop: drop)) { slot in
                    Group {
                        if slot.isFrost, drop != nil {
                            DropFrost(window: window, color: Theme.spaceColor(store.activeSpace.color))
                                .transition(.opacity)
                        } else {
                            page(slot.tab, inUseID: split == nil ? nil : active?.id,
                                 frosted: split != nil && drop?.side == slot.side ? drop?.tab : nil)
                        }
                    }
                    .frame(width: slot.side == nil ? proxy.size.width
                               : slot.side == .left ? leftWidth : max(proxy.size.width - rightX, 0),
                           height: proxy.size.height)
                    // Padding, not an offset, so the web view itself moves, not just its picture.
                    .padding(.leading, slot.side == .right ? rightX : 0)
                }
                if let split {
                    grip(split, room: room)
                        .frame(height: proxy.size.height)
                        .padding(.leading, leftWidth)
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BrowserWindow.space)) } action: {
            window.pagesFrame = $0
        }
    }

    /// What shows where: a split's two pages; one page beside the frost of
    /// a tab dragged over the other half (or beside an empty page while
    /// one is picked); or one page across the whole width.
    private func slots(active: FirnCore.Tab?, pair: [FirnCore.Tab], drop: PageDrop?) -> [PageSlot] {
        if pair.count == 2 {
            return [PageSlot(id: pair[0].id, tab: pair[0], side: .left),
                    PageSlot(id: pair[1].id, tab: pair[1], side: .right)]
        }
        let id = active?.id ?? PageSlot.emptyID
        if let drop {
            // The tab on screen dragged over a half goes there; the frost
            // shows where a new page will be.
            let frostSide = drop.tab.id == active?.id ? drop.side.other : drop.side
            return [PageSlot(id: id, tab: active, side: frostSide.other),
                    PageSlot(id: frostSide == .left ? PageSlot.leftFrostID : PageSlot.rightFrostID,
                             tab: nil, side: frostSide, isFrost: true)]
        }
        if window.isPickingSplit {
            return [PageSlot(id: id, tab: active, side: window.splitPickSide),
                    PageSlot(id: PageSlot.emptyID, tab: nil, side: window.splitPickSide.other)]
        }
        return [PageSlot(id: id, tab: active, side: nil)]
    }

    private func grip(_ split: SplitGroup, room: CGFloat) -> some View {
        SidebarResizeGrip(
            onDrag: { distance in
                let start = startFraction ?? split.leftFraction
                startFraction = start
                store.setLeftFraction(of: split, to: start + distance / room)
            },
            onEnd: { startFraction = nil },
            onDoubleClick: {
                withAnimation(Theme.slide(reduceMotion: reduceMotion)) {
                    store.setLeftFraction(of: split, to: 0.5)
                }
            }
        )
        .frame(width: Theme.pageInset)
        .accessibilityLabel("Resize split view")
        .accessibilityValue("Left page \(Int((split.leftFraction * 100).rounded())) percent")
        // VoiceOver can move the divider too, a twentieth of the way at a time.
        .accessibilityAdjustableAction { direction in
            let step = switch direction {
            case .increment: 0.05
            case .decrement: -0.05
            @unknown default: 0.0
            }
            store.setLeftFraction(of: split, to: split.leftFraction + step)
        }
    }

    /// A page; in split view (`inUseID` set), ringed when it's the one in
    /// use, and made the one in use when pressed.
    /// `frosted`: a tab dragged over this half of a split, which would take its place.
    private func page(_ tab: FirnCore.Tab?, inUseID: UUID?, frosted: FirnCore.Tab?) -> some View {
        let isInUse = tab != nil && tab?.id == inUseID
        let pressable = inUseID != nil && !isInUse
        // With no tab open at all, the empty page is First light, in this space's snow.
        let firstLight = store.activeTab == nil && inUseID == nil ? store.activeSpace.color : nil
        return PagePane(store: store, tab: tab, firstLight: firstLight,
                        onPointerDown: pressable ? { if let tab { store.select(tab) } } : nil)
            .overlay {
                if frosted != nil {
                    DropFrost(window: window, color: Theme.spaceColor(store.activeSpace.color))
                        .transition(.opacity)
                }
            }
            .overlay {
                if window.isFullScreen { MenuBarCover(drop: window.menuBarDrop, color: store.activeSpace.color) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                    .strokeBorder(Theme.frost, lineWidth: 2)
                    .padding(.top, window.menuBarDrop)
                    .opacity(isInUse ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: isInUse)
    }
}

/// In full screen, with the menu bar down: the window's own frame, laid over
/// the page's top, so the page's edge sits as far under the menu bar as it
/// does under the screen's edge at rest. The page underneath keeps its size
/// (no reflow); its top is only covered, as Dia's is. SwiftUI can't clip the
/// web view (its corners are its own layer's), so this covers instead.
struct MenuBarCover: View {
    var drop: CGFloat
    let color: String

    var body: some View {
        let cover = PageTopCover(drop: drop, radius: Theme.pageCornerRadius)
        ZStack {
            FrameGlass()
            SpaceTint(color: color)
        }
        .mask(cover)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The page's top `drop` points, with its corners rounded again below them.
struct PageTopCover: Shape {
    var drop: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { drop }
        set { drop = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard drop >= 0.5 else { return Path() }
        // The band down to where the new corners end, less the page below the new edge.
        let band = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: drop + radius))
        let page = Path(roundedRect: CGRect(x: rect.minX, y: rect.minY + drop, width: rect.width,
                                            height: max(rect.height - drop, radius * 2)),
                        cornerRadius: radius, style: .continuous)
        return band.subtracting(page)
    }
}
