import AppKit
import FirnCore
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Passwords: the logins saved in the space on screen (and the
/// spaces sharing its sign-ins), and the sites Firn never saves for.
///
/// The list holds only sites and usernames. Showing, copying, or editing a
/// password asks for the Mac's password or Touch ID first; after that the
/// pane stays unlocked until it's left, Firn goes to the background, or the
/// space changes. A password is read from the Keychain only when it's asked for.
struct PasswordsSettings: View {
    let store: BrowserStore

    private struct Row: Identifiable, Hashable {
        let site: PasswordSite
        let username: String
        var id: String { "\(site.name)\n\(username)" }
    }

    @State private var rows: [Row] = []
    @State private var icons: [String: Data] = [:]
    @State private var cantRead = false
    @State private var cantDelete = false
    @State private var search = ""
    @State private var unlocked = false
    /// Passwords asked to be shown, until the pane locks.
    @State private var shown: [Row.ID: String] = [:]
    @State private var editing: EditedLogin?
    @State private var deleting: Row?
    @State private var choosingFile = false
    @State private var importing: PasswordImport?

    private var space: Space { store.activeSpace }
    private var passwords: PasswordStore { .keychain }

    var body: some View {
        Form {
            Section {
                header
            }
            Section {
                list
            } footer: {
                footnote("Passwords stay on this Mac, in its Keychain. Only spaces that share sign-ins see them.")
            }
            Section {
                importRow
            }
            let never = store.neverSavePasswordSites(in: space.dataStoreID)
            if !never.isEmpty {
                Section {
                    ForEach(never, id: \.self) { site in
                        HStack {
                            Text(site).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Remove") { store.allowSavingPasswords(on: site, in: space.dataStoreID) }
                                .accessibilityLabel("Remove \(site)")
                        }
                    }
                } header: {
                    Text("Never saved for")
                } footer: {
                    footnote("Firn doesn't offer to save passwords on these sites. Remove one to be asked again.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onDisappear(perform: lock)
        .onChange(of: space.dataStoreID) { lock(); reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in lock() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in lock() }
        // A password saved in the browser while Settings is open shows up on coming back.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .sheet(item: $editing) { login in
            PasswordEditSheet(login: login) { username, password in
                try passwords.change(
                    username: login.username, on: login.site, in: login.dataStoreID,
                    toUsername: username, password: password
                )
                shown = [:]
                reload()
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText]) { result in
            guard case .success(let url) = result else { return }
            let space = space
            let others = store.spacesSharingData(with: space).map(\.name)
            Task {
                let stage = await PasswordImport.read(url)
                importing = PasswordImport(file: url, space: space, sharedWith: others, stage: stage)
            }
        }
        .fileDialogMessage("Choose a passwords file exported from another browser or password manager.")
        .fileDialogConfirmationLabel("Choose")
        .sheet(item: $importing) { session in
            PasswordImportSheet(session: session, passwords: passwords) {
                reload()
            }
        }
        .confirmationDialog(
            deleting.map { "Delete the password for \($0.username.isEmpty ? $0.site.name : "\($0.username) on \($0.site.name)")?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { row in
            Button("Delete Password", role: .destructive) { delete(row) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(deleteMessage)
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Passwords in \(space.name)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(sharingLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            if unlocked {
                Button("Lock", action: lock)
                    .help("Hide passwords until you unlock again")
            }
            TextField("Search", text: $search, prompt: Text("Search"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 170)
                .accessibilityLabel("Search passwords")
        }
    }

    private var importRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import passwords")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Text("Export your passwords from Chrome, Arc, Safari, Firefox, 1Password, or Bitwarden, then choose the file here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button("Import…") { choosingFile = true }
                .accessibilityLabel("Import passwords into \(space.name)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var list: some View {
        if cantDelete && !cantRead {
            quietLine("Firn couldn't delete that password. Try again in a moment.")
        }
        if cantRead {
            quietLine("Firn can't read the Keychain right now.")
        } else if rows.isEmpty {
            quietLine("No saved passwords in this space yet. After you sign in to a site, Firn offers to save the password.")
        } else if filtered.isEmpty {
            quietLine("Nothing matches “\(search)”.")
        } else {
            ForEach(filtered) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 10) {
            SiteMark(site: row.site.host, icon: icons[row.site.host])
            VStack(alignment: .leading, spacing: 2) {
                Text(row.site.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Text(row.username.isEmpty ? "No username" : row.username)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 12)
            Group {
                if let password = shown[row.id] {
                    // Not selectable: Copy Password marks the copy concealed, a selection wouldn't.
                    Text(password)
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Password: \(password)")
                } else {
                    Text("••••••••")
                        .foregroundStyle(Theme.faint)
                        .accessibilityLabel("Password hidden")
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 160, alignment: .trailing)
            Menu {
                actions(for: row)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Theme.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(row.site.name)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu { actions(for: row) }
    }

    @ViewBuilder private func actions(for row: Row) -> some View {
        if shown[row.id] == nil {
            Button("Show Password") { withUnlock { show(row) } }
        } else {
            Button("Hide Password") { shown[row.id] = nil }
        }
        Button("Copy Password") { withUnlock { copyPassword(row) } }
        if !row.username.isEmpty {
            Button("Copy Username") { copy(row.username, concealed: false) }
        }
        Divider()
        Button("Edit…") { withUnlock { edit(row) } }
        Button("Delete…") { deleting = row }
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sharingLine: String {
        let others = store.spacesSharingData(with: space).map(\.name)
        return others.isEmpty
            ? "Only this space sees them."
            : "Shared with \(others.formatted(.list(type: .and)))."
    }

    private var deleteMessage: String {
        let others = store.spacesSharingData(with: space).map(\.name)
        guard !others.isEmpty else { return "Firn won't fill it in any more. This can't be undone." }
        return "It's deleted from \(([space.name] + others).formatted(.list(type: .and))). This can't be undone."
    }

    private var filtered: [Row] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.site.name.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Doing

    private func reload() {
        let dataStoreID = space.dataStoreID
        do {
            // Only sites and usernames are kept; the passwords read along
            // with them are dropped here.
            rows = try passwords.allLogins(in: dataStoreID).map { Row(site: $0.site, username: $0.username) }
            cantRead = false
        } catch {
            rows = []
            cantRead = true
        }
        // Site icons from this space's own tabs, where there are any.
        let spaceIDs = Set(store.spaces.filter { $0.dataStoreID == dataStoreID }.map(\.id))
        var found: [String: Data] = [:]
        for tab in store.tabs where spaceIDs.contains(tab.spaceID) {
            guard let host = tab.url?.host(percentEncoded: false)?.lowercased(), found[host] == nil,
                  let icon = tab.icon else { continue }
            found[host] = icon
        }
        icons = found
    }

    private func lock() {
        unlocked = false
        shown = [:]
        cantDelete = false
    }

    /// Runs `action` once the person has proved it's them, asking only if
    /// the pane is locked.
    private func withUnlock(_ action: @escaping @MainActor () -> Void) {
        if unlocked { action(); return }
        Task {
            guard await Self.authenticate() else { return }
            unlocked = true
            action()
        }
    }

    /// The Mac's own check: Touch ID, or the login password.
    private nonisolated static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: "use your saved passwords"
        )) ?? false
    }

    private func password(for row: Row) -> String? {
        try? passwords.password(for: row.username, on: row.site, in: space.dataStoreID)
    }

    private func show(_ row: Row) {
        shown[row.id] = password(for: row)
    }

    private func copyPassword(_ row: Row) {
        guard let password = password(for: row) else { return }
        copy(password, concealed: true)
    }

    /// A password is marked concealed, so clipboard-history apps that follow
    /// the nspasteboard.org convention don't keep it.
    private func copy(_ text: String, concealed: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if concealed {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
    }

    private func edit(_ row: Row) {
        guard let password = password(for: row) else { reload(); return }
        editing = EditedLogin(dataStoreID: space.dataStoreID, site: row.site, username: row.username, password: password)
    }

    private func delete(_ row: Row) {
        do {
            try passwords.delete(username: row.username, on: row.site, in: space.dataStoreID)
            cantDelete = false
        } catch {
            cantDelete = true
        }
        shown[row.id] = nil
        reload()
    }
}

/// A login open in the Edit sheet, password and all, until it closes.
private struct EditedLogin: Identifiable {
    let id = UUID()
    let dataStoreID: UUID
    let site: PasswordSite
    let username: String
    let password: String
}

/// Changes a saved login's username and password.
private struct PasswordEditSheet: View {
    let login: EditedLogin
    let save: (String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            Text("Edit password")
                .font(Theme.panelTitleFont)
                .foregroundStyle(Theme.ink)
            Text(login.site.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Form {
                TextField("Username", text: $username)
                TextField("Password", text: $password)
                    .font(.system(size: 13, design: .monospaced))
            }
            .formStyle(.columns)
            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SheetButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: finish)
                    .buttonStyle(SheetButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            username = login.username
            password = login.password
        }
    }

    private func finish() {
        do {
            try save(username.trimmingCharacters(in: .whitespacesAndNewlines), password)
            dismiss()
        } catch PasswordError.usernameTaken {
            problem = "That username is already saved for this site."
        } catch PasswordError.notALogin {
            problem = "That password can't be saved."
        } catch {
            problem = "Firn couldn't save the change. Try again in a moment."
        }
    }
}
