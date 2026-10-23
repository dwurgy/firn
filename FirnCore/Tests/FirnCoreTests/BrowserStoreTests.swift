import CoreGraphics
import Foundation
import Observation
import Testing
@testable import FirnCore

/// A page that remembers what it was asked to do, without WebKit.
@MainActor
@Observable
final class FakePage: PageController {
    let dataStoreID: UUID
    var url: URL?
    var title = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var icon: Data?
    var loadError: LoadError?
    var stopped = false
    var onRequest: (@MainActor (PageRequest) -> Void)?
    var sendsOtherSitesToLookout = false

    init(dataStoreID: UUID) { self.dataStoreID = dataStoreID }

    func load(_ url: URL) { self.url = url }
    func goBack() {}
    func goForward() {}
    func reload() {}
    func stopLoading() { stopped = true }
    func focus() {}
    func snapshot(width: CGFloat) async -> CGImage? { nil }
    func printPage() {}
    var zoom: Double = 1
    func setZoom(_ zoom: Double) { self.zoom = zoom }
    func find(_ text: String, _ direction: FindOnPage.Direction) async -> Int { 0 }
    func selectedText() async -> String { "" }
    /// Where it resumed from, if it woke from a sleep that kept its place.
    var resumedFrom: URL?
    var inUse = false
    func memory() -> PageMemory? { url.map { PageMemory(state: $0) } }
    func resume(from memory: PageMemory) {
        resumedFrom = memory.state as? URL
        url = resumedFrom
    }
    func isInUse() async -> Bool { inUse }
    var sound: PageSound = .silent
    func setMuted(_ muted: Bool) {}
}

@MainActor
struct BrowserStoreTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore() -> BrowserStore {
        BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func titles(_ store: BrowserStore) -> [String] {
        store.openTabs.map { $0.url?.host() ?? "" }
    }

    @Test func newTabOpensAtTheEndAndIsShown() {
        let store = makeStore()
        store.openTab(url("a"))
        let b = store.openTab(url("b"))
        #expect(titles(store) == ["a.example", "b.example"])
        #expect(store.activeTabID == b.id)
        #expect(b.page?.url == url("b"))
    }

    @Test func pagesUseTheirSpacesDataStore() {
        let store = makeStore()
        let tab = store.openTab(url("a"))
        #expect((tab.page as? FakePage)?.dataStoreID == space.dataStoreID)
    }

    @Test func linkOpensRightBelowItsOpener() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        let c = store.openTab(url("c"), opener: a)
        #expect(titles(store) == ["a.example", "c.example", "b.example"])
        #expect(c.openerTabID == a.id)
    }

    @Test func closingTheShownTabShowsTheOneBelow() {
        let store = makeStore()
        store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let c = store.openTab(url("c"))
        store.select(b)
        let page = b.page as? FakePage
        store.close(b)
        #expect(titles(store) == ["a.example", "c.example"])
        #expect(store.activeTabID == c.id)
        #expect(page?.stopped == true)
        #expect(b.page == nil)
    }

    @Test func closingTheLastTabInTheListShowsTheOneAbove() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        store.close(b)
        #expect(store.activeTabID == a.id)
    }

    @Test func closingABackgroundTabKeepsTheShownOne() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        store.close(a)
        #expect(store.activeTabID == b.id)
    }

    @Test func closingEveryTabLeavesNothingShown() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.close(a)
        #expect(store.openTabs.isEmpty)
        #expect(store.activeTabID == nil)
        #expect(store.activeTab == nil)
    }

    @Test func numberShortcutsAndCycling() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let c = store.openTab(url("c"))
        store.selectTab(at: 0)
        #expect(store.activeTabID == a.id)
        store.selectTab(at: 8) // ⌘9 means the last tab
        #expect(store.activeTabID == c.id)
        store.selectTab(by: 1)
        #expect(store.activeTabID == a.id)
        store.selectTab(by: -1)
        #expect(store.activeTabID == c.id)
        store.selectTab(by: -1)
        #expect(store.activeTabID == b.id)
    }

    @Test func moveReorders() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        let c = store.openTab(url("c"))
        store.move(c, to: 0)
        #expect(titles(store) == ["c.example", "a.example", "b.example"])
        store.move(a, to: 3)
        #expect(titles(store) == ["c.example", "b.example", "a.example"])
        store.move(a, to: 1)
        #expect(titles(store) == ["c.example", "a.example", "b.example"])
    }

    @Test func switchingUpdatesLastActive() {
        var clock = Date(timeIntervalSince1970: 0)
        let store = BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) }, now: { clock })
        let a = store.openTab(url("a"))
        clock = Date(timeIntervalSince1970: 100)
        store.openTab(url("b"))
        #expect(a.lastActiveAt == Date(timeIntervalSince1970: 100)) // left at 100
    }

    @Test func titleFallsBackToHost() {
        let store = makeStore()
        let tab = store.openTab(url("a"))
        #expect(tab.title == "a.example")
        (tab.page as? FakePage)?.title = "Hello"
        #expect(tab.title == "Hello")
    }

    // MARK: - Pages asking for tabs

    /// Has `tab`'s page ask the browser for something, as WebKit would.
    private func request(_ request: PageRequest, from tab: Tab) {
        (tab.page as? FakePage)?.onRequest?(request)
    }

    @Test func popupBecomesATabBelowItsOpenerAndIsShownAsIs() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.select(a)
        let popup = FakePage(dataStoreID: space.dataStoreID)
        request(.openPage(popup, inBackground: false), from: a)

        let tab = store.openTabs[1]
        #expect(tab.page === popup)
        #expect(popup.url == nil) // WebKit loads it; Firn mustn't load it again.
        #expect(tab.openerTabID == a.id)
        #expect(tab.spaceID == a.spaceID)
        #expect(store.activeTabID == tab.id)
    }

    @Test func backgroundLinksWaitInOrderWithoutSwitching() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.select(a)
        request(.openURL(url("c1"), inBackground: true), from: a)
        request(.openURL(url("c2"), inBackground: true), from: a)

        #expect(titles(store) == ["a.example", "c1.example", "c2.example", "b.example"])
        #expect(store.activeTabID == a.id)
        #expect(store.openTabs[1].page == nil) // Loads when first shown.
        store.select(store.openTabs[1])
        #expect(store.openTabs[1].page?.url == url("c1"))
    }

    @Test func popupClosingItselfHandsBackToItsOpener() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.select(a)
        request(.openPage(FakePage(dataStoreID: space.dataStoreID), inBackground: false), from: a)
        let popup = store.openTabs[1]
        request(.close, from: popup)

        #expect(titles(store) == ["a.example", "b.example"])
        #expect(store.activeTabID == a.id) // Not b, the neighbor.
    }

    @Test func closedTabsCantAskForAnything() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        let page = a.page as? FakePage
        store.close(a)
        page?.onRequest?(.openURL(url("c"), inBackground: false))
        #expect(titles(store) == ["b.example"])
    }

    /// The engine hands a popup to WebKit only if a tab took it in, which
    /// it tells by the page being listened to.
    @Test func onlyAPopupATabTookInIsListenedTo() {
        let store = makeStore()
        let opener = store.openTab(URL(string: "https://a.example")!)
        let taken = FakePage(dataStoreID: space.dataStoreID)
        store.handle(.openPage(taken, inBackground: false), from: opener)
        #expect(taken.onRequest != nil)

        store.close(opener)
        let refused = FakePage(dataStoreID: space.dataStoreID)
        store.handle(.openPage(refused, inBackground: false), from: opener)
        #expect(refused.onRequest == nil)
    }
}
