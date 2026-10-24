import Foundation
import Security
import Testing
@testable import FirnCore

/// Saved logins in a plain list, standing in for the Keychain (tests run
/// unsigned, and the data protection keychain refuses unsigned apps).
/// Known by data store, site, and username, as `KeychainVault` is.
final class MemoryVault: PasswordVault, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SavedLogin] = []

    private func same(_ a: SavedLogin, _ b: SavedLogin) -> Bool {
        a.dataStoreID == b.dataStoreID && a.site == b.site && a.username == b.username
    }

    func save(_ login: SavedLogin) throws {
        lock.withLock {
            items.removeAll { same($0, login) }
            items.append(login)
        }
    }

    func logins(in dataStoreID: UUID, for site: PasswordSite?) throws -> [SavedLogin] {
        lock.withLock { items.filter { $0.dataStoreID == dataStoreID && (site == nil || $0.site == site) } }
    }

    func delete(_ login: SavedLogin) throws {
        lock.withLock { items.removeAll { same($0, login) } }
    }

    func deleteAll(in dataStoreID: UUID) throws {
        lock.withLock { items.removeAll { $0.dataStoreID == dataStoreID } }
    }

    func dataStoreIDs() throws -> Set<UUID> {
        lock.withLock { Set(items.map(\.dataStoreID)) }
    }
}

struct PasswordStoreTests {
    private let store = PasswordStore(vault: MemoryVault())
    private let personal = UUID()
    private let work = UUID()

    private func site(_ address: String) -> PasswordSite { PasswordSite(URL(string: address)!)! }

    // MARK: - The exact site

    @Test func aSiteIsTheExactHttpsHostAndPort() {
        #expect(site("https://Example.com/sign-in?next=1") == site("https://example.com"))
        #expect(site("https://example.com:443") == site("https://example.com"))
        #expect(site("https://login.example.com") != site("https://example.com"))
        #expect(site("https://example.com:8443") != site("https://example.com"))
        #expect(site("https://example.com:8443").name == "example.com:8443")
        #expect(site("https://example.com").name == "example.com")
    }

    @Test func onlyHttpsHasASite() {
        #expect(PasswordSite(URL(string: "http://example.com")!) == nil)
        #expect(PasswordSite(URL(string: "file:///Users/me/a.html")!) == nil)
        #expect(PasswordSite(URL(string: "javascript:alert(1)")!) == nil)
        #expect(PasswordSite(URL(string: "about:blank")!) == nil)
    }

    // MARK: - Saving and finding

    @Test func aSavedLoginIsFoundOnlyOnItsOwnSite() throws {
        try store.save(username: "dana", password: "snow", for: site("https://example.com"), in: personal)
        #expect(try store.logins(for: site("https://example.com"), in: personal).map(\.username) == ["dana"])
        #expect(try store.logins(for: site("https://login.example.com"), in: personal).isEmpty)
        #expect(try store.logins(for: site("https://example.com:8443"), in: personal).isEmpty)
    }

    @Test func savingTheSameUsernameAgainChangesItsPassword() throws {
        let example = site("https://example.com")
        try store.save(username: "dana", password: "old", for: example, in: personal)
        try store.save(username: "dana", password: "new", for: example, in: personal)
        try store.save(username: "sam", password: "other", for: example, in: personal)
        let logins = try store.logins(for: example, in: personal)
        #expect(logins.map(\.username) == ["dana", "sam"])
        #expect(logins.first?.password == "new")
    }

    @Test func whatAPageOffersIsCheckedBeforeSaving() throws {
        let example = site("https://example.com")
        #expect(throws: PasswordError.notALogin) {
            try store.save(username: "dana", password: "", for: example, in: personal)
        }
        #expect(throws: PasswordError.notALogin) {
            try store.save(username: "dana", password: String(repeating: "x", count: 1025), for: example, in: personal)
        }
        #expect(throws: PasswordError.notALogin) {
            try store.save(username: String(repeating: "x", count: 513), password: "snow", for: example, in: personal)
        }
        try store.save(username: "", password: "pin only", for: example, in: personal)
        #expect(try store.logins(for: example, in: personal).count == 1)
    }

    @Test func aLoginNeverShowsItsPasswordWhenPrinted() throws {
        try store.save(username: "dana", password: "hunter2", for: site("https://example.com"), in: personal)
        let login = try #require(try store.allLogins(in: personal).first)
        #expect(!"\(login)".contains("hunter2"))
        #expect(!String(reflecting: login).contains("hunter2"))
    }

    // MARK: - Spaces stay separate

    @Test func aSeparateSpaceNeverSeesAnothersPasswords() throws {
        let example = site("https://example.com")
        try store.save(username: "dana", password: "personal", for: example, in: personal)
        #expect(try store.logins(for: example, in: work).isEmpty)
        #expect(try store.allLogins(in: work).isEmpty)

        // The same username on the same site is its own login in each space.
        try store.save(username: "dana", password: "work", for: example, in: work)
        #expect(try store.logins(for: example, in: personal).map(\.password) == ["personal"])
        #expect(try store.logins(for: example, in: work).map(\.password) == ["work"])
    }

    @MainActor @Test func aSharedSpaceSeesTheSamePasswords() throws {
        // Spaces that share sign-ins share a data store id, so they ask for the same one.
        let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: personal)
        let shared = BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) })
            .addSpace(name: "Family", icon: "home", color: "sand", sharingWith: space)
        try store.save(username: "dana", password: "snow", for: site("https://example.com"), in: personal)
        #expect(try store.allLogins(in: shared.dataStoreID).map(\.username) == ["dana"])
    }

    // MARK: - Deleting

    @Test func deletingOneLoginLeavesTheRest() throws {
        let example = site("https://example.com")
        try store.save(username: "dana", password: "a", for: example, in: personal)
        try store.save(username: "sam", password: "b", for: example, in: personal)
        try store.save(username: "dana", password: "c", for: example, in: work)
        try store.delete(try #require(try store.logins(for: example, in: personal).first))
        #expect(try store.logins(for: example, in: personal).map(\.username) == ["sam"])
        #expect(try store.logins(for: example, in: work).count == 1)
    }

    @Test func removingADataStoreDeletesOnlyItsPasswords() throws {
        try store.save(username: "dana", password: "a", for: site("https://example.com"), in: personal)
        try store.save(username: "dana", password: "b", for: site("https://example.com"), in: work)
        try store.removeAll(in: work)
        #expect(try store.allLogins(in: work).isEmpty)
        #expect(try store.allLogins(in: personal).count == 1)
    }

    @Test func passwordsOfSpacesThatAreGoneAreRemovedAtLaunch() throws {
        let gone = UUID()
        try store.save(username: "dana", password: "a", for: site("https://example.com"), in: personal)
        try store.save(username: "dana", password: "b", for: site("https://example.com"), in: gone)
        try store.removeUnused(keeping: [personal])
        #expect(try store.allLogins(in: gone).isEmpty)
        #expect(try store.allLogins(in: personal).count == 1)
    }

    // MARK: - The Keychain's queries

    @Test func everyKeychainQueryNamesItsDataStoreAndStaysOnThisMac() {
        let query = KeychainVault.query(in: personal, for: site("https://example.com:8443"), username: "dana")
        #expect(query[kSecAttrSecurityDomain] as? String == personal.uuidString)
        #expect(query[kSecAttrServer] as? String == "example.com")
        #expect(query[kSecAttrPort] as? Int == 8443)
        #expect(query[kSecAttrAccount] as? String == "dana")
        #expect(query[kSecUseDataProtectionKeychain] as? Bool == true)
        #expect(query[kSecAttrSynchronizable] as? Bool == false)
        #expect(query[kSecAttrProtocol] as? String == kSecAttrProtocolHTTPS as String)
        #expect(KeychainVault.query(in: work)[kSecAttrSecurityDomain] as? String == work.uuidString)
    }

    @Test func aKeychainItemFromAnotherDataStoreOrSiteIsNeverHandedBack() {
        let item: [CFString: Any] = [
            kSecAttrSecurityDomain: work.uuidString, kSecAttrServer: "example.com", kSecAttrPort: 443,
            kSecAttrAccount: "dana", kSecValueData: Data("snow".utf8),
        ]
        #expect(KeychainVault.login(from: item, in: work, for: site("https://example.com"))?.password == "snow")
        #expect(KeychainVault.login(from: item, in: personal, for: nil) == nil)
        #expect(KeychainVault.login(from: item, in: work, for: site("https://login.example.com")) == nil)
    }
}
