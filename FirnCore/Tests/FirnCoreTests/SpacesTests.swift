import Foundation
import Testing
@testable import FirnCore

@MainActor
struct SpacesTests {
    private let personal = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore(
        restoring session: Session? = nil, removed: ((UUID) -> Void)? = nil
    ) -> BrowserStore {
        BrowserStore(
            restoring: session, defaultSpaces: [personal], makePage: { FakePage(dataStoreID: $0) },
            removeData: { removed?($0) }
        )
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func dataStore(of tab: FirnCore.Tab) -> UUID? {
        (tab.page as? FakePage)?.dataStoreID
    }

    // MARK: - Making and switching

    @Test func aNewSpaceIsSeparateEmptyAndShown() {
        let store = makeStore()
        store.openTab(url("a"))
        let work = store.addSpace(name: "  Work\n", color: "sand")
        #expect(work.name == "Work")
        #expect(work.dataStoreID != personal.dataStoreID)
        #expect(store.activeSpaceID == work.id)
        #expect(store.activeTab == nil)
        #expect(store.tabListItems.isEmpty)
        #expect(store.spaces.map(\.order) == [0, 1])
    }

    @Test func aSharedSpaceUsesTheSameDataButItsOwnTabs() {
        let store = makeStore()
        store.openTab(url("a"))
        let shared = store.addSpace(name: "Side project", color: "sage", sharingWith: personal)
        #expect(shared.dataStoreID == personal.dataStoreID)
        #expect(store.tabListItems.isEmpty)
        #expect(store.spacesSharingData(with: shared).map(\.id) == [personal.id])
        let tab = store.openTab(url("b"))
        #expect(dataStore(of: tab) == personal.dataStoreID)
    }

    @Test func tabsOpenInTheirOwnSpacesDataStore() {
        let store = makeStore()
        let mine = store.openTab(url("a"))
        let work = store.addSpace(name: "Work", color: "sand")
        let theirs = store.openTab(url("b"))
        #expect(dataStore(of: mine) == personal.dataStoreID)
        #expect(dataStore(of: theirs) == work.dataStoreID)
    }

    @Test func switchingBackFindsTheTabLastOnScreen() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.select(a)
        let work = store.addSpace(name: "Work", color: "sand")
        let c = store.openTab(url("c"))
        store.selectSpace(store.spaces[0])
        #expect(store.activeTabID == a.id)
        store.selectSpace(work)
        #expect(store.activeTabID == c.id)
    }

    @Test func spacesWrapAroundAndPositionsClamp() {
        let store = makeStore()
        let work = store.addSpace(name: "Work", color: "sand")
        let home = store.addSpace(name: "Home", color: "sage")
        store.selectSpace(by: 1)
        #expect(store.activeSpaceID == personal.id)
        store.selectSpace(by: -1)
        #expect(store.activeSpaceID == home.id)
        store.selectSpace(at: 1)
        #expect(store.activeSpaceID == work.id)
        store.selectSpace(at: 8)
        #expect(store.activeSpaceID == home.id)
    }

    @Test func editingAndReordering() throws {
        let store = makeStore()
        let work = store.addSpace(name: "Work", color: "sand")
        store.updateSpace(work, name: "   ", color: "dusk")
        let edited = try #require(store.spaces.first { $0.id == work.id })
        #expect(edited.name == "Work")
        #expect(edited.color == "dusk")
        store.moveSpace(work, to: 0)
        #expect(store.spaces.map(\.id) == [work.id, personal.id])
        #expect(store.spaces.map(\.order) == [0, 1])
    }

    // MARK: - Nothing crosses between spaces

    @Test func groupsAndReopeningStayInTheirSpace() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.close(a)
        let work = store.addSpace(name: "Work", color: "sand")
        #expect(store.nextToReopen == nil)
        let b = store.openTab(url("b"))
        let c = store.openTab(url("c"))
        // A tab can't be grouped with one from another space.
        store.selectSpace(store.spaces[0])
        let d = store.openTab(url("d"))
        store.group(d, with: b)
        #expect(d.groupID == nil && b.groupID == nil)
        store.selectSpace(work)
        store.group(b, with: c)
        #expect(b.groupID != nil)
        #expect(store.tabGroups.count == 1)
        store.selectSpace(store.spaces[0])
        #expect(store.tabGroups.isEmpty)
    }

    // MARK: - Stopping sharing

    @Test func stopSharingStartsFreshAndLeavesTheOtherSpaceAlone() throws {
        let store = makeStore()
        let mine = store.openTab(url("a"))
        let shared = store.addSpace(name: "Side", color: "sage", sharingWith: personal)
        let onScreen = store.openTab(url("b"))
        let resting = store.openTab(url("c"))
        store.select(onScreen)
        store.stopSharing(shared)
        let fresh = try #require(store.spaces.first { $0.id == shared.id })
        #expect(fresh.dataStoreID != personal.dataStoreID)
        #expect(store.spaces[0].dataStoreID == personal.dataStoreID)
        // The tab on screen loads again in the new store; the others rest.
        #expect(dataStore(of: onScreen) == fresh.dataStoreID)
        #expect(onScreen.url == url("b"))
        #expect(resting.isResting)
        #expect(dataStore(of: mine) == personal.dataStoreID)
        store.select(resting)
        #expect(dataStore(of: resting) == fresh.dataStoreID)
    }

    @Test func aSeparateSpaceCantStopSharing() throws {
        let store = makeStore()
        let work = store.addSpace(name: "Work", color: "sand")
        store.stopSharing(work)
        #expect(store.spaces.first { $0.id == work.id }?.dataStoreID == work.dataStoreID)
    }

    // MARK: - Deleting

    @Test func deletingASeparateSpaceErasesItsTabsAndData() {
        var removed: [UUID] = []
        let store = makeStore { removed.append($0) }
        let work = store.addSpace(name: "Work", color: "sand")
        let tab = store.openTab(url("w"))
        store.newGroup(with: tab)
        store.openTab(url("x"))
        store.deleteSpace(work)
        #expect(store.spaces.map(\.id) == [personal.id])
        #expect(store.activeSpaceID == personal.id)
        #expect(store.tabs.allSatisfy { $0.spaceID == personal.id })
        #expect(store.groups.isEmpty)
        #expect(tab.isResting)
        #expect(removed == [work.dataStoreID])
    }

    @Test func deletingASharedSpaceKeepsTheDataTheOtherStillUses() {
        var removed: [UUID] = []
        let store = makeStore { removed.append($0) }
        let shared = store.addSpace(name: "Side", color: "sage", sharingWith: personal)
        store.deleteSpace(shared)
        #expect(removed.isEmpty)
        #expect(store.spaces.count == 1)
    }

    @Test func theLastSpaceStays() {
        var removed: [UUID] = []
        let store = makeStore { removed.append($0) }
        store.openTab(url("a"))
        store.deleteSpace(personal)
        #expect(store.spaces.count == 1)
        #expect(store.tabs.count == 1)
        #expect(removed.isEmpty)
    }

    @Test func deletingTheSpaceOnScreenShowsTheOneBelow() {
        let store = makeStore()
        let work = store.addSpace(name: "Work", color: "sand")
        let home = store.addSpace(name: "Home", color: "sage")
        store.selectSpace(work)
        store.deleteSpace(work)
        #expect(store.activeSpaceID == home.id)
        store.deleteSpace(home)
        #expect(store.activeSpaceID == personal.id)
    }

    @Test func reopeningForgetsADeletedSpace() {
        let store = makeStore()
        let work = store.addSpace(name: "Work", color: "sand")
        store.close(store.openTab(url("w")))
        store.deleteSpace(work)
        #expect(store.nextToReopen == nil)
    }

    // MARK: - Saving

    @Test func spacesAndEachSpacesTabComeBack() throws {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let work = store.addSpace(name: "Work", color: "sand")
        let w = store.openTab(url("w"))
        store.selectSpace(store.spaces[0])
        let session = store.session(sidebarWidth: 260, sidebarCollapsed: false)
        let data = try JSONEncoder().encode(session)
        let reopened = makeStore(restoring: try JSONDecoder().decode(Session.self, from: data))
        #expect(reopened.spaces.map(\.id) == [personal.id, work.id])
        #expect(reopened.spaces[1].dataStoreID == work.dataStoreID)
        #expect(reopened.activeTabID == a.id)
        reopened.selectSpace(reopened.spaces[1])
        #expect(reopened.activeTabID == w.id)
    }

    @Test func savedSpaceNamesAreTidied() {
        var messy = personal
        messy.name = "\n\t "
        let session = Session(
            spaces: [messy], tabs: [],
            window: WindowRecord(id: UUID(), activeSpaceID: messy.id, activeTabID: nil, sidebarWidth: 260, sidebarCollapsed: false)
        )
        #expect(makeStore(restoring: session).spaces[0].name == Space.defaultName)
    }

    @Test func aSpaceSavedWithAnIconStillOpens() throws {
        let json = """
        {"id":"\(UUID())","name":"Work","icon":"leaf","color":"sand","order":0,
         "dataStoreID":"\(UUID())","lastChangedAt":0}
        """
        let space = try JSONDecoder().decode(Space.self, from: Data(json.utf8))
        #expect(space.name == "Work")
        #expect(space.color == "sand")
        let saved = String(decoding: try JSONEncoder().encode(space), as: UTF8.self)
        #expect(!saved.contains("icon"))
    }
}
