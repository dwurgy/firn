import Foundation
import SQLite3
import Testing
@testable import FirnCore

/// History's side of sync: the last 30 days out, other devices' visits in.
struct HistorySyncTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "FirnHistorySyncTests-\(UUID().uuidString)")
    let work = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 60 * 60

    func makeStore() -> HistoryStore { HistoryStore(directory: folder) }

    func visit(_ host: String, at time: Date, id: String = HistoryStore.newSyncID()) -> SyncedVisit {
        SyncedVisit(id: id, dataStoreID: work, url: URL(string: "https://\(host).example/")!, title: host, visitedAt: time)
    }

    @Test func onlyTheLast30DaysGoOut() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.record(URL(string: "https://old.example/")!, at: now - 31 * day, in: work)
        await store.record(URL(string: "https://new.example/")!, title: "New", at: now - 29 * day, in: work)
        let out = await store.syncedVisits(in: work, now: now)
        #expect(out.map(\.url.host) == ["new.example"])
        #expect(out.first.map { HistoryStore.isSyncID($0.id) } == true)
        #expect(out.first?.title == "New")
    }

    @Test func visitsComeInOnceEach() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = visit("a", at: now - day)
        #expect(await store.addSyncedVisits([one, visit("b", at: now - 2 * day)], now: now) == 2)
        var renamed = one
        renamed.title = "A, titled"
        #expect(await store.addSyncedVisits([renamed], now: now) == 0)
        let visits = await store.visits(in: work)
        #expect(visits.count == 2)
        #expect(visits.first?.title == "A, titled")
    }

    @Test func strangeVisitsAreTurnedAway() async {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        var script = visit("a", at: now)
        script.url = URL(string: "javascript:alert(1)")!
        let added = await store.addSyncedVisits([
            script,
            visit("old", at: now - 40 * day),
            visit("future", at: now + 3 * day),
            visit("badid", at: now, id: "'; DROP TABLE visits; --"),
        ], now: now)
        #expect(added == 0)
        #expect(await store.visits(in: work).isEmpty)
    }

    @Test func historyFromBeforeSyncGetsSyncIDs() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A file in the first layout, with one visit.
        var handle: OpaquePointer?
        let path = folder.appending(path: "\(work.uuidString).sqlite").path(percentEncoded: false)
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        sqlite3_exec(handle, """
            CREATE TABLE visits (id INTEGER PRIMARY KEY, url TEXT NOT NULL, site TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '', visited_at REAL NOT NULL);
            INSERT INTO visits (url, site, title, visited_at) VALUES ('https://kept.example/', 'kept.example', 'Kept', \(now.timeIntervalSince1970));
            PRAGMA user_version = 1;
            """, nil, nil, nil)
        sqlite3_close(handle)
        let store = makeStore()
        let out = await store.syncedVisits(in: work, now: now)
        #expect(out.map(\.title) == ["Kept"])
        #expect(out.first.map { HistoryStore.isSyncID($0.id) } == true)
    }
}
