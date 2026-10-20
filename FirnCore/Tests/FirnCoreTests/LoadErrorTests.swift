import Foundation
import Testing
@testable import FirnCore

@MainActor
struct LoadErrorTests {
    private let address = URL(string: "https://www.exampel.com/page")!

    private func urlError(_ code: Int, failing: URL? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let failing { info[NSURLErrorFailingURLErrorKey] = failing }
        return NSError(domain: NSURLErrorDomain, code: code, userInfo: info)
    }

    @Test func cancelledAndInterruptedLoadsAreNotErrors() {
        #expect(LoadError(urlError(NSURLErrorCancelled, failing: address), fallbackURL: address) == nil)
        #expect(LoadError(NSError(domain: "WebKitErrorDomain", code: 102), fallbackURL: address) == nil)
        #expect(LoadError(NSError(domain: "WebKitErrorDomain", code: 204), fallbackURL: address) == nil)
    }

    @Test func reasonsInPlainWords() {
        let cases: [(Int, LoadError.Reason)] = [
            (NSURLErrorNotConnectedToInternet, .offline),
            (NSURLErrorNetworkConnectionLost, .offline),
            (NSURLErrorCannotFindHost, .noSuchSite),
            (NSURLErrorDNSLookupFailed, .noSuchSite),
            (NSURLErrorTimedOut, .notAnswering),
            (NSURLErrorCannotConnectToHost, .notAnswering),
            (NSURLErrorServerCertificateUntrusted, .notSecure),
            (NSURLErrorSecureConnectionFailed, .notSecure),
            (NSURLErrorBadServerResponse, .other),
        ]
        for (code, reason) in cases {
            #expect(LoadError(urlError(code, failing: address), fallbackURL: nil)?.reason == reason)
        }
    }

    @Test func usesTheAddressThatFailed() {
        let other = URL(string: "https://elsewhere.org")!
        #expect(LoadError(urlError(NSURLErrorCannotFindHost, failing: address), fallbackURL: other)?.url == address)
        #expect(LoadError(urlError(NSURLErrorCannotFindHost), fallbackURL: other)?.url == other)
        #expect(LoadError(urlError(NSURLErrorCannotFindHost), fallbackURL: nil) == nil)
    }

    @Test func onlyWebAddressesAreShown() {
        let file = URL(string: "file:///etc/hosts")!
        #expect(LoadError(urlError(NSURLErrorCannotFindHost, failing: file), fallbackURL: address) == nil)
    }

    @Test func headlineNamesTheSite() {
        let error = LoadError(url: address, reason: .noSuchSite)
        #expect(error.site == "exampel.com")
        #expect(error.headline == "Firn couldn’t reach exampel.com")
        #expect(LoadError(url: URL(string: "http://localhost:8080")!, reason: .notAnswering).site == "localhost:8080")
    }

    // MARK: - The tab tells the truth

    @Test func failedTabShowsTheFailedAddressNotTheOldPage() {
        let page = FakePage(dataStoreID: UUID())
        page.url = URL(string: "https://old.example")!
        page.title = "Old page"
        page.icon = Data([1])
        let tab = Tab(spaceID: UUID(), url: page.url, lastActiveAt: .now, page: page)

        page.loadError = LoadError(url: address, reason: .noSuchSite)
        #expect(tab.url == address)
        #expect(tab.title == "exampel.com")
        #expect(tab.icon == nil)
        #expect(tab.savedTitle == "")

        page.loadError = nil
        #expect(tab.url == page.url)
        #expect(tab.title == "Old page")
    }

    @Test func sleepingAfterAnErrorRestsAtTheFailedAddress() {
        let page = FakePage(dataStoreID: UUID())
        page.url = URL(string: "https://old.example")!
        page.title = "Old page"
        let tab = Tab(spaceID: UUID(), url: page.url, lastActiveAt: .now, page: page)
        page.loadError = LoadError(url: address, reason: .offline)
        tab.sleep()
        #expect(tab.url == address)
        // The old page's title isn't kept; a row falls back to the host.
        #expect(tab.title == "www.exampel.com")
    }
}
