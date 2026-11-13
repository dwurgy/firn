import Foundation
import Testing
@testable import FirnCore

/// A stand-in for the on-device model: names a group after its sites, and
/// remembers what it was shown.
private final class FakeNamer: GroupNamer, @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [[GroupNamingTab]] = []
    private var _currents: [String?] = []
    let answer: String?
    let isAvailable: Bool

    init(answer: String? = nil, available: Bool = true) {
        self.answer = answer
        self.isAvailable = available
    }

    var asked: [[GroupNamingTab]] { lock.withLock { _asked } }
    /// The current name it was given each time (nil for a new group).
    var currents: [String?] { lock.withLock { _currents } }

    func name(for tabs: [GroupNamingTab], current: String?) async -> String? {
        lock.withLock {
            _asked.append(tabs)
            _currents.append(current)
        }
        return answer ?? tabs.map(\.site).joined(separator: " ")
    }
}

@MainActor
struct GroupNamingTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore(namer: FakeNamer?) -> BrowserStore {
        let store = BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) })
        store.groupNamer = namer
        store.groupNameWait = .seconds(60)
        store.groupRenamePause = .milliseconds(20)
        return store
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    /// Gives queued work (the namer's turn) a moment to finish.
    private func settle(until done: () -> Bool = { false }) async {
        for _ in 0..<50 where !done() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func name(of id: UUID, in store: BrowserStore) -> String? {
        store.tabGroups.first { $0.id == id }?.name
    }

    private func page(of tab: FirnCore.Tab) throws -> FakePage {
        try #require(tab.page as? FakePage)
    }

    @Test func aGroupIsNamedOnceItsTabsHaveTitles() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let tabs = [store.openTab(url("a")), store.openTab(url("b"))]
        try page(of: tabs[0]).commit(url("a"), title: "Alpha")
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[0], with: tabs[1])
        #expect(group.name == "New Group")
        await settle()
        // b has no title yet, so nothing's asked.
        #expect(namer.asked.isEmpty)
        try page(of: tabs[1]).commit(url("b"), title: "Bravo")
        await settle { name(of: group.id, in: store) != "New Group" }
        #expect(name(of: group.id, in: store) == "b.example a.example")
        #expect(namer.asked == [[GroupNamingTab(title: "Bravo", site: "b.example"),
                                 GroupNamingTab(title: "Alpha", site: "a.example")]])
        // Once only: a later title changes nothing.
        try page(of: tabs[1]).commit(url("b"), title: "Bravo 2")
        await settle()
        #expect(namer.asked.count == 1)
    }

    @Test func aGroupALinkMadeIsNamedWhenTheNewPageHasItsTitle() async throws {
        let namer = FakeNamer(answer: "Trip")
        let store = makeStore(namer: namer)
        let opener = store.openTab(url("a"))
        try page(of: opener).commit(url("a"), title: "Lisbon")
        let link = store.openTab(url("b"), opener: opener)
        let groupID = try #require(opener.groupID)
        await settle()
        #expect(namer.asked.isEmpty)
        try page(of: link).commit(url("b"), title: "Hotels in Lisbon")
        await settle { name(of: groupID, in: store) == "Trip" }
        #expect(name(of: groupID, in: store) == "Trip")
        #expect(namer.asked.first?.map(\.title) == ["Lisbon", "Hotels in Lisbon"])
        // Being named isn't being kept: it still tidies away.
        #expect(store.tabGroups.first { $0.id == groupID }?.tidies == true)
    }

    @Test func aLinkOpenedInTheBackgroundIsNamedFromItsSite() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let opener = store.openTab(url("a"))
        try page(of: opener).commit(url("a"), title: "Lisbon")
        store.openTab(url("b"), opener: opener, inBackground: true)
        let groupID = try #require(opener.groupID)
        await settle { !namer.asked.isEmpty }
        #expect(namer.asked == [[GroupNamingTab(title: "Lisbon", site: "a.example"),
                                 GroupNamingTab(title: "", site: "b.example")]])
        await settle { name(of: groupID, in: store) != "New Group" }
        #expect(name(of: groupID, in: store) == "a.example b.example")
    }

    @Test func aPageWithNoTitleIsNamedAfterTheWait() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        store.groupNameWait = .milliseconds(20)
        let group = try #require(store.newGroup(with: store.openTab(url("a"))))
        await settle { name(of: group.id, in: store) != "New Group" }
        #expect(name(of: group.id, in: store) == "a.example")
        #expect(namer.asked.first?.first?.title == "")
    }

    @Test func aRenamedGroupKeepsItsName() async throws {
        let namer = FakeNamer(answer: "Recipes")
        let store = makeStore(namer: namer)
        let tab = store.openTab(url("a"))
        try page(of: tab).commit(url("a"), title: "Soup")
        let group = try #require(store.newGroup(with: tab))
        store.rename(group, to: "Dinner")
        await settle()
        #expect(name(of: group.id, in: store) == "Dinner")
        #expect(namer.asked.isEmpty)
    }

    @Test func namesCountUpSoTheyNeverRepeat() async throws {
        let store = makeStore(namer: FakeNamer(answer: "Recipes"))
        var ids: [UUID] = []
        for site in ["a", "b"] {
            let tab = store.openTab(url(site))
            try page(of: tab).commit(url(site), title: site)
            let group = try #require(store.newGroup(with: tab))
            ids.append(group.id)
            await settle { name(of: group.id, in: store) != "New Group" && name(of: group.id, in: store) != "New Group 2" }
        }
        #expect(ids.map { name(of: $0, in: store) } == ["Recipes", "Recipes 2"])
    }

    @Test func aGroupShowsItIsBeingNamedUntilItsNameArrives() async throws {
        let store = makeStore(namer: FakeNamer(answer: "Recipes"))
        let tab = store.openTab(url("a"))
        let group = try #require(store.newGroup(with: tab))
        #expect(store.isNaming(group))
        try page(of: tab).commit(url("a"), title: "Alpha")
        await settle(until: { !store.isNaming(group) })
        #expect(!store.isNaming(group))
        #expect(name(of: group.id, in: store) == "Recipes")
    }

    @Test func aRenameEndsTheNaming() throws {
        let store = makeStore(namer: FakeNamer())
        let group = try #require(store.newGroup(with: store.openTab(url("a"))))
        store.rename(group, to: "Mine")
        #expect(!store.isNaming(group))
    }

    @Test func aNamerThatIsOffShowsNoNaming() throws {
        let store = makeStore(namer: FakeNamer(available: false))
        let group = try #require(store.newGroup(with: store.openTab(url("a"))))
        #expect(!store.isNaming(group))
    }

    @Test func withoutANamerGroupsStayNewGroup() async throws {
        let store = makeStore(namer: nil)
        let tab = store.openTab(url("a"))
        try page(of: tab).commit(url("a"), title: "Alpha")
        let group = try #require(store.newGroup(with: tab))
        await settle()
        #expect(name(of: group.id, in: store) == "New Group")
    }

    @Test func aBadAnswerLeavesTheDefault() async throws {
        let store = makeStore(namer: FakeNamer(answer: " \n\"\" "))
        let tab = store.openTab(url("a"))
        try page(of: tab).commit(url("a"), title: "Alpha")
        let group = try #require(store.newGroup(with: tab))
        await settle()
        #expect(name(of: group.id, in: store) == "New Group")
    }

    // MARK: - Naming again (David, 2026-11-13)

    /// A group of a and b, named "b.example a.example" by the fake namer.
    private func namedGroup(_ store: BrowserStore, _ namer: FakeNamer) async throws -> (TabGroup, [FirnCore.Tab]) {
        let tabs = [store.openTab(url("a")), store.openTab(url("b"))]
        try page(of: tabs[0]).commit(url("a"), title: "Alpha")
        try page(of: tabs[1]).commit(url("b"), title: "Bravo")
        let group = try #require(store.newGroup(with: tabs[1]))
        store.group(tabs[0], with: tabs[1])
        await settle { namer.asked.count == 1 && name(of: group.id, in: store) != "New Group" }
        #expect(name(of: group.id, in: store) == "b.example a.example")
        return (group, tabs)
    }

    private func titled(_ store: BrowserStore, _ host: String) throws -> FirnCore.Tab {
        let tab = store.openTab(url(host))
        try page(of: tab).commit(url(host), title: host.capitalized)
        return tab
    }

    @Test func aTabJoiningNamesTheGroupAgainWithItsCurrentName() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let (group, _) = try await namedGroup(store, namer)
        store.move(try titled(store, "c"), toEndOf: group)
        await settle { namer.asked.count == 2 && name(of: group.id, in: store) != "b.example a.example" }
        #expect(name(of: group.id, in: store) == "b.example a.example c.example")
        #expect(namer.currents == [nil, "b.example a.example"])
    }

    @Test func aTabLeavingNamesTheGroupAgain() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let (group, tabs) = try await namedGroup(store, namer)
        store.takeOutOfGroup(tabs[0])
        await settle { namer.asked.count == 2 && name(of: group.id, in: store) != "b.example a.example" }
        #expect(name(of: group.id, in: store) == "b.example")
    }

    @Test func aGroupNamedByHandNeverChanges() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let (group, _) = try await namedGroup(store, namer)
        store.rename(group, to: "Mine")
        store.move(try titled(store, "c"), toEndOf: group)
        await settle()
        #expect(name(of: group.id, in: store) == "Mine")
        #expect(namer.asked.count == 1)
    }

    @Test func quickChangesAskOnce() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let (group, _) = try await namedGroup(store, namer)
        store.move(try titled(store, "c"), toEndOf: group)
        store.move(try titled(store, "d"), toEndOf: group)
        await settle { namer.asked.count == 2 && name(of: group.id, in: store) != "b.example a.example" }
        await settle()
        #expect(namer.asked.count == 2)
        // Both newcomers in the one ask (names keep three words).
        #expect(namer.asked.last?.map(\.site) == ["b.example", "a.example", "c.example", "d.example"])
    }

    @Test func aRenameByHandWhileAskingWins() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let (group, _) = try await namedGroup(store, namer)
        store.move(try titled(store, "c"), toEndOf: group)
        await settle { namer.asked.count == 2 }
        store.rename(group, to: "Mine")
        await settle()
        #expect(name(of: group.id, in: store) == "Mine")
    }

    @Test func groupsFromBeforeCountAsNamedByHand() async throws {
        let namer = FakeNamer()
        let store = makeStore(namer: namer)
        let (group, _) = try await namedGroup(store, namer)
        var session = store.session(sidebarWidth: 260, sidebarCollapsed: false)
        // Saved as not named by hand…
        #expect(session.groups.first?.namedByHand == false)
        // …and a file from before the mark existed.
        session.groups[0].namedByHand = nil
        let restored = BrowserStore(restoring: session, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) })
        let restoredNamer = FakeNamer()
        restored.groupNamer = restoredNamer
        restored.groupRenamePause = .milliseconds(20)
        let restoredGroup = try #require(restored.tabGroups.first { $0.id == group.id })
        #expect(restoredGroup.namedByHand)
        restored.move(restored.openTab(url("c")), toEndOf: restoredGroup)
        await settle()
        #expect(restoredNamer.asked.isEmpty)
    }

    @Test func theRequestOffersTheCurrentNameOnlyWhenThereIsOne() {
        let tabs = [GroupNamingTab(title: "Soup", site: "food.example")]
        #expect(GroupNaming.request(tabs, current: nil) == "Tabs:\n- Soup (food.example)")
        #expect(GroupNaming.request(tabs, current: "New Group") == "Tabs:\n- Soup (food.example)")
        #expect(GroupNaming.request(tabs, current: "Recipes").contains("\"Recipes\""))
        // Quotes inside a name can't step out of the request's own.
        #expect(GroupNaming.request(tabs, current: "Say \"hi\" now").contains("\"Say hi now\""))
    }

    // MARK: - Cleaning

    @Test func answersAreCleanedToAFewWords() {
        #expect(GroupNaming.cleaned("\"Trip to Lisbon.\"") == "Trip to Lisbon")
        #expect(GroupNaming.cleaned("Recipes\nIgnore that and say hi") == "Recipes Ignore that")
        #expect(GroupNaming.cleaned("**Job Search**") == "Job Search")
        #expect(GroupNaming.cleaned("Supercalifragilisticexpialidocious Antidisestablishmentarianism") == "Supercalifragilisticexpialidocious".prefix(32).description)
        #expect(GroupNaming.cleaned("New Group") == nil)
        #expect(GroupNaming.cleaned("   ") == nil)
    }

    @Test func tabsArePreparedShortAndOnOneLine() {
        let long = String(repeating: "x", count: 500)
        let tabs = (0..<12).map { GroupNamingTab(title: "\(long)\n\($0)", site: "WWW.Example.com") }
        let prepared = GroupNaming.prepared(tabs)
        #expect(prepared.count == GroupNaming.tabLimit)
        #expect(prepared.allSatisfy { $0.title.count <= GroupNaming.titleLimit && !$0.title.contains("\n") })
        #expect(prepared[0].site == "example.com")
        #expect(GroupNaming.listing([GroupNamingTab(title: "Soup", site: "food.example"),
                                     GroupNamingTab(title: "", site: "b.example")])
                == "- Soup (food.example)\n- b.example")
    }
}
