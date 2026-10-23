import Foundation
import Testing
@testable import FirnCore

/// The mini player: a tab out of sight in this space, playing or paused from it.
@MainActor
struct MiniPlayerTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore() -> BrowserStore {
        BrowserStore(restoring: nil, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    @Test func showsATabPlayingOutOfSight() throws {
        let store = makeStore()
        let music = store.openTab(url("music"))
        let page = try #require(music.page as? FakePage)
        page.sound = .playing
        #expect(store.miniPlayerTab == nil)
        store.openTab(url("work"))
        #expect(store.miniPlayerTab?.id == music.id)
        page.sound = .silent
        #expect(store.miniPlayerTab == nil)
    }

    @Test func staysWhilePausedAndLetsGoOnScreen() throws {
        let store = makeStore()
        let music = store.openTab(url("music"))
        let page = try #require(music.page as? FakePage)
        page.sound = .playing
        store.openTab(url("work"))
        music.togglePaused()
        page.sound = .silent
        #expect(store.miniPlayerTab?.id == music.id)
        store.select(music)
        #expect(!music.isPausedByFirn)
        store.openTab(url("more"))
        #expect(store.miniPlayerTab == nil)
    }

    @Test func picksTheOneLookedAtLast() throws {
        let store = makeStore()
        let first = store.openTab(url("first"))
        let second = store.openTab(url("second"))
        for tab in [first, second] { try #require(tab.page as? FakePage).sound = .playing }
        store.openTab(url("work"))
        #expect(store.miniPlayerTab?.id == second.id)
    }

    @Test func neverShowsAnotherSpacesTab() throws {
        let store = makeStore()
        let music = store.openTab(url("music"))
        try #require(music.page as? FakePage).sound = .playing
        store.addSpace(name: "Work", icon: "leaf", color: "sage")
        #expect(store.miniPlayerTab == nil)
    }
}
