import Foundation

/// The exact site a password belongs to: an https host and port. Nothing
/// looser: `login.example.com` isn't `example.com`, and a different port is
/// a different site. Only https, so a password is never kept for (or later
/// filled into) a page anyone on the network could read or change.
public struct PasswordSite: Hashable, Sendable {
    public let host: String
    public let port: Int

    /// The site of a page's address, or nil if it isn't https.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return nil }
        let port = url.port ?? 443
        guard (1...65535).contains(port) else { return nil }
        self.host = host
        self.port = port
    }

    /// How the site reads to people: the host, plus the port if it isn't
    /// the usual one.
    public var name: String { port == 443 ? host : "\(host):\(port)" }

    /// The site a `name` stands for, or nil if it isn't exactly one (read
    /// back from a saved file, which may be damaged or edited).
    init?(name: String) {
        guard let url = URL(string: "https://\(name)/"), let site = PasswordSite(url), site.name == name else { return nil }
        self = site
    }
}

/// A sign-in a page just sent, as the engine noticed it: the username and
/// password typed, and the exact site they were typed into (WebKit's own
/// origin for the page, never what the page claimed). Kept in memory only.
public struct SubmittedLogin: Hashable, Sendable {
    public let site: PasswordSite
    public let username: String
    public let password: String

    public init(site: PasswordSite, username: String, password: String) {
        self.site = site
        self.username = username
        self.password = password
    }
}

extension SubmittedLogin: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "SubmittedLogin(\(site.name), password hidden)" }
    public var debugDescription: String { description }
}

/// One saved sign-in: a username and password for one site, in one data
/// store (so every space sharing that store sees it, and no other).
public struct SavedLogin: Hashable, Sendable {
    public let dataStoreID: UUID
    public let site: PasswordSite
    public let username: String
    public let password: String
    /// When it was saved or last changed (the Keychain keeps this).
    public let lastChangedAt: Date?

    public init(dataStoreID: UUID, site: PasswordSite, username: String, password: String, lastChangedAt: Date? = nil) {
        self.dataStoreID = dataStoreID
        self.site = site
        self.username = username
        self.password = password
        self.lastChangedAt = lastChangedAt
    }
}

/// Firn's offer to save (or update) a password just used on a tab, for its
/// data store. In memory only, until answered.
public struct PasswordOffer: Identifiable, Sendable {
    public let id = UUID()
    /// The tab it was used on (its opener, once a sign-in popup closes).
    public internal(set) var tabID: UUID
    public let spaceID: UUID
    public let dataStoreID: UUID
    public let login: SubmittedLogin
    /// That username is saved with another password: "Update", not "Save".
    public let isUpdate: Bool
}

extension PasswordOffer: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "PasswordOffer(\(login.site.name), password hidden)" }
    public var debugDescription: String { description }
}

/// Never print a password by accident, in a log or a test failure.
extension SavedLogin: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "SavedLogin(\(site.name), password hidden)" }
    public var debugDescription: String { description }
}

/// Where saved logins are kept: the Keychain in the app (`KeychainVault`),
/// a plain list in tests. A login is known by its data store, site, and
/// username; saving one that's already there replaces its password.
public protocol PasswordVault: Sendable {
    func save(_ login: SavedLogin) throws
    /// The data store's logins, only for `site` if one is given.
    func logins(in dataStoreID: UUID, for site: PasswordSite?) throws -> [SavedLogin]
    func delete(_ login: SavedLogin) throws
    func deleteAll(in dataStoreID: UUID) throws
    /// Every data store that has a login.
    func dataStoreIDs() throws -> Set<UUID>
}

public enum PasswordError: Error, Equatable {
    /// What a page offered isn't something to keep: an empty password, or
    /// one so long it can't be real.
    case notALogin
    /// The Keychain said no, with its status code (never what was saved).
    case keychain(Int32)
}

/// Firn's saved passwords, each kept in its space's data store, so a
/// separate space never sees another's. Nothing in here touches WebKit.
public struct PasswordStore: Sendable {
    /// Longer than any real username or password; anything longer came
    /// from a page that's up to something.
    static let usernameLimit = 512
    static let passwordLimit = 1024

    private let vault: any PasswordVault

    public init(vault: any PasswordVault) {
        self.vault = vault
    }

    /// The app's store, in the Keychain on this Mac only.
    public static let keychain = PasswordStore(vault: KeychainVault())

    /// Saves a sign-in, or changes the password of the one already saved for
    /// this username. An empty username is fine (some sites ask only for a
    /// password); an empty password isn't.
    public func save(username: String, password: String, for site: PasswordSite, in dataStoreID: UUID) throws {
        guard !password.isEmpty, password.count <= Self.passwordLimit, username.count <= Self.usernameLimit else {
            throw PasswordError.notALogin
        }
        try vault.save(SavedLogin(dataStoreID: dataStoreID, site: site, username: username, password: password))
    }

    /// The logins saved for exactly this site in this data store, by username.
    public func logins(for site: PasswordSite, in dataStoreID: UUID) throws -> [SavedLogin] {
        try sorted(vault.logins(in: dataStoreID, for: site))
    }

    /// Every login in this data store, by site, then username.
    public func allLogins(in dataStoreID: UUID) throws -> [SavedLogin] {
        try sorted(vault.logins(in: dataStoreID, for: nil))
    }

    /// What to ask about a sign-in a page just sent: nil when there's nothing
    /// to ask (that login is already saved, or what was sent can't be one),
    /// `false` to save a new one, `true` to update the password saved for
    /// that username. A sign-in with no username (a site's second step,
    /// often) matching a saved password counts as saved. Throws if the
    /// Keychain can't be read, so nothing is offered that couldn't be saved.
    public func needsUpdate(for login: SubmittedLogin, in dataStoreID: UUID) throws -> Bool? {
        guard !login.password.isEmpty, login.password.count <= Self.passwordLimit,
              login.username.count <= Self.usernameLimit else { return nil }
        let saved = try vault.logins(in: dataStoreID, for: login.site)
        if saved.contains(where: { $0.password == login.password && (login.username.isEmpty || $0.username == login.username) }) {
            return nil
        }
        return saved.contains { $0.username == login.username }
    }

    public func delete(_ login: SavedLogin) throws {
        try vault.delete(login)
    }

    /// Deletes every password in a data store no space uses any more.
    public func removeAll(in dataStoreID: UUID) throws {
        try vault.deleteAll(in: dataStoreID)
    }

    /// Deletes the passwords of every data store not in `keeping`: what's
    /// left of spaces deleted when the Keychain couldn't be reached. Like
    /// `BrowserEngine.removeUnusedData`, only with the spaces of a session
    /// that really loaded.
    public func removeUnused(keeping: Set<UUID>) throws {
        for id in try vault.dataStoreIDs() where !keeping.contains(id) {
            try vault.deleteAll(in: id)
        }
    }

    private func sorted(_ logins: [SavedLogin]) -> [SavedLogin] {
        logins.sorted {
            ($0.site.host, $0.site.port, $0.username.lowercased()) < ($1.site.host, $1.site.port, $1.username.lowercased())
        }
    }
}
