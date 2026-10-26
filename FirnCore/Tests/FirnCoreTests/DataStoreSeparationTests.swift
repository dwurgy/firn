import Foundation
import Testing
import WebKit
@testable import FirnCore

/// The privacy promise, checked against real WebKit stores: a sign-in made
/// in one space never reaches a separate space, and does reach a space that
/// shares with it (CLAUDE.md, Security).
@MainActor
struct DataStoreSeparationTests {
    private func cookieStore(of tab: FirnCore.Tab) throws -> WKHTTPCookieStore {
        let page = try #require(tab.page as? WebKitPageController)
        return page.webView.configuration.websiteDataStore.httpCookieStore
    }

    @Test func aSignInStaysInItsOwnSpace() async throws {
        let personal = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())
        let store = BrowserStore(spaces: [personal], makePage: BrowserEngine.makePage)
        let signIn = try #require(HTTPCookie(properties: [
            .domain: "separation.test", .path: "/", .name: "signedIn", .value: "yes",
            .secure: "TRUE", .expires: Date.now.addingTimeInterval(3600),
        ]))
        let signedIn = { (cookies: [HTTPCookie]) in cookies.contains { $0.name == "signedIn" } }

        let personalTab = store.openTab(URL(string: "about:blank")!)
        try await cookieStore(of: personalTab).setCookie(signIn)

        let work = store.addSpace(name: "Work", color: "sand")
        let workTab = store.openTab(URL(string: "about:blank")!)
        let shared = store.addSpace(name: "Side", color: "sage", sharingWith: personal)
        let sharedTab = store.openTab(URL(string: "about:blank")!)

        #expect(signedIn(try await cookieStore(of: personalTab).allCookies()))
        #expect(!signedIn(try await cookieStore(of: workTab).allCookies()))
        #expect(signedIn(try await cookieStore(of: sharedTab).allCookies()))

        // Stopping sharing starts signed out.
        store.stopSharing(shared)
        #expect(!signedIn(try await cookieStore(of: sharedTab).allCookies()))

        let ids = [personal.dataStoreID, work.dataStoreID] + store.spaces.map(\.dataStoreID)
        for tab in store.tabs { store.close(tab) }
        await Task.yield()
        for id in Set(ids) { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
    }
}
