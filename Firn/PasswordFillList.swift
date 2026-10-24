import AppKit
import FirnCore
import SwiftUI

/// The saved logins for a site, in a small frosted list just under the
/// sign-in field that was clicked (above it, near the page's bottom).
/// Nothing enters the page until one is picked.
///
/// It never takes the keyboard: typing still goes into the field, and any
/// key but ↓, ↑, Return, and Esc closes the list as it goes through. ↓
/// steps into the list, Return fills the one marked, Esc closes. A click
/// anywhere else, scrolling, or the page changing size closes it too.
struct PasswordFillList: View {
    let store: BrowserStore
    let offer: FillOffer
    let color: Color
    /// The page's size, to keep the list inside it.
    let pageSize: CGSize
    @State private var marked: Int?
    @State private var hovered: Int?
    @State private var height: CGFloat = 0

    private static let rowHeight: CGFloat = 32
    private static let visibleRows = 5
    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text("Saved for \(offer.site.name)")
                .font(Theme.hintFont)
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(Array(offer.usernames.enumerated()), id: \.offset) { index, username in
                        row(index, username)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: rowsHeight)
        }
        .padding(6)
        .frame(width: width)
        .background { CommandBarGlass(shape: shape, color: color) }
        .clipShape(shape)
        .shadow(color: Theme.shadowSoft, radius: 10, x: 0, y: 4)
        .background { FillListKeys(onKey: key, onOutside: store.dismissFillOffer) }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .offset(x: x, y: y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved passwords for \(offer.site.name)")
        .onChange(of: pageSize) { store.dismissFillOffer() }
        // VoiceOver stays in the page's field, so the list says it's there.
        .onAppear {
            AccessibilityNotification.Announcement(
                "Saved passwords for \(offer.site.name). Press Down Arrow to choose one."
            ).post()
        }
        .onChange(of: marked) {
            guard let marked, offer.usernames.indices.contains(marked) else { return }
            AccessibilityNotification.Announcement(Self.spoken(offer.usernames[marked])).post()
        }
    }

    private static func spoken(_ username: String) -> String {
        username.isEmpty ? "Fill saved password" : "Fill \(username)"
    }

    private func row(_ index: Int, _ username: String) -> some View {
        let isMarked = marked == index
        return Button { pick(index) } label: {
            HStack(spacing: 8) {
                Image(systemName: "key")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 16)
                Text(username.isEmpty ? "No username" : username)
                    .font(Theme.tabFont)
                    .foregroundStyle(username.isEmpty ? Theme.muted : Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(isMarked ? Theme.frost : hovered == index ? Theme.hover : .clear)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .accessibilityLabel(Self.spoken(username))
    }

    private var rowsHeight: CGFloat {
        let rows = CGFloat(min(offer.usernames.count, Self.visibleRows))
        return rows * Self.rowHeight + (rows - 1) * 2
    }

    private var width: CGFloat {
        min(max(offer.field.width, 240), 360, max(pageSize.width - Self.margin * 2, 1))
    }

    private var x: CGFloat {
        min(max(offer.field.minX, Self.margin), max(pageSize.width - width - Self.margin, Self.margin))
    }

    /// Under the field, or above it when there's no room below.
    private var y: CGFloat {
        let below = offer.field.maxY + Self.gap
        if below + height + Self.margin <= pageSize.height { return below }
        return max(offer.field.minY - Self.gap - height, Self.margin)
    }

    private func pick(_ index: Int) {
        guard offer.usernames.indices.contains(index) else { return }
        let username = offer.usernames[index]
        Task { await store.fill(username: username) }
    }

    /// True when the key was the list's to take.
    private func key(_ key: FillListKeys.Key) -> Bool {
        let last = offer.usernames.count - 1
        switch key {
        case .down:
            marked = min((marked ?? -1) + 1, last)
            return true
        case .up:
            guard let current = marked else { return false }
            marked = max(current - 1, 0)
            return true
        case .enter:
            guard let marked else { return false }
            pick(marked)
            return true
        case .escape:
            store.dismissFillOffer()
            return true
        case .other:
            store.dismissFillOffer()
            return false
        }
    }
}

/// Hears keys, clicks, and scrolling in the list's window while it's open
/// (AppKit event monitors, since the page keeps the keyboard). Clicks
/// outside the list close it and still reach whatever was clicked; it
/// passes every key on except the ones the list takes. Draws nothing and
/// takes no clicks itself.
private struct FillListKeys: NSViewRepresentable {
    enum Key { case down, up, enter, escape, other }

    let onKey: (Key) -> Bool
    let onOutside: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.onKey = onKey
        view.onOutside = onOutside
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.onKey = onKey
        view.onOutside = onOutside
    }

    static func dismantleNSView(_ view: Catcher, coordinator: ()) {
        view.stop()
    }

    final class Catcher: NSView {
        var onKey: ((Key) -> Bool)?
        var onOutside: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { [weak self] event in
                let caught = MainActor.assumeIsolated { self?.catches(event) ?? false }
                return caught ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func catches(_ event: NSEvent) -> Bool {
            guard let window, event.window === window else { return false }
            switch event.type {
            case .keyDown:
                let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                let key: Key = switch (plain, event.keyCode) {
                case (true, 125): .down
                case (true, 126): .up
                case (true, 36), (true, 76): .enter
                case (true, 53): .escape
                default: .other
                }
                return onKey?(key) ?? false
            case .scrollWheel:
                // Scrolling the list itself is fine; scrolling the page moves the field away.
                if !bounds.contains(convert(event.locationInWindow, from: nil)) { onOutside?() }
                return false
            default:
                if !bounds.contains(convert(event.locationInWindow, from: nil)) { onOutside?() }
                return false
            }
        }
    }
}
