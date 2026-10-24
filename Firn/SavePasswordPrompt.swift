import FirnCore
import SwiftUI

/// Firn's offer to save a password just used, in a popover from the address
/// bar: the site and username, then Never for this site, Not now, and Save
/// (or Update, when that username's password changed). Clicking away or
/// Esc is Not now. The password itself is never shown here.
struct SavePasswordPrompt: View {
    let store: BrowserStore
    let offer: PasswordOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.isUpdate ? "Update saved password?" : "Save password?")
                    .font(Theme.tabFont.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(details)
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 4) {
                Button("Never for this site") { store.neverSavePasswordsForOffer() }
                    .buttonStyle(TextActionStyle())
                    .accessibilityHint("Firn won’t offer to save passwords for \(offer.login.site.name) in this space")
                Spacer(minLength: 8)
                Button("Not now") { store.dismissPasswordOffer() }
                    .buttonStyle(TextActionStyle())
                    .keyboardShortcut(.cancelAction)
                Button(offer.isUpdate ? "Update" : "Save") { store.savePasswordOffer() }
                    .buttonStyle(InkButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// "example.com · dana", or just the site when no username was found.
    private var details: String {
        let site = offer.login.site.name
        return offer.login.username.isEmpty ? site : "\(site) · \(offer.login.username)"
    }
}

/// Shows `SavePasswordPrompt` from the view it's on (the address bar) while
/// the store has an offer. A hidden sidebar slides out to hold it first and
/// stays out until it's answered.
struct SavePasswordPopover: ViewModifier {
    let store: BrowserStore
    let window: WindowModel
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                if let offer = store.passwordOffer {
                    SavePasswordPrompt(store: store, offer: offer)
                }
            }
            .task(id: store.passwordOffer?.id) { await follow() }
            .onChange(of: isShown) {
                // Clicked away, or Esc: Not now.
                if !isShown {
                    store.dismissPasswordOffer()
                    window.holdPeekForPrompt(false)
                }
            }
    }

    private func follow() async {
        guard store.passwordOffer != nil else {
            isShown = false
            return
        }
        if window.sidebarCollapsed {
            window.holdPeekForPrompt(true)
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            guard !Task.isCancelled else { return }
        }
        isShown = true
    }
}
