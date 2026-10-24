import Foundation
import Testing
@testable import FirnCore

struct SignInScriptTests {
    @Test func readsTheExactShapes() {
        #expect(SignInScript.parse(["kind": "submitted", "username": "dana", "password": "snow"])
            == .submitted(username: "dana", password: "snow"))
        #expect(SignInScript.parse(["kind": "submitted", "username": "", "password": "snow"])
            == .submitted(username: "", password: "snow"))
        #expect(SignInScript.parse(["kind": "gone"]) == .gone)
    }

    @Test func refusesAnythingElse() {
        #expect(SignInScript.parse("submitted") == nil)
        #expect(SignInScript.parse(["kind": "gone", "extra": 1]) == nil)
        #expect(SignInScript.parse(["kind": "submitted", "username": "dana", "password": ""]) == nil)
        #expect(SignInScript.parse(["kind": "submitted", "username": "dana"]) == nil)
        #expect(SignInScript.parse(["kind": "submitted", "username": 1, "password": "snow"]) == nil)
        #expect(SignInScript.parse(["kind": "submitted", "username": "dana", "password": "snow", "site": "x"]) == nil)
        #expect(SignInScript.parse(["kind": "fill"]) == nil)
    }

    @Test func refusesWhatsTooLong() {
        let long = String(repeating: "a", count: 1025)
        #expect(SignInScript.parse(["kind": "submitted", "username": "dana", "password": long]) == nil)
        let longName = String(repeating: "a", count: 513)
        #expect(SignInScript.parse(["kind": "submitted", "username": longName, "password": "snow"]) == nil)
    }
}

@MainActor
struct PasswordOfferTests {
    private let personal = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())
    private let work = Space(name: "Work", icon: "work", color: "sand", order: 1, dataStoreID: UUID())
    private let passwords = PasswordStore(vault: MemoryVault())
    private let site = PasswordSite(URL(string: "https://example.com/login")!)!

    private func makeStore(_ spaces: [Space]? = nil) -> BrowserStore {
        BrowserStore(spaces: spaces ?? [personal, work], makePage: { FakePage(dataStoreID: $0) }, passwords: passwords)
    }

    private func login(_ username: String = "dana", _ password: String = "snow") -> SubmittedLogin {
        SubmittedLogin(site: site, username: username, password: password)
    }

    private func signIn(on tab: Tab, _ login: SubmittedLogin) {
        tab.page?.onRequest?(.offerToSave(login))
    }

    @Test func offersToSaveAndSavesInTheTabsDataStore() throws {
        let store = makeStore()
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        let offer = try #require(store.passwordOffer)
        #expect(offer.isUpdate == false)
        #expect(offer.login.site == site)
        #expect(store.savePasswordOffer())
        #expect(store.passwordOffer == nil)
        #expect(try passwords.logins(for: site, in: personal.dataStoreID).map(\.username) == ["dana"])
        #expect(try passwords.logins(for: site, in: work.dataStoreID).isEmpty)
    }

    @Test func noOfferWhenAlreadySaved() throws {
        let store = makeStore()
        try passwords.save(username: "dana", password: "snow", for: site, in: personal.dataStoreID)
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        #expect(store.passwordOffer == nil)
        // A second step with no username, matching a saved password, counts too.
        signIn(on: tab, login("", "snow"))
        #expect(store.passwordOffer == nil)
    }

    @Test func aChangedPasswordIsAnUpdate() throws {
        let store = makeStore()
        try passwords.save(username: "dana", password: "snow", for: site, in: personal.dataStoreID)
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login("dana", "firn"))
        #expect(store.passwordOffer?.isUpdate == true)
        store.savePasswordOffer()
        #expect(try passwords.logins(for: site, in: personal.dataStoreID).map(\.password) == ["firn"])
    }

    @Test func savedInAnotherSpaceStillOffers() throws {
        let store = makeStore()
        try passwords.save(username: "dana", password: "snow", for: site, in: work.dataStoreID)
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        #expect(store.passwordOffer?.isUpdate == false)
    }

    @Test func notNowSavesNothing() throws {
        let store = makeStore()
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        store.dismissPasswordOffer()
        #expect(store.passwordOffer == nil)
        #expect(try passwords.logins(for: site, in: personal.dataStoreID).isEmpty)
        signIn(on: tab, login())
        #expect(store.passwordOffer != nil)
    }

    @Test func neverStopsAskingInThatSpaceOnly() {
        let store = makeStore()
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        store.neverSavePasswordsForOffer()
        #expect(store.spaces[0].neverSavePasswordSites == ["example.com"])
        signIn(on: tab, login())
        #expect(store.passwordOffer == nil)

        store.selectSpace(store.spaces[1])
        let other = store.openTab(URL(string: "https://example.com")!)
        signIn(on: other, login())
        #expect(store.passwordOffer != nil)
    }

    @Test func aSharedSpaceHonorsItsPartnersNever() {
        let store = makeStore([personal])
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        store.neverSavePasswordsForOffer()
        store.addSpace(name: "Family", icon: "leaf", color: "sage", sharingWith: store.spaces[0])
        let shared = store.openTab(URL(string: "https://example.com")!)
        signIn(on: shared, login())
        #expect(store.passwordOffer == nil)
    }

    @Test func showingAnotherTabDropsTheOffer() {
        let store = makeStore()
        let a = store.openTab(URL(string: "https://example.com")!)
        let b = store.openTab(URL(string: "https://example.org")!)
        signIn(on: b, login())
        #expect(store.passwordOffer != nil)
        store.select(a)
        #expect(store.passwordOffer == nil)
    }

    @Test func onlyTheTabOnScreenOffers() {
        let store = makeStore()
        let a = store.openTab(URL(string: "https://example.com")!)
        store.openTab(URL(string: "https://example.org")!)
        signIn(on: a, login())
        #expect(store.passwordOffer == nil)
    }

    @Test func noPasswordStoreNoOffers() {
        let store = BrowserStore(spaces: [personal], makePage: { FakePage(dataStoreID: $0) })
        let tab = store.openTab(URL(string: "https://example.com")!)
        signIn(on: tab, login())
        #expect(store.passwordOffer == nil)
    }

    @Test func aLookoutNeverOffers() throws {
        let store = makeStore()
        store.openTab(URL(string: "https://example.com")!)
        store.openLookout(URL(string: "https://example.com/login")!)
        store.lookout?.page.onRequest?(.offerToSave(login()))
        #expect(store.passwordOffer == nil)
    }

    @Test func theNeverListSurvivesSavingAndDropsJunk() throws {
        var space = personal
        space.neverSavePasswordSites = ["example.com", "example.com:8443", "not a site", "example.com", "EXAMPLE.org"]
        let data = try JSONEncoder().encode(space)
        let back = try JSONDecoder().decode(Space.self, from: data)
        #expect(back.neverSavePasswordSites == ["example.com", "example.com:8443"])
    }
}

struct PasswordNeedsUpdateTests {
    private let store = PasswordStore(vault: MemoryVault())
    private let site = PasswordSite(URL(string: "https://example.com")!)!
    private let id = UUID()

    @Test func refusesWhatCantBeALogin() throws {
        #expect(try store.needsUpdate(for: SubmittedLogin(site: site, username: "dana", password: ""), in: id) == nil)
        let long = String(repeating: "a", count: 1025)
        #expect(try store.needsUpdate(for: SubmittedLogin(site: site, username: "dana", password: long), in: id) == nil)
    }

    @Test func aNewUsernameIsANewLogin() throws {
        try store.save(username: "dana", password: "snow", for: site, in: id)
        #expect(try store.needsUpdate(for: SubmittedLogin(site: site, username: "sam", password: "firn"), in: id) == false)
    }
}
