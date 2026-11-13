import FirnCore
import SwiftUI

/// Settings on the iPhone (docs/IOS-PLAN.md, phase 4, step 3): for now only
/// Spaces (sync's switch joins it later). Every space in its order (hold and
/// drag to reorder), and below, the one picked: its name, color, sign-ins,
/// and Delete, in the Mac's words (`Firn/SpacesSettings.swift`). Changes
/// apply as they're made; only Stop Sharing and Delete ask first.
///
/// One list rather than a page per space: the same shape as the Mac's, and
/// no navigation bar of stock glass. On Firn's warm paper washed in the
/// picked space's color, as New Space is.
struct SettingsSheet: View {
    let store: BrowserStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: UUID?
    /// The name as typed; the store keeps the last name that wasn't blank.
    @State private var name = ""
    @State private var confirmingStopSharing = false
    @State private var deleting: Space?
    @FocusState private var nameFocused: Bool

    /// The space picked, or the one on screen when none is (or it's gone).
    private var selected: Space {
        store.spaces.first { $0.id == selectedID } ?? store.activeSpace
    }

    var body: some View {
        let space = selected
        VStack(spacing: 0) {
            header
            List {
                Section {
                    ForEach(store.spaces) { space in
                        row(space)
                    }
                    .onMove { from, to in
                        guard let index = from.first else { return }
                        // `to` counts the row being moved; FirnCore's doesn't.
                        store.moveSpace(store.spaces[index], to: to > index ? to - 1 : to)
                    }
                } header: {
                    sectionTitle("Spaces")
                } footer: {
                    if store.spaces.count > 1 {
                        footnote("Hold a space and drag to change the order.")
                    }
                }

                Section {
                    nameField
                        .listRowBackground(Theme.hover)
                    SpaceSwatches(selection: Binding(
                        get: { selected.color },
                        set: { store.updateSpace(selected, name: selected.name, color: $0) }
                    ))
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Theme.hover)
                    signIns(of: space)
                        .listRowBackground(Theme.hover)
                } header: {
                    sectionTitle(space.name)
                }

                if store.spaces.count > 1 {
                    Section {
                        Button { deleting = space } label: {
                            Text("Delete Space…")
                                .font(.body)
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.hover)
                        .accessibilityLabel("Delete \(space.name)")
                    } footer: {
                        // A separate space's sign-ins go too; shared ones stay.
                        footnote(store.spacesSharingData(with: space).isEmpty
                                 ? "Its tabs, groups, Basecamp, and sign-ins go with it."
                                 : "Its tabs, groups, and Basecamp go with it.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 44)
        }
        .presentationDetents([.large])
        .presentationBackground {
            ZStack {
                Theme.page
                Theme.frameTint(space.color)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: space.color)
            }
        }
        .tint(Theme.ink)
        .onAppear {
            selectedID = store.activeSpaceID
            name = selected.name
        }
        // The space picked was deleted, or another was picked.
        .onChange(of: selected.id) { name = selected.name }
        .confirmationDialog(
            "Stop sharing sign-ins?",
            isPresented: $confirmingStopSharing,
            titleVisibility: .visible,
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
            titleVisibility: .visible,
            presenting: deleting
        ) { space in
            Button("Delete Space", role: .destructive) { delete(space) }
            Button("Cancel", role: .cancel) {}
        } message: { space in
            Text(deleteMessage(for: space))
        }
    }

    // MARK: Parts

    /// The title in the middle and Done on the right, as iOS's settings sheets.
    private var header: some View {
        ZStack {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.muted)
            .textCase(nil)
            .lineLimit(1)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.muted)
    }

    /// One space: its color, name, and whose sign-ins it uses. The picked
    /// one sits on the paper-white of the tab on screen; the rest on a soft
    /// wash, as on the Mac.
    private func row(_ space: Space) -> some View {
        let isSelected = space.id == selected.id
        return Button { select(space) } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.spaceColor(space.color))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.body.weight(isSelected ? .medium : .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(sharingLine(for: space))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Theme.activeTab : Theme.hover)
        // No lines between spaces: the picked one's paper already sets it apart.
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Move Up") { move(space, by: -1) }
        .accessibilityAction(named: "Move Down") { move(space, by: 1) }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Text("Name")
                .font(.body)
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField(Space.defaultName, text: $name)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .focused($nameFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Name")
                .onChange(of: name) { store.updateSpace(selected, name: name, color: selected.color) }
                // A blank name isn't kept: the field shows the saved one again.
                .onSubmit { name = selected.name }
                .onChange(of: nameFocused) { if !nameFocused { name = selected.name } }
        }
    }

    private func signIns(of space: Space) -> some View {
        let others = store.spacesSharingData(with: space)
        return VStack(alignment: .leading, spacing: 8) {
            Text(others.isEmpty
                 ? "Separate: its own sign-ins, cookies, and history."
                 : "Shared with \(names(others)).")
                .font(.body)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !others.isEmpty {
                Button("Stop Sharing…") { confirmingStopSharing = true }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Actions

    private func select(_ space: Space) {
        guard space.id != selected.id else { return }
        nameFocused = false
        selectedID = space.id
    }

    private func move(_ space: Space, by step: Int) {
        guard let index = store.spaces.firstIndex(where: { $0.id == space.id }) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            store.moveSpace(space, to: index + step)
        }
    }

    private func delete(_ space: Space) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.deleteSpace(space) }
        if selectedID == space.id { selectedID = store.activeSpaceID }
    }

    // MARK: Words (the Mac's)

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
