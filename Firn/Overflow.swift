import FirnCore
import SwiftUI

/// The overflow: one small button in the space row, always in view, opening
/// a calm panel with the space's tidied-away tabs and Recently closed (and
/// later its history). Only the space on screen, so nothing crosses
/// between spaces. A dot in the space's color says tabs were tidied away
/// since it was last opened.
struct OverflowButton: View {
    static let symbol = "clock.arrow.circlepath"
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unseen = store.hasUnseenTidied
        ChromeButton("Tidied away and recently closed tabs", systemImage: Self.symbol) {
            window.showsOverflow.toggle()
        }
        .overlay(alignment: .topTrailing) {
            if unseen {
                Circle()
                    .fill(Theme.spaceColor(store.activeSpace.color))
                    .frame(width: 6, height: 6)
                    .padding(3)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: unseen)
        .accessibilityValue(unseen ? "New tabs tidied away" : "")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Sidebar.space)) } action: {
            window.overflowButtonFrame = $0
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
                    section("Tidied away", note: "Tabs you haven’t looked at in a while. They’re deleted after 30 days.",
                            action: ("Restore all", restoreAll)) {
                        ForEach(drifted) { tab in
                            TabRow(tab: tab, isActive: false) { bringBack(tab) } close: { window.close(tab) } menu: {
                                Button("Close Tab", systemImage: "xmark") { window.close(tab) }
                            }
                        }
                    }
                }
                if !closed.isEmpty {
                    section("Recently closed", note: nil, action: nil) {
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
        .onAppear { store.markTidiedSeen() }
    }

    private func section(
        _ title: String, note: String?, action: (label: String, perform: () -> Void)?,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Theme.groupNameFont)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let action {
                        Button(action.label, action: action.perform)
                            .buttonStyle(TextActionStyle())
                    }
                }
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

    /// All of them back where new tabs go; the tab on screen stays.
    private func restoreAll() {
        window.showsOverflow = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { store.restoreAllDrifted() }
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

/// A small word button in a section's header ("Restore all"): ink, with
/// the warm wash on hover, never system blue.
private struct TextActionStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.labelFont.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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

// MARK: - Tidying away

/// What the overflow button says once tabs are tidied away.
struct TidyAnnouncement: Equatable {
    let id = UUID()
    let count: Int

    var text: String { count == 1 ? "Tidied away 1 tab" : "Tidied away \(count) tabs" }
}

/// A tidied tab's site icon on its way down to the overflow button.
struct FlyingIcon: Identifiable {
    static let duration = 0.7
    let id: UUID
    let icon: Data?
    /// The icon's middle in its row, in the sidebar's space.
    let from: CGPoint
}

/// The icons drifting down to the overflow button, over the whole sidebar.
struct TidyFlights: View {
    let window: WindowModel

    var body: some View {
        let frame = window.overflowButtonFrame
        ZStack(alignment: .topLeading) {
            ForEach(window.flyingIcons) { flight in
                FlightView(flight: flight, to: CGPoint(x: frame.midX, y: frame.midY)) {
                    window.flyingIcons.removeAll { $0.id == flight.id }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One icon, like a flake: it lifts a touch, sways, and falls into the
/// button, shrinking, and fading as it arrives. Transforms and opacity only.
private struct FlightView: View {
    let flight: FlyingIcon
    let to: CGPoint
    let done: () -> Void
    @State private var started = false

    private struct Pose {
        var x = 0.0
        var y = 0.0
        var scale = 1.0
        var opacity = 1.0
    }

    var body: some View {
        let dx = to.x - flight.from.x
        let dy = to.y - flight.from.y
        SiteIconView(icon: flight.icon, size: 16) {
            Image(systemName: "globe").foregroundStyle(Theme.muted)
        }
        .frame(width: 16, height: 16)
        .shadow(color: Theme.shadowSoft, radius: 2, y: 1)
        .keyframeAnimator(initialValue: Pose(), trigger: started) { content, pose in
            content
                .scaleEffect(pose.scale)
                .opacity(pose.opacity)
                .offset(x: pose.x, y: pose.y)
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                CubicKeyframe(-6, duration: 0.15)
                CubicKeyframe(dy, duration: FlyingIcon.duration - 0.15)
            }
            KeyframeTrack(\.x) {
                CubicKeyframe(6, duration: 0.25)
                CubicKeyframe(dx, duration: FlyingIcon.duration - 0.25)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.1, duration: 0.15)
                CubicKeyframe(0.55, duration: FlyingIcon.duration - 0.15)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: FlyingIcon.duration - 0.2)
                LinearKeyframe(0, duration: 0.2)
            }
        }
        .position(flight.from)
        .task {
            try? await Task.sleep(for: .milliseconds(16))
            started = true
            try? await Task.sleep(for: .seconds(FlyingIcon.duration - 0.02))
            done()
        }
    }
}

/// The overflow button saying so: frost forms over it in the space's
/// color, it widens to "Tidied away 4 tabs", and then thaws back. Clicking
/// it opens the overflow.
struct TidyPill: View {
    let text: String
    let open: Bool
    let color: Color
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: OverflowButton.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
                if open {
                    Text(text)
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 12)
                        .transition(.opacity)
                }
            }
            .frame(width: open ? nil : 28, height: 28, alignment: .leading)
            .background { FrostGlass(shape: shape, color: color) }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("Show tidied away tabs")
        // The button beneath and the spoken announcement cover it.
        .accessibilityHidden(true)
    }
}
