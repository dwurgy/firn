import FirnCore
import SwiftUI

/// The same frosted glass as the Basecamp tiles. With a color, washed in it
/// (the overflow button's "Tidied away" pill, drop spots); without one, exactly
/// a tile's frost (group cards, David 2026-10-22, so the sidebar has one glass).
struct FrostGlass: View {
    let shape: RoundedRectangle
    var color: Color? = nil
    /// Picked up by a drag: the same glass over the frame (`LiftBacking`),
    /// so it never turns see-through over the page.
    var lifted = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Frosted fills, like the tiles: never glass on the window's glass.
        FirnFrost(shape: shape,
                  fill: color == nil ? Theme.tileFill : Theme.groupFill,
                  tint: (color ?? .clear).opacity(Theme.groupTint),
                  solid: reduceTransparency,
                  shadow: color == nil ? Theme.shadowSoft : .clear,
                  hairlineOutset: color == nil ? 0.5 : 0) {
            if lifted { LiftBacking(shape: shape) }
        }
    }
}


/// What's under anything lifted off the sidebar: the frame and the space's
/// tint, nearly opaque. Over the sidebar, the glass on it looks just as it
/// does at rest; over the page, it stays frost instead of turning clear.
struct LiftBacking: View {
    let shape: RoundedRectangle
    @Environment(\.spaceColorName) private var space

    var body: some View {
        shape.fill(Theme.liftBacking)
            .overlay { shape.fill(Theme.frameTint(space)) }
    }
}

extension EnvironmentValues {
    /// The active space's color, for what's drawn over the frame (`LiftBacking`).
    @Entry var spaceColorName = "glacier"
}


/// A group's glass as its frost forms or thaws, in the same motion as the
/// card's tabs but ahead of them: its lower edge leads theirs and reaches
/// its place first (David, 2026-10-23). `progress` moves with the card's
/// own layout (0 thawed, 1 formed), and `growth` is how much taller the
/// formed card is.
struct GlassLead<Glass: View>: ViewModifier, Animatable {
    var progress: CGFloat
    let growth: CGFloat
    @ViewBuilder let glass: Glass

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // Eased ahead of the layout, meeting it at both ends.
        let ahead = 1 - (1 - progress) * (1 - progress)
        content.background(alignment: .top) {
            glass
                .padding(.bottom, -growth * (ahead - progress))
                .opacity(min(1, ahead * 2))
        }
    }
}

/// A group: a soft frosted card tinted by the space's color, with its name
/// (over the tabs' icons) and a fold arrow. The close button shows
/// only while the pointer is on the name line.
struct GroupCard<Rows: View>: View {
    let group: TabGroup
    /// False while a dragged tab has left it with none to show.
    let hasRows: Bool
    let color: Color
    @Binding var renaming: UUID?
    /// True while the group is being dragged, so letting go doesn't fold it.
    let foldLocked: Bool
    /// True while it thaws away (Ungroup) or before its frost forms (a new
    /// group): no name line, insets, or glass, so its tabs sit exactly
    /// where they do as loose tabs.
    let thawed: Bool
    /// True while it lifts away (Close Group): it folds up under its name
    /// line and fades.
    let closing: Bool
    /// True for a group still forming under a held tab: its name shows
    /// faintly, and it can't be clicked yet.
    var preview = false
    /// True for the copy a drag carries: solid, not frosted.
    var lifted = false
    let store: BrowserStore
    let ungroup: () -> Void
    let close: () -> Void
    @ViewBuilder let rows: Rows
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous) }
    private var isRenaming: Bool { renaming == group.id }
    /// New, and its name is on the way from the on-device model.
    private var isNaming: Bool { store.isNaming(group) }

    var body: some View {
        let inset = thawed ? 0 : Theme.panelRadius - Theme.tabRadius
        VStack(spacing: 0) {
            header
                // The name fades a hair ahead of a thaw, and a hair after
                // its line opens as frost forms.
                .opacity(thawed ? 0 : preview ? 0.6 : 1)
                .animation(.easeOut(duration: 0.16).delay(thawed ? 0 : 0.14), value: thawed)
                .frame(height: thawed ? 0 : Theme.groupHeaderHeight, alignment: .top)
                .clipped()
                .padding(.bottom, thawed || group.folded ? 0 : Theme.rowSpacing)
            // A folded group's tabs come out as it thaws.
            if !group.folded || thawed {
                VStack(spacing: Theme.rowSpacing) { rows }
            }
        }
        // Rows sit 4pt inside the card, so their 10pt corners nest in its 14pt.
        .padding(.horizontal, inset)
        .padding(.bottom, (group.folded && !thawed) || !hasRows ? 0 : inset)
        .modifier(GlassLead(
            progress: thawed ? 0 : 1,
            growth: group.folded ? 0 : Theme.groupHeaderHeight + Theme.rowSpacing
                + (hasRows ? Theme.panelRadius - Theme.tabRadius : 0)
        ) { card })
        // Closing, it folds up from the bottom: the tabs go first, the name line last.
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: closing ? 0 : nil, alignment: .top)
        // The clip snaps on (it matches the bounds then); only the height moves.
        .animation(nil) { $0.clipShape(Rectangle().inset(by: closing ? 0 : -Theme.rowHeight)) }
        .opacity(closing ? 0 : 1)
        .allowsHitTesting(!thawed && !closing && !preview)
        .accessibilityHidden(preview)
        .contextMenu {
            Group {
                Button("Rename", systemImage: "pencil", action: startRenaming)
                Button("Ungroup", systemImage: "folder.badge.minus", action: ungroup)
                Divider()
                Button("Close Group", systemImage: "xmark", action: close)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var header: some View {
        // No dot: the card's tint already carries the space's color (David, 2026-10-22).
        HStack(spacing: 6) {
            if isRenaming {
                nameField
            } else {
                // While the on-device model names a new group, quiet dots
                // stand where the name will be, the chevron just after
                // them; then the name fades in and the chevron glides to
                // its end (a fade and a short glide; Reduce Motion: a swap).
                Group {
                    if isNaming {
                        NamingDots(color: Theme.groupName)
                    } else {
                        Text(group.name)
                            .font(Theme.groupHeaderFont)
                            .foregroundStyle(Theme.groupName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // The new name swaps in while hidden, so "New
                            // Group" never fades out over it.
                            .contentTransition(.identity)
                    }
                }
                .transition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(group.folded ? -90 : 0))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            if hovering, !isRenaming {
                Button("Close group", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CloseButtonStyle())
                    .help("Close group")
            }
        }
        .padding(.leading, Theme.rowPadding)
        .padding(.trailing, 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isNaming)
        .frame(height: Theme.groupHeaderHeight)
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming, !foldLocked { toggleFold() } }
        .onHover { hovering = $0 }
        // While renaming, VoiceOver reaches the name field itself.
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(isNaming ? "New group, naming" : group.name)
        // The name arrived: VoiceOver hears it, as the dots fade (step 4's look over).
        .onChange(of: isNaming) { was, now in
            if was, !now { AccessibilityNotification.Announcement("Group named \(group.name)").post() }
        }
        .accessibilityValue(group.folded ? "Folded" : "Open")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(group.folded ? "Shows the group's tabs" : "Hides the group's tabs")
        .accessibilityAction { toggleFold() }
        .accessibilityAction(named: "Rename", startRenaming)
        .accessibilityAction(named: "Close group", close)
    }

    private var nameField: some View {
        TextField("Group name", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.groupHeaderFont)
            .foregroundStyle(Theme.ink)
            .focused($nameFocused)
            .onSubmit(finishRenaming)
            .onExitCommand { renaming = nil }
            .onChange(of: nameFocused) { _, focused in if !focused { finishRenaming() } }
            .onAppear {
                draft = group.name
                nameFocused = true
            }
    }

    private var card: some View { FrostGlass(shape: shape, lifted: lifted) }

    private func toggleFold() {
        animate { store.setFolded(group, !group.folded) }
    }

    private func startRenaming() {
        renaming = group.id
    }

    private func finishRenaming() {
        guard isRenaming else { return }
        store.rename(group, to: draft)
        renaming = nil
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2), change)
    }
}

/// Icon and title, as every sidebar row shows them.
struct RowLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 16)
            configuration.title
                .font(Theme.tabFont)
                .foregroundStyle(color)
                .modifier(FadesAtEdge())
        }
    }
}

/// A 36pt sidebar row: a warm wash on hover and press, lifted when it's the tab on screen.
struct RowButtonStyle: ButtonStyle {
    let isActive: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.rowPadding)
            .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
            .background {
                if isActive {
                    ActiveTabBackground()
                } else {
                    RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                        .fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

/// The tab on screen: a lifted sheet of snow, lit along its top edge, with a
/// warm hairline, a contact shadow, and a wider, fainter one beneath.
struct ActiveTabBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
        shape
            .fill(Theme.activeTab)
            .overlay {
                shape.inset(by: 0.5).strokeBorder(
                    LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5)
            }
            .overlay { shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
            .shadow(color: Theme.shadowSoft, radius: 1, y: 1)
            .shadow(color: Theme.shadowLift, radius: 5, y: 3)
    }
}

struct CloseButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 20, height: 20)
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
