import Foundation
import Testing
@testable import FirnCore

@MainActor
struct GroupsTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())

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

    // MARK: - Making groups

    @Test func newGroupsCountUpSoNamesNeverRepeat() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        let second = try #require(store.newGroup(with: tabs[1]))
        let third = try #require(store.newGroup(with: tabs[2]))
        #expect([first, second, third].map(\.name) == ["New Group", "New Group 2", "New Group 3"])
        // A renamed group frees its name for the next one.
        store.rename(second, to: "Trip")
        let fourth = try #require(store.newGroup(with: tabs[3]))
        #expect(fourth.name == "New Group 2")
    }

    @Test func aNewGroupStaysWhereItsTabWas() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        #expect(group.name == "New Group")
        #expect(store.tabGroups.map(\.id) == [group.id])
        #expect(hosts(store.tabs(in: group)) == ["b.example"])
        #expect(hosts(store.looseTabs) == ["a.example", "c.example"])
        #expect(store.tabListItems.map(\.id) == [tabs[0].id, group.id, tabs[2].id])
        #expect(hosts(store.sidebarTabs) == ["a.example", "b.example", "c.example"])
    }

    @Test func aTabTakenFromAGroupStartsItsNewOneJustBelow() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        let second = try #require(store.newGroup(with: tabs[0]))
        #expect(store.tabListItems.map(\.id) == [first.id, second.id, tabs[2].id])
        #expect(hosts(store.tabs(in: first)) == ["b.example"])
    }

    @Test func groupsAndLooseTabsShareOneOrder() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[0], with: tabs[1])
        // c, then the group (b, a).
        store.move(tabs[2], to: 0)
        #expect(store.tabListItems.map(\.id) == [tabs[2].id, group.id])
        // Out of the group, below it; the group itself counts as one.
        store.move(tabs[0], toGroup: nil, at: 2)
        #expect(store.tabListItems.map(\.id) == [tabs[2].id, group.id, tabs[0].id])
        store.move(group, to: 2)
        #expect(store.tabListItems.map(\.id) == [tabs[2].id, tabs[0].id, group.id])
        // Tab shortcuts go down the list as it's shown.
        #expect(hosts(store.sidebarTabs) == ["c.example", "a.example", "b.example"])
    }

    @Test func linksNeverLandInsideAGroup() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        let first = store.openTab(url("link1"), opener: tabs[0], inBackground: true)
        store.move(first, into: group, at: 0)
        // link1 sits right below a, but in the group; link2 stays out of it.
        store.openTab(url("link2"), opener: tabs[0], inBackground: true)
        #expect(hosts(store.tabs(in: group)) == ["link1.example", "b.example"])
        #expect(store.tabListItems.map(\.id).last == group.id)
        #expect(hosts(store.looseTabs) == ["a.example", "link2.example"])
    }

    @Test func droppingATabOnALooseTabStartsAGroupOfTwo() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        store.group(tabs[2], with: tabs[0])
        let group = try #require(store.tabGroups.first)
        #expect(hosts(store.tabs(in: group)) == ["a.example", "c.example"])
        #expect(hosts(store.looseTabs) == ["b.example"])
    }

    @Test func droppingATabOnAGroupedTabJoinsJustAfterIt() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        store.group(tabs[2], with: tabs[0])
        #expect(hosts(store.tabs(in: group)) == ["a.example", "c.example", "b.example"])
        // Moving within the group: a dropped after b.
        store.group(tabs[0], with: tabs[1])
        #expect(hosts(store.tabs(in: group)) == ["c.example", "b.example", "a.example"])
        #expect(store.tabGroups.count == 1)
    }

    @Test func basecampTilesDontJoinGroups() {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        store.addToBasecamp(tabs[0])
        #expect(store.newGroup(with: tabs[0]) == nil)
        store.group(tabs[0], with: tabs[1])
        store.group(tabs[1], with: tabs[0])
        #expect(store.tabGroups.isEmpty)
    }

    // MARK: - Moving tabs in and out

    @Test func movingATabIntoAGroupAtAPosition() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.move(tabs[1], into: group, at: 1)
        store.move(tabs[2], into: group, at: 0)
        #expect(hosts(store.tabs(in: group)) == ["c.example", "a.example", "b.example"])
        store.move(tabs[1], to: 0) // Reorders within the group.
        #expect(hosts(store.tabs(in: group)) == ["b.example", "c.example", "a.example"])
    }

    @Test func takingATabOutPutsItRightBelowTheGroup() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let group = try #require(store.newGroup(with: tabs[2]))
        store.group(tabs[0], with: tabs[2])
        store.group(tabs[3], with: tabs[2])
        store.move(group, to: 0)
        // The group (c, d, a) sits at the top; new tabs go at the bottom.
        store.takeOutOfGroup(tabs[2])
        #expect(hosts(store.tabs(in: group)) == ["d.example", "a.example"])
        #expect(store.tabListItems.map(\.id) == [group.id, tabs[2].id, tabs[1].id])
        // The setting doesn't matter: it stays by the group.
        store.newTabPlacement = .top
        store.takeOutOfGroup(tabs[0])
        #expect(store.tabListItems.map(\.id) == [group.id, tabs[0].id, tabs[2].id, tabs[1].id])
        // Dragged out, it goes where it was dropped.
        store.takeOutOfGroup(tabs[3], to: 3)
        #expect(hosts(store.looseTabs) == ["a.example", "c.example", "b.example", "d.example"])
        #expect(store.tabGroups.isEmpty) // Its last tab left.
    }

    @Test func newTabsGoAtTheTopOrTheBottom() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.openTab(url("c")) // Bottom: below the group.
        #expect(store.tabListItems.last?.id == store.activeTabID)
        store.newTabPlacement = .top
        let d = store.openTab(url("d")) // Top: above everything.
        #expect(store.tabListItems.map(\.id).prefix(2) == [d.id, tabs[0].id])
        #expect(hosts(store.tabs(in: group)) == ["b.example"])
    }

    @Test func movingTheLastTabToAnotherGroupEndsTheOldOne() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        let second = try #require(store.newGroup(with: tabs[1]))
        store.move(tabs[0], into: second, at: 0)
        #expect(store.tabGroups.map(\.id) == [second.id])
        #expect(!store.groups.contains { $0.id == first.id })
    }

    @Test func aDraggedTabLandsWhereItIsDropped() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        let second = try #require(store.newGroup(with: tabs[1]))
        // Loose into a group, after its tab.
        store.move(tabs[2], toGroup: first, at: 1)
        #expect(hosts(store.tabs(in: first)) == ["a.example", "c.example"])
        // Group to group.
        store.move(tabs[2], toGroup: second, at: 0)
        #expect(hosts(store.tabs(in: second)) == ["c.example", "b.example"])
        // Out of a group, to the bottom (below both groups and d).
        store.move(tabs[2], toGroup: nil, at: 3)
        #expect(tabs[2].groupID == nil)
        #expect(hosts(store.looseTabs) == ["d.example", "c.example"])
        // Loose to loose.
        store.move(tabs[2], toGroup: nil, at: 0)
        #expect(hosts(store.looseTabs) == ["c.example", "d.example"])
        // The last tab out of a group ends it.
        store.move(tabs[0], toGroup: nil, at: 0)
        #expect(store.tabGroups.map(\.id) == [second.id])
        #expect(hosts(store.looseTabs) == ["a.example", "c.example", "d.example"])
    }

    @Test func addingAGroupedTabToBasecampTakesItOut() throws {
        let store = makeStore()
        let tabs = open("a", in: store)
        store.newGroup(with: tabs[0])
        store.addToBasecamp(tabs[0])
        #expect(tabs[0].groupID == nil)
        #expect(store.tabGroups.isEmpty)
        #expect(hosts(store.basecampTabs) == ["a.example"])
    }

    // MARK: - Closing and links

    @Test func closingAGroupedTabReallyClosesItAndShowsItsNeighbor() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        store.select(tabs[0])
        store.close(tabs[0])
        #expect(!store.tabs.contains { $0.id == tabs[0].id })
        #expect(store.activeTabID == tabs[1].id) // Its neighbor in the group, not c.
        store.close(tabs[1])
        #expect(!store.groups.contains { $0.id == group.id }) // Its last tab closed.
        #expect(store.activeTabID == tabs[2].id)
    }

    @Test func linksFromAGroupedTabOpenInItsGroupBelowIt() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[2], with: tabs[1])
        store.openTab(url("link1"), opener: tabs[1], inBackground: true)
        store.openTab(url("link2"), opener: tabs[1], inBackground: true)
        #expect(hosts(store.tabs(in: group)) == ["b.example", "link1.example", "link2.example", "c.example"])
        #expect(hosts(store.looseTabs) == ["a.example"])
        // From the group's last tab, still in the group.
        store.openTab(url("link3"), opener: tabs[2], inBackground: true)
        #expect(hosts(store.tabs(in: group)).last == "link3.example")
    }

    // MARK: - Whole groups

    @Test func renamingTidiesTheName() throws {
        let store = makeStore()
        let group = try #require(store.newGroup(with: store.openTab(url("a"))))
        store.rename(group, to: "  Trip\nplanning  ")
        #expect(store.tabGroups.first?.name == "Trip planning")
        store.rename(group, to: "   ")
        #expect(store.tabGroups.first?.name == "Trip planning")
        store.rename(group, to: String(repeating: "x", count: 500))
        #expect(store.tabGroups.first?.name.count == TabGroup.nameLimit)
    }

    @Test func foldedGroupsAreSkippedByTabShortcuts() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.setFolded(group, true)
        #expect(store.tabGroups.first?.folded == true)
        #expect(hosts(store.sidebarTabs) == ["b.example"])
        #expect(hosts(store.openTabs) == ["a.example", "b.example"])
    }

    @Test func groupsReorder() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        let second = try #require(store.newGroup(with: tabs[1]))
        let third = try #require(store.newGroup(with: tabs[2]))
        store.move(third, to: 0)
        #expect(store.tabGroups.map(\.id) == [third.id, first.id, second.id])
        store.move(third, to: 3)
        #expect(store.tabGroups.map(\.id) == [first.id, second.id, third.id])
        #expect(hosts(store.sidebarTabs) == ["a.example", "b.example", "c.example"])
    }

    @Test func ungroupingKeepsTheTabsWhereTheGroupWas() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[2], with: tabs[1])
        store.ungroup(group)
        #expect(store.tabGroups.isEmpty)
        #expect(hosts(store.looseTabs) == ["a.example", "b.example", "c.example", "d.example"])
        store.newTabPlacement = .top
        let again = try #require(store.newGroup(with: tabs[3]))
        store.ungroup(again)
        #expect(hosts(store.looseTabs) == ["a.example", "b.example", "c.example", "d.example"])
    }

    @Test func closingAGroupClosesItsTabs() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[2], with: tabs[1])
        store.select(tabs[2])
        store.close(group)
        #expect(store.tabGroups.isEmpty)
        #expect(hosts(store.openTabs) == ["a.example"])
        #expect(tabs[1].isResting && tabs[2].isResting) // Their pages let go.
        #expect(store.activeTabID == tabs[0].id)
    }

    // MARK: - Saving

    @Test func groupsComeBackAsTheyWere() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        let trip = try #require(store.newGroup(with: tabs[2]))
        store.group(tabs[0], with: tabs[2])
        store.rename(trip, to: "Trip")
        let work = try #require(store.newGroup(with: tabs[3]))
        store.setFolded(work, true)

        let restored = makeStore(restoring: save(store))
        #expect(restored.tabGroups.map(\.name) == ["Trip", "New Group"])
        #expect(restored.tabGroups.map(\.folded) == [false, true])
        #expect(hosts(restored.tabs(in: restored.tabGroups[0])) == ["c.example", "a.example"])
        #expect(hosts(restored.tabs(in: restored.tabGroups[1])) == ["d.example"])
        #expect(hosts(restored.looseTabs) == ["b.example"])
        #expect(save(restored).groups.map(\.id) == save(store).groups.map(\.id))
    }

    @Test func aGroupsLastChangedOnlyMovesWhenItChanges() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let store = makeStore(now: { clock })
        let tabs = open("a", "b", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        store.newGroup(with: tabs[1])
        let before = save(store).groups
        clock += 60
        store.rename(first, to: "Renamed")
        let after = save(store).groups
        #expect(after[0].lastChangedAt == clock)
        #expect(after[1].lastChangedAt == before[1].lastChangedAt)
    }

    @Test func filesFromBeforeGroupsStillLoad() throws {
        let store = makeStore()
        store.openTab(url("a"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(save(store))) as? [String: Any]
        )
        json["groups"] = nil
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(session.groups.isEmpty)
        #expect(hosts(makeStore(restoring: session).looseTabs) == ["a.example"])
    }

    @Test func restoringPutsAGroupsTabsBackTogether() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        var session = save(store)
        // A file where c ended up between the group's tabs.
        func record(_ name: String) -> Int { session.tabs.firstIndex { $0.url == url(name) }! }
        session.tabs[record("a")].order = 0
        session.tabs[record("c")].order = 1
        session.tabs[record("b")].order = 2

        let restored = makeStore(restoring: session)
        #expect(restored.tabListItems.map(\.id) == [group.id, tabs[2].id])
        #expect(hosts(restored.sidebarTabs) == ["a.example", "b.example", "c.example"])
    }

    @Test func restoringRefusesGroupsThatDontFit() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", "d", in: store)
        store.newGroup(with: tabs[0])
        store.addToBasecamp(tabs[3])
        var session = save(store)
        let real = session.groups[0]
        let otherSpace = GroupRecord(
            id: UUID(), spaceID: UUID(), name: "Elsewhere", order: 1, folded: false, lastChangedAt: .now
        )
        let duplicate = GroupRecord(
            id: real.id, spaceID: real.spaceID, name: "Copy", order: 2, folded: false, lastChangedAt: .now
        )
        let empty = GroupRecord(
            id: UUID(), spaceID: real.spaceID, name: "Empty", order: 3, folded: false, lastChangedAt: .now
        )
        var blank = real
        blank.name = " \n "
        session.groups = [blank, otherSpace, duplicate, empty]
        func record(_ name: String) -> Int { session.tabs.firstIndex { $0.url == url(name) }! }
        session.tabs[record("b")].groupID = otherSpace.id // A group from a space that isn't here.
        session.tabs[record("c")].groupID = UUID() // A group that doesn't exist.
        session.tabs[record("d")].groupID = real.id // Basecamp tiles aren't grouped.

        let restored = makeStore(restoring: session)
        #expect(restored.groups.count == 1)
        #expect(restored.tabGroups.first?.name == "New Group")
        #expect(hosts(restored.tabs(in: restored.tabGroups[0])) == ["a.example"])
        #expect(hosts(restored.looseTabs) == ["b.example", "c.example"])
        #expect(restored.basecampTabs.first?.groupID == nil)
    }

    // MARK: - Right-click: Move to Group and Duplicate

    @Test func moveToGroupPutsTheTabAtTheEnd() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        store.move(tabs[2], toEndOf: group)
        #expect(hosts(store.tabs(in: group)) == ["a.example", "b.example", "c.example"])
        #expect(store.looseTabs.isEmpty)
    }

    @Test func moveToGroupOpensAFoldedGroupForTheTabOnScreen() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.setFolded(group, true)
        // b isn't on screen (c is), so the group stays folded.
        store.move(tabs[1], toEndOf: group)
        #expect(store.tabGroups.first?.folded == true)
        store.move(tabs[2], toEndOf: group)
        #expect(store.tabGroups.first?.folded == false)
    }

    @Test func moveToAnotherGroupEndsTheOldOneIfEmpty() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        let second = try #require(store.newGroup(with: tabs[1]))
        store.move(tabs[0], toEndOf: second)
        #expect(store.tabGroups.map(\.id) == [second.id])
        #expect(!store.tabGroups.contains { $0.id == first.id })
    }

    @Test func duplicateOpensRightBelowInTheSameGroupAndShowsIt() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[0]))
        store.group(tabs[1], with: tabs[0])
        let copy = try #require(store.duplicate(tabs[0]))
        #expect(copy.id != tabs[0].id)
        #expect(copy.groupID == group.id)
        #expect(hosts(store.tabs(in: group)) == ["a.example", "a.example", "b.example"])
        #expect(store.activeTabID == copy.id)
        // A loose tab's copy stays loose, right below it.
        let looseCopy = try #require(store.duplicate(tabs[2]))
        #expect(looseCopy.groupID == nil)
        #expect(hosts(store.looseTabs) == ["c.example", "c.example"])
    }

    // MARK: - The tab on screen never vanishes

    /// A clock that moves on a second each time it's read.
    private func ticking() -> () -> Date {
        var seconds = 0.0
        return { seconds += 1; return Date(timeIntervalSince1970: seconds) }
    }

    @Test func closingATilePrefersATabTheSidebarShows() throws {
        let store = makeStore(now: ticking())
        let tabs = open("a", "b", "t", in: store)
        store.addToBasecamp(tabs[2])
        let group = try #require(store.newGroup(with: tabs[1]))
        store.select(tabs[0])
        store.select(tabs[1]) // Seen more recently than a, then folded away.
        store.setFolded(group, true)
        store.select(tabs[2])
        store.close(tabs[2])
        #expect(store.activeTabID == tabs[0].id)
        #expect(store.tabGroups.first?.folded == true)
    }

    @Test func aTabOnlyInAFoldedGroupOpensTheGroup() throws {
        let store = makeStore(now: ticking())
        let tabs = open("a", "t", in: store)
        store.addToBasecamp(tabs[1])
        let group = try #require(store.newGroup(with: tabs[0]))
        store.setFolded(group, true)
        store.select(tabs[1])
        store.close(tabs[1])
        #expect(store.activeTabID == tabs[0].id)
        #expect(store.tabGroups.first?.folded == false)
    }
}
