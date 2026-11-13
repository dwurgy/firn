import FirnCore
import SwiftUI

extension EnvironmentValues {
    /// Opens the New Space sheet (`BrowserScreen` shows it): from the space
    /// menu in the overview and from the command bar.
    @Entry var newSpace: NewSpaceAction? = nil
}

/// Whether the New Space sheet is up (`BrowserScreen` owns one).
@MainActor @Observable final class NewSpaceRequest {
    var shown = false
}

/// Opens the New Space sheet. Always equal to itself, so setting it never
/// makes the overview draw again (a bare closure can't be compared).
struct NewSpaceAction: Equatable {
    let open: @MainActor () -> Void
    @MainActor func callAsFunction() { open() }
    static func == (_: Self, _: Self) -> Bool { true }
}

/// New Space on the iPhone (docs/IOS-PLAN.md, phase 4, step 2): a name, a
/// color, and the one sharing choice, in the Mac's words
/// (`Firn/SpaceSheet.swift`). Nothing changes until Create Space.
///
/// iOS's own sheet (it slides up, swipes down to cancel, and keeps the
/// keyboard clear), but on Firn's warm paper rather than stock glass, washed
/// in the color being picked, so it previews the space as it's made.
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
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    section("Name") { nameField }
                    section("Color") { swatches }
                    section("Sign-ins") { sharingChoice }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            createButton
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .presentationDetents([.large])
        .presentationBackground {
            ZStack {
                Theme.page
                Theme.frameTint(color)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: color)
            }
        }
        .tint(Theme.ink)
        .onAppear(perform: start)
    }

    // MARK: Parts

    /// Cancel on the left, the title in the middle, as iOS's sheets.
    private var header: some View {
        ZStack {
            Text("New Space")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var nameField: some View {
        TextField(Space.defaultName, text: $name)
            .font(.body)
            .foregroundStyle(Theme.ink)
            .focused($nameFocused)
            .submitLabel(.done)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(Theme.hover)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .strokeBorder(nameFocused ? Theme.frost : .clear, lineWidth: 2)
            }
            .accessibilityLabel("Name")
    }

    /// The eight colors, spread across the width (each at least 44pt to tap).
    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(Theme.spaceColorNames, id: \.self) { name in
                Button { color = name } label: {
                    Circle()
                        .fill(Theme.spaceColor(name))
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay {
                            Circle().strokeBorder(Theme.spaceColor(name).opacity(name == color ? 1 : 0), lineWidth: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: color)
                .accessibilityLabel(name.capitalized)
                .accessibilityAddTraits(name == color ? .isSelected : [])
            }
        }
    }

    /// Separate (recommended), or sharing another space's sign-ins.
    private var sharingChoice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Choice(
                isSelected: !shares,
                title: "Keep this space separate",
                caption: "Recommended. It starts signed out of everything."
            ) { shares = false }
            if let target = shareTarget {
                Choice(
                    isSelected: shares,
                    title: "Share sign-ins with “\(target.name)”",
                    caption: "It starts signed in wherever “\(target.name)” is. Its tabs and Basecamp are still its own."
                ) { shares = true }
                if shares, store.spaces.count > 1 {
                    // With more than one space to share with, pick which;
                    // only once sharing is chosen, so the default stays quiet.
                    HStack {
                        Text("Share with")
                            .font(.body)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Picker("Share with", selection: $shareWith) {
                            ForEach(store.spaces) { space in
                                Text(space.name).tag(Optional(space.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .padding(.leading, 34)
                    .frame(minHeight: 44)
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shares)
    }

    /// Ink, never the system blue (CLAUDE.md: buttons are ink).
    private var createButton: some View {
        Button(action: finish) {
            Text("Create Space")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.page)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background { Capsule().fill(Theme.ink) }
                .contentShape(Capsule())
        }
        .buttonStyle(FrostPress(shape: Capsule()))
    }

    // MARK: Actions

    /// The space a new one would share with: the one picked, or the one on screen.
    private var shareTarget: Space? {
        store.spaces.first { $0.id == shareWith } ?? store.spaces.first { $0.id == store.activeSpaceID }
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

/// A radio-style row: a ring that fills when chosen, a title, and a quiet
/// caption (the Mac's `ChoiceRow`, at the iPhone's sizes).
private struct Choice: View {
    let isSelected: Bool
    let title: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle()
                    .strokeBorder(isSelected ? Theme.ink : Theme.faint, lineWidth: 1.5)
                    .overlay { Circle().fill(isSelected ? Theme.ink : .clear).padding(5) }
                    .frame(width: 20, height: 20)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
