import FirnCore
import SwiftUI

/// The bar at the bottom of the screen: back and forward in a small glass
/// pill, and the address field beside it, with reload (or stop) inside.
/// Tapping the field hides the pill so the field has the whole width, picks
/// out the whole address, and the bar rides up with the keyboard. Go opens
/// it; tapping the page cancels. At rest it shows only the committed
/// address's site, never a pending one.
struct AddressBar: View {
    let store: BrowserStore
    var editing: FocusState<Bool>.Binding
    @Namespace private var glass

    private var page: (any PageController)? { store.activeTab?.page }
    private var space: String { store.activeSpace.color }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let page, !editing.wrappedValue {
                    NavigationPill(page: page, space: space)
                        .glassEffectID("navigation", in: glass)
                }
                AddressField(store: store, editing: editing)
                    .glassEffectID("field", in: glass)
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, editing.wrappedValue ? 8 : 4)
    }
}

/// Back and forward. A button that can't go anywhere fades rather than
/// leaving, so nothing shifts as you browse.
private struct NavigationPill: View {
    let page: any PageController
    let space: String

    var body: some View {
        HStack(spacing: 0) {
            BarButton(symbol: "chevron.backward", label: "Back", action: page.goBack)
                .disabled(!page.canGoBack)
            BarButton(symbol: "chevron.forward", label: "Forward", action: page.goForward)
                .disabled(!page.canGoForward)
        }
        .padding(.horizontal, 2)
        .background(Theme.barFrost, in: .capsule)
        .glassEffect(.regular.tint(Theme.frameTint(space)), in: .capsule)
    }
}

private struct AddressField: View {
    let store: BrowserStore
    var editing: FocusState<Bool>.Binding
    @State private var text = ""
    @State private var selection: TextSelection?

    private var page: (any PageController)? { store.activeTab?.page }
    private var frontURL: URL? { page?.url }
    private var isEditing: Bool { editing.wrappedValue }

    var body: some View {
        HStack(spacing: 0) {
            // Balances the button on the right, so the site sits centered.
            if !isEditing, frontURL != nil { Color.clear.frame(width: BarButton.size) }
            TextField("Address", text: $text, selection: $selection,
                      prompt: Text("Search or enter address").foregroundStyle(Theme.muted))
                .font(.body)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(isEditing ? .leading : .center)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused(editing)
                .padding(.leading, isEditing ? 18 : 0)
                .accessibilityLabel("Address")
                .onSubmit(open)
                // At rest the field only shows the site; a tap on it starts
                // editing (below), so the finger never drops a cursor into
                // the middle of the address.
                .allowsHitTesting(isEditing)
                .accessibilityHidden(!isEditing)
                .overlay {
                    if !isEditing {
                        Button(action: beginEditing) { Color.clear.contentShape(.rect) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Address")
                            .accessibilityValue(text)
                            .accessibilityHint("Edit the address or search")
                    }
                }
            trailingButton
        }
        .frame(height: 48)
        .background {
            LoadingFrost(isLoading: page?.isLoading ?? false, progress: page?.progress ?? 0, space: store.activeSpace.color)
                .clipShape(.capsule)
        }
        .background(Theme.barFrost, in: .capsule)
        .glassEffect(.regular.tint(Theme.frameTint(store.activeSpace.color)), in: .capsule)
        .onChange(of: isEditing) { startOrEndEditing() }
        .onChange(of: frontURL) { showRestingAddress() }
        .onAppear(perform: showRestingAddress)
    }

    @ViewBuilder private var trailingButton: some View {
        if isEditing {
            BarButton(symbol: "xmark.circle.fill", label: "Clear", tint: Theme.faint) { text = "" }
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty)
        } else if let page, page.isLoading {
            BarButton(symbol: "xmark", label: "Stop", action: page.stopLoading)
        } else if let page, page.url != nil {
            BarButton(symbol: "arrow.clockwise", label: "Reload", action: page.reload)
        }
    }

    /// Typing starts from the whole address, all picked out, so it can be
    /// edited or simply typed over.
    private func beginEditing() {
        text = frontURL?.absoluteString ?? ""
        editing.wrappedValue = true
    }

    private func startOrEndEditing() {
        guard isEditing else { return showRestingAddress() }
        // The field takes focus first, then the selection; set together,
        // UIKit puts the cursor at the end instead.
        Task { @MainActor in
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func open() {
        defer { editing.wrappedValue = false }
        guard let url = AddressInput.url(for: text, searchEngine: SearchEngine.chosen) else { return }
        if let page {
            page.load(url)
        } else {
            store.openTab(url)
        }
    }

    private func showRestingAddress() {
        guard !isEditing else { return }
        selection = nil
        text = WebAddress.site(of: frontURL)
    }
}

/// A round 44pt tap target with an SF Symbol, in Firn's ink.
private struct BarButton: View {
    static let size: CGFloat = 44
    let symbol: String
    let label: String
    var tint: Color = Theme.ink
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.3))
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private extension Theme {
    /// A soft layer of the page's own color inside the bar's glass, so its
    /// words stay easy to read over any page (bare glass let busy or dark
    /// pages show through too clearly).
    static let barFrost = Theme.page.opacity(0.72)
}
