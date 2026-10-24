import FirnCore
import SwiftUI

/// Which space sheet is open: making a new space, or editing one.
enum SpaceSheetMode: Hashable, Identifiable {
    case new
    case edit(UUID)

    var id: Self { self }
}

/// The New space and Edit space card over the page, drawn like the command
/// bar: Firn's glass over a dimmed page. Not a system sheet: a sheet is its
/// own window, so its glass can't see the page behind it. Esc, Cancel, or a
/// click on the dim closes it; it rises a hair as it fades in (Reduce Motion: fades).
struct SpaceSheetLayer: View {
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let mode = window.spaceSheet {
                RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                    .fill(Theme.commandDim)
                    .contentShape(Rectangle())
                    .onTapGesture { window.closeSpaceSheet() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                SpaceSheet(window: window, mode: mode)
                    .id(mode)
                    .padding(24)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: window.spaceSheet)
    }
}

/// The card itself: a name, a color, an icon, and (for a new space) the one
/// sharing choice (CLAUDE.md, How spaces work). Nothing changes until Create
/// or Save; Stop Sharing is the exception, after its own confirmation. Its
/// glass takes the color being chosen, so it previews the space as it's made.
struct SpaceSheet: View {
    let window: WindowModel
    let mode: SpaceSheetMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var color = Theme.spaceColorNames[0]
    @State private var icon = SpaceIcon.default
    /// New space only: keep it separate (the default), or share sign-ins.
    @State private var shares = false
    @State private var shareWith: UUID?
    @State private var confirmingStopSharing = false
    /// Return can reach both the name field and the default button; act once.
    @State private var finished = false
    @FocusState private var nameFocused: Bool

    private var store: BrowserStore { window.store }
    private var editing: Space? {
        guard case let .edit(id) = mode else { return nil }
        return store.spaces.first { $0.id == id }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            Text(editing == nil ? "New space" : "Edit space")
                .font(Theme.panelTitleFont)
                .foregroundStyle(Theme.ink)
            section("Name") { nameField }
            section("Color") { swatches }
            section("Icon") { icons }
            section("Sign-ins") {
                if let editing { signInsStatus(of: editing) } else { sharingChoice }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { window.closeSpaceSheet() }
                    .buttonStyle(SheetButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create Space" : "Save", action: finish)
                    .buttonStyle(SheetButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380)
        .background {
            CommandBarGlass(shape: shape, color: Theme.spaceColor(color))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: color)
        }
        .clipShape(shape)
        .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
        .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
        .onExitCommand { window.closeSpaceSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(editing == nil ? "New space" : "Edit space")
        .accessibilityAddTraits(.isModal)
        .onAppear(perform: start)
        // The space being edited was deleted meanwhile: nothing left to edit.
        .onChange(of: editing == nil) {
            if case .edit = mode, editing == nil { window.closeSpaceSheet() }
        }
        .confirmationDialog(
            "Stop sharing sign-ins?",
            isPresented: $confirmingStopSharing,
            presenting: editing
        ) { space in
            Button("Stop Sharing", role: .destructive) { store.stopSharing(space) }
            Button("Cancel", role: .cancel) {}
        } message: { space in
            Text(stopSharingMessage(for: space))
        }
    }

    // MARK: Parts

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.labelFont)
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var nameField: some View {
        TextField(Space.defaultName, text: $name)
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused($nameFocused)
            .onSubmit(finish)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(Theme.hover)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .strokeBorder(nameFocused ? Theme.frost : .clear, lineWidth: 2)
            }
            .accessibilityLabel("Name")
    }

    private var swatches: some View {
        HStack(spacing: 6) {
            ForEach(Theme.spaceColorNames, id: \.self) { name in
                ColorSwatch(name: name, isSelected: name == color) { color = name }
            }
        }
    }

    /// Two even rows of eight. The chosen one wears the space's color.
    private var icons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
            ForEach(SpaceIcon.allCases, id: \.self) { choice in
                IconChoice(icon: choice, color: Theme.spaceColor(color), isSelected: choice == icon) { icon = choice }
            }
        }
    }

    /// New space: separate (recommended), or sharing another space's sign-ins.
    private var sharingChoice: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChoiceRow(
                isSelected: !shares,
                title: Text("Keep this space separate"),
                caption: "Recommended. It starts signed out of everything."
            ) { shares = false }
            if let target = shareTarget {
                ChoiceRow(
                    isSelected: shares,
                    title: Text("Share sign-ins with “\(target.name)”"),
                    caption: "It starts signed in wherever “\(target.name)” is. Its tabs and Basecamp are still its own."
                ) { shares = true }
                if store.spaces.count > 1 {
                    // With more than one space to share with, pick which.
                    Picker("Share with", selection: $shareWith) {
                        ForEach(store.spaces) { space in
                            Text(space.name).tag(Optional(space.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .padding(.leading, 30)
                    .disabled(!shares)
                    .opacity(shares ? 1 : 0.5)
                }
            }
        }
    }

    /// Edit space: says whose sign-ins it uses, and offers Stop Sharing.
    @ViewBuilder private func signInsStatus(of space: Space) -> some View {
        let others = store.spacesSharingData(with: space).map { "“\($0.name)”" }
        if others.isEmpty {
            Text("Separate: its own sign-ins, cookies, and history.")
                .font(Theme.labelFont)
                .foregroundStyle(Theme.ink)
        } else {
            HStack(spacing: 12) {
                Text("Shares sign-ins with \(others.formatted(.list(type: .and))).")
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Stop Sharing…") { confirmingStopSharing = true }
                    .buttonStyle(SheetButtonStyle(prominent: false))
            }
        }
    }

    // MARK: Actions

    /// The space a new one would share with: the one picked, or the one on screen.
    private var shareTarget: Space? {
        store.spaces.first { $0.id == shareWith } ?? store.spaces.first { $0.id == store.activeSpaceID }
    }

    private func start() {
        if let editing {
            name = editing.name
            color = editing.color
            icon = SpaceIcon(stored: editing.icon)
        } else {
            color = window.freeSpaceColor
            icon = window.freeSpaceIcon
            shareWith = store.activeSpaceID
        }
        // Once the card is in the window, as the command bar does.
        Task { @MainActor in
            await Task.yield()
            nameFocused = true
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let editing {
            store.updateSpace(editing, name: name, icon: icon.rawValue, color: color)
            window.closeSpaceSheet()
        } else {
            let sharing = shares ? shareTarget : nil
            window.closeSpaceSheet()
            window.showSpace { store.addSpace(name: name, icon: icon.rawValue, color: color, sharingWith: sharing) }
        }
    }

    private func stopSharingMessage(for space: Space) -> String {
        let others = store.spacesSharingData(with: space).map { "“\($0.name)”" }.formatted(.list(type: .and))
        return "“\(space.name)” will start fresh, signed out of everything. \(others) will stay signed in."
    }
}

/// One of the space colors: a soft dot, ringed in its own color when chosen.
/// The welcome's space step uses it too, so both look the same.
struct ColorSwatch: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.spaceColor(name))
                .frame(width: 20, height: 20)
                .padding(4)
                .overlay {
                    Circle().strokeBorder(
                        Theme.spaceColor(name).opacity(isSelected ? 1 : hovering ? 0.35 : 0),
                        lineWidth: 2
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
        .help(name.capitalized)
        .accessibilityLabel(name.capitalized)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One icon to pick: ink until chosen, then the space's color on a soft
/// wash of it, as in the approved draft.
struct IconChoice: View {
    let icon: SpaceIcon
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            SpaceIconView(icon: icon, size: 22, color: isSelected ? color : Theme.ink)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .fill(isSelected ? color.opacity(colorScheme == .dark ? 0.22 : 0.18) : hovering ? Theme.hover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: color)
        .help(icon.spokenName)
        .accessibilityLabel(icon.spokenName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A radio-style row: a ring that fills when chosen, a title, and a quiet caption.
struct ChoiceRow: View {
    let isSelected: Bool
    let title: Text
    let caption: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .strokeBorder(isSelected ? Theme.ink : Theme.faint, lineWidth: 1.5)
                    .overlay { Circle().fill(isSelected ? Theme.ink : .clear).padding(4) }
                    .frame(width: 14, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                    Text(caption)
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The sheet's buttons. Firn's buttons are ink, never the system blue: the
/// main one is filled with ink, the others a quiet wash.
private struct SheetButtonStyle: ButtonStyle {
    let prominent: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Theme.page : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if prominent { return Theme.ink.opacity(pressed ? 0.8 : hovering ? 0.9 : 1) }
        return pressed ? Theme.press : hovering ? Theme.press : Theme.hover
    }
}
