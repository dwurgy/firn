import FirnCore
import SwiftUI

/// The overflow: one small button in the space row, always in view, opening
/// a calm panel with the space's tidied-away tabs and Recently closed (and
/// later its history). Only the space on screen, so nothing crosses
/// between spaces. A dot in the space's color says tabs were tidied away
/// since it was last opened.
struct OverflowButton: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lidOpen = false

    var body: some View {
        let unseen = store.hasUnseenTidied
        let falling = !window.flyingIcons.isEmpty
        ChromeButton("Tidied away and recently closed tabs") {
            window.showsOverflow.toggle()
        } icon: {
            SnowBoxIcon(lidOpen: lidOpen)
        }
        // The lid lifts as the first icon nears and shuts as the last one lands.
        .task(id: falling) {
            if falling && !reduceMotion {
                try? await Task.sleep(for: .milliseconds(380))
                if !Task.isCancelled { lidOpen = true }
            } else {
                lidOpen = false
            }
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
                SnowBoxIcon()
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

/// The overflow button's icon, Firn's own: an archive box whose lid is a
/// drift of snow, crest on the left (clear of the unseen dot), easing down
/// to the right. Where tidied tabs are kept. Approved by David on
/// 2026-10-21 ("D3, rounded shoulder"), drawn in the space icons' style
/// (24pt grid, 1.6 stroke, round caps and joins); also kept as
/// docs/overflow-icon.svg. Change it only with David's OK, and update that
/// file to match.
///
/// In the tidy moment the lid lifts on its right corner to catch the falling
/// icons, and the drift slumps downhill toward the hinge: slow to start,
/// stopping short, never past the end (snow, not water). As the lid lands,
/// the drift settles back into its usual shape. Approved by David on
/// 2026-10-21 ("B"); the preview is docs/overflow-lid-animation.html.
struct SnowBoxIcon: View {
    var size: CGFloat = 18
    /// Lifted while tidied tabs fall in.
    var lidOpen = false
    @State private var lidAngle = 0.0
    @State private var slump = 0.0

    private static let lift = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.22)
    private static let slide = Animation.timingCurve(0.55, 0, 0.25, 1, duration: 0.48)
    /// Eases in so the lid lands softly and never overshoots.
    private static let land = Animation.timingCurve(0.45, 0, 0.25, 1, duration: 0.26)
    private static let settle = Animation.easeOut(duration: 0.34).delay(0.03)

    var body: some View {
        let style = StrokeStyle(lineWidth: size * 1.6 / 24, lineCap: .round, lineJoin: .round)
        ZStack {
            SnowBoxShape().stroke(style: style)
            SnowLidShape(slump: slump)
                .stroke(style: style)
                .rotationEffect(.degrees(lidAngle), anchor: SnowLidShape.hinge)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: lidOpen) { _, open in
            if open {
                withAnimation(Self.lift) { lidAngle = 20 }
                withAnimation(Self.slide) { slump = 1 }
            } else {
                withAnimation(Self.land) { lidAngle = 0 }
                withAnimation(Self.settle) { slump = 0 }
            }
        }
    }
}

/// Fits drawing in the 24pt grid to `rect`, centered.
private func fitGrid(_ rect: CGRect) -> CGAffineTransform {
    let scale = min(rect.width, rect.height) / 24
    return CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        .scaledBy(x: scale, y: scale)
}

/// The box without its lid.
private struct SnowBoxShape: Shape {
    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    /// Built once from the approved path data (viewBox 0 0 24 24).
    private static let path: Path = {
        var path = Path()
        for data in [
            "M5 10v7.5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V10",
            "M10 13.5h4",
        ] {
            path.addPath(Path(SVGPath.cgPath(data)))
        }
        return path
    }()
}

/// The lid, a drift of snow. At rest it is exactly the approved path
/// ("M3.5 10c0-3 1.8-5.3 4.6-5.3 2.6 0 4.2 1.6 6.4 2.8 2 1.1 4 1.5 6 1.6V10Z",
/// in absolute points below); `slump` 1 is the same drift slid toward the hinge.
private struct SnowLidShape: Shape {
    var slump: Double

    var animatableData: Double {
        get { slump }
        set { slump = newValue }
    }

    /// The lid's right corner, where it lifts from.
    static let hinge = UnitPoint(x: 20.5 / 24, y: 10 / 24)

    private static let rest: [CGFloat] = [3.5, 10, 3.5, 7, 5.3, 4.7, 8.1, 4.7, 10.7, 4.7, 12.3, 6.3,
                                          14.5, 7.5, 16.5, 8.6, 18.5, 9.0, 20.5, 9.1]
    private static let slumped: [CGFloat] = [3.5, 10, 3.5, 8.1, 6.4, 5.3, 10.2, 5.3, 12.8, 5.3, 14.4, 6.3,
                                             16.2, 7.3, 17.7, 8.0, 19.2, 8.4, 20.5, 8.6]

    func path(in rect: CGRect) -> Path {
        let k = CGFloat(slump)
        let v = zip(Self.rest, Self.slumped).map { $0 + ($1 - $0) * k }
        func p(_ i: Int) -> CGPoint { CGPoint(x: v[i * 2], y: v[i * 2 + 1]) }
        var path = Path()
        path.move(to: p(0))
        path.addCurve(to: p(3), control1: p(1), control2: p(2))
        path.addCurve(to: p(6), control1: p(4), control2: p(5))
        path.addCurve(to: p(9), control1: p(7), control2: p(8))
        path.addLine(to: CGPoint(x: 20.5, y: 10))
        path.closeSubpath()
        return path.applying(fitGrid(rect))
    }
}
