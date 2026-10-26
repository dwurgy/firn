import Foundation
import Testing
@testable import FirnCore

@MainActor
struct TabSwitcherTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    /// A store whose clock moves on a second each time it's read, so every
    /// switch happens at its own time.
    private func makeStore(spaces: [Space]? = nil) -> BrowserStore {
        var seconds = 0.0
        return BrowserStore(spaces: spaces ?? [space], makePage: { FakePage(dataStoreID: $0) }, now: {
            seconds += 1
            return Date(timeIntervalSince1970: seconds)
        })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    // MARK: - The order

    @Test func theTabOnScreenLeadsThenTheMostRecentlyLeft() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let c = store.openTab(url("c"))
        store.select(a)
        #expect(store.recentRows.map(\.id) == [a.id, c.id, b.id])
        store.select(b)
        #expect(store.recentRows.map(\.id) == [b.id, a.id, c.id])
    }

    @Test func tilesAndFoldedGroupsCount() throws {
        let store = makeStore()
        let tile = store.openTab(url("tile"))
        #expect(store.addToBasecamp(tile))
        let grouped = store.openTab(url("grouped"))
        let group = try #require(store.newGroup(with: grouped))
        let loose = store.openTab(url("loose"))
        store.setFolded(group, true)
        store.select(tile)
        #expect(store.recentRows.map(\.id) == [tile.id, loose.id, grouped.id])
    }

    @Test func aSplitCountsOnceAsItsHalfUsedLast() throws {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let c = store.openTab(url("c"))
        _ = try #require(store.openSplit(b, beside: a))
        store.select(b)
        store.select(c)
        #expect(store.recentRows.map(\.id) == [c.id, b.id])
    }

    @Test func onlyTheSpaceOnScreen() {
        let other = Space(name: "Work", color: "sage", order: 1, dataStoreID: UUID())
        let store = makeStore(spaces: [space, other])
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        store.selectSpace(other)
        let w = store.openTab(url("w"))
        #expect(store.recentRows.map(\.id) == [w.id])
        store.selectSpace(space)
        #expect(Set(store.recentRows.map(\.id)) == [a.id, b.id])
    }

    // MARK: - Picking

    @Test func startsOnTheTabUsedBeforeOrTheOldestGoingBack() throws {
        let ids = (0..<3).map { _ in UUID() }
        #expect(try #require(TabSwitcher(tabIDs: ids)).pickedID == ids[1])
        #expect(try #require(TabSwitcher(tabIDs: ids, backward: true)).pickedID == ids[2])
    }

    @Test func showsAtMostFiveAndNeedsTwo() {
        let ids = (0..<8).map { _ in UUID() }
        #expect(TabSwitcher(tabIDs: ids)?.tabIDs == Array(ids.prefix(5)))
        #expect(TabSwitcher(tabIDs: [UUID()]) == nil)
        #expect(TabSwitcher(tabIDs: []) == nil)
    }

    @Test func movingWrapsAround() throws {
        let ids = (0..<3).map { _ in UUID() }
        var switcher = try #require(TabSwitcher(tabIDs: ids))
        switcher.move(by: 1)
        #expect(switcher.pickedID == ids[2])
        switcher.move(by: 1)
        #expect(switcher.pickedID == ids[0])
        switcher.move(by: -1)
        #expect(switcher.pickedID == ids[2])
        switcher.pick(ids[0])
        #expect(switcher.pickedID == ids[0])
        switcher.pick(UUID())
        #expect(switcher.pickedID == ids[0])
    }
}
