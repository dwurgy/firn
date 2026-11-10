import FirnCore
import SwiftUI

/// Where one page sits in `PageArea`: a half, or the whole width (`side` nil).
struct PageSlot: Identifiable {
    /// The empty page beside one being picked for, or with no tab at all.
    static let emptyID = UUID()
    /// A frost on each side, so moving halves thaws one and forms the other.
    static let leftFrostID = UUID()
    static let rightFrostID = UUID()
    let id: UUID
    let tab: FirnCore.Tab?
    let side: SplitSide?
    var isFrost = false
}

/// A tab dragged out of the sidebar, over a half of the page.
struct PageDrop: Equatable {
    let tab: FirnCore.Tab
    private let tabID: UUID
    var side: SplitSide

    @MainActor init(tab: FirnCore.Tab, side: SplitSide) {
        self.tab = tab
        tabID = tab.id
        self.side = side
    }

    static func == (a: PageDrop, b: PageDrop) -> Bool { a.tabID == b.tabID && a.side == b.side }
}

/// Where a dragged tab would open: frost over that half, in the space's
/// color (`docs/split-drop-design.html`), forming from under its picture.
struct DropFrost: View {
    let window: WindowModel
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where it starts forming: under the picture, in the frost's own space.
    @State private var origin: CGPoint?
    /// 0 nothing yet, 1 frosted across the whole half.
    @State private var formed: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        GeometryReader { proxy in
            let size = proxy.size
            let start = origin ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = Self.farthest(from: start, in: size) + Self.softEdge * 2
            ZStack {
                glass(shape)
                shape.strokeBorder(Theme.frost, lineWidth: 1.5)
            }
            // Ice forming on a window: a soft-edged circle widening from the picture.
            .mask {
                Circle()
                    .frame(width: reach * 2, height: reach * 2)
                    .scaleEffect(formed)
                    .position(start)
                    .blur(radius: Self.softEdge)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BrowserWindow.space)) } action: { begin(in: $0) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let softEdge: CGFloat = 24
    /// Once, when it first has a place: forms from under the picture.
    private func begin(in area: CGRect) {
        guard origin == nil, area.width > 0 else { return }
        var start = CGPoint(x: area.width / 2, y: area.height / 2)
        if let lift = window.tabLift {
            let card = Theme.liftedCard
            start = CGPoint(x: window.dragPointer.x + (0.5 - lift.grab.x) * card.width - area.minX,
                            y: window.dragPointer.y + (0.5 - lift.grab.y) * card.height - area.minY)
            start.x = min(max(start.x, 0), area.width)
            start.y = min(max(start.y, 0), area.height)
        }
        origin = start
        guard !reduceMotion else { formed = 1; return }
        withAnimation(.smooth(duration: 0.4)) { formed = 1 }
    }

    private static func farthest(from point: CGPoint, in size: CGSize) -> CGFloat {
        let dx = max(point.x, size.width - point.x), dy = max(point.y, size.height - point.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    @ViewBuilder private func glass(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid).overlay { shape.fill(color.opacity(Theme.dropTint)) }
        } else if #available(macOS 26, *) {
            shape.fill(.clear).glassEffect(.regular.tint(color.opacity(Theme.dropTint)), in: shape)
        } else {
            shape.fill(.ultraThinMaterial).overlay { shape.fill(color.opacity(Theme.dropTint)) }
        }
    }
}

extension SplitSide {
    var other: SplitSide { self == .left ? .right : .left }
}

/// Where the pages sit while a split is being picked: halves, as a new split has.
enum SplitPicking {
    static func leftWidth(in width: CGFloat) -> CGFloat {
        max(width - Theme.pageInset, 1) * 0.5
    }
}

/// One page, floating in the frame, or a calm empty page with no tab.
struct PagePane: View {
    let store: BrowserStore
    let tab: FirnCore.Tab?
    /// The space's color, when this is the empty page (no tab open).
    var firstLight: String? = nil
    var onPointerDown: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        ZStack {
            // The sidebar covers whatever shadow falls on it, which would leave a hard
            // line in the gap. So the shadow leans right and down and fades inside the gap.
            shape
                .fill(Theme.page)
                .shadow(color: Theme.shadowPageFar, radius: 12, x: 4, y: 8)
            if tab == nil, let firstLight {
                FirstLightScene(spaceColor: firstLight)
                    .clipShape(shape)
                    .transition(.opacity)
            }
            if let tab, let page = tab.page {
                PageView(page: page, cornerRadius: Theme.pageCornerRadius, onPointerDown: onPointerDown)
                    .overlay {
                        if let error = page.loadError {
                            LoadErrorView(error: error, isRetrying: page.isLoading, retry: page.reload)
                                .clipShape(shape)
                                .transition(.opacity)
                                .simultaneousGesture(TapGesture().onEnded { onPointerDown?() })
                        } else if page.url == nil {
                            // Until something has loaded, show Firn's calm page color, not WebKit's white.
                            shape.fill(Theme.page).allowsHitTesting(false)
                        }
                    }
                    // A plain fade either way; quicker with Reduce Motion.
                    .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: page.loadError)
                    .overlay(alignment: .topLeading) { fillList(on: tab, page: page) }
                    .onChange(of: page.url) {
                        if store.fillOffer?.tabID == tab.id { store.dismissFillOffer() }
                    }
                    .id(tab.id)
            }
        }
    }
}

extension PagePane {
    /// The saved logins under a sign-in field just clicked on this page.
    /// It fades in and out, with a short drop when motion is on.
    @ViewBuilder
    private func fillList(on tab: FirnCore.Tab, page: any PageController) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let offer = store.fillOffer, offer.tabID == tab.id, page.loadError == nil {
                    PasswordFillList(store: store, offer: offer,
                                     color: Theme.spaceColor(store.activeSpace.color), pageSize: proxy.size)
                        .id(offer.id)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeOut(duration: 0.15), value: store.fillOffer?.id)
        }
        // Never in the way of the page when there's no list.
        .allowsHitTesting(store.fillOffer?.tabID == tab.id)
    }
}
