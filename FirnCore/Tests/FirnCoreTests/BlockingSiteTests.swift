import Foundation
import Testing
@testable import FirnCore

/// Turning blocking off for one site, per space (CLAUDE.md, ad and tracker blocking step 3).
@MainActor
struct BlockingSiteTests {
    private let work = Space(name: "Work", color: "glacier", order: 0, dataStoreID: UUID())

    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func aSiteIsItsHostWithoutWWW() {
        #expect(BlockingSite.of(url("https://www.Example.com/news")) == "example.com")
        #expect(BlockingSite.of(url("http://shop.example.com")) == "shop.example.com")
        #expect(BlockingSite.of(url("file:///Users/me/a.html")) == nil)
        #expect(BlockingSite.of(url("about:blank")) == nil)
    }

    @Test func offForASiteCoversItsSubdomainsOnly() {
        let store = BrowserStore(spaces: [work], makePage: { FakePage(dataStoreID: $0) })
        store.setBlocksContent(false, on: url("https://www.example.com/a"))
        #expect(store.activeSpace.blockingOffSites == ["example.com"])
        #expect(!store.blocksContent(on: url("https://example.com/")))
        #expect(!store.blocksContent(on: url("https://shop.example.com/")))
        #expect(store.blocksContent(on: url("https://notexample.com/")))
        #expect(store.blocksContent(on: url("https://example.com.evil.test/")))
    }

    @Test func turningItBackOnClearsAWiderSite() {
        let store = BrowserStore(spaces: [work], makePage: { FakePage(dataStoreID: $0) })
        store.setBlocksContent(false, on: url("https://example.com/"))
        store.setBlocksContent(false, on: url("https://shop.example.com/"))
        #expect(store.activeSpace.blockingOffSites == ["example.com"])
        store.setBlocksContent(true, on: url("https://shop.example.com/"))
        #expect(store.activeSpace.blockingOffSites.isEmpty)
    }

    @Test func eachSpaceKeepsItsOwnEvenWhenSharing() {
        let store = BrowserStore(spaces: [work], makePage: { FakePage(dataStoreID: $0) })
        store.setBlocksContent(false, on: url("https://example.com/"))
        let shared = store.addSpace(name: "Shared", color: "sage", sharingWith: work)
        #expect(store.activeSpaceID == shared.id)
        #expect(store.blocksContent(on: url("https://example.com/")))
    }

    @Test func pagesAskTheirOwnSpace() throws {
        let store = BrowserStore(spaces: [work], makePage: { FakePage(dataStoreID: $0) })
        let tab = store.openTab(url("https://example.com/"))
        let other = store.addSpace(name: "Personal", color: "sage")
        store.openLookout(url("https://example.com/"))
        let tabAsks = try #require(tab.page?.blocksContent)
        let lookoutAsks = try #require(store.lookout?.page.blocksContent)
        store.selectSpace(work)
        store.setBlocksContent(false, on: url("https://example.com/"))
        #expect(!tabAsks(url("https://example.com/")))
        #expect(lookoutAsks(url("https://example.com/")))
        #expect(store.spaces.first { $0.id == other.id }?.blockingOffSites.isEmpty == true)
    }

    @Test func theListIsSavedAndOldFilesStillLoad() throws {
        var space = work
        space.blockingOffSites = ["example.com"]
        let again = try JSONDecoder().decode(Space.self, from: JSONEncoder().encode(space))
        #expect(again.blockingOffSites == ["example.com"])

        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(work)) as? [String: Any])
        old["blockingOffSites"] = nil
        let loaded = try JSONDecoder().decode(Space.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(loaded.blockingOffSites.isEmpty)
    }

    @Test func aDamagedListIsCleaned() {
        #expect(BlockingSite.clean(["example.com", "Example.com", "a b", "", "www.x.com", "example.com", "x.test"])
            == ["example.com", "x.test"])
    }
}
