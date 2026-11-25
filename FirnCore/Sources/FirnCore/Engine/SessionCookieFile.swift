import CryptoKit
import Foundation
import os
import Security

/// One session cookie, as Firn keeps it: the kind a site marks "until the
/// browser closes", which WebKit never writes down (see `SessionCookies`).
/// Cookies come from sites, so everything here is bounded, and one that
/// can't be put back exactly as it was isn't kept at all.
struct SavedCookie: Codable, Equatable, Sendable {
    var name: String
    var value: String
    /// With a leading dot for a site and its subdomains, without for that
    /// host alone, as the site set it.
    var domain: String
    var path: String
    var isSecure: Bool
    var isHTTPOnly: Bool
    var sameSite: String?

    /// Browsers cap a cookie's name and value at 4096 bytes together.
    static let sizeLimit = 8192

    init?(_ cookie: HTTPCookie) {
        // A cookie kept apart by the site it's embedded in can't be put back
        // that way, and would turn into one that follows you between sites.
        guard cookie.isSessionOnly, cookie.properties?[.init("StoragePartition")] == nil else { return nil }
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        sameSite = cookie.sameSitePolicy?.rawValue
        guard isWithinLimits else { return nil }
    }

    private var isWithinLimits: Bool {
        !name.isEmpty && !domain.isEmpty && domain != "." && path.hasPrefix("/")
            && name.utf8.count + value.utf8.count + domain.utf8.count + path.utf8.count <= Self.sizeLimit
    }

    /// The cookie again, with all its protections, or nil: never one that a
    /// page's scripts could read, or that goes over http, when it couldn't before.
    var cookie: HTTPCookie? {
        guard isWithinLimits else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path, .discard: "TRUE",
        ]
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[.init("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite }
        guard let cookie = HTTPCookie(properties: properties), SavedCookie(cookie) == self else { return nil }
        return cookie
    }
}

/// Seals one data store's session cookies. AES-GCM, with the store's id
/// bound in as authenticated data, so one space's file can't be passed off
/// as another's.
struct SessionCookieSeal: Sendable {
    static let keySize = 32
    /// More than any real store; a page can't fill the disk.
    static let countLimit = 3000
    static let fileLimit = 8 * 1024 * 1024
    /// Not opened in this long, a space's session cookies are let go.
    static let keptFor: TimeInterval = 30 * 24 * 60 * 60

    private let key: SymmetricKey

    init?(keyData: Data) {
        guard keyData.count == Self.keySize else { return nil }
        key = SymmetricKey(data: keyData)
    }

    static func makeKeyData() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    private struct Contents: Codable {
        var savedAt: Date
        var cookies: [SavedCookie]
    }

    private static func bound(to dataStoreID: UUID) -> Data {
        Data("Firn session cookies 1 \(dataStoreID.uuidString)".utf8)
    }

    func seal(_ cookies: [SavedCookie], for dataStoreID: UUID, at now: Date) throws -> Data {
        let contents = Contents(savedAt: now, cookies: Array(cookies.prefix(Self.countLimit)))
        let box = try AES.GCM.seal(
            JSONEncoder().encode(contents), using: key, authenticating: Self.bound(to: dataStoreID))
        guard let sealed = box.combined, sealed.count <= Self.fileLimit else { throw CocoaError(.fileWriteUnknown) }
        return sealed
    }

    /// What a file holds, or nil: another key, another store's file, changed,
    /// damaged, or too old.
    func open(_ sealed: Data, for dataStoreID: UUID, at now: Date) -> [SavedCookie]? {
        guard sealed.count <= Self.fileLimit,
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key, authenticating: Self.bound(to: dataStoreID)),
              let contents = try? JSONDecoder().decode(Contents.self, from: data)
        else { return nil }
        let age = now.timeIntervalSince(contents.savedAt)
        // A little ahead is a clock put right; far ahead isn't to be trusted.
        guard age < Self.keptFor, age > -24 * 60 * 60 else { return nil }
        return Array(contents.cookies.prefix(Self.countLimit))
    }
}

/// The key session cookies are sealed with.
protocol SessionCookieKey: Sendable {
    /// The key, made first if there is none. Throws if it can't be had now.
    func key() throws -> Data
}

/// In the Keychain (the per-app, data protection one): on this Mac only,
/// never synced, and only while it's unlocked. An app signed without a
/// provisioning profile has no such Keychain, and then nothing is kept.
/// Blocks on the Keychain: keep it off the main thread.
struct KeychainSessionCookieKey: SessionCookieKey {
    private static var base: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false,
            kSecAttrService: "com.firnbrowser.firn.session-cookies",
            kSecAttrAccount: "key",
        ]
    }

    /// Only the Keychain's error number, never anything about the key.
    struct Failure: Error { let status: OSStatus }

    private func read() throws -> Data? {
        var search = Self.base
        search[kSecMatchLimit] = kSecMatchLimitOne
        search[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = result as? Data, data.count == SessionCookieSeal.keySize else {
            throw Failure(status: errSecDecode)
        }
        return data
    }

    func key() throws -> Data {
        if let key = try read() { return key }
        var item = Self.base
        item[kSecValueData] = SessionCookieSeal.makeKeyData()
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel] = "Firn session key"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure(status: status) }
        guard let key = try read() else { throw Failure(status: errSecItemNotFound) }
        return key
    }
}

/// The sealed files, one per data store. Every call runs on one queue, in
/// order, so a save never lands after its space's erasing.
final class SessionCookieFiles: Sendable {
    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "session-cookies")
    private let directory: URL
    private let source: any SessionCookieKey
    private let queue = DispatchQueue(label: "com.firnbrowser.firn.session-cookies", qos: .userInitiated)
    /// Only touched on `queue`: the seal once it's been had, and the data
    /// stores erased since launch, which are never written again.
    private nonisolated(unsafe) var sealed: SessionCookieSeal?
    private nonisolated(unsafe) var erased: Set<UUID> = []

    init(directory: URL, key: any SessionCookieKey) {
        self.directory = directory
        source = key
    }

    private func seal() -> SessionCookieSeal? {
        if let sealed { return sealed }
        do {
            sealed = SessionCookieSeal(keyData: try source.key())
        } catch {
            // Without its key Firn keeps no session cookies, and leaves any
            // file alone: the Keychain may only be locked.
            Self.log.notice("No key for session cookies; none are kept for now")
        }
        return sealed
    }

    /// A data store's saved cookies, and whether Firn may write its file
    /// (it has the key).
    func load(_ id: UUID, at now: Date = Date()) async -> (cookies: [SavedCookie], canSave: Bool) {
        await withCheckedContinuation { done in
            queue.async { done.resume(returning: self.read(id, at: now)) }
        }
    }

    private func read(_ id: UUID, at now: Date) -> (cookies: [SavedCookie], canSave: Bool) {
        guard let seal = seal(), !erased.contains(id) else { return ([], false) }
        let url = file(for: id)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0 else { return ([], true) }
        guard size <= SessionCookieSeal.fileLimit, let data = try? Data(contentsOf: url),
              let cookies = seal.open(data, for: id, at: now)
        else {
            // Damaged, another store's, sealed with a key that's gone, or too old.
            try? FileManager.default.removeItem(at: url)
            return ([], true)
        }
        return (cookies, true)
    }

    /// Saves, or with no cookies takes the file away. `wait` for quit.
    func save(_ cookies: [SavedCookie], for id: UUID, wait: Bool = false) {
        if wait {
            queue.sync { write(cookies, for: id) }
        } else {
            queue.async { self.write(cookies, for: id) }
        }
    }

    private func write(_ cookies: [SavedCookie], for id: UUID) {
        guard !erased.contains(id), let seal = seal() else { return }
        let url = file(for: id)
        guard !cookies.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try makeDirectory()
            try seal.seal(cookies, for: id, at: Date()).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
        } catch {
            Self.log.error("A space's session cookies couldn't be saved")
        }
    }

    /// A data store no space uses any more: its file goes, and stays gone.
    func erase(_ id: UUID) {
        queue.async {
            self.erased.insert(id)
            try? FileManager.default.removeItem(at: self.file(for: id))
        }
    }

    /// Like `BrowserEngine.removeUnusedData`, only with the spaces of a
    /// session that really loaded.
    func removeUnused(keeping: Set<UUID>) {
        queue.async {
            let names = (try? FileManager.default.contentsOfDirectory(
                atPath: self.directory.path(percentEncoded: false))) ?? []
            for name in names where name.hasSuffix(".sealed") {
                guard let id = UUID(uuidString: String(name.dropLast(".sealed".count))), !keeping.contains(id)
                else { continue }
                try? FileManager.default.removeItem(at: self.file(for: id))
            }
        }
    }

    private func file(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).sealed")
    }

    /// Made the first time, and kept out of backups: sign-ins never leave
    /// this Mac.
    private func makeDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directory
        try directory.setResourceValues(values)
    }
}
