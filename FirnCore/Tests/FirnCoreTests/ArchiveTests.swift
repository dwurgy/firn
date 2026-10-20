import Foundation
import Testing
@testable import FirnCore

/// Archived: loose tabs not looked at for a number of days Firn was used
/// move out of the way, and come back with a click.
@MainActor
struct ArchiveTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())

    /// A clock the test moves by whole days, starting at noon so no day is
    /// ever skipped or repeated.
    private final class Clock {
        var date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!
        func advance(days: Int) { date = Calendar.current.date(byAdding: .day, value: days, to: date)! }
    }

    private func makeStore(_ clock: Clock, restoring session: Session? = nil) -> BrowserStore {
        BrowserStore(restoring: session, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) }, now: { clock.date })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func hosts(_ tabs: [FirnCore.Tab]) -> [String] {
        tabs.map { $0.url?.host() ?? "" }
    }

    /// Uses Firn on each of the next `days` days.
    private func use(_ store: BrowserStore, _ clock: Clock, days: Int) {
        for _ in 0 ..< days {
            clock.advance(days: 1)
            store.archiveIdleTabs()
        }
    }

    @Test func aTabUnseenForSevenDaysOfUseIsArchived() {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.archiveIdleTabs()
        use(store, clock, days: 6)
        #expect(hosts(store.openTabs) == ["a.example", "b.example"])
        use(store, clock, days: 1)
        #expect(hosts(store.openTabs) == ["b.example"])
        #expect(hosts(store.archivedTabs) == ["a.example"])
        #expect(a.place == .archived)
        #expect(a.isResting)
        #expect(a.title == "a.example")
    }

    @Test func daysAwayFromFirnDontCount() {
        let clock = Clock()
        let store = makeStore(clock)
        store.openTab(url("a"))
        store.openTab(url("b"))
        store.archiveIdleTabs()
        clock.advance(days: 60)
        store.archiveIdleTabs()
        #expect(store.archivedTabs.isEmpty)
    }

    @Test func basecampGroupedAndOnScreenTabsAreNeverArchived() {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .oneDay
        let tile = store.openTab(url("tile"))
        store.addToBasecamp(tile)
        let kept = store.openTab(url("kept"))
        _ = store.newGroup(with: kept)
        store.openTab(url("loose"))
        let shown = store.openTab(url("shown"))
        use(store, clock, days: 3)
        #expect(hosts(store.archivedTabs) == ["loose.example"])
        #expect(hosts(store.basecampTabs) == ["tile.example"])
        #expect(hosts(store.openTabs) == ["kept.example", "shown.example"])
        #expect(store.activeTabID == shown.id)
    }

    @Test func neverMeansNever() {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .never
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 40)
        #expect(store.archivedTabs.isEmpty)
    }

    @Test func aShorterSettingArchivesAtOnce() {
        let clock = Clock()
        let store = makeStore(clock)
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 2)
        #expect(store.archivedTabs.isEmpty)
        store.archiveAfter = .oneDay
        store.archiveIdleTabs()
        #expect(hosts(store.archivedTabs) == ["a.example"])
    }

    @Test func theMostRecentlyArchivedComesFirst() {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        #expect(hosts(store.archivedTabs) == ["a.example"])
        store.openTab(url("c"))
        use(store, clock, days: 1)
        #expect(hosts(store.archivedTabs) == ["b.example", "a.example"])
    }

    @Test func clickingAnArchivedTabBringsItBackWhereNewTabsGo() {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .oneDay
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.openTab(url("c"))
        use(store, clock, days: 1)
        #expect(hosts(store.archivedTabs) == ["b.example", "a.example"])
        store.select(a)
        #expect(a.place == .open)
        #expect(store.activeTabID == a.id)
        #expect(hosts(store.openTabs) == ["c.example", "a.example"])
        #expect(hosts(store.archivedTabs) == ["b.example"])

        store.newTabPlacement = .top
        let b = store.archivedTabs[0]
        store.select(b)
        #expect(hosts(store.openTabs) == ["b.example", "c.example", "a.example"])
        #expect(store.archivedTabs.isEmpty)
    }

    @Test func closingAnArchivedTabCanBeUndone() {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .oneDay
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        store.close(a)
        #expect(store.archivedTabs.isEmpty)
        #expect(store.nextToReopen == .tab)
        store.reopenClosed()
        #expect(a.place == .open)
        #expect(hosts(store.openTabs) == ["b.example", "a.example"])
        #expect(store.activeTabID == a.id)
    }

    @Test func switchingBackToASpaceSkipsItsArchivedTab() {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .oneDay
        store.openTab(url("a"))
        let work = store.addSpace(name: "Work", icon: "leaf", color: "sage")
        store.openTab(url("w"))
        use(store, clock, days: 1)
        #expect(store.activeSpaceID == work.id)
        store.selectSpace(at: 0)
        #expect(hosts(store.archivedTabs) == ["a.example"])
        #expect(store.activeTabID == nil)
    }

    private func quitAndReopen(_ store: BrowserStore, _ clock: Clock) throws -> BrowserStore {
        let data = try JSONEncoder().encode(store.session(sidebarWidth: 260, sidebarCollapsed: false))
        return makeStore(clock, restoring: try JSONDecoder().decode(Session.self, from: data))
    }

    @Test func archivedTabsSurviveQuitting() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.archiveAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        store.openTab(url("c"))
        use(store, clock, days: 1)
        let restored = try quitAndReopen(store, clock)
        #expect(hosts(restored.archivedTabs) == ["b.example", "a.example"])
        #expect(hosts(restored.openTabs) == ["c.example"])
        #expect(restored.archivedTabs.allSatisfy { $0.place == .archived && $0.homeURL == nil })
    }

    @Test func daysCountedBeforeQuittingStillCount() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.openTab(url("a"))
        store.openTab(url("b"))
        store.archiveIdleTabs()
        use(store, clock, days: 3)
        let restored = try quitAndReopen(store, clock)
        use(restored, clock, days: 3)
        #expect(restored.archivedTabs.isEmpty)
        use(restored, clock, days: 1)
        #expect(hosts(restored.archivedTabs) == ["a.example"])
    }

    @Test func damagedUsedDaysAreDropped() {
        let clock = Clock()
        let store = makeStore(clock)
        var session = store.session(sidebarWidth: 260, sidebarCollapsed: false)
        session.usedDays = ["nonsense", "2026-03-01", "2026-03-01", "<script>"]
        let restored = makeStore(clock, restoring: session)
        #expect(restored.session(sidebarWidth: 260, sidebarCollapsed: false).usedDays == ["2026-03-01"])
    }
}
