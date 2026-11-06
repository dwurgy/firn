import Foundation
import Testing
@testable import FirnCore

/// The tab a link opened a tab from: on iPhone and iPad, Back on a tab with
/// nowhere to go back closes it and shows that one, as in Safari.
@MainActor
struct OpenerTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore() -> BrowserStore {
        BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    @Test func aTabKnowsTheTabThatOpenedIt() {
        let store = makeStore()
        let first = store.openTab(url("a"))
        let opened = store.openTab(url("b"), opener: first)
        #expect(store.opener(of: opened)?.id == first.id)
        #expect(store.opener(of: first) == nil)
    }

    @Test func aClosedOpenerIsGone() {
        let store = makeStore()
        let first = store.openTab(url("a"))
        let opened = store.openTab(url("b"), opener: first)
        store.close(first)
        #expect(store.opener(of: opened) == nil)
    }

    @Test func closingShowingTheOpenerGoesBackToIt() {
        let store = makeStore()
        let first = store.openTab(url("a"))
        store.openTab(url("c"))
        let opened = store.openTab(url("b"), opener: first)
        store.close(opened, showing: store.opener(of: opened))
        #expect(store.activeTab?.id == first.id)
    }
}
