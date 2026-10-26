import FirnCore
import SwiftUI

/// Settings › Spaces: every space in its order (drag to reorder), and the
/// one picked: its name, color, sign-ins, and Delete. Changes apply as
/// they're made, as Mac settings do; only Stop Sharing and Delete ask first.
/// Making a space stays on the browser's New space card, where it appears.
struct SpacesSettings: View {
    let window: WindowModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: UUID?
    /// The name as typed; the store keeps the last name that wasn't blank.
    @State private var name = ""
    @State private var confirmingStopSharing = false
    @State private var deleting: Space?
    /// The row being dragged, and how far it has moved.
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    @FocusState private var nameFocused: Bool
    /// The list has keyboard focus: ↑ and ↓ pick a space, ⌥↑ and ⌥↓ move it.
    @FocusState private var listFocused: Bool

    private static let rowHeight: CGFloat = 44
    private static let rowSpacing: CGFloat = 2
    private static var rowPitch: CGFloat { rowHeight + rowSpacing }

    private var store: BrowserStore { window.store }
    /// The space picked, or the one on screen when none is (or it's gone).
    private var selected: Space {
        store.spaces.first { $0.id == selectedID } ?? store.activeSpace
    }

    var body: some View {
        let space = selected
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsCard { list }
                    HStack(alignment: .center) {
                        SettingsFootnote("Drag to change the order. The first nine switch with ⌃1 to ⌃9.")
                        Button("New Space…") {
                            window.newSpace()
                            openWindow(id: "browser")
                        }
                        .buttonStyle(SheetButtonStyle(prominent: false))
                        .fixedSize()
                    }
                    .padding(.horizontal, 4)
                }
                SettingsCard {
                    SettingsCardRow(label: "Name") {
                        FirnTextField(placeholder: Space.defaultName, text: $name, focused: $nameFocused)
                            .frame(maxWidth: 260)
                            .accessibilityLabel("Name")
                            .onChange(of: name) { store.updateSpace(selected, name: name, color: selected.color) }
                            // A blank name isn't kept: the field shows the saved one again.
                            .onSubmit { name = selected.name }
                            .onChange(of: nameFocused) { if !nameFocused { name = selected.name } }
                    }
                    SettingsCardRow(label: "Color") {
                        HStack(spacing: 2) {
                            ForEach(Theme.spaceColorNames, id: \.self) { color in
                                ColorSwatch(name: color, isSelected: color == space.color) {
                                    store.updateSpace(space, name: space.name, color: color)
                                }
                            }
                        }
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    }
                    signIns(of: space)
                }
                if store.spaces.count > 1 {
                    SettingsCard {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Delete “\(space.name)”")
                                    .font(Theme.tabFont)
                                    .foregroundStyle(Theme.ink)
                                // A separate space's sign-ins go too; shared ones stay.
                                Text(store.spacesSharingData(with: space).isEmpty
                                     ? "Its tabs, groups, Basecamp, and sign-ins go with it."
                                     : "Its tabs, groups, and Basecamp go with it.")
                                    .font(Theme.hintFont)
                                    .foregroundStyle(Theme.muted)
                            }
                            .accessibilityElement(children: .combine)
                            Spacer(minLength: 12)
                            Button("Delete Space…") { deleting = space }
                                .buttonStyle(SheetButtonStyle(prominent: false))
                                .accessibilityLabel("Delete \(space.name)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            selectedID = window.settingsSpaceID ?? store.activeSpaceID
            window.settingsSpaceID = nil
            name = selected.name
        }
        // Space Settings… from the bottom row while Settings is already open.
        .onChange(of: window.settingsSpaceID) {
            guard let id = window.settingsSpaceID else { return }
            select(id)
            window.settingsSpaceID = nil
        }
        // The space picked was deleted, or the space on screen changed under it.
        .onChange(of: selected.id) { name = selected.name }
        .confirmationDialog(
            "Stop sharing sign-ins?",
            isPresented: $confirmingStopSharing,
            presenting: space
        ) { space in
            Button("Stop Sharing", role: .destructive) { store.stopSharing(space) }
            Button("Cancel", role: .cancel) {}
        } message: { space in
            Text(stopSharingMessage(for: space))
        }
        .confirmationDialog(
            deleting.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { space in
            Button("Delete Space", role: .destructive) { delete(space) }
            Button("Cancel", role: .cancel) {}
        } message: { space in
            Text(deleteMessage(for: space))
        }
    }

    // MARK: Parts

    /// The spaces, in order. A row follows the pointer while dragged; the
    /// others glide aside to make room, and it settles where it's let go.
    private var list: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceSettingsRow(
                    space: space,
                    sharing: sharingLine(for: space),
                    isSelected: space.id == selected.id,
                    isDragged: space.id == dragging,
                    showsFocus: listFocused
                )
                .frame(height: Self.rowHeight)
                .offset(y: offset(of: space, at: index))
                // The others glide aside; the dragged row stays under the pointer.
                .animation(space.id == dragging || reduceMotion ? nil : .smooth(duration: 0.2), value: dragOffset)
                .zIndex(space.id == dragging ? 1 : 0)
                .onTapGesture {
                    select(space)
                    listFocused = true
                }
                .gesture(reorder(space, from: index))
                .contextMenu {
                    Button("Move Up") { move(space, by: -1) }
                        .disabled(index == 0)
                    Button("Move Down") { move(space, by: 1) }
                        .disabled(index == store.spaces.count - 1)
                }
                .accessibilityAction { select(space) }
                .accessibilityAction(named: "Move Up") { move(space, by: -1) }
                .accessibilityAction(named: "Move Down") { move(space, by: 1) }
            }
        }
        .padding(6)
        // Keyboard: the list takes focus as one control, like a list in a
        // Mac settings pane; the picked row shows the frost ring instead of
        // a ring around the whole card.
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            let step = press.key == .upArrow ? -1 : 1
            if press.modifiers.contains(.option) {
                move(selected, by: step)
            } else if let index = store.spaces.firstIndex(where: { $0.id == selected.id }) {
                let next = min(max(index + step, 0), store.spaces.count - 1)
                select(store.spaces[next])
            }
            return .handled
        }
    }

    @ViewBuilder private func signIns(of space: Space) -> some View {
        let others = store.spacesSharingData(with: space)
        SettingsCardRow(label: "Sign-ins") {
            VStack(alignment: .leading, spacing: 8) {
                Text(others.isEmpty
                     ? "Separate: its own sign-ins, cookies, and history."
                     : "Shared with \(names(others)).")
                    .font(Theme.tabFont)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !others.isEmpty {
                    Button("Stop Sharing…") { confirmingStopSharing = true }
                        .buttonStyle(SheetButtonStyle(prominent: false))
                }
            }
        }
    }

    // MARK: Dragging

    /// Where the dragged row would land, counted among the spaces.
    private func target(from index: Int) -> Int {
        let steps = Int((dragOffset / Self.rowPitch).rounded())
        return min(max(index + steps, 0), store.spaces.count - 1)
    }

    private func offset(of space: Space, at index: Int) -> CGFloat {
        guard let dragging, let from = store.spaces.firstIndex(where: { $0.id == dragging }) else { return 0 }
        if space.id == dragging { return dragOffset }
        let to = target(from: from)
        if from < to, index > from, index <= to { return -Self.rowPitch }
        if to < from, index >= to, index < from { return Self.rowPitch }
        return 0
    }

    private func reorder(_ space: Space, from index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragging == nil { dragging = space.id }
                dragOffset = value.translation.height
            }
            .onEnded { _ in
                let to = target(from: index)
                // Settled in place: the new order and no offsets, at once.
                var settle = Transaction()
                settle.disablesAnimations = true
                withTransaction(settle) {
                    store.moveSpace(space, to: to)
                    dragging = nil
                    dragOffset = 0
                }
            }
    }

    private func move(_ space: Space, by step: Int) {
        guard let index = store.spaces.firstIndex(where: { $0.id == space.id }) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            store.moveSpace(space, to: index + step)
        }
    }

    // MARK: Actions

    private func select(_ space: Space) { select(space.id) }

    private func select(_ id: UUID) {
        guard id != selectedID else { return }
        nameFocused = false
        selectedID = id
        name = selected.name
    }

    private func delete(_ space: Space) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.deleteSpace(space) }
        if selectedID == space.id { selectedID = store.activeSpaceID }
    }

    // MARK: Words

    private func names(_ spaces: [Space]) -> String {
        spaces.map { "“\($0.name)”" }.formatted(.list(type: .and))
    }

    private func sharingLine(for space: Space) -> String {
        let others = store.spacesSharingData(with: space)
        return others.isEmpty ? "Separate" : "Shares sign-ins with \(names(others))"
    }

    private func stopSharingMessage(for space: Space) -> String {
        "“\(space.name)” will start fresh, signed out of everything. \(names(store.spacesSharingData(with: space))) will stay signed in."
    }

    private func deleteMessage(for space: Space) -> String {
        let goes = "Its tabs, groups, and Basecamp will be deleted."
        if let other = store.spacesSharingData(with: space).first {
            return "\(goes) Its sign-ins stay, because “\(other.name)” still uses them."
        }
        return "\(goes) So will its sign-ins, cookies, and site data. This can’t be undone."
    }
}

/// One space in the list: its color, name, and whose sign-ins it uses. The
/// picked one sits on a soft wash, as the tab on screen does in the sidebar;
/// a grip shows on hover, to say rows can be dragged.
private struct SpaceSettingsRow: View {
    let space: Space
    let sharing: String
    let isSelected: Bool
    let isDragged: Bool
    /// The list has keyboard focus; the picked row wears the frost ring.
    let showsFocus: Bool
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.spaceColor(space.color))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(space.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(sharing)
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.faint)
                .opacity(hovering || isDragged ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background {
            shape.fill(isSelected || isDragged ? Theme.activeTab : hovering ? Theme.hover : .clear)
                .shadow(color: isSelected || isDragged ? Theme.shadowSoft : .clear, radius: isDragged ? 8 : 2, y: 1)
        }
        .overlay {
            shape.strokeBorder(isSelected || isDragged ? Theme.activeTabHairline : .clear, lineWidth: 0.5)
        }
        .overlay {
            if isSelected && showsFocus {
                shape.strokeBorder(Theme.frost, lineWidth: 2)
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
