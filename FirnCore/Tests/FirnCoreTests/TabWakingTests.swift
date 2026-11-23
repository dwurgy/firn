import Foundation
import Testing
@testable import FirnCore

/// What the address bar may show while a woken page hasn't arrived
/// (`Tab.addressWhileWaking`): the address the tab was at, never one that
/// nothing has loaded yet.
@MainActor
struct TabWakingTests {
    private let address = URL(string: "https://example.com/article")!

    /// A page that, as WebKit's, has no address until one commits.
    private func wake(_ tab: Tab) -> FakePage {
        var made: FakePage?
        tab.wake {
            let page = FakePage(dataStoreID: UUID())
            made = page
            return page
        }
        made!.url = nil
        return made!
    }

    @Test func aTabThatHadBeenThereShowsItsAddressWhileWaking() {
        let tab = Tab(spaceID: UUID(), url: address, title: "An article", lastActiveAt: .now)
        #expect(tab.addressWhileWaking == nil)
        _ = wake(tab)
        #expect(tab.addressWhileWaking == address)
    }

    @Test func aTabPutToSleepShowsWhereItWasWhileWaking() {
        let page = FakePage(dataStoreID: UUID())
        page.url = address
        page.title = "An article"
        let tab = Tab(spaceID: UUID(), url: address, lastActiveAt: .now, page: page)
        #expect(tab.addressWhileWaking == nil)
        tab.sleep()
        _ = wake(tab)
        #expect(tab.addressWhileWaking == address)
    }

    @Test func aTabJustOpenedNeverShowsAnAddressNothingHasLoaded() {
        // As a link or a typed address opens one: an address, no title.
        let tab = Tab(spaceID: UUID(), url: address, lastActiveAt: .now)
        _ = wake(tab)
        #expect(tab.addressWhileWaking == nil)
    }

    @Test func thePagesOwnAddressTakesOver() {
        let tab = Tab(spaceID: UUID(), url: address, title: "An article", lastActiveAt: .now)
        let page = wake(tab)
        let elsewhere = URL(string: "https://elsewhere.example/")!
        page.commit(elsewhere)
        #expect(tab.addressWhileWaking == nil)
        #expect(tab.url == elsewhere)
    }

    @Test func aFailedLoadShowsNoWakingAddress() {
        let tab = Tab(spaceID: UUID(), url: address, title: "An article", lastActiveAt: .now)
        let page = wake(tab)
        page.loadError = LoadError(url: address, reason: .offline)
        #expect(tab.addressWhileWaking == nil)
    }

    @Test func aPageThatIsAlreadyThereHasNoWakingAddress() {
        // A page a page opened (a popup) arrives awake, with no address yet.
        let page = FakePage(dataStoreID: UUID())
        let tab = Tab(spaceID: UUID(), url: address, title: "An article", lastActiveAt: .now, page: page)
        #expect(tab.addressWhileWaking == nil)
    }
}
