import Foundation
import Testing
import WebKit
@testable import FirnCore

/// Tabs remember their back history across a restart: the places file,
/// and the store handing places out and taking them back.
@MainActor
struct PagePlacesTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore(restoring session: Session? = nil, places: [UUID: PagePlace] = [:]) -> BrowserStore {
        BrowserStore(restoring: session, pagePlaces: places, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func tempFile() -> PagePlacesFile {
        PagePlacesFile(url: FileManager.default.temporaryDirectory
            .appending(path: "FirnTests-\(UUID().uuidString)/page-places.plist"))
    }

    // MARK: - The file

    @Test func theFileKeepsPlaces() throws {
        let file = tempFile()
        let id = UUID()
        let place = try #require(PagePlace(url: url("a"), state: Data([1, 2, 3])))
        try file.save([id: place])
        #expect(file.load() == [id: place])
    }

    @Test func noFileOrADamagedOneMeansNoPlaces() throws {
        let file = tempFile()
        #expect(file.load().isEmpty)
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: file.url)
        #expect(file.load().isEmpty)
    }

    @Test func aPlaceTooLargeOrForAFileIsntKept() {
        #expect(PagePlace(url: url("a"), state: Data(count: PagePlace.maxBytes)) != nil)
        #expect(PagePlace(url: url("a"), state: Data(count: PagePlace.maxBytes + 1)) == nil)
        #expect(PagePlace(url: URL(filePath: "/tmp/page.html"), state: Data([1])) == nil)
    }

    // MARK: - The saver

    @Test func theSaverWritesPlacesAtQuitEvenIfTheSessionDidntChange() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FirnTests-\(UUID().uuidString)")
        let sessionFile = SessionFile(url: dir.appending(path: "session.json"))
        let placesFile = PagePlacesFile(url: dir.appending(path: "page-places.plist"))
        let store = makeStore()
        let a = store.openTab(url("a"))
        let saver = SessionSaver(
            file: sessionFile, placesFile: placesFile, delay: .seconds(60),
            snapshot: { store.session(sidebarWidth: 260, sidebarCollapsed: false) },
            places: { store.pagePlaces() }
        )
        saver.saveNow()
        #expect(placesFile.load()[a.id]?.url == url("a"))
        #expect(sessionFile.load() != nil)

        // Only the page's place changes (as scrolling would): still written.
        try FileManager.default.removeItem(at: placesFile.url)
        (a.page as? FakePage)?.url = url("a/scrolled")
        saver.saveNow()
        #expect(placesFile.load()[a.id]?.url == url("a/scrolled"))
    }

    // MARK: - The store

    @Test func aRestartedTabPicksUpWhereItWas() throws {
        let store = makeStore()
        let a = store.openTab(url("a"))
        (a.page as? FakePage)?.url = url("a/page-two")
        store.openTab(url("b"))
        let places = store.pagePlaces()
        #expect(places[a.id]?.url == url("a/page-two"))

        let restored = makeStore(restoring: store.session(sidebarWidth: 260, sidebarCollapsed: false), places: places)
        let again = try #require(restored.tabs.first { $0.id == a.id })
        restored.select(again)
        #expect((again.page as? FakePage)?.resumedFrom == url("a/page-two"))
    }

    @Test func aSleepingTabsPlaceIsKeptToo() async {
        let store = BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) })
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        await store.sleepIdleTabs(memoryIsShort: true)
        #expect(a.isResting)
        #expect(store.pagePlaces()[a.id]?.url == url("a"))
    }

    @Test func aPlaceAtAnotherAddressIsIgnored() throws {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        let stale = try #require(PagePlace(url: url("elsewhere"), state: Data(url("elsewhere").absoluteString.utf8)))

        let restored = makeStore(restoring: store.session(sidebarWidth: 260, sidebarCollapsed: false), places: [a.id: stale])
        let again = try #require(restored.tabs.first { $0.id == a.id })
        restored.select(again)
        #expect((again.page as? FakePage)?.resumedFrom == nil)
        #expect(again.url == url("a"))
    }

    @Test func aClosedTabsPlaceIsGone() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        #expect(store.pagePlaces()[a.id] != nil)
        store.close(a)
        #expect(store.pagePlaces()[a.id] == nil)
    }

    // MARK: - WebKit

    /// WebKit's place is bytes, and a new web view given them can go back.
    @Test func webKitsPlaceIsBytesThatBringBackHistory() async throws {
        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            return WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
        }
        func settle(_ webView: WKWebView, until done: () -> Bool) async throws {
            for _ in 0..<100 where !done() || webView.isLoading {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        // Two real pages on disk: loading HTML strings makes no history.
        let folder = FileManager.default.temporaryDirectory.appending(path: "FirnTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let one = folder.appending(path: "one.html"), two = folder.appending(path: "two.html")
        try Data("<p>one</p>".utf8).write(to: one)
        try Data("<p>two</p>".utf8).write(to: two)
        let first = makeWebView()
        first.loadFileURL(one, allowingReadAccessTo: folder)
        try await settle(first) { first.url == one }
        first.loadFileURL(two, allowingReadAccessTo: folder)
        try await settle(first) { first.canGoBack }
        #expect(first.canGoBack)
        let data = try #require(first.interactionState as? Data)

        let second = makeWebView()
        second.interactionState = data
        try await settle(second) { second.canGoBack }
        #expect(second.canGoBack)
        #expect(second.url == two)
    }
}
