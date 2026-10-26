import FirnCore
import SwiftUI

/// Settings › Spaces: every space in its order (drag to reorder), and the
/// one picked: its name, color, sign-ins, and Delete. Changes apply as
/// they're made, as Mac settings do; only Stop Sharing and Delete ask first.
/// Making a space stays on the browser's New space card, where it appears.
struct SpacesSettings: View {
    let window: WindowModel

    @Environment(\.openWindow) private var openWindow
    @State private var selectedID: UUID?
    /// The name as typed; the store keeps the last name that wasn't blank.
    @State private var name = ""
    @State private var confirmingStopSharing = false
    @State private var deleting: Space?
    @FocusState private var nameFocused: Bool

    private var store: BrowserStore { window.store }
    /// The space picked, or the one on screen when none is (or it's gone).
    private var selected: Space {
        store.spaces.first { $0.id == selectedID } ?? store.activeSpace
    }

    var body: some View {
        let space = selected
        Form {
            Section {
                ForEach(store.spaces) { space in
                    SpaceSettingsRow(
                        space: space,
                        sharing: sharingLine(for: space),
                        isSelected: space.id == selected.id
                    ) { select(space) }
                    .contextMenu {
                        Button("Move Up") { store.moveSpace(space, to: index(of: space) - 1) }
                            .disabled(index(of: space) == 0)
                        Button("Move Down") { store.moveSpace(space, to: index(of: space) + 1) }
                            .disabled(index(of: space) == store.spaces.count - 1)
                    }
                }
                .onMove { from, to in
                    guard let first = from.first else { return }
                    let space = store.spaces[first]
                    // `to` counts the row being moved; the store's position doesn't.
                    store.moveSpace(space, to: to > first ? to - 1 : to)
                }
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    SettingsFootnote("Drag to change the order. The first nine switch with ⌃1 to ⌃9.")
                    Button("New Space…") {
                        window.newSpace()
                        openWindow(id: "browser")
                    }
                    .fixedSize()
                }
            }
            Section {
                TextField("Name", text: $name, prompt: Text(Space.defaultName))
                    .focused($nameFocused)
                    .onChange(of: name) { store.updateSpace(selected, name: name, color: selected.color) }
                    // A blank name isn't kept: the field shows the saved one again.
                    .onSubmit { name = selected.name }
                    .onChange(of: nameFocused) { if !nameFocused { name = selected.name } }
                LabeledContent("Color") {
                    HStack(spacing: 4) {
                        ForEach(Theme.spaceColorNames, id: \.self) { color in
                            ColorSwatch(name: color, isSelected: color == space.color) {
                                store.updateSpace(space, name: space.name, color: color)
                            }
                        }
                    }
                }
                signIns(of: space)
            } header: {
                Text(space.name)
            }
            if store.spaces.count > 1 {
                Section {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete this space")
                                .foregroundStyle(Theme.ink)
                            Text("Its tabs, groups, and Basecamp go with it.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 12)
                        Button("Delete Space…") { deleting = space }
                            .accessibilityLabel("Delete \(space.name)")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
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

    @ViewBuilder private func signIns(of space: Space) -> some View {
        let others = store.spacesSharingData(with: space)
        LabeledContent("Sign-ins") {
            HStack(spacing: 10) {
                Text(others.isEmpty
                     ? "Separate: its own sign-ins, cookies, and history."
                     : "Shared with \(names(others)).")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if !others.isEmpty {
                    Button("Stop Sharing…") { confirmingStopSharing = true }
                }
            }
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

    private func index(of space: Space) -> Int {
        store.spaces.firstIndex { $0.id == space.id } ?? 0
    }

    private func delete(_ space: Space) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
/// picked one sits on a soft wash, as a selected row does in the sidebar.
private struct SpaceSettingsRow: View {
    let space: Space
    let sharing: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.spaceColor(space.color))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(space.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(sharing)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(isSelected ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
