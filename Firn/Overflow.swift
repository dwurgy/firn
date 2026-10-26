import FirnCore
import SwiftUI

/// The overflow: one small button in the space row, opening a calm panel
/// with the space's tidied-away tabs. Only the space on screen, so nothing
/// crosses between spaces. It's there only while it holds something: it
/// fades in as the first tabs are tidied away, just before their icons fall
/// in, and fades out once the last has gone (its spot stays, so the spaces
/// don't shift). A dot in the space's color says tabs were tidied away
/// since it was last opened. (Recently closed lives in File › Reopen Closed
/// Tab and the command bar; David, 2026-10-23.)
struct OverflowButton: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lidOpen = false

    var body: some View {
        let unseen = store.hasUnseenTidied
        let falling = window.flyingIcons.contains { !$0.rising }
        let shown = holdsSomething
        ChromeButton("Tidied away tabs") {
            window.showsOverflow.toggle()
        } icon: {
            ArchiveBoxIcon(lidOpen: lidOpen || window.boxOpen)
        }
        // The box opens as the first icon nears and closes as the last one lands.
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
                    // Tucked into the corner, clear of the lid's.
                    .padding(1)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: unseen)
        .accessibilityValue(unseen ? "New tabs tidied away" : "")
        // Faded rather than removed, so its spot (and where icons land) stays.
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: shown)
        // Nothing left to show (the last one closed from the panel, say).
        .onChange(of: store.driftedTabs.isEmpty) { if store.driftedTabs.isEmpty { window.showsOverflow = false } }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Sidebar.space)) } action: {
            window.overflowButtonFrame = $0
        }
        .popover(isPresented: Bindable(window).showsOverflow, arrowEdge: .top) {
            OverflowPanel(store: store, window: window)
        }
    }

    /// Tidied tabs, or tabs on their way in or out of the box.
    private var holdsSomething: Bool {
        !store.driftedTabs.isEmpty || !window.tidyQueue.isEmpty || !window.riseQueue.isEmpty
            || !window.flyingIcons.isEmpty || window.boxOpen || window.tidyAnnouncement != nil
    }
}

private struct OverflowPanel: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let drifted = store.driftedTabs
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                section("Tidied away", note: "Tabs you haven’t looked at in a while. They’re deleted after 30 days.",
                        action: ("Restore all", restoreAll)) {
                    ForEach(drifted) { tab in
                        TabRow(tab: tab, isActive: false) { bringBack(tab) } close: { window.close(tab) } menu: {
                            Button("Close Tab", systemImage: "xmark") { window.close(tab) }
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
        window.rise(store.driftedTabs)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { store.restoreAllDrifted() }
    }

    /// Back where new tabs go, and on screen.
    private func bringBack(_ tab: FirnCore.Tab) {
        window.showsOverflow = false
        window.rise([tab])
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { store.select(tab) }
        window.focusPage()
    }
}

/// A small word button in a section's header ("Restore all"): ink, with
/// the warm wash on hover, never system blue.
struct TextActionStyle: ButtonStyle {
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

// MARK: - Tidying away

/// What the overflow button says once tabs are tidied away.
struct TidyAnnouncement: Equatable {
    let id = UUID()
    let count: Int

    var text: String { count == 1 ? "Tidied away 1 tab" : "Tidied away \(count) tabs" }
}

/// A site icon on its way down to the overflow button (tidied away), or up
/// out of it (brought back).
struct FlyingIcon: Identifiable {
    static let duration = 0.7
    let id: UUID
    let icon: Data?
    /// The icon's middle in its row, in the sidebar's space.
    let row: CGPoint
    /// Up out of the button to the row, rather than down into it.
    var rising = false
}

/// The icons drifting between their rows and the overflow button, over the
/// whole sidebar.
struct TidyFlights: View {
    let window: WindowModel

    var body: some View {
        let frame = window.overflowButtonFrame
        ZStack(alignment: .topLeading) {
            ForEach(window.flyingIcons) { flight in
                FlightView(flight: flight, button: CGPoint(x: frame.midX, y: frame.midY)) {
                    window.flyingIcons.removeAll { $0.id == flight.id }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One icon, like a flake. Falling: it lifts a touch, sways, and falls
/// into the button, shrinking, and fading as it arrives. Rising, the same
/// in reverse: small and faint, it lifts out of the box, then glides up to
/// its row, growing, and fades as its row fades in under it. Transforms
/// and opacity only.
private struct FlightView: View {
    let flight: FlyingIcon
    let button: CGPoint
    let done: () -> Void
    @State private var started = false

    var body: some View {
        let from = flight.rising ? button : flight.row
        let to = flight.rising ? flight.row : button
        let dx = to.x - from.x
        let dy = to.y - from.y
        SiteIconView(icon: flight.icon, size: 16) {
            Image(systemName: "globe").foregroundStyle(Theme.muted)
        }
        .frame(width: 16, height: 16)
        .shadow(color: Theme.shadowSoft, radius: 2, y: 1)
        .modifier(Flight(rising: flight.rising, dx: dx, dy: dy, started: started))
        .position(from)
        .task {
            try? await Task.sleep(for: .milliseconds(16))
            started = true
            try? await Task.sleep(for: .seconds(FlyingIcon.duration - 0.02))
            done()
        }
    }
}

/// A flight's path. Falling, it lifts a touch and sways on the way down.
/// Rising, it goes straight up out of the box, then glides over to its
/// row, each step smooth and one-way (no dip back toward the box).
private struct Flight: ViewModifier {
    let rising: Bool
    let dx: Double
    let dy: Double
    let started: Bool

    private struct Pose {
        var x = 0.0
        var y = 0.0
        var scale = 1.0
        var opacity = 1.0
    }

    func body(content: Content) -> some View {
        let rest = FlyingIcon.duration
        if rising {
            content.keyframeAnimator(initialValue: Pose(scale: 0.55, opacity: 0), trigger: started) { view, pose in
                view
                    .scaleEffect(pose.scale)
                    .opacity(pose.opacity)
                    .offset(x: pose.x, y: pose.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    CubicKeyframe(dy, duration: rest)
                }
                KeyframeTrack(\.x) {
                    LinearKeyframe(0, duration: 0.2)
                    CubicKeyframe(dx, duration: rest - 0.2)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1, duration: rest)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: rest - 0.3)
                    LinearKeyframe(0, duration: 0.15)
                }
            }
        } else {
            content.keyframeAnimator(initialValue: Pose(), trigger: started) { view, pose in
                view
                    .scaleEffect(pose.scale)
                    .opacity(pose.opacity)
                    .offset(x: pose.x, y: pose.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    CubicKeyframe(-6, duration: 0.15)
                    CubicKeyframe(dy, duration: rest - 0.15)
                }
                KeyframeTrack(\.x) {
                    CubicKeyframe(6, duration: 0.25)
                    CubicKeyframe(dx, duration: rest - 0.25)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.1, duration: 0.15)
                    CubicKeyframe(0.55, duration: rest - 0.15)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: rest - 0.2)
                    LinearKeyframe(0, duration: 0.2)
                }
            }
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
                ArchiveBoxIcon()
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

/// The overflow button's icon: a plain archive box, its lid a band a
/// little wider than the box. Where tidied tabs are kept. Drawn in the
/// style and size of the space icons Firn once had (24pt grid, 1.6 stroke,
/// round caps and joins; docs/space-icons.svg); also
/// kept as docs/overflow-icon.svg. Change it only with David's OK, and
/// update that file to match. (The snow-drift lid it replaces read as a
/// toupee; David, 2026-10-21.)
///
/// While tidied tabs fall in, or brought-back ones rise out, the lid lifts
/// on its right corner and then lands softly, never overshooting: the
/// timing approved as "B" on 2026-10-21 (docs/overflow-lid-animation.html
/// still shows it with the old snow lid).
struct ArchiveBoxIcon: View {
    var size: CGFloat = 18
    /// Lifted while tabs go in or come out.
    var lidOpen = false
    @State private var lidAngle = 0.0

    private static let lift = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.22)
    /// Eases in so the lid lands softly and never overshoots.
    private static let land = Animation.timingCurve(0.45, 0, 0.25, 1, duration: 0.26)

    var body: some View {
        let style = StrokeStyle(lineWidth: size * 1.6 / 24, lineCap: .round, lineJoin: .round)
        ZStack {
            BoxShape().stroke(style: style)
            LidShape()
                .stroke(style: style)
                .rotationEffect(.degrees(lidAngle), anchor: LidShape.hinge)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: lidOpen) { _, open in
            withAnimation(open ? Self.lift : Self.land) { lidAngle = open ? 20 : 0 }
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
private struct BoxShape: Shape {
    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    /// Built once from the path data in docs/overflow-icon.svg (viewBox 0 0 24 24).
    private static let path: Path = {
        var path = Path()
        for data in [
            "M5.5 9.5v8a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-8",
            "M10 13.5h4",
        ] {
            path.addPath(Path(SVGPath.cgPath(data)))
        }
        return path
    }()
}

/// The lid.
private struct LidShape: Shape {
    /// The lid's bottom right corner, where it lifts from.
    static let hinge = UnitPoint(x: 20 / 24, y: 9.5 / 24)

    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    /// Built once from the path data in docs/overflow-icon.svg (viewBox 0 0 24 24).
    private static let path = Path(SVGPath.cgPath("M5.5 4.5h13a1.5 1.5 0 0 1 1.5 1.5v3.5H4V6a1.5 1.5 0 0 1 1.5-1.5Z"))
}
