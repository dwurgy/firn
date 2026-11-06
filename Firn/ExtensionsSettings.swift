import FirnCore
import SwiftUI
import UniformTypeIdentifiers

/// Extension installation and enablement are scoped to the active space's data store.
struct ExtensionsSettings: View {
    let window: WindowModel

    var body: some View {
        if DemoMode.isOn {
            SettingsPage {
                SettingsGroup {
                    Text("Extensions are unavailable in demo mode.")
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.muted)
                        .padding(16)
                }
            }
        } else if #available(macOS 15.4, *) {
            SupportedExtensionsSettings(window: window)
        } else {
            SettingsPage {
                SettingsGroup {
                    Text("Extensions need macOS 15.4 or later. Firn can still browse normally on this Mac.")
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.ink)
                        .padding(16)
                }
            }
        }
    }
}

@available(macOS 15.4, *)
private struct PendingExtension: Identifiable {
    let candidate: WebExtensionInstallCandidate
    let spaceName: String
    let spaceID: UUID
    let dataStoreID: UUID
    var id: UUID { candidate.id }
}

@available(macOS 15.4, *)
private struct SupportedExtensionsSettings: View {
    let window: WindowModel
    @State private var library = WebExtensionLibrary.shared
    @State private var manager = WebExtensionManager.shared
    @State private var preparing = false
    @State private var importing = false
    @State private var pending: PendingExtension?
    @State private var pendingFailure: String?
    @State private var visible = true
    @State private var removing: InstalledWebExtension?
    @State private var errorMessage: String?

    private var store: BrowserStore { window.store }
    private var space: Space { store.activeSpace }
    private var sharedSpaces: [Space] { store.spacesSharingData(with: space) }

    var body: some View {
        SettingsPage {
            SettingsGroup(header: "In \(space.name)", footer: scopeDescription) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Install 1Password…") { prepareOnePassword() }
                        Button("Import ZIP or XPI…") { importing = true }
                        if preparing { ProgressView().controlSize(.small) }
                    }
                    .buttonStyle(SheetButtonStyle(prominent: false))
                    .disabled(preparing || pending != nil)
                    Text("Extensions can access sites you allow and send data over the network. Review each extension before installing it.")
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                    Text("1Password support is experimental and uses a separate extension account sign-in. Pairing with the desktop app and Touch ID are unavailable in Firn.")
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
            }

            SettingsGroup(header: "Installed extensions") {
                if library.extensions.isEmpty {
                    Text("No extensions installed.")
                        .font(Theme.tabFont)
                        .foregroundStyle(Theme.muted)
                        .padding(16)
                } else {
                    ForEach(library.extensions) { item in
                        extensionRow(item)
                    }
                }
            }
            if let message = library.errorMessage {
                SettingsFootnote("Extension library: \(message)")
            }
            if !library.pendingRemovals.isEmpty {
                SettingsFootnote("Extension data removal is pending. Firn retries on the next launch; some WebKit storage could remain.")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, UTType(filenameExtension: "xpi") ?? .data]) { result in
            switch result {
            case .success(let url): prepareImport(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $pending) { request in
            confirmation(for: request)
                .interactiveDismissDisabled()
        }
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            if let pending { library.cancel(pending.candidate) }
        }
        .alert("Remove extension?", isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        )) {
            Button("Remove", role: .destructive) {
                guard let item = removing else { return }
                do { try library.remove(id: item.id) }
                catch { errorMessage = error.localizedDescription }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Removing \(removing?.name ?? "this extension") disables it in every space and requests removal of its extension data. Complete storage erasure is not yet verified. Browser data and saved passwords stay in place.")
        }
        .alert("Extension error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The operation failed.")
        }
    }

    private var scopeDescription: String {
        if sharedSpaces.isEmpty { return "Extensions enabled here run only in \(space.name)." }
        return "This space shares website data and extensions with \(sharedSpaces.map(\.name).joined(separator: ", "))."
    }

    private func extensionRow(_ item: InstalledWebExtension) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(Theme.tabFont).foregroundStyle(Theme.ink)
                Text("Version \(item.version)").font(Theme.hintFont).foregroundStyle(Theme.muted)
                if let error = manager.errors[item.id] {
                    Text(error).font(Theme.hintFont).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            Toggle("Enable \(item.name) in \(space.name)", isOn: Binding(
                get: { item.enabledDataStoreIDs.contains(space.dataStoreID) },
                set: { enabled in
                    do { try library.setEnabled(enabled, id: item.id, in: space.dataStoreID) }
                    catch { errorMessage = error.localizedDescription }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .controlSize(.small)
            Button("Remove…") { removing = item }
                .buttonStyle(SheetButtonStyle(prominent: false))
                .accessibilityLabel("Remove \(item.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func prepareOnePassword() {
        let name = space.name
        let id = space.dataStoreID
        let spaceID = space.id
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let candidate = try await library.prepareOnePassword()
                if visible { pending = PendingExtension(candidate: candidate, spaceName: name, spaceID: spaceID, dataStoreID: id) }
                else { library.cancel(candidate) }
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func prepareImport(_ url: URL) {
        let name = space.name
        let id = space.dataStoreID
        let spaceID = space.id
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let candidate = try await library.prepareImport(from: url)
                if visible { pending = PendingExtension(candidate: candidate, spaceName: name, spaceID: spaceID, dataStoreID: id) }
                else { library.cancel(candidate) }
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func confirmation(for request: PendingExtension) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install \(request.candidate.name)?").font(.title3.weight(.semibold))
            Text("Version \(request.candidate.version) · Enable in \(request.spaceName)")
                .foregroundStyle(Theme.muted)
            let sharing = store.spaces.filter { $0.dataStoreID == request.dataStoreID && $0.id != request.spaceID }
            if !sharing.isEmpty {
                Text("Also enabled in \(sharing.map(\.name).joined(separator: ", ")), because these spaces share sign-ins and extension state.")
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.muted)
            }
            Text("This extension may read or change data on the websites listed below and send information to third-party services over the network. Firn cannot inspect or limit what it sends after access is granted.")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    disclosure("Requested capabilities", values: request.candidate.permissions.map { describePermission($0) })
                    disclosure("Website access", values: request.candidate.hostPatterns.map {
                        $0 == "<all_urls>" || $0 == "*://*/*" ? "All websites (HTTP and HTTPS)" : $0
                    })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            if request.candidate.permissions.contains("nativeMessaging") {
                Text("Connections to desktop apps are unavailable. For 1Password, sign in through the extension separately.")
                    .font(Theme.hintFont).foregroundStyle(Theme.muted)
            }
            if let pendingFailure {
                Text(pendingFailure).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    library.cancel(request.candidate)
                    pending = nil
                    pendingFailure = nil
                }
                Button("Install") {
                    do {
                        guard store.spaces.contains(where: { $0.id == request.spaceID && $0.dataStoreID == request.dataStoreID }) else {
                            pendingFailure = "The selected space or its sign-in sharing changed. Cancel and choose a space again."
                            return
                        }
                        _ = try library.install(request.candidate, in: request.dataStoreID)
                        pending = nil
                        pendingFailure = nil
                    } catch { pendingFailure = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func disclosure(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if values.isEmpty {
                Text("None requested").foregroundStyle(Theme.muted)
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in Text("• \(value)").textSelection(.enabled) }
            }
        }
    }

    private func describePermission(_ permission: String) -> String {
        switch permission {
        case "tabs": "See tabs in these spaces"
        case "activeTab": "Access the current tab when you use the extension"
        case "storage": "Store extension data on this Mac"
        case "unlimitedStorage": "Store larger amounts of extension data on this Mac"
        case "clipboardWrite": "Copy content to the clipboard"
        case "clipboardRead": "Read the clipboard"
        case "scripting": "Run scripts on websites you allow"
        case "webNavigation": "Observe navigation in these tabs"
        case "webRequest": "Observe website network requests"
        case "webRequestBlocking": "Block or change website network requests"
        case "declarativeNetRequest", "declarativeNetRequestWithHostAccess": "Apply website network filtering rules"
        case "contextMenus": "Add items to page menus"
        case "alarms": "Schedule extension activity"
        case "cookies": "Read and change cookies for allowed websites"
        case "downloads": "Manage downloads"
        case "nativeMessaging": "Connect to desktop apps (unavailable in Firn)"
        case "notifications": "Show system notifications (unavailable in Firn)"
        default: permission
        }
    }
}
