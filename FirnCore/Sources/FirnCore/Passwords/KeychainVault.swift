import Foundation
import os
import Security

/// Saved logins in the Keychain: the newer, per-app one (the data protection
/// keychain), so no other app can even ask for them. Each is an internet
/// password item that stays on this Mac (never synced: sync needs David's
/// OK) and opens only while the Mac is unlocked.
///
/// A login is known by its data store, site, and username. The data store
/// rides in the item's security domain (meant for a site's sign-in realm,
/// which Firn doesn't use), so it's part of what makes an item unique: the
/// same username on the same site in two separate spaces is two items, and
/// every search names its data store.
///
/// The data protection keychain needs Firn signed with a provisioning
/// profile; without one, every call fails with `errSecMissingEntitlement`.
public struct KeychainVault: PasswordVault {
    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "passwords")

    public init() {}

    public func save(_ login: SavedLogin) throws {
        let item = Self.query(in: login.dataStoreID, for: login.site, username: login.username)
        let password = Data(login.password.utf8)
        var status = SecItemUpdate(item as CFDictionary, [kSecValueData: password] as CFDictionary)
        if status == errSecItemNotFound {
            var new = item
            new[kSecValueData] = password
            new[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(new as CFDictionary, nil)
        }
        try Self.check(status, "save")
    }

    public func logins(in dataStoreID: UUID, for site: PasswordSite?) throws -> [SavedLogin] {
        var search = Self.query(in: dataStoreID, for: site)
        search[kSecMatchLimit] = kSecMatchLimitAll
        search[kSecReturnAttributes] = true
        search[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try Self.check(status, "read")
        let items = result as? [[CFString: Any]] ?? []
        return items.compactMap { Self.login(from: $0, in: dataStoreID, for: site) }
    }

    public func delete(_ login: SavedLogin) throws {
        let status = SecItemDelete(
            Self.query(in: login.dataStoreID, for: login.site, username: login.username) as CFDictionary
        )
        if status != errSecItemNotFound { try Self.check(status, "delete") }
    }

    public func deleteAll(in dataStoreID: UUID) throws {
        let status = SecItemDelete(Self.query(in: dataStoreID) as CFDictionary)
        if status != errSecItemNotFound { try Self.check(status, "delete all") }
    }

    public func dataStoreIDs() throws -> Set<UUID> {
        var search = Self.base
        search[kSecMatchLimit] = kSecMatchLimitAll
        search[kSecReturnAttributes] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try Self.check(status, "list")
        let items = result as? [[CFString: Any]] ?? []
        return Set(items.compactMap { ($0[kSecAttrSecurityDomain] as? String).flatMap(UUID.init(uuidString:)) })
    }

    // MARK: - Queries

    /// What every one of Firn's items has: an https internet password in the
    /// data protection keychain, never synced.
    static var base: [CFString: Any] {
        [
            kSecClass: kSecClassInternetPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false,
            kSecAttrProtocol: kSecAttrProtocolHTTPS,
        ]
    }

    /// The items in one data store, narrowed to a site and a username when
    /// they're given. Every query Firn makes but `dataStoreIDs` comes from here.
    static func query(in dataStoreID: UUID, for site: PasswordSite? = nil, username: String? = nil) -> [CFString: Any] {
        var query = base
        query[kSecAttrSecurityDomain] = dataStoreID.uuidString
        if let site {
            query[kSecAttrServer] = site.host
            query[kSecAttrPort] = site.port
        }
        if let username { query[kSecAttrAccount] = username }
        return query
    }

    /// A login from a Keychain item, checked once more against what was
    /// asked for, so a search that matched too much still can't hand back
    /// another data store's or another site's password.
    static func login(from item: [CFString: Any], in dataStoreID: UUID, for site: PasswordSite?) -> SavedLogin? {
        guard item[kSecAttrSecurityDomain] as? String == dataStoreID.uuidString,
              let host = item[kSecAttrServer] as? String,
              let port = (item[kSecAttrPort] as? NSNumber)?.intValue,
              let itemSite = PasswordSite(host: host, port: port),
              site == nil || itemSite == site,
              let data = item[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return SavedLogin(
            dataStoreID: dataStoreID, site: itemSite,
            username: item[kSecAttrAccount] as? String ?? "", password: password,
            lastChangedAt: item[kSecAttrModificationDate] as? Date
        )
    }

    /// Throws for anything but success, logging only the status code: never
    /// a site or a username.
    private static func check(_ status: OSStatus, _ action: StaticString) throws {
        guard status != errSecSuccess else { return }
        log.error("Keychain \(action, privacy: .public) failed: \(status, privacy: .public)")
        throw PasswordError.keychain(status)
    }
}

extension PasswordSite {
    /// A site read back from the Keychain, held to the same shape a page's
    /// address gives.
    init?(host: String, port: Int) {
        guard !host.isEmpty, host == host.lowercased(), (1...65535).contains(port) else { return nil }
        self.host = host
        self.port = port
    }
}
