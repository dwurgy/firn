import FirnCore
import SwiftUI

/// Find on page (⌘F): a small frosted field at the page's top-right corner,
/// in the command bar's glass, searching as the words are typed. Return goes
/// to the next match and ⇧Return the one before; Esc or ✕ closes it. It
/// searches the page in front (a Lookout's while one is open), and closes
/// when that page changes. It drops in a hair as it fades in; Reduce Motion: fades.
struct FindBarLayer: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if window.showsFindBar {
                FindBar(store: store, window: window)
                    .padding(12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.easeOut(duration: 0.2), value: window.showsFindBar)
        .onChange(of: store.activeTabID) { window.closeFindBar(focusingPage: false) }
        .onChange(of: store.lookout?.id) { window.closeFindBar(focusingPage: false) }
    }
}

private struct FindBar: View {
    let store: BrowserStore
    let window: WindowModel
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
            // Typing searches from the match already chosen, so it stays put while it fits.
            TextField("Find on page", text: Binding(
                get: { window.findText },
                set: { window.findText = $0; window.find(.fromHere) }
            ))
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .onSubmit {
                let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                window.find(backwards ? .previous : .next)
                focused = true
            }
            .onExitCommand { window.closeFindBar() }
            if let count = window.findCount {
                Text(FindOnPage.label(count: count))
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.faint)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack(spacing: 2) {
                FindButton(label: "Previous match", systemImage: "chevron.up") { window.find(.previous) }
                    .disabled(window.findCount ?? 0 == 0)
                FindButton(label: "Next match", systemImage: "chevron.down") { window.find(.next) }
                    .disabled(window.findCount ?? 0 == 0)
                FindButton(label: "Close", systemImage: "xmark") { window.closeFindBar() }
            }
        }
        .padding(.leading, Theme.rowPadding)
        .padding(.trailing, 6)
        .frame(width: 320, height: Theme.rowHeight)
        .background { CommandBarGlass(shape: shape, color: Theme.spaceColor(store.activeSpace.color)) }
        .clipShape(shape)
        .shadow(color: Theme.shadowPeek, radius: 16, y: 6)
        .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find on page")
        .onChange(of: window.findRequest, initial: true) {
            Task { @MainActor in
                await Task.yield()
                focused = true
                // ⌘F again selects the words, so typing replaces them.
                NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSTextView }?.selectAll(nil)
            }
        }
    }
}

/// A small icon button with the warm hover wash.
private struct FindButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.muted : Theme.faint.opacity(0.6))
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .fill(hovering && isEnabled ? Theme.hover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .onHover { hovering = $0 }
    }
}
