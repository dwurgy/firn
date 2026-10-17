import FirnCore
import SwiftUI

/// One browser window: a page, plus back, forward, reload, and the address bar.
struct BrowserWindow: View {
    // Made once in onAppear: a @State default value would build a new web view
    // every time SwiftUI re-creates this struct.
    @State private var page: (any PageController)?

    var body: some View {
        Group {
            if let page {
                BrowserView(page: page)
            } else {
                Theme.frame
            }
        }
        .onAppear {
            if page == nil { page = BrowserEngine.makePage(dataStoreID: PhaseOne.dataStoreID) }
        }
    }
}

private struct BrowserView: View {
    let page: any PageController
    @State private var addressText = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        PageView(page: page, cornerRadius: Theme.pageCornerRadius)
            .overlay {
                // Until something has loaded, show Firn's calm page color, not WebKit's white.
                if page.url == nil {
                    RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                        .fill(Theme.page)
                        .allowsHitTesting(false)
                }
            }
            .padding(Theme.pageInset)
            .background(Theme.frame)
            .toolbarBackground(Theme.frame, for: .windowToolbar)
            .navigationTitle(page.title.isEmpty ? "Firn" : page.title)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) { navigationButtons }
                ToolbarItem(placement: .principal) { addressBar }
            }
            .focusedSceneValue(\.activePage, page)
            .focusedSceneValue(\.focusAddressBar, FocusAddressBarAction(id: ObjectIdentifier(page)) { addressFocused = true })
            .onAppear { addressFocused = true }
            .onChange(of: page.url) { showCommittedAddress() }
            .onChange(of: addressFocused) { if !addressFocused { showCommittedAddress() } }
    }

    @ViewBuilder private var navigationButtons: some View {
        Button("Back", systemImage: "chevron.left") { page.goBack() }
            .disabled(!page.canGoBack)
            .help("Back")
        Button("Forward", systemImage: "chevron.right") { page.goForward() }
            .disabled(!page.canGoForward)
            .help("Forward")
        if page.isLoading {
            Button("Stop", systemImage: "xmark") { page.stopLoading() }
                .help("Stop loading")
        } else {
            Button("Reload", systemImage: "arrow.clockwise") { page.reload() }
                .disabled(page.url == nil)
                .help("Reload this page")
        }
    }

    private var addressBar: some View {
        TextField("Search or enter address", text: $addressText)
            .textFieldStyle(.roundedBorder)
            .focused($addressFocused)
            .frame(minWidth: 280, idealWidth: 560, maxWidth: 640)
            .onSubmit(openTypedAddress)
            .onExitCommand { addressFocused = false }
            .accessibilityLabel("Address")
    }

    private func openTypedAddress() {
        guard let url = AddressInput.url(for: addressText) else { return }
        page.load(url)
        addressFocused = false
        page.focus()
    }

    /// While someone isn't typing, the bar shows the committed address: never a
    /// pending one, so it can't claim to be a page that isn't there yet.
    private func showCommittedAddress() {
        guard !addressFocused else { return }
        addressText = page.url?.absoluteString ?? ""
    }
}

// MARK: - Menu commands

extension FocusedValues {
    @Entry var activePage: (any PageController)?
    @Entry var focusAddressBar: FocusAddressBarAction?
}

/// "Open Location…" for one window. Compared by window (its page), so SwiftUI
/// doesn't treat every redraw as a new action.
struct FocusAddressBarAction: Equatable {
    let id: ObjectIdentifier
    let perform: @MainActor () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Menu items for the front window, so every action can be found by looking,
/// with the Mac shortcuts as a bonus.
struct BrowserCommands: Commands {
    @FocusedValue(\.activePage) private var page
    @FocusedValue(\.focusAddressBar) private var focusAddressBar

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Location…") { focusAddressBar?.perform() }
                .keyboardShortcut("l")
                .disabled(focusAddressBar == nil)
        }
        CommandMenu("Go") {
            Button("Back") { page?.goBack() }
                .keyboardShortcut("[")
                .disabled(page?.canGoBack != true)
            Button("Forward") { page?.goForward() }
                .keyboardShortcut("]")
                .disabled(page?.canGoForward != true)
            Divider()
            Button("Reload Page") { page?.reload() }
                .keyboardShortcut("r")
                .disabled(page?.url == nil)
        }
    }
}
