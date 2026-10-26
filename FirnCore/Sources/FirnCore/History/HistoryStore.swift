import Foundation
import os
import SQLite3

/// One page visited: its address, its title (empty until the page has one),
/// and when.
public struct HistoryVisit: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let url: URL
    public let title: String
    public let visitedAt: Date
    /// The site, as the address bar shows it at rest ("example.com").
    public let site: String
}

/// Firn's own record of the pages visited, kept per data store like saved
/// passwords: a separate space never sees another's visits, and shared
/// spaces share them. One SQLite file per data store (SQLite is part of
/// macOS), in Firn's Application Support folder; it never leaves the Mac.
/// Visits are kept for a year.
///
/// An actor, so each file is only ever used from one place at a time.
public actor HistoryStore {
    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "history")

    /// How long visits are kept (David, 2026-10-25: a year, no setting).
    public static let keptFor: TimeInterval = 365 * 24 * 60 * 60
    /// Longer addresses aren't recorded; longer titles are shortened. A page
    /// chooses both, so neither may grow the file without limit.
    static let urlLimit = 8192
    static let titleLimit = 512

    private let directory: URL
    private var open: [UUID: Database] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Firn/History` (in the container).
    public static let standard = HistoryStore(
        directory: URL.applicationSupportDirectory.appending(path: "Firn/History")
    )

    // MARK: Recording

    /// Records a visit to an http or https address and returns its id (to
    /// fill in the title later), or nil if the address isn't one Firn keeps.
    @discardableResult
    public func record(_ url: URL, title: String = "", at time: Date = .now, in dataStoreID: UUID) -> Int64? {
        guard WebAddress.isWebURL(url) else { return nil }
        let address = url.absoluteString
        guard address.utf8.count <= Self.urlLimit else { return nil }
        let site = WebAddress.site(of: url).lowercased()
        return try? database(for: dataStoreID).insert(
            url: address, site: site, title: Self.trimmed(title), at: time.timeIntervalSince1970
        )
    }

    /// Fills in (or changes) a visit's title once the page has one.
    public func setTitle(_ title: String, ofVisit id: Int64, in dataStoreID: UUID) {
        try? database(for: dataStoreID).run(
            "UPDATE visits SET title = ? WHERE id = ?", .text(Self.trimmed(title)), .integer(id)
        )
    }

    // MARK: Reading

    /// Visits, newest first: all of them, or those whose title, address, or
    /// site contains `search` (ignoring case). `before` reads further back,
    /// a page at a time.
    public func visits(
        matching search: String = "", before: Date? = nil, limit: Int = 500, in dataStoreID: UUID
    ) -> [HistoryVisit] {
        guard let db = try? existingDatabase(for: dataStoreID) else { return [] }
        var conditions: [String] = []
        var values: [Database.Value] = []
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            let pattern = "%" + Self.escapedForLike(search) + "%"
            conditions.append("(title LIKE ?1 ESCAPE '\\' OR url LIKE ?1 ESCAPE '\\' OR site LIKE ?1 ESCAPE '\\')")
            values.append(.text(pattern))
        }
        if let before {
            conditions.append("visited_at < ?\(values.count + 1)")
            values.append(.real(before.timeIntervalSince1970))
        }
        values.append(.integer(Int64(max(limit, 0))))
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = """
            SELECT id, url, title, visited_at, site FROM visits \(filter)
            ORDER BY visited_at DESC, id DESC LIMIT ?\(values.count)
            """
        return (try? db.select(sql, values) { row in
            guard let url = URL(string: row.text(1)) else { return nil }
            return HistoryVisit(
                id: row.integer(0), url: url, title: row.text(2),
                visitedAt: Date(timeIntervalSince1970: row.real(3)), site: row.text(4)
            )
        }) ?? []
    }

    // MARK: Deleting

    public func delete(visits ids: [Int64], in dataStoreID: UUID) {
        guard !ids.isEmpty, let db = try? existingDatabase(for: dataStoreID) else { return }
        try? db.transaction {
            for id in ids { try db.run("DELETE FROM visits WHERE id = ?", .integer(id)) }
        }
    }

    /// Deletes every visit to a site ("example.com", as `HistoryVisit.site`).
    public func deleteAll(fromSite site: String, in dataStoreID: UUID) {
        try? existingDatabase(for: dataStoreID)?.run("DELETE FROM visits WHERE site = ?", .text(site.lowercased()))
    }

    /// Deletes the visits from `start` up to (not including) `end`.
    public func deleteVisits(from start: Date, to end: Date, in dataStoreID: UUID) {
        try? existingDatabase(for: dataStoreID)?.run(
            "DELETE FROM visits WHERE visited_at >= ? AND visited_at < ?",
            .real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)
        )
    }

    /// Deletes visits older than a year, in every data store. Called at launch.
    public func removeExpired(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Self.keptFor).timeIntervalSince1970
        for id in storedIDs() {
            try? existingDatabase(for: id)?.run("DELETE FROM visits WHERE visited_at < ?", .real(cutoff))
        }
    }

    /// Erases all of a data store's history (Clear History, or a data store
    /// no space uses any more): the file itself goes.
    public func removeAll(in dataStoreID: UUID) {
        removeFile(for: dataStoreID)
    }

    /// Erases the history of every data store not in `keeping`: what's left
    /// of spaces deleted while Firn couldn't erase it. Like
    /// `BrowserEngine.removeUnusedData`, only with the spaces of a session
    /// that really loaded.
    public func removeUnused(keeping: Set<UUID>) {
        for id in storedIDs() where !keeping.contains(id) { removeFile(for: id) }
    }

    // MARK: Files

    private func fileURL(for dataStoreID: UUID) -> URL {
        directory.appending(path: "\(dataStoreID.uuidString).sqlite")
    }

    /// The data stores that have a history file.
    func storedIDs() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".sqlite") else { return nil }
            return UUID(uuidString: String(name.dropLast(".sqlite".count)))
        }
    }

    /// The data store's open file, made if it doesn't exist yet.
    private func database(for dataStoreID: UUID) throws -> Database {
        if let db = open[dataStoreID] { return db }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: dataStoreID)
        let db: Database
        do {
            db = try Database(url: url)
        } catch let failure as Database.Failure where failure.isDamaged {
            // A damaged file is let go rather than kept: history isn't worth
            // stopping for, and an unreadable file only holds visits.
            Self.log.error("A history file couldn't be read; started it fresh")
            removeFile(for: dataStoreID)
            db = try Database(url: url)
        }
        open[dataStoreID] = db
        return db
    }

    /// The data store's file only if it already exists: reading or deleting
    /// never makes one.
    private func existingDatabase(for dataStoreID: UUID) throws -> Database? {
        if let db = open[dataStoreID] { return db }
        guard FileManager.default.fileExists(atPath: fileURL(for: dataStoreID).path(percentEncoded: false)) else {
            return nil
        }
        return try database(for: dataStoreID)
    }

    private func removeFile(for dataStoreID: UUID) {
        open[dataStoreID] = nil // closes it
        let url = fileURL(for: dataStoreID)
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
        }
    }

    private static func trimmed(_ title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.count > titleLimit ? String(title.prefix(titleLimit)) : title
    }

    /// `%`, `_`, and `\` match themselves in a search, not anything.
    private static func escapedForLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

// MARK: - SQLite

/// A small wrapper around one SQLite file: just what history needs. Every
/// value is bound, never put into the SQL, so nothing a page chooses can
/// change a statement.
final class Database {
    enum Value {
        case text(String), integer(Int64), real(Double)
    }

    struct Row {
        fileprivate let statement: OpaquePointer
        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    }

    struct Failure: Error {
        let code: Int32
        /// Not a database, or a damaged one (never a full disk or a lock).
        var isDamaged: Bool { code == SQLITE_NOTADB || code == SQLITE_CORRUPT }
    }

    private let handle: OpaquePointer

    init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(url.path(percentEncoded: false), &handle, flags, nil)
        guard code == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw Failure(code: code)
        }
        self.handle = handle
        do {
            // Deleted visits are overwritten on disk, not just unlinked.
            try execute("PRAGMA secure_delete = ON")
            try execute("""
                CREATE TABLE IF NOT EXISTS visits (
                    id INTEGER PRIMARY KEY,
                    url TEXT NOT NULL,
                    site TEXT NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    visited_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS visits_time ON visits(visited_at);
                CREATE INDEX IF NOT EXISTS visits_site ON visits(site);
                PRAGMA user_version = 1;
                """)
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func insert(url: String, site: String, title: String, at time: Double) throws -> Int64 {
        try run(
            "INSERT INTO visits (url, site, title, visited_at) VALUES (?, ?, ?, ?)",
            .text(url), .text(site), .text(title), .real(time)
        )
        return sqlite3_last_insert_rowid(handle)
    }

    func run(_ sql: String, _ values: Value...) throws {
        try step(sql, values) { _ in }
    }

    func select<T>(_ sql: String, _ values: [Value], _ read: (Row) -> T?) throws -> [T] {
        var results: [T] = []
        try step(sql, values) { row in if let value = read(row) { results.append(value) } }
        return results
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Runs SQL with no values (setup and transactions).
    private func execute(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw Failure(code: code) }
    }

    private func step(_ sql: String, _ values: [Value], _ each: (Row) -> Void) throws {
        var statement: OpaquePointer?
        var code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw Failure(code: code) }
        defer { sqlite3_finalize(statement) }
        // SQLite copies each value before this returns (SQLITE_TRANSIENT).
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let .text(text): code = sqlite3_bind_text(statement, position, text, -1, transient)
            case let .integer(number): code = sqlite3_bind_int64(statement, position, number)
            case let .real(number): code = sqlite3_bind_double(statement, position, number)
            }
            guard code == SQLITE_OK else { throw Failure(code: code) }
        }
        while true {
            code = sqlite3_step(statement)
            if code == SQLITE_ROW { each(Row(statement: statement)); continue }
            guard code == SQLITE_DONE else { throw Failure(code: code) }
            return
        }
    }
}
