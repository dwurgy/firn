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

    @Test func aNewGroupHoldsTheTabAboveTheLooseTabs() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        #expect(group.name == "New Group")
        #expect(store.tabGroups.map(\.id) == [group.id])
        #expect(hosts(store.tabs(in: group)) == ["b.example"])
        #expect(hosts(store.looseTabs) == ["a.example", "c.example"])
        #expect(hosts(store.sidebarTabs) == ["b.example", "a.example", "c.example"])
    }

    @Test func newGroupsGoBelowTheOtherGroups() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let first = try #require(store.newGroup(with: tabs[0]))
        let second = try #require(store.newGroup(with: tabs[1]))
        #expect(store.tabGroups.map(\.id) == [first.id, second.id])
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

    @Test func takingATabOutPutsItAtTheTopOfTheLooseTabs() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[2]))
        store.group(tabs[0], with: tabs[2])
        store.takeOutOfGroup(tabs[2])
        #expect(hosts(store.tabs(in: group)) == ["a.example"])
        #expect(hosts(store.looseTabs) == ["c.example", "b.example"])
        store.takeOutOfGroup(tabs[0], to: 2)
        #expect(hosts(store.looseTabs) == ["c.example", "b.example", "a.example"])
        #expect(store.tabGroups.isEmpty) // Its last tab left.
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
        // Out of a group, below the loose tab.
        store.move(tabs[2], toGroup: nil, at: 1)
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

    @Test func linksFromAGroupedTabOpenAtTheTopOfTheLooseTabs() throws {
        let store = makeStore()
        let tabs = open("a", "b", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.openTab(url("link1"), opener: tabs[1], inBackground: true)
        store.openTab(url("link2"), opener: tabs[1], inBackground: true)
        #expect(hosts(store.tabs(in: group)) == ["b.example"])
        #expect(hosts(store.looseTabs) == ["link1.example", "link2.example", "a.example"])
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

    @Test func ungroupingKeepsTheTabsAtTheTopOfTheLooseTabs() throws {
        let store = makeStore()
        let tabs = open("a", "b", "c", in: store)
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[2], with: tabs[1])
        store.ungroup(group)
        #expect(store.tabGroups.isEmpty)
        #expect(hosts(store.looseTabs) == ["b.example", "c.example", "a.example"])
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
}
