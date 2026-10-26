import FirnCore
import SwiftUI

/// The New space card over the page, drawn like the command
/// bar: Firn's glass over a dimmed page. Not a system sheet: a sheet is its
/// own window, so its glass can't see the page behind it. Esc, Cancel, or a
/// click on the dim closes it; it rises a hair as it fades in (Reduce Motion: fades).
struct SpaceSheetLayer: View {
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if window.showsSpaceSheet {
                RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                    .fill(Theme.commandDim)
                    .contentShape(Rectangle())
                    .onTapGesture { window.closeSpaceSheet() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                SpaceSheet(window: window)
                    .padding(24)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: window.showsSpaceSheet)
    }
}

/// The card itself: a name, a color, and the one sharing choice (CLAUDE.md,
/// How spaces work). Nothing changes until Create Space. Its glass takes the
/// color being chosen, so it previews the space as it's made. Changing a
/// space later is Settings › Spaces.
struct SpaceSheet: View {
    let window: WindowModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var color = Theme.spaceColorNames[0]
    /// Keep it separate (the default), or share sign-ins.
    @State private var shares = false
    @State private var shareWith: UUID?
    /// Return can reach both the name field and the default button; act once.
    @State private var finished = false
    @FocusState private var nameFocused: Bool

    private var store: BrowserStore { window.store }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            Text("New space")
                .font(Theme.panelTitleFont)
                .foregroundStyle(Theme.ink)
            section("Name") { nameField }
            section("Color") { swatches }
            section("Sign-ins") { sharingChoice }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { window.closeSpaceSheet() }
                    .buttonStyle(SheetButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("Create Space", action: finish)
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
        .accessibilityLabel("New space")
        .accessibilityAddTraits(.isModal)
        .onAppear(perform: start)
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

    // MARK: Actions

    /// The space a new one would share with: the one picked, or the one on screen.
    private var shareTarget: Space? {
        store.spaces.first { $0.id == shareWith } ?? store.spaces.first { $0.id == store.activeSpaceID }
    }

    private func start() {
        color = window.freeSpaceColor
        shareWith = store.activeSpaceID
        // Once the card is in the window, as the command bar does.
        Task { @MainActor in
            await Task.yield()
            nameFocused = true
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let sharing = shares ? shareTarget : nil
        window.closeSpaceSheet()
        window.showSpace { store.addSpace(name: name, color: color, sharingWith: sharing) }
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
struct SheetButtonStyle: ButtonStyle {
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.45)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Theme.page : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
            .onHover { hovering = isEnabled && $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if prominent && !isEnabled { return Theme.ink.opacity(0.35) }
        if prominent { return Theme.ink.opacity(pressed ? 0.8 : hovering ? 0.9 : 1) }
        return pressed ? Theme.press : hovering ? Theme.press : Theme.hover
    }
}
