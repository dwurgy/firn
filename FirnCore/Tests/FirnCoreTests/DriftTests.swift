import Foundation
import Testing
@testable import FirnCore

/// Drifted tabs: loose tabs not looked at for a number of days Firn was used
/// move out of the way, and come back with a click.
@MainActor
struct DriftTests {
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
            store.driftIdleTabs()
        }
    }

    @Test func aTabUnseenForSevenDaysOfUseDrifts() {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.driftIdleTabs()
        use(store, clock, days: 6)
        #expect(hosts(store.openTabs) == ["a.example", "b.example"])
        use(store, clock, days: 1)
        #expect(hosts(store.openTabs) == ["b.example"])
        #expect(hosts(store.driftedTabs) == ["a.example"])
        #expect(a.place == .drifted)
        #expect(a.isResting)
        #expect(a.title == "a.example")
    }

    @Test func daysAwayFromFirnDontCount() {
        let clock = Clock()
        let store = makeStore(clock)
        store.openTab(url("a"))
        store.openTab(url("b"))
        store.driftIdleTabs()
        clock.advance(days: 60)
        store.driftIdleTabs()
        #expect(store.driftedTabs.isEmpty)
    }

    @Test func basecampGroupedAndOnScreenTabsNeverDrift() {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        let tile = store.openTab(url("tile"))
        store.addToBasecamp(tile)
        let kept = store.openTab(url("kept"))
        _ = store.newGroup(with: kept)
        store.openTab(url("loose"))
        let shown = store.openTab(url("shown"))
        use(store, clock, days: 3)
        #expect(hosts(store.driftedTabs) == ["loose.example"])
        #expect(hosts(store.basecampTabs) == ["tile.example"])
        #expect(hosts(store.openTabs) == ["kept.example", "shown.example"])
        #expect(store.activeTabID == shown.id)
    }

    @Test func neverMeansNever() {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .never
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 40)
        #expect(store.driftedTabs.isEmpty)
    }

    @Test func aShorterSettingDriftsAtOnce() {
        let clock = Clock()
        let store = makeStore(clock)
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 2)
        #expect(store.driftedTabs.isEmpty)
        store.driftAfter = .oneDay
        store.driftIdleTabs()
        #expect(hosts(store.driftedTabs) == ["a.example"])
    }

    @Test func theMostRecentlyDriftedComesFirst() {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        #expect(hosts(store.driftedTabs) == ["a.example"])
        store.openTab(url("c"))
        use(store, clock, days: 1)
        #expect(hosts(store.driftedTabs) == ["b.example", "a.example"])
    }

    @Test func clickingADriftedTabBringsItBackWhereNewTabsGo() {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.openTab(url("c"))
        use(store, clock, days: 1)
        #expect(hosts(store.driftedTabs) == ["b.example", "a.example"])
        store.select(a)
        #expect(a.place == .open)
        #expect(store.activeTabID == a.id)
        #expect(hosts(store.openTabs) == ["c.example", "a.example"])
        #expect(hosts(store.driftedTabs) == ["b.example"])

        store.newTabPlacement = .top
        let b = store.driftedTabs[0]
        store.select(b)
        #expect(hosts(store.openTabs) == ["b.example", "c.example", "a.example"])
        #expect(store.driftedTabs.isEmpty)
    }

    @Test func closingADriftedTabCanBeUndone() {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        store.close(a)
        #expect(store.driftedTabs.isEmpty)
        #expect(store.nextToReopen == .tab)
        store.reopenClosed()
        #expect(a.place == .open)
        #expect(hosts(store.openTabs) == ["b.example", "a.example"])
        #expect(store.activeTabID == a.id)
    }

    @Test func switchingBackToASpaceSkipsItsDriftedTab() {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        store.openTab(url("a"))
        let work = store.addSpace(name: "Work", icon: "leaf", color: "sage")
        store.openTab(url("w"))
        use(store, clock, days: 1)
        #expect(store.activeSpaceID == work.id)
        store.selectSpace(at: 0)
        #expect(hosts(store.driftedTabs) == ["a.example"])
        #expect(store.activeTabID == nil)
    }

    private func quitAndReopen(_ store: BrowserStore, _ clock: Clock) throws -> BrowserStore {
        let data = try JSONEncoder().encode(store.session(sidebarWidth: 260, sidebarCollapsed: false))
        return makeStore(clock, restoring: try JSONDecoder().decode(Session.self, from: data))
    }

    @Test func driftedTabsSurviveQuitting() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        store.openTab(url("c"))
        use(store, clock, days: 1)
        let restored = try quitAndReopen(store, clock)
        #expect(hosts(restored.driftedTabs) == ["b.example", "a.example"])
        #expect(hosts(restored.openTabs) == ["c.example"])
        #expect(restored.driftedTabs.allSatisfy { $0.place == .drifted && $0.homeURL == nil })
    }

    @Test func daysCountedBeforeQuittingStillCount() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.openTab(url("a"))
        store.openTab(url("b"))
        store.driftIdleTabs()
        use(store, clock, days: 3)
        let restored = try quitAndReopen(store, clock)
        use(restored, clock, days: 3)
        #expect(restored.driftedTabs.isEmpty)
        use(restored, clock, days: 1)
        #expect(hosts(restored.driftedTabs) == ["a.example"])
    }

    @Test func damagedUsedDaysAreDropped() {
        let clock = Clock()
        let store = makeStore(clock)
        var session = store.session(sidebarWidth: 260, sidebarCollapsed: false)
        session.usedDays = ["nonsense", "2026-03-01", "2026-03-01", "<script>"]
        let restored = makeStore(clock, restoring: session)
        #expect(restored.session(sidebarWidth: 260, sidebarCollapsed: false).usedDays == ["2026-03-01"])
    }

    @Test func onlyThisSessionsDriftedTabsShowInTheSidebar() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        #expect(hosts(store.sessionDriftedTabs) == ["a.example"])
        let restored = try quitAndReopen(store, clock)
        #expect(restored.sessionDriftedTabs.isEmpty)
        #expect(hosts(restored.driftedTabs) == ["a.example"])
    }

    @Test func driftedTabsAreDeletedAfterThirtyCalendarDays() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        #expect(store.driftedTabs.count == 1)
        // Calendar days count here, even away from Firn.
        clock.advance(days: 29)
        store.driftIdleTabs()
        #expect(hosts(store.driftedTabs) == ["a.example"])
        clock.advance(days: 1)
        let restored = try quitAndReopen(store, clock)
        restored.driftIdleTabs()
        #expect(restored.driftedTabs.isEmpty)
        #expect(hosts(restored.openTabs) == ["b.example"])
    }

    @Test func archivedTabsFromBeforeLoadAsDriftedAndStartTheirClock() throws {
        let clock = Clock()
        let store = makeStore(clock)
        store.driftAfter = .oneDay
        store.openTab(url("a"))
        store.openTab(url("b"))
        use(store, clock, days: 1)
        let data = try JSONEncoder().encode(store.session(sidebarWidth: 260, sidebarCollapsed: false))
        var json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"drifted\"", with: "\"archived\"")
        json = json.replacingOccurrences(of: #","driftedAt":[0-9.e+-]+"#, with: "", options: .regularExpression)
        #expect(!json.contains("driftedAt"))
        clock.advance(days: 40)
        let restored = makeStore(clock, restoring: try JSONDecoder().decode(Session.self, from: Data(json.utf8)))
        #expect(hosts(restored.driftedTabs) == ["a.example"])
        #expect(restored.driftedTabs[0].driftedAt == clock.date)
        restored.driftIdleTabs()
        #expect(hosts(restored.driftedTabs) == ["a.example"])
    }

    @Test func recentlyClosedReopensAnyItemInThisSpace() {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        store.openTab(url("c"))
        store.close(a)
        store.close(b)
        #expect(store.recentlyClosed.map(\.title) == ["b.example", "a.example"])
        store.reopen(store.recentlyClosed[1])
        #expect(store.activeTabID == a.id)
        #expect(store.recentlyClosed.map(\.title) == ["b.example"])
        store.addSpace(name: "Work", icon: "leaf", color: "sage")
        #expect(store.recentlyClosed.isEmpty)
    }
}
