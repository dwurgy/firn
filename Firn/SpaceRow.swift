import FirnCore
import SwiftUI

/// The row at the bottom of the sidebar: one button per space, in order,
/// with the overflow on the left and, while there are any, the space's
/// downloads on the right. Each space shows its own icon in its color.
/// New Space… is in the icons' right-click menu (and the File menu).
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
            // As wide as the downloads button's spot, so the spaces sit truly
            // centered between the two.
            OverflowButton(store: store, window: window)
            Group {
                buttons
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, (Theme.rowHeight - 28) / 2)
                DownloadsButton(store: store, window: window)
            }
            // The spaces step back while the pill speaks.
            .opacity(pill == .open ? 0 : 1)
        }
        .frame(minHeight: Theme.rowHeight)
        .overlay(alignment: .leading) {
            if pill != .hidden, let announcement = window.tidyAnnouncement {
                TidyPill(text: announcement.text, open: pill == .open,
                         color: Theme.spaceColor(store.activeSpace.color)) {
                    window.showsOverflow = true
                }
                .transition(.opacity)
            }
        }
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

    /// Centered; when they don't fit on one line, they stack onto more.
    private var buttons: some View {
        CenteredFlow(spacing: 2, lineSpacing: Theme.rowSpacing) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceButton(
                    space: space, number: index + 1, isActive: space.id == store.activeSpaceID,
                    tint: store.activeSpace.color
                ) {
                    window.showSpace { store.selectSpace(space) }
                }
                .contextMenu {
                    Button("New Space…") { window.newSpace() }
                    Divider()
                    Button("Edit Space…") { window.editSpace(space) }
                    // The last space can't be deleted.
                    if store.spaces.count > 1 {
                        Button("Delete Space…") { deleting = space }
                    }
                }
            }
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

/// Lays its views out in centered lines. When they don't all fit on one,
/// they stack onto as few lines as it takes, shared out evenly (seven become
/// four and three, not five and two).
private struct CenteredFlow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(of: subviews, in: proposal.width ?? .infinity)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(of: subviews, in: bounds.width) {
            var x = bounds.midX - line.width / 2
            for index in line.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indexes: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(of subviews: Subviews, in width: CGFloat) -> [Line] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        // How many lines filling each as full as it goes would take…
        var count = 1
        var used: CGFloat = 0
        for size in sizes {
            let needed = used == 0 ? size.width : used + spacing + size.width
            if needed > width, used > 0 {
                count += 1
                used = size.width
            } else {
                used = needed
            }
        }
        // …then the same number of lines, shared out evenly.
        let perLine = max(Int((Double(sizes.count) / Double(count)).rounded(.up)), 1)
        var lines: [Line] = []
        for (index, size) in sizes.enumerated() {
            if index % perLine == 0 { lines.append(Line()) }
            lines[lines.count - 1].width += (lines[lines.count - 1].indexes.isEmpty ? 0 : spacing) + size.width
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
            lines[lines.count - 1].indexes.append(index)
        }
        return lines
    }
}

/// One space in the row: its icon, drawn in the space on screen's color (so
/// the row is one color, never a rainbow), lifted like the tab on screen when
/// it's the space on screen.
private struct SpaceButton: View {
    let space: Space
    /// Its place in the row, from 1; ⌃1–9 show the first nine.
    let number: Int
    let isActive: Bool
    /// The color of the space on screen, which every icon in the row takes.
    let tint: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SpaceIconView(icon: SpaceIcon(stored: space.icon), size: 18, color: Theme.spaceIconInk(tint))
                // Cross-fades with the frame's tint when the space changes.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: tint)
        }
        .buttonStyle(SpaceButtonStyle(isActive: isActive))
        .help(number <= 9 ? "\(space.name) (⌃\(number))" : space.name)
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct SpaceButtonStyle: ButtonStyle {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
                    .shadow(color: isActive ? Theme.shadowSoft : .clear, radius: 1, y: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isActive)
    }

    private func fill(pressed: Bool) -> Color {
        if isActive { return Theme.activeTab }
        if pressed { return Theme.press }
        return hovering ? Theme.hover : .clear
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
