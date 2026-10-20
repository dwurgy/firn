import FirnCore
import SwiftUI

/// The row at the bottom of the sidebar: one button per space, in order, and
/// a button to add one. Until Firn's own space icons arrive (Phase 4, step 4),
/// each space is a soft dot in its color.
struct SpaceRow: View {
    let store: BrowserStore
    let window: WindowModel
    /// The space waiting on "Delete Space…"'s confirmation.
    @State private var deleting: Space?

    var body: some View {
        HStack(spacing: 2) {
            // Side by side while they fit; with many spaces in a narrow
            // sidebar, they scroll sideways rather than squeeze.
            ViewThatFits(in: .horizontal) {
                buttons
                ScrollView(.horizontal) { buttons }
                    .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
            ChromeButton("New space", systemImage: "plus") { window.addSpace() }
        }
        .frame(height: Theme.rowHeight)
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

    private var buttons: some View {
        HStack(spacing: 2) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceButton(space: space, number: index + 1, isActive: space.id == store.activeSpaceID) {
                    window.showSpace { store.selectSpace(space) }
                }
                .contextMenu {
                    // The last space can't be deleted, so its menu stays empty.
                    if store.spaces.count > 1 {
                        Button("Delete Space…") { deleting = space }
                    }
                }
            }
        }
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

/// One space in the row: its dot, quiet until hovered, lifted like the tab on
/// screen when it's the space on screen.
private struct SpaceButton: View {
    let space: Space
    /// Its place in the row, from 1; ⌃1–9 show the first nine.
    let number: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.spaceColor(space.color))
                .frame(width: 10, height: 10)
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
            // Other spaces' dots sit back a little, so one accent leads.
            .opacity(isActive || hovering ? 1 : 0.55)
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
