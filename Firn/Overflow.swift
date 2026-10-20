import FirnCore
import SwiftUI

/// The overflow: one small button in the space row, always in view, opening
/// a calm panel with the space's drifted tabs and Recently closed (and
/// later its history). Only the space on screen, so nothing crosses
/// between spaces.
struct OverflowButton: View {
    let store: BrowserStore
    let window: WindowModel

    var body: some View {
        ChromeButton("Drifted and recently closed tabs", systemImage: "clock.arrow.circlepath") {
            window.showsOverflow.toggle()
        }
        .popover(isPresented: Bindable(window).showsOverflow, arrowEdge: .top) {
            OverflowPanel(store: store, window: window)
        }
    }
}

private struct OverflowPanel: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let drifted = store.driftedTabs
        let closed = store.recentlyClosed
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if drifted.isEmpty && closed.isEmpty {
                    Text("Nothing here yet. Tabs you haven’t looked at in a while, and tabs you close, wait here.")
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                if !drifted.isEmpty {
                    section("Drifted tabs", note: "Tabs you haven’t looked at in a while. They’re deleted after 30 days.") {
                        ForEach(drifted) { tab in
                            TabRow(tab: tab, isActive: false) { bringBack(tab) } close: { window.close(tab) } menu: {
                                Button("Close Tab", systemImage: "xmark") { window.close(tab) }
                            }
                        }
                    }
                }
                if !closed.isEmpty {
                    section("Recently closed", note: nil) {
                        ForEach(closed) { entry in
                            ClosedRow(entry: entry, color: Theme.spaceColor(store.activeSpace.color)) {
                                reopen(entry)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 300)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section(
        _ title: String, note: String?, @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.groupNameFont)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text(note)
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            rows()
        }
    }

    /// Back where new tabs go, and on screen.
    private func bringBack(_ tab: FirnCore.Tab) {
        window.showsOverflow = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { store.select(tab) }
        window.focusPage()
    }

    private func reopen(_ entry: ClosedEntry) {
        window.showsOverflow = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { store.reopen(entry) }
        window.focusPage()
    }
}

/// A closed tab (its icon and title) or group (a dot in the space's color,
/// as on its card, and its name) in Recently closed.
private struct ClosedRow: View {
    let entry: ClosedEntry
    let color: Color
    let reopen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: reopen) {
            HStack(spacing: 8) {
                Group {
                    switch entry.kind {
                    case .tab:
                        SiteIconView(icon: entry.icon, size: 16) { Image(systemName: "globe") }
                    case .group:
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                }
                .frame(width: 16, height: 16)
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
                Text(entry.title)
                    .font(Theme.tabFont)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.rowPadding)
            .frame(height: Theme.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.kind == .group ? "Reopen this group" : "Reopen this tab")
        .accessibilityLabel(entry.kind == .group ? "Group: \(entry.title)" : entry.title)
        .accessibilityHint(entry.kind == .group ? "Reopens the group" : "Reopens the tab")
    }
}
