import Foundation
import Testing
import WebKit
@testable import FirnCore

/// Session cookies kept across a quit: nothing leaks between data stores,
/// nothing comes back weaker, and hostile or damaged files open as nothing.
@Suite struct SessionCookieSealTests {
    private let seal = SessionCookieSeal(keyData: SessionCookieSeal.makeKeyData())!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func cookie(_ name: String = "sid", value: String = "secret", domain: String = "example.com",
                       path: String = "/", secure: Bool = true, httpOnly: Bool = true,
                       sameSite: HTTPCookieStringPolicy? = .sameSiteLax, expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[.init("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite.rawValue }
        if let expires { properties[.expires] = expires } else { properties[.discard] = "TRUE" }
        return HTTPCookie(properties: properties)!
    }

    @Test func sealedAndOpenedAgain() throws {
        let id = UUID()
        let cookies = [SavedCookie(Self.cookie())!, SavedCookie(Self.cookie("b", domain: ".example.com"))!]
        let sealed = try seal.seal(cookies, for: id, at: now)
        #expect(seal.open(sealed, for: id, at: now) == cookies)
        // Nothing readable in the file.
        #expect(sealed.range(of: Data("secret".utf8)) == nil)
        #expect(sealed.range(of: Data("example".utf8)) == nil)
    }

    @Test func anotherStoresFileDoesntOpen() throws {
        let sealed = try seal.seal([SavedCookie(Self.cookie())!], for: UUID(), at: now)
        #expect(seal.open(sealed, for: UUID(), at: now) == nil)
    }

    @Test func anotherKeyDoesntOpen() throws {
        let id = UUID()
        let sealed = try seal.seal([SavedCookie(Self.cookie())!], for: id, at: now)
        let other = SessionCookieSeal(keyData: SessionCookieSeal.makeKeyData())!
        #expect(other.open(sealed, for: id, at: now) == nil)
        #expect(SessionCookieSeal(keyData: Data(count: 16)) == nil)
    }

    @Test func changedOrDamagedDoesntOpen() throws {
        let id = UUID()
        var sealed = try seal.seal([SavedCookie(Self.cookie())!], for: id, at: now)
        sealed[sealed.count / 2] ^= 1
        #expect(seal.open(sealed, for: id, at: now) == nil)
        #expect(seal.open(Data(), for: id, at: now) == nil)
        #expect(seal.open(Data("not sealed at all".utf8), for: id, at: now) == nil)
        #expect(seal.open(sealed.prefix(10), for: id, at: now) == nil)
    }

    @Test func tooOldOrFromTheFutureDoesntOpen() throws {
        let id = UUID()
        let sealed = try seal.seal([SavedCookie(Self.cookie())!], for: id, at: now)
        let day: TimeInterval = 24 * 60 * 60
        #expect(seal.open(sealed, for: id, at: now + 29 * day) != nil)
        #expect(seal.open(sealed, for: id, at: now + 31 * day) == nil)
        #expect(seal.open(sealed, for: id, at: now - 2 * day) == nil)
    }

    @Test func onlySessionCookiesAreKept() {
        #expect(SavedCookie(Self.cookie()) != nil)
        #expect(SavedCookie(Self.cookie(expires: Date().addingTimeInterval(9999))) == nil)
    }

    @Test func comesBackExactlyAsItWas() throws {
        for (secure, httpOnly, sameSite) in [
            (true, true, HTTPCookieStringPolicy.sameSiteStrict), (true, true, .sameSiteLax),
            (true, false, nil), (false, true, nil), (false, false, .sameSiteLax),
        ] {
            for domain in ["example.com", ".example.com", "a.b.example.co.uk"] {
                let was = Self.cookie(domain: domain, path: "/x", secure: secure, httpOnly: httpOnly, sameSite: sameSite)
                let back = try #require(SavedCookie(was)?.cookie)
                #expect(back.isSecure == secure)
                #expect(back.isHTTPOnly == httpOnly)
                #expect(back.sameSitePolicy == was.sameSitePolicy)
                #expect(back.domain == was.domain)
                #expect(back.path == "/x")
                #expect(back.isSessionOnly)
            }
        }
    }

    /// Sealed with the right key, but not what Firn writes.
    @Test func badContentsComeBackAsNothing() throws {
        func cookie(_ changes: [String: Any]) throws -> HTTPCookie? {
            var fields: [String: Any] = ["name": "sid", "value": "v", "domain": "example.com", "path": "/",
                                         "isSecure": true, "isHTTPOnly": true]
            fields.merge(changes) { $1 }
            return try JSONDecoder().decode(
                SavedCookie.self, from: JSONSerialization.data(withJSONObject: fields)).cookie
        }
        #expect(try cookie([:]) != nil)
        #expect(try cookie(["name": ""]) == nil)
        #expect(try cookie(["domain": ""]) == nil)
        #expect(try cookie(["domain": "."]) == nil)
        #expect(try cookie(["path": "nowhere"]) == nil)
        #expect(try cookie(["value": String(repeating: "x", count: 9000)]) == nil)
    }

    /// One kept apart by the site it's embedded in isn't kept.
    @Test func partitionedIsLeftOut() {
        let cookie = HTTPCookie(properties: [
            .name: "sid", .value: "v", .domain: "example.com", .path: "/", .secure: "TRUE",
            .init("StoragePartition"): "https://elsewhere.com",
        ])
        if let cookie, cookie.properties?[.init("StoragePartition")] != nil { #expect(SavedCookie(cookie) == nil) }
    }
}

private struct FixedKey: SessionCookieKey {
    var data: Data? = SessionCookieSeal.makeKeyData()
    struct Locked: Error {}
    func key() throws -> Data {
        guard let data else { throw Locked() }
        return data
    }
}

@Suite struct SessionCookieFilesTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "session-cookies-\(UUID().uuidString)")
    private let cookies = [SavedCookie(SessionCookieSealTests.cookie())!]

    private func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: "\(id.uuidString).sealed").path(percentEncoded: false))
    }

    @Test func savedLoadedAndTakenAway() async {
        let files = SessionCookieFiles(directory: directory, key: FixedKey())
        let id = UUID()
        files.save(cookies, for: id, wait: true)
        #expect(await files.load(id).cookies == cookies)
        files.save([], for: id, wait: true)
        #expect(!exists(id))
    }

    @Test func onlyTheOwnerCanReadIt() throws {
        let files = SessionCookieFiles(directory: directory, key: FixedKey())
        let id = UUID()
        files.save(cookies, for: id, wait: true)
        let path = directory.appending(path: "\(id.uuidString).sealed").path(percentEncoded: false)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func withoutAKeyNothingIsWrittenOrLost() async {
        let key = FixedKey()
        let id = UUID()
        SessionCookieFiles(directory: directory, key: key).save(cookies, for: id, wait: true)
        let locked = SessionCookieFiles(directory: directory, key: FixedKey(data: nil))
        let (read, canSave) = await locked.load(id)
        #expect(read.isEmpty)
        #expect(!canSave)
        locked.save([], for: id, wait: true)
        #expect(exists(id))
        // The Keychain is back: so are the cookies.
        #expect(await SessionCookieFiles(directory: directory, key: key).load(id).cookies == cookies)
    }

    @Test func aFileMovedToAnotherStoreOpensAsNothingAndGoes() async throws {
        let files = SessionCookieFiles(directory: directory, key: FixedKey())
        let (a, b) = (UUID(), UUID())
        files.save(cookies, for: a, wait: true)
        try FileManager.default.copyItem(
            at: directory.appending(path: "\(a.uuidString).sealed"), to: directory.appending(path: "\(b.uuidString).sealed"))
        #expect(await files.load(b).cookies.isEmpty)
        #expect(!exists(b))
        #expect(await files.load(a).cookies == cookies)
    }

    @Test func erasedStaysErased() async {
        let files = SessionCookieFiles(directory: directory, key: FixedKey())
        let id = UUID()
        files.save(cookies, for: id, wait: true)
        files.erase(id)
        files.save(cookies, for: id, wait: true)
        #expect(await files.load(id).cookies.isEmpty)
        #expect(!exists(id))
    }

    @Test func unusedStoresGo() async {
        let files = SessionCookieFiles(directory: directory, key: FixedKey())
        let (kept, gone) = (UUID(), UUID())
        files.save(cookies, for: kept, wait: true)
        files.save(cookies, for: gone, wait: true)
        files.removeUnused(keeping: [kept])
        #expect(await files.load(kept).cookies == cookies)
        #expect(!exists(gone))
    }
}

/// With real WebKit stores: what one sitting leaves, the next has again, in
/// its own store only.
@MainActor @Suite(.serialized) struct SessionCookiesTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "session-cookies-\(UUID().uuidString)")
    private let key = FixedKey()

    private func keeper() -> SessionCookies {
        SessionCookies(files: SessionCookieFiles(directory: directory, key: key))
    }

    private func ready(_ keeper: SessionCookies, _ store: WKWebsiteDataStore) async {
        keeper.willUse(store)
        await withCheckedContinuation { done in keeper.whenReady(store) { done.resume() } }
        // Its state is set just after the waiting loads are let go or before; give it a turn.
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func backInTheNextSittingAndOnlyInItsOwnStore() async throws {
        let (mine, other) = (UUID(), UUID())
        let store = WKWebsiteDataStore(forIdentifier: mine)
        let first = keeper()
        await ready(first, store)
        await store.httpCookieStore.setCookie(SessionCookieSealTests.cookie("sid", value: "abc"))
        first.saveNow()

        // A quit: WebKit's session cookies are gone.
        for cookie in await store.httpCookieStore.allCookies() { await store.httpCookieStore.deleteCookie(cookie) }
        #expect(await store.httpCookieStore.allCookies().isEmpty)

        let next = keeper()
        await ready(next, store)
        let back = try #require(await store.httpCookieStore.allCookies().first)
        #expect(back.name == "sid")
        #expect(back.value == "abc")
        #expect(back.isHTTPOnly)
        #expect(back.isSecure)
        #expect(back.isSessionOnly)

        let otherStore = WKWebsiteDataStore(forIdentifier: other)
        await ready(next, otherStore)
        #expect(await otherStore.httpCookieStore.allCookies().isEmpty)
    }

    @Test func signedOutStaysSignedOut() async {
        let store = WKWebsiteDataStore(forIdentifier: UUID())
        let first = keeper()
        await ready(first, store)
        let cookie = SessionCookieSealTests.cookie("sid")
        await store.httpCookieStore.setCookie(cookie)
        first.saveNow()
        await store.httpCookieStore.deleteCookie(cookie)
        first.saveNow()
        await ready(keeper(), store)
        #expect(await store.httpCookieStore.allCookies().isEmpty)
    }

    @Test func loadsWaitForTheirCookiesInOrder() async {
        let store = WKWebsiteDataStore(forIdentifier: UUID())
        let keeper = keeper()
        keeper.willUse(store)
        var order: [Int] = []
        keeper.whenReady(store) { order.append(1) }
        keeper.whenReady(store) { order.append(2) }
        #expect(order.isEmpty)
        await withCheckedContinuation { done in keeper.whenReady(store) { done.resume() } }
        #expect(order == [1, 2])
        keeper.whenReady(store) { order.append(3) }
        #expect(order == [1, 2, 3])
    }

    @Test func anErasedStoreIsNeverSavedAgain() async {
        let id = UUID()
        let store = WKWebsiteDataStore(forIdentifier: id)
        let keeper = keeper()
        await ready(keeper, store)
        await store.httpCookieStore.setCookie(SessionCookieSealTests.cookie())
        keeper.erase(id)
        keeper.saveNow()
        let files = SessionCookieFiles(directory: directory, key: key)
        #expect(await files.load(id).cookies.isEmpty)
    }
}
