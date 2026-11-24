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
    /// A folded group's site icons in TestFlight's grid (`GroupIcons`).
    var icons: [FirnCore.Tab] = []
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
                            // A name that follows its tabs fades into the
                            // next in place (the chevron glides to its end).
                            // A first name arrives while the dots stand
                            // here, so "New Group" never fades out over it.
                            .contentTransition(reduceMotion ? .identity : .opacity)
                    }
                }
                .transition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(group.folded ? -90 : 0))
                    .fixedSize()
                Spacer(minLength: 14)
                if !icons.isEmpty {
                    GroupIcons(tabs: icons)
                        .padding(.trailing, 14)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: naming)
            // Only a name Firn chose fades; a rename by hand just shows.
            .animation(reduceMotion || group.namedByHand ? nil : .smooth(duration: 0.3), value: group.name)
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
        // The name arrived, or followed its tabs: VoiceOver hears it.
        .onChange(of: GroupNameState(naming: naming, name: group.name)) { was, now in
            if was.arrived(now, namedByHand: group.namedByHand) {
                AccessibilityNotification.Announcement("Group named \(group.name)").post()
            }
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

/// The card behind a group: the iPhone's one glass (`FirnGlass`), iOS's
/// own, frosty with no tint (David, 2026-11-18; it was the Mac's group
/// frost with the space's color in it). The tabs on it are flat.
struct GroupCard: View {
    let space: String

    /// The cards' 15pt corners plus the 12pt at the sides, so the corners
    /// run evenly around the tabs: 27pt, which is Safari's too.
    static let cornerRadius: CGFloat = OverviewRow.gridCornerRadius + side
    /// Safari's open group, measured from David's recording (2026-11-18):
    /// tabs 12pt in from the sides and 16pt apart across; down, a title and
    /// the grid's own 9pt, as loose tabs; 5pt under the last titles.
    static let side: CGFloat = 12
    static let columnGap: CGFloat = 16
    static let rowGap: CGFloat = OverviewGridMetrics.rowSpacing
    static let bottom: CGFloat = 5
    /// Around an open group in the grid, as Safari's: 10pt under the
    /// titles above it (a row's usual room; measured from David's
    /// screenshots, 2026-11-19: the 24pt first read from a recording was
    /// Safari's floating button, not the title), 16pt to the cards below.
    static let gapAbove: CGFloat = 10
    static let gapBelow: CGFloat = 16

    /// The shadow's spread: wider than the Mac's 1pt, to lift the card off the haze.
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 2
    /// The header's height at the default text size (it grows with it).
    static let headerHeight: CGFloat = 44
    /// A folded group's height at the default text size (it grows too):
    /// a slim row's, so it reads as one line in the list.
    static let foldedHeight: CGFloat = OverviewRow.rowHeight

    var body: some View {
        // iOS's glass, frosty with no tint, as every glass on the iPhone
        // (David, 2026-11-18); Reduce Transparency: Firn's solid frost.
        FirnGlass(shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}

/// Nothing shows below a group's tint while it changes size: a card
/// folding away is cut off by the tint closing over it, not left fading
/// under the row below (David's recording, 2026-11-06). Open at the sides
/// and top, and a little below, so the ring around the tab on screen keeps
/// its glow.
struct FoldMask: ViewModifier {
    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .padding(.horizontal, -24)
                .padding(.top, -24)
                .padding(.bottom, -2)
        }
    }
}
