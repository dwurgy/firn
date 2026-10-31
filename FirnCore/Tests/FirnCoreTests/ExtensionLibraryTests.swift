#if os(macOS)
import Foundation
import Testing
@testable import FirnCore

struct ExtensionLibraryTests {
    @available(macOS 15.4, *)
    private func archive(in root: URL, name: String) throws -> URL {
        let folder = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 2, "name": name, "description": "Synthetic security test extension", "version": "1.0", "permissions": ["storage"],
                                       "background": ["scripts": ["background.js"], "persistent": true]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
        try Data("void 0;".utf8).write(to: folder.appending(path: "background.js"))
        let output = root.appending(path: UUID().uuidString + ".zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", folder.path, output.path]
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        return output
    }

    @Test @MainActor func malformedArchiveIsRejectedWithoutInstalling() async throws {
        guard #available(macOS 15.4, *) else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appending(path: "bad.xpi")
        try Data("not a ZIP".utf8).write(to: archive)
        let library = WebExtensionLibrary(rootURL: root.appending(path: "library"))
        var rejected = false
        do { _ = try await library.prepareImport(from: archive) }
        catch WebExtensionLibraryError.invalidArchive { rejected = true }
        #expect(rejected)
        #expect(library.extensions.isEmpty)
    }

    @Test @MainActor func corruptIndexFailsClosed() throws {
        guard #available(macOS 15.4, *) else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: root.appending(path: "extensions.json"))
        let library = WebExtensionLibrary(rootURL: root)
        #expect(library.errorMessage != nil)
        var rejected = false
        do { try library.removeData(for: UUID()) }
        catch WebExtensionLibraryError.persistence { rejected = true }
        #expect(rejected)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "extensions.json").path))
    }

    @Test @MainActor func missingIndexedPackageDoesNotResetTheLibrary() throws {
        guard #available(macOS 15.4, *) else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = InstalledWebExtension(id: UUID(), name: "Missing", version: "1", permissions: [], hostPatterns: [], enabledDataStoreIDs: [UUID()])
        struct Index: Encodable { let records: [InstalledWebExtension]; let sources: [UUID: String] }
        let bytes = try JSONEncoder().encode(Index(records: [record], sources: [record.id: "import"]))
        let index = root.appending(path: "extensions.json")
        try bytes.write(to: index)
        let library = WebExtensionLibrary(rootURL: root)
        #expect(library.errorMessage != nil)
        #expect(throws: WebExtensionLibraryError.self) { try library.removeData(for: UUID()) }
        #expect(try Data(contentsOf: index) == bytes)
    }

    @Test @MainActor func approvalCannotInstallChangedArchiveBytes() async throws {
        guard #available(macOS 15.4, *) else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = WebExtensionLibrary(rootURL: root.appending(path: "library"))
        let candidate = try await library.prepareImport(from: archive(in: root, name: "Approved"))
        let replacement = try archive(in: root, name: "Different")
        try Data(contentsOf: replacement).write(to: candidate.stagedURL)
        #expect(throws: WebExtensionLibraryError.self) { try library.install(candidate, in: UUID()) }
        #expect(library.extensions.isEmpty)
        library.cancel(candidate)
    }

    @Test @MainActor func interruptedUninstallRetainsCleanupWorkAfterRestart() async throws {
        guard #available(macOS 15.4, *) else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let libraryRoot = root.appending(path: "library")
        let library = WebExtensionLibrary(rootURL: libraryRoot)
        let candidate = try await library.prepareImport(from: archive(in: root, name: "Uninstall fixture"))
        let installed = try library.install(candidate, in: UUID())
        try library.remove(id: installed.id)
        let restarted = WebExtensionLibrary(rootURL: libraryRoot)
        #expect(restarted.extensions.isEmpty)
        #expect(restarted.pendingRemovals[installed.id] == installed.enabledDataStoreIDs)
        try restarted.completeRemoval(id: installed.id)
        #expect(WebExtensionLibrary(rootURL: libraryRoot).pendingRemovals.isEmpty)
    }
}
#endif
