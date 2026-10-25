import AppKit
import FirnCore
import SwiftUI

/// One import, from the file the person picked to the Trash offer. It holds
/// the file's passwords in memory only while the sheet is open.
@Observable @MainActor
final class PasswordImport: Identifiable {
    let id = UUID()
    let file: URL
    /// The space on screen when the file was picked; the sheet names it,
    /// so the logins go there even if the space changes meanwhile.
    let spaceName: String
    let sharedWith: [String]
    let dataStoreID: UUID
    var stage: Stage

    init(file: URL, space: Space, sharedWith: [String], stage: Stage) {
        self.file = file
        spaceName = space.name
        self.sharedWith = sharedWith
        dataStoreID = space.dataStoreID
        self.stage = stage
    }

    enum Stage: Sendable {
        case problem(String)
        case ready(PasswordImportFile)
        case importing
        case done(PasswordImportResult)
    }

    /// Reads and checks the file, off the main thread. Nothing is saved.
    nonisolated static func read(_ url: URL) async -> Stage {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Mapped, so a huge file is turned away without being read in.
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                return .problem("Firn couldn't open that file.")
            }
            do {
                return .ready(try PasswordImportFile(data))
            } catch let error as PasswordImportError {
                return .problem(message(for: error))
            } catch {
                return .problem("Firn couldn't open that file.")
            }
        }.value
    }

    private nonisolated static func message(for error: PasswordImportError) -> String {
        switch error {
        case .tooLarge: "That file is too big to be a password export."
        case .tooManyRows: "That file has more logins than Firn can import at once."
        case .notText: "Firn can't read that file. A password export is a CSV text file."
        case .damaged: "That file looks damaged, so Firn didn't use any of it. Try exporting it again."
        case .notRecognized:
            "Firn doesn't recognize this file. Export your passwords as a CSV file from Chrome, Safari, Firefox, 1Password, or Bitwarden, then try again."
        }
    }
}

/// The sheet for an import: what will come over, then what did, then the
/// offer to move the plain-text file to the Trash.
struct PasswordImportSheet: View {
    let session: PasswordImport
    let passwords: PasswordStore
    let finished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cantTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.stage {
            case .problem(let text):
                title("Can't import this file")
                line(text)
                buttons { primary("OK") { dismiss() } }
            case .ready(let file):
                ready(file)
            case .importing:
                title("Importing…")
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .done(let result):
                done(result)
            }
        }
        .padding(24)
        .frame(width: 400, alignment: .leading)
        .interactiveDismissDisabled(isImporting)
    }

    // MARK: - Stages

    @ViewBuilder private func ready(_ file: PasswordImportFile) -> some View {
        let count = file.logins.count
        if count == 0 {
            title("Nothing in this file can come over")
        } else {
            title("Import \(Self.passwords(count)) into \(session.spaceName)?")
        }
        if let skipped = Self.skippedLine(file) { line(skipped) }
        if count > 0 {
            line(sharingLine + "A password already saved in Firn stays as it is.")
        }
        buttons {
            if count == 0 {
                primary("OK") { dismiss() }
            } else {
                secondary("Cancel") { dismiss() }
                primary("Import") { startImport(file.logins) }
            }
        }
    }

    @ViewBuilder private func done(_ result: PasswordImportResult) -> some View {
        title(result.imported == 0 ? "No new passwords" : "Imported \(Self.passwords(result.imported)).")
        ForEach(Self.resultLines(result), id: \.self) { line($0) }
        Divider().padding(.vertical, 4)
        Text("“\(session.file.lastPathComponent)” has every password in plain text.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
        line(cantTrash
             ? "Firn couldn't move it to the Trash. You can delete it in Finder."
             : "Anyone who opens it can read them. In the Trash, it stays readable until the Trash is emptied.")
        buttons {
            secondary("Keep") { dismiss() }
            primary("Move to Trash", action: moveToTrash)
                .disabled(cantTrash)
        }
    }

    // MARK: - Parts

    private func title(_ text: String) -> some View {
        Text(text)
            .font(Theme.panelTitleFont)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Spacer()
            content()
        }
        .padding(.top, 8)
    }

    private func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(SheetButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(SheetButtonStyle(prominent: false))
            .keyboardShortcut(.cancelAction)
    }

    private var sharingLine: String {
        let others = session.sharedWith
        guard !others.isEmpty else { return "" }
        let names = others.formatted(.list(type: .and))
        return others.count == 1
            ? "\(names) shares sign-ins with \(session.spaceName), so it gets them too. "
            : "\(names) share sign-ins with \(session.spaceName), so they get them too. "
    }

    private var isImporting: Bool {
        if case .importing = session.stage { true } else { false }
    }

    // MARK: - Doing

    /// Keychain writes take a moment each, so hundreds run off the main thread.
    private func startImport(_ logins: [ImportedLogin]) {
        let passwords = passwords
        let dataStoreID = session.dataStoreID
        session.stage = .importing
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                try? passwords.importLogins(logins, into: dataStoreID)
            }.value
            if let result {
                session.stage = .done(result)
            } else {
                session.stage = .problem("Firn can't read the Keychain right now, so nothing was imported. Try again in a moment.")
            }
            finished()
        }
    }

    private func moveToTrash() {
        let url = session.file
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            dismiss()
        } catch {
            cantTrash = true
        }
    }

    // MARK: - Words

    static func passwords(_ count: Int) -> String {
        count == 1 ? "1 password" : "\(count.formatted()) passwords"
    }

    /// "6 can't come over: 4 aren't https and 2 have no website."
    static func skippedLine(_ file: PasswordImportFile) -> String? {
        let reasons = [
            phrase(file.notHttps, one: "isn't https", many: "aren't https"),
            phrase(file.noWebsite, one: "has no website", many: "have no website"),
            phrase(file.notALogin, one: "has no usable password", many: "have no usable password"),
            phrase(file.repeated, one: "is listed twice", many: "are listed twice"),
        ].compactMap { $0 }
        let total = file.notHttps + file.noWebsite + file.notALogin + file.repeated
        guard total > 0 else { return nil }
        return "\(total.formatted()) can't come over: \(reasons.formatted(.list(type: .and)))."
    }

    static func resultLines(_ result: PasswordImportResult) -> [String] {
        [
            phrase(result.alreadySaved, one: "was already saved.", many: "were already saved."),
            phrase(result.keptFirns, one: "was already saved with another password; Firn kept its own.",
                   many: "were already saved with other passwords; Firn kept its own."),
            phrase(result.notSaved, one: "couldn't be saved. Import the file again in a moment to try it.",
                   many: "couldn't be saved. Import the file again in a moment to try them."),
        ].compactMap { $0 }
    }

    private static func phrase(_ count: Int, one: String, many: String) -> String? {
        switch count {
        case 0: nil
        case 1: "1 \(one)"
        default: "\(count.formatted()) \(many)"
        }
    }
}
