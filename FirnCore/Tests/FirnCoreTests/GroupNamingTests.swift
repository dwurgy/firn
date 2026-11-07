import Foundation
import Testing
@testable import FirnCore

/// A stand-in for the on-device model: names a group after its sites, and
/// remembers what it was shown.
private final class FakeNamer: GroupNamer, @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [[GroupNamingTab]] = []
    let answer: String?

    init(answer: String? = nil) { self.answer = answer }

    var asked: [[GroupNamingTab]] { lock.withLock { _asked } }

    func name(for tabs: [GroupNamingTab]) async -> String? {
        lock.withLock { _asked.append(tabs) }
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
