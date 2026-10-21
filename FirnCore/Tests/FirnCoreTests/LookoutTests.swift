import Foundation
import Testing
@testable import FirnCore

@MainActor
struct LookoutTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())
    private let work = Space(name: "Work", icon: "work", color: "sand", order: 1, dataStoreID: UUID())

    private func makeStore() -> BrowserStore {
        BrowserStore(spaces: [space, work], makePage: { FakePage(dataStoreID: $0) })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    @Test func shiftClickOpensALookoutInTheSpacesStore() throws {
        let store = makeStore()
        let tab = store.openTab(url("a"))
        tab.page?.onRequest?(.openInLookout(url("b")))
        let page = try #require(store.lookout?.page as? FakePage)
        #expect(page.url == url("b"))
        #expect(page.dataStoreID == space.dataStoreID)
        #expect(store.openTabs.count == 1)
        #expect(store.activeTabID == tab.id)
    }

    @Test func onlyTheTabOnScreenOpensALookout() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        a.page?.onRequest?(.openInLookout(url("c")))
        #expect(store.lookout == nil)
    }

    @Test func onlyWebAddresses() {
        let store = makeStore()
        store.openLookout(URL(string: "file:///etc/passwd")!)
        store.openLookout(URL(string: "javascript:alert(1)")!)
        #expect(store.lookout == nil)
    }

    @Test func aNewLookoutReplacesTheOld() throws {
        let store = makeStore()
        store.openLookout(url("a"))
        let first = try #require(store.lookout?.page as? FakePage)
        store.openLookout(url("b"))
        #expect(first.stopped)
        #expect(store.lookout?.page.url == url("b"))
    }

    @Test func keepingMakesATabWithTheSamePage() throws {
        let store = makeStore()
        store.openTab(url("a"))
        store.openLookout(url("b"))
        let page = try #require(store.lookout?.page)
        let kept = try #require(store.keepLookout())
        #expect(store.lookout == nil)
        #expect(kept.page === page)
        #expect(store.activeTabID == kept.id)
        #expect(store.openTabs.map(\.id).last == kept.id)
    }

    @Test func keptTabGoesWhereNewTabsGo() throws {
        let store = makeStore()
        store.newTabPlacement = .top
        store.openTab(url("a"))
        store.openLookout(url("b"))
        let kept = try #require(store.keepLookout())
        #expect(store.openTabs.first?.id == kept.id)
    }

    @Test func showingAnotherTabOrSpaceClosesIt() throws {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.openLookout(url("c"))
        let page = try #require(store.lookout?.page as? FakePage)
        store.select(a)
        #expect(store.lookout == nil)
        #expect(page.stopped)

        store.openLookout(url("c"))
        store.selectSpace(work)
        #expect(store.lookout == nil)
    }

    @Test func stoppingSharingClosesIt() {
        let store = makeStore()
        let shared = store.addSpace(name: "Shared", icon: "home", color: "sage", sharingWith: space)
        store.openLookout(url("a"))
        store.stopSharing(shared)
        #expect(store.lookout == nil)
    }

    @Test func linksInsideStayInside() {
        let store = makeStore()
        store.openLookout(url("a"))
        store.lookout?.page.onRequest?(.openInLookout(url("b")))
        #expect(store.lookout?.page.url == url("b"))
        #expect(store.openTabs.isEmpty)
    }

    @Test func commandClickInsideOpensATab() {
        let store = makeStore()
        store.openLookout(url("a"))
        store.lookout?.page.onRequest?(.openURL(url("b"), inBackground: true))
        #expect(store.openTabs.map(\.url) == [url("b")])
        #expect(store.lookout != nil)
    }

    @Test func aPopupKeepsTheLookoutAsItsOpener() throws {
        let store = makeStore()
        store.openLookout(url("a"))
        let lookoutPage = try #require(store.lookout?.page)
        let popup = FakePage(dataStoreID: space.dataStoreID)
        lookoutPage.onRequest?(.openPage(popup, inBackground: false))
        #expect(store.lookout == nil)
        let tabs = store.openTabs
        #expect(tabs.count == 2)
        #expect(tabs[0].page === lookoutPage)
        #expect(tabs[1].page === popup)
        #expect(tabs[1].openerTabID == tabs[0].id)
        #expect(store.activeTabID == tabs[1].id)
    }

    @Test func aClosedLookoutHearsNothing() throws {
        let store = makeStore()
        store.openLookout(url("a"))
        let page = try #require(store.lookout?.page)
        let request = try #require(page.onRequest)
        store.closeLookout()
        request(.openURL(url("b"), inBackground: false))
        #expect(store.openTabs.isEmpty)
        #expect(page.onRequest == nil)
    }
}
