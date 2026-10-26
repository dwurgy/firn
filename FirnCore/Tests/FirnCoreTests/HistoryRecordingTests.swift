import Foundation
import Testing
@testable import FirnCore

/// Tabs' visits reaching history, in a folder of its own.
@MainActor
struct HistoryRecordingTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "FirnHistoryRecordingTests-\(UUID().uuidString)")
    let work = Space(name: "Work", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())
    let personal = Space(name: "Personal", icon: "leaf", color: "sage", order: 1, dataStoreID: UUID())

    func makeStores() -> (BrowserStore, HistoryStore) {
        let history = HistoryStore(directory: folder)
        let store = BrowserStore(spaces: [work, personal], makePage: { FakePage(dataStoreID: $0) }, history: history)
        return (store, history)
    }

    func url(_ text: String) -> URL { URL(string: text)! }

    func page(_ tab: Tab) -> FakePage { tab.page as! FakePage }

    @Test func aVisitIsRecordedWithItsTitle() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tab = store.openTab(url("https://a.example/"))
        page(tab).commit(url("https://a.example/"), title: "A")
        page(tab).commit(url("https://b.example/"), title: "B")
        await store.history?.settled()
        let visits = await history.visits(in: work.dataStoreID)
        #expect(visits.map(\.title) == ["B", "A"])
        #expect(visits.map(\.url) == [url("https://b.example/"), url("https://a.example/")])
    }

    @Test func reloadsAndSectionJumpsAreNotNewVisits() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tab = store.openTab(url("https://a.example/"))
        page(tab).commit(url("https://a.example/page"), title: "Page")
        page(tab).commit(url("https://a.example/page"))
        page(tab).commit(url("https://a.example/page#part-2"))
        page(tab).commit(url("https://a.example/page"), title: "Page, renamed")
        await store.history?.settled()
        let visits = await history.visits(in: work.dataStoreID)
        #expect(visits.map(\.title) == ["Page, renamed"])
    }

    @Test func onlyWebAddressesAreRecorded() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tab = store.openTab(url("https://a.example/"))
        page(tab).commit(url("file:///Users/me/page.html"), title: "Local")
        page(tab).commit(url("about:blank"))
        await store.history?.settled()
        #expect(await history.visits(in: work.dataStoreID).isEmpty)
    }

    @Test func eachSpaceRecordsInItsOwnStore() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workTab = store.openTab(url("https://a.example/"))
        page(workTab).commit(url("https://work.example/"), title: "Work")
        store.selectSpace(personal)
        let personalTab = store.openTab(url("https://a.example/"))
        page(personalTab).commit(url("https://home.example/"), title: "Home")
        await store.history?.settled()
        #expect(await history.visits(in: work.dataStoreID).map(\.title) == ["Work"])
        #expect(await history.visits(in: personal.dataStoreID).map(\.title) == ["Home"])
    }

    @Test func aLookoutIsRecordedOnlyOnceKept() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.openTab(url("https://a.example/"))
        store.openLookout(url("https://glance.example/"))
        let lookoutPage = store.lookout?.page as! FakePage
        lookoutPage.commit(url("https://glance.example/"), title: "Glance")
        await store.history?.settled()
        #expect(await history.visits(in: work.dataStoreID).isEmpty)
        store.keepLookout()
        lookoutPage.commit(url("https://glance.example/next"), title: "Next")
        await store.history?.settled()
        #expect(await history.visits(in: work.dataStoreID).map(\.title) == ["Next", "Glance"])
    }

    @Test func theHistoryWindowReadsOnlyItsSpacePageByPage() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let start = Date(timeIntervalSince1970: 1_000_000)
        let count = BrowserStore.historyPageSize + 5
        for n in 0..<count {
            await history.record(url("https://w\(n).example/"), title: "Work \(n)", at: start + Double(n), in: work.dataStoreID)
        }
        await history.record(url("https://home.example/"), title: "Home", at: start, in: personal.dataStoreID)
        let first = await store.historyVisits(in: work)
        #expect(first.count == BrowserStore.historyPageSize)
        #expect(first.first?.title == "Work \(count - 1)")
        let rest = await store.historyVisits(in: work, before: first.last?.visitedAt)
        #expect(rest.map(\.title) == (0..<5).reversed().map { "Work \($0)" })
        #expect(await store.historyVisits(in: work, matching: "home").isEmpty)
        #expect(await store.historyVisits(in: personal).map(\.title) == ["Home"])
    }

    @Test func deletingVisitsAndSitesTouchesOnlyThatHistory() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = await history.record(url("https://a.example/1"), title: "A1", in: work.dataStoreID)!
        await history.record(url("https://a.example/2"), title: "A2", in: work.dataStoreID)
        await history.record(url("https://b.example/"), title: "B", in: work.dataStoreID)
        await history.record(url("https://c.example/"), title: "C", in: work.dataStoreID)
        await history.record(url("https://b.example/"), title: "Home B", in: personal.dataStoreID)
        await store.deleteHistory(visits: [a], in: work)
        await store.deleteHistory(fromSite: "b.example", in: work)
        #expect(await store.historyVisits(in: work).map(\.title) == ["C", "A2"])
        #expect(await store.historyVisits(in: personal).map(\.title) == ["Home B"])
    }

    @Test func clearingARangeKeepsOlderVisits() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date.now
        await history.record(url("https://old.example/"), title: "Old", at: now - 3 * 60 * 60, in: work.dataStoreID)
        await history.record(url("https://new.example/"), title: "New", at: now - 10 * 60, in: work.dataStoreID)
        await store.clearHistory(.lastHour, in: work, now: now)
        #expect(await store.historyVisits(in: work).map(\.title) == ["Old"])
    }

    @Test func clearingAllWaitsForVisitsBeingSavedAndSparesOtherSpaces() async {
        let (store, history) = makeStores()
        defer { try? FileManager.default.removeItem(at: folder) }
        await history.record(url("https://home.example/"), title: "Home", in: personal.dataStoreID)
        let tab = store.openTab(url("https://a.example/"))
        page(tab).commit(url("https://a.example/"), title: "A") // not yet saved
        await store.clearHistory(.all, in: work)
        #expect(await store.historyVisits(in: work).isEmpty)
        #expect(await store.historyVisits(in: personal).map(\.title) == ["Home"])
    }

    @Test func sharedSpacesShareOneHistory() async {
        let shared = Space(name: "Side", icon: "leaf", color: "sand", order: 2, dataStoreID: work.dataStoreID)
        let history = HistoryStore(directory: folder)
        let store = BrowserStore(spaces: [work, personal, shared], makePage: { FakePage(dataStoreID: $0) }, history: history)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(store.spacesSharingHistory(with: shared).map(\.name) == ["Work", "Side"])
        #expect(store.spacesSharingHistory(with: personal).map(\.name) == ["Personal"])
        await history.record(url("https://a.example/"), title: "A", in: work.dataStoreID)
        await store.clearHistory(.today, in: shared)
        #expect(await store.historyVisits(in: work).isEmpty)
    }

    @Test func clearRangesStartWhereTheyShould() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9, minute: 30))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        #expect(HistoryClearRange.lastHour.start(now: now, calendar: calendar) == now - 60 * 60)
        #expect(HistoryClearRange.today.start(now: now, calendar: calendar) == midnight)
        #expect(HistoryClearRange.todayAndYesterday.start(now: now, calendar: calendar)
            == calendar.date(from: DateComponents(year: 2026, month: 10, day: 24)))
        #expect(HistoryClearRange.all.start(now: now, calendar: calendar) == nil)
    }
}
