import AppKit
import FirnCore
import SwiftUI

/// The row at the bottom of the sidebar: the space on screen's name,
/// centered, in its color, with a dot for each space under it; the
/// overflow on the left and, while there are any, the space's downloads on
/// the right. The name opens the list of spaces. No space icons: a name
/// says where you are, and stays calm however many spaces there are
/// (David, 2026-10-25).
struct SpaceRow: View {
    let store: BrowserStore
    let window: WindowModel
    /// The space waiting on "Delete Space…"'s confirmation.
    @State private var deleting: Space?
    /// How far along the "Tidied away" pill is.
    @State private var pill = PillPhase.hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum PillPhase { case hidden, frosted, open }

    var body: some View {
        HStack(spacing: 2) {
            // As wide as the downloads button's spot, so the name sits truly
            // centered between the two.
            OverflowButton(store: store, window: window)
            Group {
                VStack(spacing: 2) {
                    SpaceNameButton(store: store, window: window) { deleting = $0 }
                    if store.spaces.count > 1 {
                        SpaceDots(store: store, window: window)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                DownloadsButton(store: store, window: window)
            }
            // The name steps back while the pill speaks.
            .opacity(pill == .open ? 0 : 1)
        }
        .overlay(alignment: .leading) {
            if pill != .hidden, let announcement = window.tidyAnnouncement {
                TidyPill(text: announcement.text, open: pill == .open,
                         color: Theme.spaceColor(store.activeSpace.color)) {
                    window.showsOverflow = true
                }
                .transition(.opacity)
            }
        }
        .frame(minHeight: Theme.rowHeight)
        .task(id: window.tidyAnnouncement?.id) { await announce() }
        .confirmationDialog(
            deleting.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { space in
            Button("Delete Space", role: .destructive) {
                window.showSpace { store.deleteSpace(space) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { space in
            Text(deleteMessage(for: space))
        }
    }

    /// Frost forms over the overflow button, it widens to say how many tabs
    /// were tidied away, holds, and thaws back. Reduce Motion: the pill
    /// fades in and out.
    private func announce() async {
        guard window.tidyAnnouncement != nil else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { pill = .open }
            try? await Task.sleep(for: .seconds(2.8))
            withAnimation(.easeOut(duration: 0.3)) { pill = .hidden }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { pill = .frosted }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(Theme.thaw) { pill = .open }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(Theme.thaw) { pill = .frosted }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.25)) { pill = .hidden }
        }
        try? await Task.sleep(for: .milliseconds(300))
        // A newer announcement has taken over.
        guard !Task.isCancelled else { return }
        window.tidyAnnouncement = nil
    }

    /// Says plainly what goes: with a separate space, its sign-ins too; with
    /// a shared one, which space keeps them.
    private func deleteMessage(for space: Space) -> String {
        let goes = "Its tabs, groups, and Basecamp will be deleted."
        if let other = store.spacesSharingData(with: space).first {
            return "\(goes) Its sign-ins stay, because “\(other.name)” still uses them."
        }
        return "\(goes) So will its sign-ins, cookies, and site data. This can’t be undone."
    }
}

/// The space on screen's name, in its color. A click opens the list of
/// spaces; so does a right-click.
private struct SpaceNameButton: View {
    let store: BrowserStore
    let window: WindowModel
    let delete: (Space) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = MenuAnchor()

    var body: some View {
        let space = store.activeSpace
        Button { showMenu() } label: {
            Text(space.name)
                .font(.system(size: 13, weight: .semibold))
                // The space's color, deepened toward ink so it reads on the tint.
                .foregroundStyle(Theme.spaceInk(space.color))
                .lineLimit(1)
                .truncationMode(.tail)
            // Cross-fades with the frame's tint when the space changes.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: space.id)
        }
        .buttonStyle(SpaceNameStyle())
        .background { MenuAnchorView(anchor: anchor) { showMenu() } }
        .help("Spaces")
        .accessibilityLabel("Space: \(space.name)")
        .accessibilityHint("Shows your spaces")
    }

    private func select(_ space: Space) {
        window.showSpace { store.selectSpace(space) }
    }

    /// A native menu, like a pop-up button's: the space on screen sits over
    /// the name, checked; each space has its color and ⌃1–9.
    private func showMenu() {
        guard let view = anchor.view else { return }
        let target = MenuTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        var current: NSMenuItem?
        for (index, space) in store.spaces.enumerated() {
            let item = target.item(space.name) { select(space) }
            item.image = Self.dot(NSColor(Theme.spaceColor(space.color)))
            if index < 9 {
                item.keyEquivalent = "\(index + 1)"
                item.keyEquivalentModifierMask = .control
            }
            if space.id == store.activeSpaceID {
                item.state = .on
                current = item
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(target.item("New Space…") { window.newSpace() })
        // Until Settings › Spaces exists: editing and deleting the space on screen.
        let space = store.activeSpace
        menu.addItem(.separator())
        menu.addItem(target.item("Edit Space…") { window.editSpace(space) })
        if store.spaces.count > 1 {
            menu.addItem(target.item("Delete Space…") { delete(space) })
        }
        // The space on screen lands over the name, as a pop-up button's does.
        menu.popUp(positioning: current, at: NSPoint(x: 0, y: view.bounds.maxY - 2), in: view)
        withExtendedLifetime(target) {}
    }

    /// A small filled circle in a space's color, for the menu (kept in color,
    /// not turned into a template).
    private static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// One small dot per space, the space on screen's in its color, the rest
/// faint. Clicking one goes to that space. (The menu and ⌃1–9 do the same,
/// so VoiceOver hears the name, not the dots.)
private struct SpaceDots: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = Theme.spaceInk(store.activeSpace.color)
        HStack(spacing: 0) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                let isActive = space.id == store.activeSpaceID
                Button {
                    window.showSpace { store.selectSpace(space) }
                } label: {
                    Circle()
                        .fill(isActive ? ink : Theme.faint.opacity(0.6))
                        .frame(width: 5, height: 5)
                        // A comfortable spot to click, wider than the dot.
                        .frame(width: 11, height: 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: store.activeSpaceID)
        .accessibilityHidden(true)
    }
}

/// Runs the spaces menu's items. AppKit, because SwiftUI's menus can't show
/// the spaces' colors or open over the name like a pop-up button.
@MainActor
private final class MenuTarget: NSObject {
    private var actions: [() -> Void] = []

    func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self
        item.tag = actions.count
        actions.append(action)
        return item
    }

    @objc private func run(_ sender: NSMenuItem) { actions[sender.tag]() }
}

/// The AppKit view the spaces menu pops up from.
@MainActor
private final class MenuAnchor {
    weak var view: NSView?
}

/// Sits behind the name; also catches a right-click, which opens the same menu.
private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    let rightClick: @MainActor () -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        anchor.view = nsView
        nsView.rightClick = rightClick
    }

    final class AnchorView: NSView {
        var rightClick: (@MainActor () -> Void)?
        override func rightMouseDown(with event: NSEvent) { rightClick?() }
        // Only right-clicks stop here; everything else reaches the button.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }
    }
}

private struct SpaceNameStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
    }
}

/// The active space's wash over the frame. A new color cross-fades in over
/// the old one; with Reduce Motion it changes in place.
struct SpaceTint: View {
    let color: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.frameTint(color)
                .id(color)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: color)
    }
}
