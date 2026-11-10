import FirnCore
import SwiftUI

/// Watches the pointer while a Basecamp tile is over the tab list (or a tab
/// over Basecamp), so only this redraws as it moves, not the list.
struct PointerWatch: View {
    let window: WindowModel
    let moved: (CGPoint) -> Void

    var body: some View {
        Color.clear.onChange(of: window.dragPointer) { moved(window.dragPointer) }
    }
}

/// Where a dragged tab would land: a place among a group's tabs, or in the
/// tab list, where each group counts as one (not counting the tab itself).
enum DropTarget: Equatable {
    case group(UUID, Int)
    case list(Int)
}

struct TabDrag {
    let tab: FirnCore.Tab
    /// Where the pointer holds the row, from its top-left.
    let grab: CGSize
    /// The pointer, in the list's space.
    var location: CGPoint
    var target: DropTarget
    /// True while the lifted copy glides into its slot after the drop.
    var settling = false
    /// True when moved from the menu: the copy follows its slot, not a pointer.
    var follows = false
    /// True while it's out over the page (see `TabList.overPage`).
    var overPage = false
    /// True while it's held up over Basecamp (see `TabList.overBasecamp`).
    var overBasecamp = false
    /// A Basecamp tile held out over the list (Basecamp's drag moves it).
    var fromBasecamp = false
    /// The loose row it's held over, to start a group with; the list
    /// holds still meanwhile (`target` stays where it was).
    var onto: UUID?
}

/// The group a tab held over a loose row would make with it (see
/// `TabList.holdOnto`). Not in the store until it's let go there.
struct GroupPreview {
    let group: TabGroup
    /// The loose row it's held over.
    let other: FirnCore.Tab
    /// True if the dragged tab goes above `other`; it follows the tab.
    var above: Bool
    /// False while it shows as just the rows, before its frost forms or
    /// once it has thawed.
    var formed = false
}

struct GroupDrag {
    let group: TabGroup
    /// Where the pointer holds the card, from its top-left.
    let grab: CGSize
    /// The pointer, in the list's space.
    var location: CGPoint
    /// Its place in the tab list, not counting itself.
    var target: Int
    /// True while the lifted card glides into its slot after the drop.
    var settling = false
}

struct NewTabRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New tab", systemImage: "plus")
                .labelStyle(RowLabelStyle(color: Theme.muted))
        }
        .buttonStyle(RowButtonStyle(isActive: false))
        .help("New tab (⌘T)")
    }
}

struct TabRow<MenuItems: View>: View {
    let tab: FirnCore.Tab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void
    @ViewBuilder let menu: MenuItems
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Label {
                    Text(tab.title)
                } icon: {
                    SiteIconView(icon: tab.icon, size: 16) { Image(systemName: "globe") }
                }
                    .labelStyle(RowLabelStyle(color: isActive ? Theme.ink : Theme.tabRest))
                Spacer(minLength: 0)
            }
            // Room for the speaker and close button, so long titles stop short of them.
            .padding(.trailing, (hovering ? 20 : 0) + (tab.sound != .silent ? 22 : 0))
        }
        .buttonStyle(RowButtonStyle(isActive: isActive))
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                SoundButton(tab: tab)
                if hovering {
                    Button("Close tab", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(CloseButtonStyle())
                        .help("Close tab (⌘W)")
                }
            }
            .padding(.trailing, 8)
        }
        .onHover { hovering = $0 }
        // Icons beside the words: SwiftUI's Mac menus leave them out otherwise.
        .contextMenu { menu.labelStyle(.titleAndIcon) }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: "Close tab", close)
    }
}

/// A tab's speaker, there only while its page makes sound (or would, if
/// it weren't muted). Clicking it mutes or unmutes the tab. It fades in
/// and out as the sound starts and stops.
struct SoundButton: View {
    let tab: FirnCore.Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sound = tab.sound
        ZStack {
            if sound != .silent {
                let muted = sound == .muted
                Button(muted ? "Unmute tab" : "Mute tab",
                       systemImage: muted ? "speaker.slash" : "speaker.wave.2") { tab.toggleMuted() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(CloseButtonStyle())
                    .contentTransition(.symbolEffect(.replace))
                    .help(muted ? "Unmute tab" : "Mute tab")
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: sound)
    }
}

/// "Mute Tab" or "Unmute Tab" for a tab's menu, while it makes sound.
struct MuteMenuItem: View {
    let tab: FirnCore.Tab

    var body: some View {
        switch tab.sound {
        case .silent: EmptyView()
        case .playing: Button("Mute Tab", systemImage: "speaker.slash") { tab.toggleMuted() }
        case .muted: Button("Unmute Tab", systemImage: "speaker.wave.2") { tab.toggleMuted() }
        }
    }
}

/// Split view's row (docs/split-row-design.html): one ordinary tab row,
/// lifted like the tab on screen while the split is, holding both pages
/// side by side, each its icon and a title that fades at the edge. Their
/// widths follow the split's divider. Which page is in use shows only on
/// the pages themselves (their frost ring), never here. Clicking a half
/// shows the split with that page in use.
///
/// Its motion: a new split's right half grows in beside the left as the
/// left's title draws back. Separate Tabs ends it at once, the right's tab
/// gliding in as its own row below; closing one half closes it at once.
/// Reduce Motion: short fades.
struct SplitRow<MenuItems: View>: View {
    let left: FirnCore.Tab
    let right: FirnCore.Tab
    /// The left page's share of the width, as on screen.
    let fraction: Double
    /// The page in use, when the split is on screen.
    let inUseID: UUID?
    let select: (FirnCore.Tab) -> Void
    /// Closes a half.
    let close: (FirnCore.Tab) -> Void
    /// Separates the two tabs.
    let separate: () -> Void
    /// Called once a new split's halves have formed.
    var formed: () -> Void = {}
    @ViewBuilder let menu: (FirnCore.Tab) -> MenuItems

    /// Pointing anywhere on the row shows both halves' close buttons, as in Dia.
    @State private var rowHovered = false
    /// While forming, the left half's share, in place of the split's own.
    @State private var share: Double?
    /// The right half, while it's forming.
    @State private var faded: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(left: FirnCore.Tab, right: FirnCore.Tab, fraction: Double, inUseID: UUID?, forming: Bool = false,
         select: @escaping (FirnCore.Tab) -> Void, close: @escaping (FirnCore.Tab) -> Void,
         separate: @escaping () -> Void, formed: @escaping () -> Void = {},
         @ViewBuilder menu: @escaping (FirnCore.Tab) -> MenuItems) {
        self.left = left
        self.right = right
        self.fraction = fraction
        self.inUseID = inUseID
        self.select = select
        self.close = close
        self.separate = separate
        self.formed = formed
        self.menu = menu
        // A new split starts as its left tab's row, ready to open.
        _share = State(initialValue: forming ? 1 : nil)
        _faded = State(initialValue: forming ? right.id : nil)
    }

    private var isOnScreen: Bool { inUseID != nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
        SplitPanes(share: share ?? fraction) {
            half(left)
            half(right)
        }
        .frame(height: Theme.rowHeight)
        .background {
            if isOnScreen { ActiveTabBackground() } else { shape.fill(rowHovered ? Theme.hover : .clear) }
        }
        .contentShape(shape)
        .onHover { rowHovered = $0 }
        .onAppear { if share != nil { form() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split view")
    }

    private func half(_ tab: FirnCore.Tab) -> some View {
        let hovering = rowHovered
        return Button { select(tab) } label: {
            HStack(spacing: 8) {
                SiteIconView(icon: tab.icon, size: 16) { Image(systemName: "globe") }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 16)
                FadingTitle(text: tab.title, onScreen: isOnScreen)
            }
            .padding(.leading, Theme.rowPadding)
            // Room for the speaker and close button, so the title fades out before them.
            .padding(.trailing, (hovering ? 28 : 4) + (tab.sound != .silent ? 22 : 0))
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Its contents shrink away when it closes or the split forms.
        .clipped()
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                SoundButton(tab: tab)
                if hovering && faded == nil {
                    Button("Close tab", systemImage: "xmark") { closeHalf(tab) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(CloseButtonStyle())
                        .help(tab.id == inUseID ? "Close tab (⌘W)" : "Close tab")
                }
            }
            .padding(.trailing, 8)
        }
        .opacity(faded == tab.id ? 0 : 1)
        .contextMenu {
            Group {
                Button("Separate Tabs", systemImage: "rectangle.split.2x1.slash") { part() }
                Divider()
                menu(tab)
            }
            .labelStyle(.titleAndIcon)
        }
        .accessibilityAddTraits(tab.id == inUseID ? .isSelected : [])
        .accessibilityAction(named: "Close tab") { closeHalf(tab) }
        .accessibilityAction(named: "Separate Tabs") { part() }
    }

    /// A new split: the right half grows in beside the left.
    private func form() {
        let animation = reduceMotion ? Animation.easeOut(duration: 0.2) : Theme.thaw
        withAnimation(animation) {
            share = nil
            faded = nil
        } completion: {
            formed()
        }
    }

    /// Separate Tabs: the split ends at once, its pages and rows gliding
    /// apart together (no show first; you just want the two tabs).
    private func part() {
        separate()
    }

    /// Closing one half: it goes at once, the other page widening as it does.
    private func closeHalf(_ tab: FirnCore.Tab) {
        close(tab)
    }
}

/// A split row's two halves, side by side: the left takes `share` of the
/// width, the right the rest. Animatable, so the halves grow and follow
/// the divider smoothly.
struct SplitPanes: Layout {
    var share: Double

    var animatableData: Double {
        get { share }
        set { share = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 240, height: proposal.height ?? Theme.rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let left = bounds.width * min(max(share, 0), 1)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: left, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + left, y: bounds.minY),
                          proposal: ProposedViewSize(width: bounds.width - left, height: bounds.height))
    }
}

/// A title on one line that fades out at the edge instead of ending in "…".
struct FadingTitle: View {
    let text: String
    /// Both halves lead while the split is on screen, like the tab on screen.
    let onScreen: Bool

    var body: some View {
        Text(text)
            .font(Theme.tabFont)
            .foregroundStyle(onScreen ? Theme.ink : Theme.tabRest)
            .modifier(FadesAtEdge())
            .accessibilityLabel(text)
    }
}

/// A one-line title that fades out at the row's edge rather than ending in
/// "…". Its text never changes as the row's width does, so it glides with
/// its row (re-cut with "…" mid-glide, a title was redrawn and broke away
/// from its row; David, 2026-10-22).
struct FadesAtEdge: ViewModifier {
    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask { TrailingFade(width: 18) }
    }
}

/// A mask that fades its view out over the last `width` points at the right.
struct TrailingFade: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
        }
    }
}

/// A point kept out of SwiftUI's view updates.
final class PointBox {
    var point: CGPoint = .zero
}

/// A rectangle kept out of SwiftUI's view updates.
final class RectBox {
    var rect: CGRect = .zero
}
