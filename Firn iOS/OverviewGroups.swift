import FirnCore
import SwiftUI

/// A group's header: the name lined up over its tabs' icons and the fold
/// chevron at the trailing edge, over the rows' X; no count (as on the
/// Mac). Tapping it folds or unfolds the group; holding it opens its menu.
struct GroupLine: View {
    let group: TabGroup
    /// The header's 44pt, or a folded group's 48pt: the name and chevron
    /// stay in the middle, so they glide there as it folds.
    let height: CGFloat
    /// New, and its name is on the way from the on-device model.
    let naming: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            // The chevron sits just after the name, as on the Mac (David,
            // 2026-11-07): it belongs to the name, and the right edge is
            // left to the tabs' X. A long name shortens first, so the
            // chevron always shows.
            HStack(spacing: 6) {
                // While the on-device model names a new group, quiet dots
                // stand where the name will be, the chevron just after
                // them; then the name fades in and the chevron glides to
                // its end (a fade and a short glide; Reduce Motion: a swap).
                Group {
                    if naming {
                        NamingDots(color: Theme.ink, size: 5)
                    } else {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            // The new name swaps in while hidden, so "New
                            // Group" never fades out over it.
                            .contentTransition(.identity)
                    }
                }
                .transition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(group.folded ? -90 : 0))
                    .fixedSize()
                Spacer(minLength: 14)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: naming)
            // Over the slim rows' icons (24pt, 14pt in from the row).
            .padding(.leading, 14)
            .frame(minHeight: height)
            .contentShape(Rectangle())
        }
        // Not iOS's plain style: it dims the name and chevron as they're
        // pressed, then fades them back while the group folds, which read
        // as a flash (David's recording, 2026-11-06).
        .buttonStyle(UndimmedPress())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel(naming ? "New group, naming" : group.name)
        // The name arrived: VoiceOver hears it, as the dots fade (step 4's look over).
        .onChange(of: naming) { was, now in
            if was, !now { AccessibilityNotification.Announcement("Group named \(group.name)").post() }
        }
        .accessibilityValue(group.folded ? "Folded" : "Open")
        .accessibilityHint(group.folded ? "Shows the group's tabs" : "Folds the group")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A group's hold menu (Firn's own, by its name line; the whole group
/// lifts as one piece); `actions` gives the same three to VoiceOver on its
/// name line.
@MainActor struct GroupMenu {
    let rename: @MainActor () -> Void
    let ungroup: @MainActor () -> Void
    let close: @MainActor () -> Void

    var sections: [[HoldMenuItem]] {
        [[HoldMenuItem(title: "Rename", systemImage: "pencil", action: rename),
          HoldMenuItem(title: "Ungroup", systemImage: "folder.badge.minus", action: ungroup)],
         [HoldMenuItem(title: "Close Group", systemImage: "xmark", closes: true, action: close)]]
    }

    var actions: GroupActions { GroupActions(rename: rename, ungroup: ungroup, close: close) }
}

/// The group menu's three, as VoiceOver actions on the name line.
@MainActor struct GroupActions: ViewModifier {
    let rename: @MainActor () -> Void
    let ungroup: @MainActor () -> Void
    let close: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            Button("Rename", action: rename)
            Button("Ungroup", action: ungroup)
            Button("Close Group", action: close)
        }
    }
}

/// A group's Move Up and Move Down (nil at an end), for its name line,
/// which is where VoiceOver finds the group.
struct GroupMoves {
    var up: (() -> Void)?
    var down: (() -> Void)?
}

/// VoiceOver's Move Up and Move Down on a group's name line.
struct GroupMoveActions: ViewModifier {
    let moves: GroupMoves

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let up = moves.up { Button("Move Up", action: up) }
            if let down = moves.down { Button("Move Down", action: down) }
        }
    }
}

/// A button that doesn't dim while it's pressed: what it does (a group
/// folding) is the answer to the tap.
struct UndimmedPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The card behind a group: the Mac's group frost (`FrostGlass` in
/// `Firn/Sidebar.swift`), not Liquid Glass (David, 2026-11-08). A frosted
/// fill with the space's color in it, a 1pt rim lighter at the top, a
/// hairline, and a soft shadow: an outline that differs from the haze in
/// lightness, which a space-colored edge couldn't over a haze of the same
/// color. No blur: the haze behind is already a blur of the page. Reduce
/// Transparency, the solid tile color. The tabs on it are flat.
struct GroupCard: View {
    let space: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The rows' and cards' 14pt corners plus the 8pt inside, so the
    /// corners run evenly around the tabs.
    static let cornerRadius: CGFloat = OverviewRow.cornerRadius + inset
    /// Inside on the left, right, and bottom, and between tabs.
    static let inset: CGFloat = 8

    /// The shadow's spread: wider than the Mac's 1pt, to lift the card off the haze.
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 2
    /// The header's height at the default text size (it grows with it).
    static let headerHeight: CGFloat = 44
    /// A folded group's height at the default text size (it grows too):
    /// a slim row's, so it reads as one line in the list.
    static let foldedHeight: CGFloat = OverviewRow.rowHeight

    var body: some View {
        Frost(shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
              space: space, fill: Theme.groupCardFill, solid: reduceTransparency,
              shadow: Theme.groupCardShadow, shadowRadius: Self.shadowRadius, shadowY: Self.shadowY)
    }
}
