import SwiftUI

/// Settings › Keyboard: Firn's shortcuts, to look up (David, 2026-11-25,
/// in place of the welcome's tips). The same ones as in the menus
/// (`BrowserCommands`) and ⌘1–9 (`TabShortcuts`): one changed there is
/// changed here too. Nothing to set.
struct KeyboardSettings: View {
    private struct Shortcut: Identifiable {
        let name: String
        /// One per key, as drawn, and as VoiceOver says them together.
        let keys: [String]
        let spoken: String
        var id: String { name }

        init(_ name: String, _ keys: [String], _ spoken: String) {
            self.name = name
            self.keys = keys
            self.spoken = spoken
        }
    }

    private static let tabs = [
        Shortcut("New tab", ["⌘", "T"], "Command T"),
        Shortcut("Close tab", ["⌘", "W"], "Command W"),
        Shortcut("Reopen closed tab", ["⇧", "⌘", "T"], "Shift Command T"),
        Shortcut("Last used tab", ["⌃", "Tab"], "Control Tab"),
        Shortcut("Next tab", ["⇧", "⌘", "]"], "Shift Command right bracket"),
        Shortcut("Previous tab", ["⇧", "⌘", "["], "Shift Command left bracket"),
        Shortcut("A tab by its place", ["⌘", "1–9"], "Command 1 to 9"),
        Shortcut("New group with this tab", ["⌃", "⌘", "N"], "Control Command N"),
    ]
    private static let page = [
        Shortcut("Address bar", ["⌘", "L"], "Command L"),
        Shortcut("Back", ["⌘", "["], "Command left bracket"),
        Shortcut("Forward", ["⌘", "]"], "Command right bracket"),
        Shortcut("Reload", ["⌘", "R"], "Command R"),
        Shortcut("Reader", ["⇧", "⌘", "R"], "Shift Command R"),
        Shortcut("Find", ["⌘", "F"], "Command F"),
        Shortcut("Find next", ["⌘", "G"], "Command G"),
        Shortcut("Find previous", ["⇧", "⌘", "G"], "Shift Command G"),
        Shortcut("Copy link", ["⇧", "⌘", "C"], "Shift Command C"),
        Shortcut("Print", ["⌘", "P"], "Command P"),
        Shortcut("Zoom in", ["⌘", "+"], "Command plus"),
        Shortcut("Zoom out", ["⌘", "−"], "Command minus"),
        Shortcut("Actual size", ["⌘", "0"], "Command zero"),
    ]
    private static let spaces = [
        Shortcut("A space by its place", ["⌃", "1–9"], "Control 1 to 9"),
        Shortcut("Next space", ["⌥", "⌘", "→"], "Option Command right arrow"),
        Shortcut("Previous space", ["⌥", "⌘", "←"], "Option Command left arrow"),
    ]
    private static let window = [
        Shortcut("Show or hide the sidebar", ["⌘", "S"], "Command S"),
        Shortcut("History", ["⌘", "Y"], "Command Y"),
        Shortcut("Settings", ["⌘", ","], "Command comma"),
        Shortcut("Close window", ["⇧", "⌘", "W"], "Shift Command W"),
    ]

    var body: some View {
        SettingsPage {
            group("Tabs", Self.tabs)
            group("Page", Self.page)
            group("Spaces", Self.spaces)
            group("Window", Self.window)
        }
    }

    private func group(_ title: String, _ shortcuts: [Shortcut]) -> some View {
        SettingsGroup(header: title) {
            VStack(spacing: 0) {
                ForEach(shortcuts) { shortcut in
                    HStack(spacing: 16) {
                        Text(shortcut.name)
                            .font(Theme.tabFont)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 12)
                        HStack(spacing: 4) {
                            ForEach(shortcut.keys, id: \.self) { KeyCap(key: $0) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(shortcut.name): \(shortcut.spoken)")
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// A key, drawn as a small frosted cap.
private struct KeyCap: View {
    let key: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(key)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background { shape.fill(reduceTransparency ? Theme.tileSolid : Theme.hover) }
    }
}
