import Foundation
import Testing
@testable import FirnCore

/// History in a folder of its own, deleted after each test.
struct HistoryStoreTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "FirnHistoryTests-\(UUID().uuidString)")
    let work = UUID()
    let personal = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeStore() -> HistoryStore { HistoryStore(directory: folder) }

    func url(_ text: String) -> URL { URL(string: text)! }

    @Test func recordsAndReadsNewestFirst() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.record(url("https://example.com/a"), title: "First", at: start, in: work)
        await store.record(url("https://www.Example.com/b"), title: "Second", at: start + 60, in: work)
        let visits = await store.visits(in: work)
        #expect(visits.map(\.title) == ["Second", "First"])
        #expect(visits.first?.site == "example.com")
        #expect(visits.first?.visitedAt == start + 60)
    }

    @Test func onlyWebAddressesAreRecorded() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(await store.record(url("file:///Users/me/page.html"), in: work) == nil)
        #expect(await store.record(url("javascript:alert(1)"), in: work) == nil)
        #expect(await store.record(url("about:blank"), in: work) == nil)
        let long = "https://example.com/" + String(repeating: "a", count: HistoryStore.urlLimit)
        #expect(await store.record(url(long), in: work) == nil)
        #expect(await store.visits(in: work).isEmpty)
    }

    @Test func titleIsFilledInLaterAndKeptShort() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = try #require(await store.record(url("https://example.com"), at: start, in: work))
        #expect(await store.visits(in: work).first?.title == "")
        await store.setTitle("  " + String(repeating: "t", count: 2000) + "  ", ofVisit: id, in: work)
        #expect(await store.visits(in: work).first?.title.count == HistoryStore.titleLimit)
    }

    /// The privacy promise: a separate space never sees another's visits.
    @Test func dataStoresAreSeparate() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.record(url("https://mail.example.com"), title: "Work mail", in: work)
        #expect(await store.visits(in: personal).isEmpty)
        #expect(await store.visits(matching: "mail", in: personal).isEmpty)
        // Reading never makes a file for the other store.
        #expect(Set(await store.storedIDs()) == [work])
    }

    @Test func searchesTitleAddressAndSite() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.record(url("https://news.site/one"), title: "Glacier report", at: start, in: work)
        await store.record(url("https://recipes.example/soup"), title: "Soup", at: start + 1, in: work)
        await store.record(url("https://other.example/100%_off"), title: "Sale", at: start + 2, in: work)
        #expect(await store.visits(matching: "glacier", in: work).map(\.title) == ["Glacier report"])
        #expect(await store.visits(matching: "RECIPES", in: work).map(\.title) == ["Soup"])
        #expect(await store.visits(matching: "/soup", in: work).map(\.title) == ["Soup"])
        // % and _ match only themselves.
        #expect(await store.visits(matching: "%", in: work).map(\.title) == ["Sale"])
        #expect(await store.visits(matching: "_", in: work).map(\.title) == ["Sale"])
        #expect(await store.visits(matching: "'; DROP TABLE visits; --", in: work).isEmpty)
        #expect(await store.visits(in: work).count == 3)
    }

    @Test func readsBackAPageAtATime() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        for minute in 0..<5 {
            await store.record(url("https://example.com/\(minute)"), title: "\(minute)", at: start + Double(minute * 60), in: work)
        }
        let first = await store.visits(limit: 2, in: work)
        #expect(first.map(\.title) == ["4", "3"])
        let next = await store.visits(before: first.last?.visitedAt, limit: 2, in: work)
        #expect(next.map(\.title) == ["2", "1"])
    }

    @Test func deletesVisitsSitesAndTimeRanges() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = try #require(await store.record(url("https://a.example/1"), title: "a1", at: start, in: work))
        await store.record(url("https://a.example/2"), title: "a2", at: start + 10, in: work)
        await store.record(url("https://www.b.example/"), title: "b", at: start + 20, in: work)
        await store.record(url("https://c.example/"), title: "c", at: start + 30, in: work)
        await store.record(url("https://d.example/"), title: "d", at: start + 40, in: work)

        await store.delete(visits: [one], in: work)
        #expect(await store.visits(in: work).map(\.title) == ["d", "c", "b", "a2"])
        await store.deleteAll(fromSite: "B.example", in: work)
        #expect(await store.visits(in: work).map(\.title) == ["d", "c", "a2"])
        await store.deleteVisits(from: start + 30, to: start + 40, in: work)
        #expect(await store.visits(in: work).map(\.title) == ["d", "a2"])
        await store.removeAll(in: work)
        #expect(await store.visits(in: work).isEmpty)
        #expect(await store.storedIDs().isEmpty)
    }

    @Test func visitsOlderThanAYearAreDeleted() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = start + HistoryStore.keptFor + 100
        await store.record(url("https://old.example"), title: "old", at: start, in: work)
        await store.record(url("https://new.example"), title: "new", at: start + 200, in: work)
        await store.record(url("https://old.example"), title: "old", at: start, in: personal)
        await store.removeExpired(now: now)
        #expect(await store.visits(in: work).map(\.title) == ["new"])
        #expect(await store.visits(in: personal).isEmpty)
    }

    @Test func unusedDataStoresAreErased() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.record(url("https://example.com"), in: work)
        await store.record(url("https://example.com"), in: personal)
        await store.removeUnused(keeping: [work])
        #expect(await store.storedIDs() == [work])
        #expect(await store.visits(in: personal).isEmpty)
        #expect(await store.visits(in: work).count == 1)
    }

    /// History survives quitting: a new store reads the same file.
    @Test func visitsComeBackAfterRelaunch() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        await makeStore().record(url("https://example.com"), title: "Kept", in: work)
        #expect(await makeStore().visits(in: work).map(\.title) == ["Kept"])
    }

    @Test func damagedFileStartsFresh() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a database at all, just some words".utf8)
            .write(to: folder.appending(path: "\(work.uuidString).sqlite"))
        let store = makeStore()
        #expect(await store.visits(in: work).isEmpty)
        await store.record(url("https://example.com"), title: "Fresh", in: work)
        #expect(await store.visits(in: work).map(\.title) == ["Fresh"])
    }
}
