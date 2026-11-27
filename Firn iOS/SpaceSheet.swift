import FirnCore
import SwiftUI

extension EnvironmentValues {
    /// Opens the New Space sheet (`BrowserScreen` shows it): from the space
    /// menu in the overview and from the command bar.
    @Entry var newSpace: SheetAction? = nil
    /// Opens Settings, on its Spaces (`BrowserScreen` shows it): Space
    /// Settings… in the space menu.
    @Entry var spaceSettings: SheetAction? = nil
}

/// Which of the spaces' sheets is up (`BrowserScreen` owns one).
@MainActor @Observable final class SpaceSheets {
    var newSpace = false
    var settings = false
    /// Downloads (docs/IOS-PLAN.md, phase 6): the page menu, the command
    /// bar, or the pill above the bar.
    var downloads = false
    /// History (docs/IOS-PLAN.md, section 12): the page menu or the command
    /// bar.
    var history = false
    /// Tidied Away: the space menu's row, or the pill while it speaks.
    var tidied = false
}

/// Opens a sheet. Always equal to itself, so setting it never makes the
/// overview draw again (a bare closure can't be compared).
struct SheetAction: Equatable {
    let open: @MainActor () -> Void
    @MainActor func callAsFunction() { open() }
    static func == (_: Self, _: Self) -> Bool { true }
}

/// New Space on the iPhone (docs/IOS-PLAN.md, phase 4, step 2): a name, a
/// color, and the one sharing choice, in the Mac's words
/// (`Firn/SpaceSheet.swift`). Nothing changes until the ✓.
///
/// iOS's own form, as Settings (docs/IOS-PLAN.md, section 9): a grouped list
/// on iOS's neutral background, never washed in the space's color; the picked
/// swatch's ring is the only space color here. ✕ cancels, the ink ✓ creates.
struct NewSpaceSheet: View {
    let store: BrowserStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var color = Theme.spaceColorNames[0]
    /// Keep it separate (the default), or share sign-ins.
    @State private var shares = false
    @State private var shareWith: UUID?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(Space.defaultName, text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Name")
                        .tint(Theme.accent)
                        .onChange(of: name) {
                            if name.count > Space.nameLimit { name = String(name.prefix(Space.nameLimit)) }
                        }
                } header: {
                    Text("Name")
                }

                Section {
                    SpaceSwatches(selection: $color)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                } header: {
                    Text("Color")
                }

                sharingSection
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .tint(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Space", systemImage: "checkmark", role: .confirm, action: finish)
                        .tint(Theme.ink)
                }
            }
        }
        // Ink, as Settings: no words are Glacier (the "Share with" value was).
        // The cursor and the check take their Glacier by themselves.
        .tint(Theme.ink)
        .presentationDetents([.large])
        .onAppear(perform: start)
    }

    // MARK: Parts

    /// Separate (recommended), or sharing another space's sign-ins.
    private var sharingSection: some View {
        Section {
            Choice(
                isSelected: !shares,
                title: "Keep this space separate",
                caption: "Recommended. It starts signed out of everything."
            ) { choose(sharing: false) }
            if let target = shareTarget {
                Choice(
                    isSelected: shares,
                    title: "Share sign-ins with “\(target.name)”",
                    caption: "It starts signed in wherever “\(target.name)” is. Its tabs and Basecamp are still its own."
                ) { choose(sharing: true) }
                if shares, store.spaces.count > 1 {
                    // With more than one space to share with, pick which;
                    // only once sharing is chosen, so the default stays quiet.
                    Picker("Share with", selection: $shareWith) {
                        ForEach(store.spaces) { space in
                            Text(space.name).tag(Optional(space.id))
                        }
                    }
                }
            }
        } header: {
            Text("Sign-ins")
        }
    }

    // MARK: Actions

    /// The space a new one would share with: the one picked, or the one on screen.
    private var shareTarget: Space? {
        store.spaces.first { $0.id == shareWith } ?? store.spaces.first { $0.id == store.activeSpaceID }
    }

    private func choose(sharing: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { shares = sharing }
    }

    private func start() {
        color = Theme.freeSpaceColor(among: store.spaces)
        shareWith = store.activeSpaceID
        nameFocused = true
    }

    /// The new space is shown at once: its tabs (none yet) take the list's
    /// place and the tint cross-fades as the sheet slides away.
    private func finish() {
        let sharing = shares ? shareTarget : nil
        dismiss()
        withAnimation(.easeOut(duration: 0.25)) {
            _ = store.addSpace(name: name, color: color, sharingWith: sharing)
        }
    }
}

/// The eight colors, spread across the width (each at least 44pt to tap);
/// the one picked wears a ring of its own color. Shared by New Space and
/// Settings.
struct SpaceSwatches: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Theme.spaceColorNames, id: \.self) { name in
                Button { selection = name } label: {
                    Circle()
                        .fill(Theme.spaceColor(name))
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay {
                            Circle().strokeBorder(Theme.spaceColor(name).opacity(name == selection ? 1 : 0), lineWidth: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selection)
                .accessibilityLabel(name.capitalized)
                .accessibilityAddTraits(name == selection ? .isSelected : [])
            }
        }
    }
}

/// One of the sign-in choices, as iOS's own pick-one rows: a title, a quiet
/// caption, and a check on the one chosen.
private struct Choice: View {
    let isSelected: Bool
    let title: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // `Color`, not `.primary`: inside a list's button the
                    // style would follow the tint.
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
