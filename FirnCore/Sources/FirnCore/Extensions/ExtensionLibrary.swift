#if os(macOS)
import CryptoKit
import Foundation
import Observation
import WebKit

@available(macOS 15.4, *)
public struct InstalledWebExtension: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let version: String
    public let permissions: [String]
    public let hostPatterns: [String]
    public var enabledDataStoreIDs: Set<UUID>
}

@available(macOS 15.4, *)
public struct WebExtensionInstallCandidate: Identifiable {
    public let id: UUID
    public let name: String
    public let version: String
    public let permissions: [String]
    public let hostPatterns: [String]
    let stagedURL: URL
    let source: String
    let archiveDigest: Data
}

@available(macOS 15.4, *)
public enum WebExtensionLibraryError: LocalizedError {
    case invalidArchive, invalidExtension, invalidSource, tooLarge, alreadyInstalled, unavailable, persistence
    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "The selected file is not a supported extension archive."
        case .invalidExtension: "The archive does not contain a valid browser extension."
        case .invalidSource: "The extension download could not be verified."
        case .tooLarge: "The extension download is too large."
        case .alreadyInstalled: "This extension is already installed."
        case .unavailable: "The extension is no longer available."
        case .persistence: "The extension could not be saved."
        }
    }
}

@MainActor @Observable @available(macOS 15.4, *)
public final class WebExtensionLibrary {
    public static let shared = WebExtensionLibrary(rootURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Firn/Extensions"))
    public private(set) var extensions: [InstalledWebExtension] = []
    public private(set) var pendingRemovals: [UUID: Set<UUID>] = [:]
    public private(set) var errorMessage: String?
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private var sources: [UUID: String] = [:]
    @ObservationIgnored private var candidates: [UUID: URL] = [:]
    private var packagesURL: URL { rootURL.appending(path: "Packages", directoryHint: .isDirectory) }
    private var stagingURL: URL { rootURL.appending(path: "Staging", directoryHint: .isDirectory) }
    private var indexURL: URL { rootURL.appending(path: "extensions.json") }

    private struct Index: Codable {
        var records: [InstalledWebExtension]
        var sources: [UUID: String]
        var pendingRemovals: [UUID: Set<UUID>]?
    }

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        let data: Data
        do { data = try Data(contentsOf: indexURL) }
        catch CocoaError.fileReadNoSuchFile { return }
        catch {
            errorMessage = "Installed extensions could not be read. Extension changes are disabled until the library is repaired."
            return
        }
        do {
            let index = try JSONDecoder().decode(Index.self, from: data)
            guard Set(index.records.map(\.id)).count == index.records.count,
                  Set(index.records.map(\.id)) == Set(index.sources.keys) else {
                throw WebExtensionLibraryError.persistence
            }
            // Complete an interrupted uninstall by restoring its owned package when
            // the old index was still committed.
            for record in index.records {
                let archive = archiveURL(for: record.id)
                let retired = stagingURL.appending(path: record.id.uuidString + ".removed")
                if !FileManager.default.fileExists(atPath: archive.path), FileManager.default.fileExists(atPath: retired.path) {
                    try FileManager.default.moveItem(at: retired, to: archive)
                }
                let values = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw WebExtensionLibraryError.persistence }
            }
            extensions = index.records
            sources = index.sources
            pendingRemovals = index.pendingRemovals ?? [:]
        } catch { errorMessage = "Installed extensions could not be read. Extension changes are disabled until the library is repaired." }
    }

    public func archiveURL(for id: UUID) -> URL { packagesURL.appending(path: id.uuidString + ".zip") }

    public func prepareImport(from url: URL) async throws -> WebExtensionInstallCandidate {
        try ready()
        guard ["zip", "xpi"].contains(url.pathExtension.lowercased()) else { throw WebExtensionLibraryError.invalidArchive }
        try makeDirectories()
        let id = UUID()
        let staged = stagingURL.appending(path: id.uuidString + ".zip")
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try ExtensionArchive.validate(url)
            try FileManager.default.copyItem(at: url, to: staged)
            try ExtensionArchive.validate(staged)
            return try await parse(staged, id: id, source: "import")
        } catch { try? FileManager.default.removeItem(at: staged); throw error }
    }

    public func prepareOnePassword() async throws -> WebExtensionInstallCandidate {
        try ready()
        let metadataURL = URL(string: "https://addons.mozilla.org/api/v5/addons/addon/1password-x-password-manager/")!
        let metadata: Data
        do { metadata = try await download(metadataURL, allowedHosts: ["addons.mozilla.org"], limit: 1_000_000) }
        catch WebExtensionLibraryError.tooLarge { throw WebExtensionLibraryError.tooLarge }
        catch { throw WebExtensionLibraryError.invalidSource }
        struct Addon: Decodable {
            let id: Int; let guid: String; let slug: String; let authors: [Author]
            struct Author: Decodable { let id: Int; let name: String }
            let current_version: Version
            struct Version: Decodable { let file: File; struct File: Decodable { let url: URL; let hash: String; let size: Int? } }
        }
        guard let addon = try? JSONDecoder().decode(Addon.self, from: metadata),
              addon.id == 950528, addon.guid.lowercased() == "{d634138d-c276-4fc8-924b-40a0ea21d284}",
              addon.slug == "1password-x-password-manager",
              addon.authors.contains(where: { $0.id == 19257918 && $0.name == "1Password Devs" }),
              let expectedHash = addon.current_version.file.hash.split(separator: ":").last,
              addon.current_version.file.hash.lowercased().hasPrefix("sha256:"), expectedHash.count == 64,
              addon.current_version.file.size.map({ $0 > 0 && $0 <= ExtensionArchive.maximumBytes }) ?? true else { throw WebExtensionLibraryError.invalidSource }
        let package: Data
        do { package = try await download(addon.current_version.file.url, allowedHosts: ["addons.mozilla.org", "prod.outgoing.prod.webservices.mozgcp.net", "extensions.cdn.mozilla.net"], limit: ExtensionArchive.maximumBytes) }
        catch WebExtensionLibraryError.tooLarge { throw WebExtensionLibraryError.tooLarge }
        catch { throw WebExtensionLibraryError.invalidSource }
        guard SHA256.hash(data: package).map({ String(format: "%02x", $0) }).joined() == expectedHash.lowercased() else { throw WebExtensionLibraryError.invalidSource }
        try makeDirectories()
        let id = UUID(), staged = stagingURL.appending(path: id.uuidString + ".zip")
        do {
            try package.write(to: staged, options: .atomic)
            try ExtensionArchive.validate(staged)
            return try await parse(staged, id: id, source: "amo:950528")
        } catch { try? FileManager.default.removeItem(at: staged); throw error }
    }

    private func parse(_ url: URL, id: UUID, source: String) async throws -> WebExtensionInstallCandidate {
        let digest = Data(SHA256.hash(data: try Data(contentsOf: url)))
        let webExtension: WKWebExtension
        do { webExtension = try await WKWebExtension(resourceBaseURL: url) }
        catch { throw WebExtensionLibraryError.invalidExtension }
        guard webExtension.errors.isEmpty,
              let name = webExtension.displayName, !name.isEmpty,
              let version = webExtension.version, !version.isEmpty,
              Data(SHA256.hash(data: try Data(contentsOf: url))) == digest else { throw WebExtensionLibraryError.invalidExtension }
        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        let hosts = webExtension.requestedPermissionMatchPatterns.map(\.string).sorted()
        candidates[id] = url
        return WebExtensionInstallCandidate(id: id, name: name, version: version, permissions: permissions, hostPatterns: hosts, stagedURL: url, source: source, archiveDigest: digest)
    }

    public func install(_ candidate: WebExtensionInstallCandidate, in dataStoreID: UUID) throws -> InstalledWebExtension {
        try ready()
        guard candidates[candidate.id] == candidate.stagedURL,
              candidate.stagedURL == stagingURL.appending(path: candidate.id.uuidString + ".zip"),
              FileManager.default.fileExists(atPath: candidate.stagedURL.path) else { throw WebExtensionLibraryError.unavailable }
        guard !sources.values.contains(candidate.source) || candidate.source == "import" else { throw WebExtensionLibraryError.alreadyInstalled }
        guard !extensions.contains(where: { $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame }) else { throw WebExtensionLibraryError.alreadyInstalled }
        try ExtensionArchive.validate(candidate.stagedURL)
        let approvedBytes = try Data(contentsOf: candidate.stagedURL)
        guard Data(SHA256.hash(data: approvedBytes)) == candidate.archiveDigest else { throw WebExtensionLibraryError.invalidSource }
        try makeDirectories()
        let destination = archiveURL(for: candidate.id)
        let record = InstalledWebExtension(id: candidate.id, name: candidate.name, version: candidate.version, permissions: candidate.permissions, hostPatterns: candidate.hostPatterns, enabledDataStoreIDs: [dataStoreID])
        do {
            try approvedBytes.write(to: destination, options: .atomic)
            try persist(extensions + [record], sources.merging([candidate.id: candidate.source]) { _, new in new })
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw WebExtensionLibraryError.persistence
        }
        try? FileManager.default.removeItem(at: candidate.stagedURL)
        extensions.append(record); sources[candidate.id] = candidate.source; candidates.removeValue(forKey: candidate.id); onChange?()
        return record
    }

    public func cancel(_ candidate: WebExtensionInstallCandidate) {
        guard candidates.removeValue(forKey: candidate.id) == candidate.stagedURL else { return }
        try? FileManager.default.removeItem(at: candidate.stagedURL)
    }

    public func setEnabled(_ enabled: Bool, id: UUID, in dataStoreID: UUID) throws {
        try ready()
        guard let index = extensions.firstIndex(where: { $0.id == id }) else { throw WebExtensionLibraryError.unavailable }
        var updated = extensions
        if enabled { updated[index].enabledDataStoreIDs.insert(dataStoreID) }
        else { updated[index].enabledDataStoreIDs.remove(dataStoreID) }
        guard updated != extensions else { return }
        try persist(updated, sources); extensions = updated; onChange?()
    }

    public func remove(id: UUID) throws {
        try ready()
        guard let removed = extensions.first(where: { $0.id == id }) else { throw WebExtensionLibraryError.unavailable }
        let archive = archiveURL(for: id), retired = stagingURL.appending(path: id.uuidString + ".removed")
        try makeDirectories()
        do {
            try FileManager.default.moveItem(at: archive, to: retired)
            var updatedSources = sources; updatedSources.removeValue(forKey: id)
            var pending = pendingRemovals
            pending[id, default: []].formUnion(removed.enabledDataStoreIDs)
            try persist(extensions.filter { $0.id != id }, updatedSources, pendingRemovals: pending)
            pendingRemovals = pending
            extensions.removeAll { $0.id == id }; sources = updatedSources; onChange?()
            try? FileManager.default.removeItem(at: retired)
        } catch {
            try? FileManager.default.moveItem(at: retired, to: archive)
            throw WebExtensionLibraryError.persistence
        }
    }

    public func removeData(for dataStoreID: UUID) throws {
        try ready()
        var updated = extensions
        for index in updated.indices { updated[index].enabledDataStoreIDs.remove(dataStoreID) }
        guard updated != extensions else { return }
        try persist(updated, sources); extensions = updated; onChange?()
    }

    /// Keep uninstall work durable until WebKit confirms its data was erased.
    func completeRemoval(id: UUID) throws {
        try ready()
        guard pendingRemovals[id] != nil else { return }
        var pending = pendingRemovals
        pending[id] = nil
        try persist(extensions, sources, pendingRemovals: pending)
        pendingRemovals = pending
    }

    private func ready() throws { if errorMessage != nil { throw WebExtensionLibraryError.persistence } }
    private func makeDirectories() throws {
        try FileManager.default.createDirectory(at: packagesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
    }
    private func persist(_ records: [InstalledWebExtension], _ sources: [UUID: String], pendingRemovals: [UUID: Set<UUID>]? = nil) throws {
        do { try makeDirectories(); try JSONEncoder().encode(Index(records: records, sources: sources, pendingRemovals: pendingRemovals ?? self.pendingRemovals)).write(to: indexURL, options: .atomic) }
        catch { throw WebExtensionLibraryError.persistence }
    }

    private nonisolated func download(_ url: URL, allowedHosts: Set<String>, limit: Int) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), allowedHosts.contains(host) else { throw WebExtensionLibraryError.invalidSource }
        let policy = ExtensionDownloadPolicy(hosts: allowedHosts)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: policy, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, finalURL.scheme == "https", let finalHost = finalURL.host?.lowercased(), allowedHosts.contains(finalHost),
              http.expectedContentLength < 0 || http.expectedContentLength <= limit else { throw WebExtensionLibraryError.invalidSource }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw WebExtensionLibraryError.tooLarge }
            data.append(byte)
        }
        return data
    }
}

@available(macOS 15.4, *)
private final class ExtensionDownloadPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let hosts: Set<String>
    init(hosts: Set<String>) { self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), hosts.contains(host) else { completionHandler(nil); return }
        completionHandler(request)
    }
}
#endif
