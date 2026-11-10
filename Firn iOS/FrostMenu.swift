import SwiftUI
import UIKit

/// Firn's own hold menu (iPhone, phase 3 step 3c; look from
/// docs/hold-menu-design.html). iOS's menu takes the finger away from
/// Firn once it opens, so nothing could be dragged off it without iOS's
/// own copy of the tile flickering in (David, 2026-11-09: Safari and Brave
/// show it too). With Firn's own menu the finger stays Firn's.
///
/// An open menu: the tile it's for (global points, as lifted) and its items.
struct OpenHoldMenu {
    /// This opening (the same tile can open its menu again).
    let token = UUID()
    let id: UUID
    let tile: CGRect
    /// Which side of the tile the finger held: the menu lines up with it.
    let fingerX: CGFloat
    let sections: [[HoldMenuItem]]
    /// The screen as the menu opened, small, for the card's frost.
    let backdrop: UIImage?
}

/// The open menu, placed beside its tile: below it if there's room, else
/// above, lined up with the side of the tile nearest the finger, and kept
/// inside the screen's safe area. Fills the safe area; only the card takes
/// touches.
struct HoldMenuPlacement: View {
    /// The open menu; nil while none is (the last one thaws where it was).
    let menu: OpenHoldMenu?
    let space: String
    let pick: (HoldMenuItem) -> Void
    /// A tap anywhere but the card, or VoiceOver's escape: the menu closes.
    let dismiss: () -> Void

    static let width: CGFloat = 250
    /// Between the tile and the card, and the card and the screen's edges.
    static let gap: CGFloat = 10
    static let margin: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var last: OpenHoldMenu?
    /// The safe area (global), measured by a view that takes no touches.
    @State private var safe: CGRect = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { safe = $0 }
            if menu != nil {
                // Under the card: the whole screen, the dim drawn under the
                // lifted tab. A tap there closes the menu.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)
                    .accessibilityLabel("Close Menu")
                    .accessibilityAddTraits(.isButton)
            }
            if let placed = menu ?? last, safe.width > 0 {
                let place = placement(of: placed, in: safe)
                let frost = AnyTransition.modifier(
                    active: Frosting(formed: false, anchor: place.anchor, still: reduceMotion),
                    identity: Frosting(formed: true, anchor: place.anchor, still: reduceMotion))
                // Hung from a line at the tile's edge (zero height), below
                // it or above it, so a height change (Move to Group's list)
                // glides away from the tile.
                ZStack {
                    if let menu {
                        FrostMenu(sections: menu.sections, space: space, backdrop: menu.backdrop, pick: pick)
                            .frame(width: place.width)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(menu.token)
                            .transition(.asymmetric(
                                insertion: frost.animation(reduceMotion ? .easeOut(duration: 0.2)
                                                                        : .smooth(duration: 0.22)),
                                removal: frost.animation(.easeOut(duration: 0.15))))
                    }
                }
                .frame(width: place.width, height: 0, alignment: place.below ? .top : .bottom)
                .offset(x: place.x - safe.minX, y: place.line - safe.minY)
            }
        }
        .onChange(of: menu?.token) { if let menu { last = menu } }
        .accessibilityAction(.escape) { if menu != nil { dismiss() } }
    }

    private struct Place {
        let x: CGFloat
        let width: CGFloat
        /// The line the card hangs from (below) or stands on (above).
        let line: CGFloat
        let below: Bool
        let anchor: UnitPoint
    }

    /// Where the card goes. Its height is worked out from its rows (larger
    /// text may make it a little taller, away from the tile).
    private func placement(of menu: OpenHoldMenu, in safe: CGRect) -> Place {
        let width = min(Self.width, safe.width - 2 * Self.margin)
        let height = FrostMenu.height(of: menu.sections)
        let tile = menu.tile
        let leading = menu.fingerX < tile.midX
        let minX = safe.minX + Self.margin
        let maxX = safe.maxX - Self.margin - width
        let x = min(max(leading ? tile.minX : tile.maxX - width, minX), maxX)
        let top = safe.minY + Self.margin
        let bottom = safe.maxY - Self.margin
        let roomBelow = bottom - (tile.maxY + Self.gap)
        let roomAbove = (tile.minY - Self.gap) - top
        let below = roomBelow >= height || (roomAbove < height && roomBelow >= roomAbove)
        let ox: CGFloat = leading ? 0.2 : 0.8
        if below {
            // Too little room either way: it covers the tile's end rather
            // than leave the screen.
            let y = roomBelow >= height ? tile.maxY + Self.gap : max(top, bottom - height)
            return Place(x: x, width: width, line: y, below: true, anchor: UnitPoint(x: ox, y: 0))
        }
        let y = roomAbove >= height ? tile.minY - Self.gap : min(bottom, top + height)
        return Place(x: x, width: width, line: y, below: false, anchor: UnitPoint(x: ox, y: 1))
    }
}

/// The card forming like frost: from a little smaller, soft, and clear,
/// out of the tile's side. With Reduce Motion, only a fade.
private struct Frosting: ViewModifier {
    let formed: Bool
    let anchor: UnitPoint
    let still: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(formed || still ? 1 : 0.86, anchor: anchor)
            .blur(radius: formed || still ? 0 : 6)
            .opacity(formed ? 1 : 0)
    }
}

/// The menu's card: Firn's frost, 14pt corners, a warm shadow; 44pt rows,
/// a symbol then the words; sections set apart by a hairline. Close rows
/// in muted terracotta. A row with a list (Move to Group) opens it in the
/// same card, with a back row at the top.
struct FrostMenu: View {
    let sections: [[HoldMenuItem]]
    let space: String
    let backdrop: UIImage?
    let pick: (HoldMenuItem) -> Void

    static let rowHeight: CGFloat = 44
    static let padding: CGFloat = 4
    /// A hairline with 4pt above and below.
    static let separator: CGFloat = 9

    /// The card's height at the usual text size.
    static func height(of sections: [[HoldMenuItem]]) -> CGFloat {
        let shown = sections.filter { !$0.isEmpty }
        let rows = shown.reduce(0) { $0 + $1.count }
        return 2 * padding + CGFloat(rows) * rowHeight + CGFloat(max(shown.count - 1, 0)) * separator
    }

    /// The row whose list is open (its section and place), if any.
    @State private var open: [Int]?
    @State private var turns = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [[HoldMenuItem]] { sections.filter { !$0.isEmpty } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            if let open, let parent = item(at: open) {
                Group {
                    Button { turn(to: nil) } label: {
                        MenuRow(title: parent.title, symbol: "chevron.left", back: true)
                    }
                    .accessibilityLabel("Back")
                    MenuSeparator()
                    ForEach(Array(parent.children.enumerated()), id: \.offset) { _, child in
                        Button { pick(child) } label: {
                            MenuRow(title: child.title, dot: Theme.spaceColor(space))
                        }
                    }
                }
                .transition(.opacity)
            } else {
                Group {
                    ForEach(Array(shown.enumerated()), id: \.offset) { s, items in
                        if s > 0 { MenuSeparator() }
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            Button {
                                if item.children.isEmpty { pick(item) } else { turn(to: [s, i]) }
                            } label: {
                                MenuRow(title: item.title, symbol: item.systemImage, closes: item.closes,
                                        more: !item.children.isEmpty)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .buttonStyle(MenuRowStyle())
        .padding(Self.padding)
        // Never takes a touch: its picture of the screen is clipped to the
        // card but still covers the whole screen, and it took every tap
        // outside the card, so the menu wouldn't close (2026-11-09).
        .background { MenuFrost(backdrop: backdrop).allowsHitTesting(false) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Theme.holdMenuEdge, lineWidth: 1)
            // The top's light, as on Basecamp's tiles.
            shape.strokeBorder(LinearGradient(colors: [Theme.tileRimTop, .clear],
                                              startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                               lineWidth: 1)
        }
        .shadow(color: Theme.shadowSoft, radius: 3, y: 2)
        .shadow(color: Theme.holdMenuShadow, radius: 17, y: 14)
        .sensoryFeedback(.impact(weight: .light), trigger: turns)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func item(at path: [Int]) -> HoldMenuItem? {
        guard path.count == 2, shown.indices.contains(path[0]), shown[path[0]].indices.contains(path[1])
        else { return nil }
        return shown[path[0]][path[1]]
    }

    /// Into or out of a row's list: the card glides to its new height.
    private func turn(to path: [Int]?) {
        turns += 1
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2)) { open = path }
    }
}

/// Behind the card: a real blur of the screen as the menu opened (dimmed,
/// as it is behind the card), under the veil, at one level for every
/// screen. The screen's picture is lined up with where the card is. With
/// Reduce Transparency, a solid fill.
private struct MenuFrost: View {
    let backdrop: UIImage?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Theme.tileSolid
        } else {
            GeometryReader { box in
                let frame = box.frame(in: .global)
                ZStack(alignment: .topLeading) {
                    if let backdrop {
                        Image(uiImage: backdrop)
                            .resizable()
                            .frame(width: backdrop.size.width, height: backdrop.size.height)
                            .offset(x: -frame.minX, y: -frame.minY)
                            // Soft enough that what's behind is light and
                            // color, never shapes that fight the words; a
                            // bright page is held down a little in dark mode
                            // (David, 2026-11-09: readability).
                            .blur(radius: 30, opaque: true)
                            .saturation(1.3)
                            .brightness(scheme == .light ? 0.04 : -0.08)
                        Theme.holdDim
                    } else {
                        Theme.frame
                    }
                    Theme.holdMenuVeil
                }
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipped()
            }
        }
    }
}

private struct MenuRow: View {
    let title: String
    var symbol: String?
    var closes = false
    var more = false
    var back = false
    var dot: Color?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                } else if let symbol {
                    // 16pt, so the widest (Basecamp's mountains) fits the column.
                    Image(systemName: symbol)
                        .font(back ? .footnote.weight(.semibold) : .system(size: 16))
                }
            }
            .frame(width: 24)
            .foregroundStyle(closes ? Theme.menuDanger : Theme.muted)
            .accessibilityHidden(true)
            Text(title)
                .font(back ? .footnote.weight(.semibold) : .callout)
                .foregroundStyle(closes ? Theme.menuDanger : back ? Theme.muted : Theme.ink)
                .lineLimit(1)
                // Tightens a little before it's cut off ("New Group with This Tab").
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if more {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: FrostMenu.rowHeight)
        .contentShape(Rectangle())
    }
}

/// A warm wash under the finger.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : .clear)
            }
    }
}

private struct MenuSeparator: View {
    var body: some View {
        Theme.holdMenuHairline
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

/// A small picture of the whole screen, taken as a menu opens, for its
/// frost. Kept in memory with the open menu only, never saved.
@MainActor enum ScreenPicture {
    static func take() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return nil }
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        // It's blurred anyway: a quarter of the points is plenty, and quick.
        format.scale = 0.25
        format.opaque = true
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}
