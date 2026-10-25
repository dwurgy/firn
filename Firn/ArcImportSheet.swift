import AppKit
import FirnCore
import SwiftUI

/// One import from Arc, from the file the person picked to the spaces it added.
@Observable @MainActor
final class ArcImport: Identifiable {
    let id = UUID()
    var stage: Stage

    init(stage: Stage) { self.stage = stage }

    enum Stage: Sendable {
        case problem(String)
        case ready(ArcImportPlan)
        case done([Space])
    }

    /// Reads and checks the file, off the main thread. Nothing is added.
    nonisolated static func read(_ url: URL) async -> Stage {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Mapped, so a huge file is turned away without being read in.
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                return .problem("Firn couldn't open that file.")
            }
            do {
                return .ready(try ArcImportPlan(data))
            } catch let error as ArcImportError {
                return .problem(message(for: error))
            } catch {
                return .problem("Firn couldn't open that file.")
            }
        }.value
    }

    private nonisolated static func message(for error: ArcImportError) -> String {
        switch error {
        case .tooLarge: "That file is too big to be Arc's sidebar."
        case .damaged: "That file looks damaged, so Firn didn't use any of it."
        case .notRecognized: "Firn doesn't recognize this file. In Arc's folder, choose StorableSidebar.json."
        }
    }

    /// Arc's folder, where the Open panel starts. The sandbox's home is
    /// Firn's container, so this asks for the real one.
    static var arcFolder: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)
    }
}

/// The Open panel and the sheet, for File › Import from Arc… and the button
/// in Settings.
struct ArcImportFlow: ViewModifier {
    @Binding var choosing: Bool
    let window: WindowModel
    @State private var session: ArcImport?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                Task { session = ArcImport(stage: await ArcImport.read(url)) }
            }
            .fileDialogDefaultDirectory(ArcImport.arcFolder)
            .fileDialogMessage("Choose StorableSidebar.json in Arc's folder.")
            .fileDialogConfirmationLabel("Choose")
            .sheet(item: $session) { session in
                ArcImportSheet(session: session, window: window)
            }
    }
}

/// What will come over from Arc, then what did.
struct ArcImportSheet: View {
    let session: ArcImport
    let window: WindowModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// More than this, and the rest are "and 4 more spaces", so the sheet stays small.
    private static let listedSpaces = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.stage {
            case .problem(let text):
                title("Can't import this file")
                line(text)
                buttons { primary("OK") { dismiss() } }
            case .ready(let plan):
                ready(plan)
            case .done(let spaces):
                done(spaces)
            }
        }
        .padding(24)
        .frame(width: 400, alignment: .leading)
    }

    // MARK: - Stages

    @ViewBuilder private func ready(_ plan: ArcImportPlan) -> some View {
        if plan.spaces.isEmpty {
            title("Nothing in this file can come over")
            line("Arc's sidebar here has no spaces.")
            buttons { primary("OK") { dismiss() } }
        } else {
            title(plan.spaces.count == 1
                  ? "Import \(plan.spaces[0].name) from Arc?"
                  : "Import \(plan.spaces.count) spaces from Arc?")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.spaces.prefix(Self.listedSpaces).enumerated()), id: \.offset) { _, space in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(space.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        line(Self.contents(of: space))
                    }
                    .accessibilityElement(children: .combine)
                }
                let more = plan.spaces.count - Self.listedSpaces
                if more > 0 { line(more == 1 ? "and 1 more space" : "and \(more) more spaces") }
            }
            .padding(.vertical, 4)
            line(Self.signInsLine(plan))
            line(Self.leftBehindLine(plan))
            buttons {
                secondary("Cancel") { dismiss() }
                primary("Import") { add(plan) }
            }
        }
    }

    @ViewBuilder private func done(_ spaces: [Space]) -> some View {
        title(Self.doneTitle(spaces))
        line(Self.doneLine(spaces))
        buttons {
            secondary("Done") { dismiss() }
            if let first = spaces.first {
                primary("Show \(first.name)") {
                    dismiss()
                    window.showSpace { window.store.selectSpace(first) }
                }
            }
        }
    }

    // MARK: - Parts

    private func title(_ text: String) -> some View {
        Text(text)
            .font(Theme.panelTitleFont)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
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

    // MARK: - Doing

    /// The spaces glide into the row at the bottom of the sidebar; the one
    /// on screen stays.
    private func add(_ plan: ArcImportPlan) {
        let store = window.store
        let added = withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            store.importFromArc(plan) { existing in
                let style = WindowModel.freeStyle(among: existing)
                return (style.icon.rawValue, style.color)
            }
        }
        session.stage = .done(added)
        // The sheet changes under VoiceOver's focus, so say how it went.
        AccessibilityNotification.Announcement("\(Self.doneTitle(added)) \(Self.doneLine(added))").post()
    }

    // MARK: - Words

    /// "4 Basecamp sites and 2 groups with 9 tabs"
    static func contents(of space: ArcImportPlan.Space) -> String {
        let tabs = space.groups.reduce(0) { $0 + $1.sites.count }
        let parts = [
            count(space.basecamp.count, one: "Basecamp site", many: "Basecamp sites"),
            space.groups.isEmpty ? nil
                : "\(count(space.groups.count, one: "group", many: "groups")!) with \(count(tabs, one: "tab", many: "tabs")!)",
        ].compactMap { $0 }
        return parts.isEmpty ? "Empty: no favorites or pinned tabs" : parts.formatted(.list(type: .and))
    }

    static func signInsLine(_ plan: ArcImportPlan) -> String {
        let signedOut = "starts signed out of everything."
        if plan.spaces.count == 1 { return "It \(signedOut)" }
        if plan.profileCount == 1 { return "They share sign-ins with each other, as in Arc. Each \(signedOut)" }
        let sharing = plan.sharingSignIns
        if sharing.isEmpty { return "Each keeps its own sign-ins, as in Arc, and \(signedOut)" }
        let groups = sharing.map { "\($0.formatted(.list(type: .and))) share sign-ins" }
        return "\(groups.formatted(.list(type: .and))), as in Arc; the others keep their own. Each \(signedOut)"
    }

    static func leftBehindLine(_ plan: ArcImportPlan) -> String {
        var text = "Unpinned tabs, sign-ins, and history stay in Arc."
        if let skipped = count(plan.skipped, one: "tab that isn't a website stays", many: "tabs that aren't websites stay") {
            text += " \(skipped) behind too."
        }
        return text + " To bring passwords, export them from Arc and import them in Settings › Passwords."
    }

    static func doneTitle(_ spaces: [Space]) -> String {
        "Added \(spaces.map(\.name).formatted(.list(type: .and)))."
    }

    static func doneLine(_ spaces: [Space]) -> String {
        (spaces.count == 1 ? "It's" : "They're")
            + " at the bottom of the sidebar, with your other spaces. Each tab loads when you first click it."
    }

    private static func count(_ count: Int, one: String, many: String) -> String? {
        switch count {
        case 0: nil
        case 1: "1 \(one)"
        default: "\(count.formatted()) \(many)"
        }
    }
}
