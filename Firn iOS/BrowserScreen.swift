import FirnCore
import SwiftUI

/// The one screen of phase 1: the page, with a plain address field below it.
/// Step 3 gives the field Firn's look, and back, forward, and reload.
struct BrowserScreen: View {
    let store: BrowserStore

    var body: some View {
        VStack(spacing: 0) {
            if let page = store.activeTab?.page {
                PageView(page: page)
                    // A new tab gets a new web view, not the last one's.
                    .id(ObjectIdentifier(page))
            } else {
                Theme.page
            }
            AddressField(store: store)
        }
        .background(Theme.page)
    }
}

/// Takes an address or a search, as on the Mac. While no one is typing it
/// shows only the committed address's site, never a pending one.
private struct AddressField: View {
    let store: BrowserStore
    @State private var text = ""
    @FocusState private var focused: Bool

    private var frontURL: URL? { store.activeTab?.page?.url }

    var body: some View {
        TextField("Search or enter address", text: $text)
            .font(.body)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(focused ? .leading : .center)
            .keyboardType(.webSearch)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.frame, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityLabel("Address")
            .onSubmit(open)
            .onChange(of: focused) {
                if focused { text = frontURL?.absoluteString ?? "" } else { showRestingAddress() }
            }
            .onChange(of: frontURL) { showRestingAddress() }
            .onAppear(perform: showRestingAddress)
    }

    private func open() {
        guard let url = AddressInput.url(for: text, searchEngine: SearchEngine.chosen) else { return }
        if let page = store.activeTab?.page {
            page.load(url)
        } else {
            store.openTab(url)
        }
        focused = false
    }

    private func showRestingAddress() {
        guard !focused else { return }
        text = WebAddress.site(of: frontURL)
    }
}
