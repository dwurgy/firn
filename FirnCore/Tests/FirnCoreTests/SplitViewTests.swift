import Foundation
import Testing
@testable import FirnCore

/// Split view: two everyday tabs side by side, kept together in the tab
/// list, never drifting, and Basecamp tiles never leaving Basecamp.
@MainActor
struct SplitViewTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private final class Clock {
        var date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!
        func advance(days: Int) { date = Calendar.current.date(byAdding: .day, value: days, to: date)! }
    }

    private func makeStore(restoring session: Session? = nil, now: @escaping () -> Date = Date.init) -> BrowserStore {
        BrowserStore(restoring: session, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) }, now: now)
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func hosts(_ tabs: [FirnCore.Tab]) -> [String] {
        tabs.map { $0.url?.host() ?? "" }
    }

    private func save(_ store: BrowserStore) -> Session {
        store.session(sidebarWidth: 300, sidebarCollapsed: false)
    }

    /// Opens tabs named a, b, c, … in order.
    private func open(_ names: String..., in store: BrowserStore) -> [FirnCore.Tab] {
        names.map { store.openTab(url($0)) }
    }

    // MARK: - Making one

    @Test func aTabJoinsTheOneOnScreenOnTheChosenSide() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let split = try #require(store.openSplit(tabs[3], beside: tabs[1]))
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "d.example", "c.example"])
        #expect(hosts(store.tabs(in: split)) == ["b.example", "d.example"])
        #expect(store.activeTabID == tabs[3].id)
        #expect(store.splitPartner(of: tabs[3])?.id == tabs[1].id)
        #expect(split.leftFraction == 0.5)
        // Both halves are awake, since both are on screen.
        #expect(!tabs[1].isResting && !tabs[3].isResting)

        let other = try #require(store.openSplit(tabs[0], beside: tabs[2], on: .left))
        #expect(hosts(store.tabs(in: other)) == ["a.example", "c.example"])
    }

    @Test func aPairCanSwapSides() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let split = try #require(store.openSplit(tabs[1], beside: tabs[0]))
        #expect(store.openSplit(tabs[1], beside: tabs[0], on: .left)?.id == split.id)
        #expect(hosts(store.tabs(in: split)) == ["b.example", "a.example"])
        #expect(store.splits.count == 1)
    }

    @Test func aTabCantSplitWithItselfOrAnotherSpace() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        #expect(store.openSplit(a, beside: a) == nil)
        let other = store.addSpace(name: "Work", color: "sand")
        store.selectSpace(other)
        let b = store.openTab(url("b"))
        #expect(store.openSplit(b, beside: a) == nil)
        #expect(store.splits.isEmpty)
    }

    @Test func aTabFromAGroupJoinsTheOtherTabsGroup() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        // b leaves the group to sit beside loose c.
        store.openSplit(tabs[1], beside: tabs[2])
        #expect(hosts(store.tabs(in: group)) == ["a.example"])
        #expect(tabs[1].groupID == nil)
        // a's group's only tab leaves: the group ends.
        store.openSplit(tabs[0], beside: tabs[2], on: .left)
        #expect(store.tabGroups.isEmpty)
    }

    @Test func droppingOnAHalfReplacesIt() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let first = try #require(store.openSplit(tabs[1], beside: tabs[0]))
        // c dropped on b's half: b leaves, right below the new pair.
        let second = try #require(store.openSplit(tabs[2], beside: tabs[0]))
        #expect(!store.splits.contains { $0.id == first.id })
        #expect(hosts(store.tabs(in: second)) == ["a.example", "c.example"])
        #expect(hosts(store.openTabs) == ["a.example", "c.example", "b.example"])
        #expect(tabs[1].splitID == nil)

        // Dropped on the left half instead: the left one leaves.
        let third = try #require(store.openSplit(tabs[1], beside: tabs[2], on: .left))
        #expect(hosts(store.tabs(in: third)) == ["b.example", "c.example"])
        #expect(hosts(store.openTabs) == ["b.example", "c.example", "a.example"])
    }

    @Test func aTabFromAnotherSplitEndsThatSplit() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        store.openSplit(tabs[3], beside: tabs[2])
        store.openSplit(tabs[1], beside: tabs[2])
        #expect(store.splits.count == 1)
        #expect(tabs[0].splitID == nil)
        #expect(tabs[3].splitID == nil)
        #expect(store.splitPartner(of: tabs[1])?.id == tabs[2].id)
    }

    // MARK: - Basecamp

    @Test func aTileIsCopiedAndNeverLeavesBasecamp() throws {
        let store = makeStore()
        store.newTabPlacement = .bottom
        let tabs = open("tile", "a", "b", in: store)
        store.addToBasecamp(tabs[0])
        // The tile dropped beside a: a copy of it sits beside a.
        let split = try #require(store.openSplit(tabs[0], beside: tabs[1]))
        #expect(hosts(store.basecampTabs) == ["tile.example"])
        #expect(tabs[0].splitID == nil)
        let pair = store.tabs(in: split)
        #expect(hosts(pair) == ["a.example", "tile.example"])
        #expect(pair[1].id != tabs[0].id)
        #expect(pair[1].place == .open && pair[1].homeURL == nil)
        #expect(store.activeTabID == pair[1].id)
    }

    @Test func splittingFromATileCopiesItWhereNewTabsGo() throws {
        let store = makeStore()
        store.newTabPlacement = .top
        let tabs = open("tile", "a", "b", in: store)
        store.addToBasecamp(tabs[0])
        store.select(tabs[0])
        let split = try #require(store.openSplit(tabs[2], beside: tabs[0]))
        #expect(hosts(store.basecampTabs) == ["tile.example"])
        #expect(hosts(store.openTabs) == ["tile.example", "b.example", "a.example"])
        #expect(hosts(store.tabs(in: split)) == ["tile.example", "b.example"])
    }

    @Test func aTidiedTabComesBackToSplit() throws {
        let clock = Clock()
        let store = makeStore(now: { clock.date })
        store.driftAfter = .oneDay
        let tabs = open("a", "b", in: store)
        clock.advance(days: 1)
        store.driftIdleTabs()
        clock.advance(days: 1)
        store.driftIdleTabs()
        #expect(tabs[0].place == .drifted)
        let split = try #require(store.openSplit(tabs[0], beside: tabs[1]))
        #expect(tabs[0].place == .open && tabs[0].driftedAt == nil)
        #expect(hosts(store.tabs(in: split)) == ["b.example", "a.example"])
    }

    // MARK: - Ending one

    @Test func closingTheSplitLeavesTwoTabsInPlace() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let split = try #require(store.openSplit(tabs[2], beside: tabs[0]))
        store.closeSplit(split)
        #expect(store.splits.isEmpty)
        #expect(tabs[0].splitID == nil && tabs[2].splitID == nil)
        #expect(hosts(store.openTabs) == ["a.example", "c.example", "b.example"])
        #expect(store.activeTabID == tabs[2].id)
    }

    @Test func closingOneHalfShowsTheOther() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.openSplit(tabs[0], beside: tabs[2])
        store.close(tabs[0])
        #expect(store.splits.isEmpty)
        #expect(tabs[2].splitID == nil)
        #expect(store.activeTabID == tabs[2].id)
        // ⇧⌘T brings it back as an ordinary tab.
        store.reopenClosed()
        #expect(tabs[0].splitID == nil)
    }

    @Test func closingAGroupEndsItsSplits() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.openSplit(tabs[1], beside: tabs[0])
        store.close(group)
        #expect(store.splits.isEmpty)
        store.reopenClosed()
        #expect(tabs[0].splitID == nil && tabs[1].splitID == nil)
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "c.example"])
    }

    @Test func theWidthStaysWithinLimits() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let split = try #require(store.openSplit(tabs[1], beside: tabs[0]))
        store.setLeftFraction(of: split, to: 0.05)
        #expect(store.splits[0].leftFraction == 0.3)
        store.setLeftFraction(of: split, to: .nan)
        #expect(store.splits[0].leftFraction == 0.5)
        store.setLeftFraction(of: split, to: 0.62)
        #expect(store.splits[0].leftFraction == 0.62)
    }

    // MARK: - Staying together

    @Test func movingEitherHalfMovesThePair() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        store.move(tabs[1], to: 3)
        #expect(hosts(store.openTabs) == ["c.example", "d.example", "a.example", "b.example"])
        store.move(tabs[0], to: 0)
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "c.example", "d.example"])
    }

    @Test func aTabDroppedBetweenTheHalvesGoesBelowThem() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        // Counting each tab, position 1 would land between a and b.
        store.move(tabs[2], to: 1)
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "c.example"])
    }

    @Test func aSplitIsOneRow() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        #expect(store.tabListItems.map(\.id) == [tabs[0].id, tabs[2].id, tabs[3].id])
        // Position 1 is just below the pair, whichever half is moved.
        store.move(tabs[3], to: 1)
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "d.example", "c.example"])
        store.move(tabs[1], to: 1)
        #expect(hosts(store.openTabs) == ["d.example", "a.example", "b.example", "c.example"])
        store.move(tabs[2], toGroup: nil, at: 1)
        #expect(hosts(store.openTabs) == ["d.example", "c.example", "a.example", "b.example"])
    }

    @Test func aSplitIsOneRowInAGroup() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.move(tabs[1], toEndOf: group)
        store.move(tabs[2], toEndOf: group)
        store.openSplit(tabs[1], beside: tabs[0])
        #expect(store.rows(in: group).map(\.id) == [tabs[0].id, tabs[2].id])
        // d dropped at 1 lands below the pair, not between its halves.
        store.move(tabs[3], into: group, at: 1)
        #expect(hosts(store.tabs(in: group)) == ["a.example", "b.example", "d.example", "c.example"])
        // The right half moved to the end brings its left half along.
        store.move(tabs[1], into: group, at: 2)
        #expect(hosts(store.tabs(in: group)) == ["d.example", "c.example", "a.example", "b.example"])
    }

    @Test func shortcutsCountASplitOnce() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        #expect(store.sidebarRows.map(\.id) == [tabs[0].id, tabs[2].id])
        store.selectTab(at: 1)
        #expect(store.activeTabID == tabs[2].id)
        store.selectTab(at: 0)
        #expect(store.activeTabID == tabs[0].id)
        // From the right half, the next row is c, not the left half.
        store.select(tabs[1])
        store.selectTab(by: 1)
        #expect(store.activeTabID == tabs[2].id)
        store.selectTab(by: 1)
        #expect(store.activeTabID == tabs[0].id)
    }

    @Test func addingAHalfToBasecampEndsTheSplit() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        store.addToBasecamp(tabs[1])
        #expect(store.splits.isEmpty)
        #expect(tabs[0].splitID == nil && tabs[1].splitID == nil)
    }

    @Test func groupingEitherHalfGroupsBoth() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        let group = try #require(store.newGroup(with: tabs[1]))
        #expect(hosts(store.tabs(in: group)) == ["a.example", "b.example"])
        store.takeOutOfGroup(tabs[0])
        #expect(store.tabGroups.isEmpty)
        #expect(tabs[0].groupID == nil && tabs[1].groupID == nil)

        let other = try #require(store.newGroup(with: tabs[2]))
        store.move(tabs[0], toEndOf: other)
        #expect(hosts(store.tabs(in: other)) == ["c.example", "a.example", "b.example"])
    }

    @Test func linksAndCopiesOpenBelowThePair() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        store.openTab(url("link"), opener: tabs[0])
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "link.example", "c.example"])
        store.duplicate(tabs[0])
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "a.example", "link.example", "c.example"])
        #expect(store.splits.count == 1)
    }

    @Test func splitTabsNeverDrift() throws {
        let clock = Clock()
        let store = makeStore(now: { clock.date })
        store.driftAfter = .oneDay
        let tabs = open("a", "b", "c", "shown", in: store)
        store.openSplit(tabs[1], beside: tabs[0])
        store.select(tabs[3])
        for _ in 0 ..< 3 {
            clock.advance(days: 1)
            store.driftIdleTabs()
        }
        #expect(hosts(store.driftedTabs) == ["c.example"])
        #expect(hosts(store.openTabs) == ["a.example", "b.example", "shown.example"])
    }

    @Test func endingASplitOnScreenKeepsBothFromDrifting() throws {
        let clock = Clock()
        let store = makeStore(now: { clock.date })
        store.driftAfter = .oneDay
        let tabs = open("a", "b", in: store)
        let split = try #require(store.openSplit(tabs[1], beside: tabs[0]))
        clock.advance(days: 2)
        store.closeSplit(split)
        // a was on screen as the other half until just now.
        #expect(store.idleTabs().isEmpty)
    }

    // MARK: - Saving

    @Test func splitsComeBackAfterQuitting() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[2]))
        let split = try #require(store.openSplit(tabs[0], beside: tabs[2]))
        store.setLeftFraction(of: split, to: 0.4)

        let restored = makeStore(restoring: save(store))
        #expect(restored.splits == [SplitGroup(id: split.id, spaceID: space.id, leftFraction: 0.4)])
        let pair = restored.tabs(in: restored.splits[0])
        #expect(hosts(pair) == ["c.example", "a.example"])
        #expect(pair.allSatisfy { $0.groupID == group.id })
        #expect(restored.activeTabID == tabs[0].id)
        #expect(pair.allSatisfy { !$0.isResting })
    }

    @Test func aBrokenSavedSplitIsDropped() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let split = try #require(store.openSplit(tabs[1], beside: tabs[0]))
        var session = save(store)
        // A third tab claims the same split: none of them stay split.
        let index = try #require(session.tabs.firstIndex { $0.id == tabs[2].id })
        session.tabs[index].splitID = split.id
        let restored = makeStore(restoring: session)
        #expect(restored.splits.isEmpty)
        #expect(restored.openTabs.allSatisfy { $0.splitID == nil })

        // A pair split apart in the file goes back together.
        var apart = save(store)
        let b = try #require(apart.tabs.firstIndex { $0.id == tabs[1].id })
        apart.tabs[b].order = 99
        let rejoined = makeStore(restoring: apart)
        #expect(hosts(rejoined.openTabs) == ["a.example", "b.example", "c.example"])
    }

    @Test func filesFromBeforeSplitViewStillLoad() throws {
        let store = makeStore()
        open("a", "b", in: store)
        let data = try JSONEncoder().encode(save(store))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["splits"] = nil
        let old = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.splits.isEmpty)
        #expect(makeStore(restoring: old).openTabs.count == 2)
    }

    // MARK: - Dragging onto the page

    @Test func droppingOnAHalfOfOnePageOpensASplitThere() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.select(tabs[0])
        let split = try #require(store.dropOnPage(tabs[2], on: .left))
        #expect(hosts(store.tabs(in: split)) == ["c.example", "a.example"])
        #expect(store.activeTabID == tabs[2].id)
    }

    @Test func droppingOnAHalfOfASplitReplacesThatHalf() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let split = try #require(store.openSplit(tabs[1], beside: tabs[0]))
        let replaced = try #require(store.dropOnPage(tabs[3], on: .left))
        #expect(replaced.id != split.id)
        #expect(hosts(store.tabs(in: replaced)) == ["d.example", "b.example"])
        // The replaced half goes right below the pair.
        #expect(hosts(store.openTabs) == ["d.example", "b.example", "a.example", "c.example"])
        #expect(tabs[0].splitID == nil)
    }

    @Test func whatsOnScreenAndSplitsCantBeDropped() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        try #require(store.openSplit(tabs[1], beside: tabs[0]))
        #expect(!store.canDropOnPage(tabs[0]))
        #expect(!store.canDropOnPage(tabs[1]))
        #expect(store.canDropOnPage(tabs[2]))
        store.select(tabs[2])
        // A split not on screen is two pages already.
        #expect(!store.canDropOnPage(tabs[0]))
        #expect(store.dropOnPage(tabs[2], on: .right) == nil)
    }

    @Test func aTileDroppedOnThePageStaysInBasecamp() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        #expect(store.addToBasecamp(tabs[1]))
        store.select(tabs[0])
        let split = try #require(store.dropOnPage(tabs[1], on: .right))
        #expect(store.basecampTabs.map(\.id) == [tabs[1].id])
        #expect(hosts(store.tabs(in: split)) == ["a.example", "b.example"])
        #expect(store.tabs(in: split).allSatisfy { $0.place == .open })
    }
}
