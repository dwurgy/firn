import Foundation

extension BrowserStore {
    /// How many visits the History window reads at a time.
    public static let historyPageSize = 300

    /// `space`'s visits for the History window, newest first: all of them, or
    /// those matching `search`. `before` reads further back, a page at a
    /// time. Only that space's data store is read, so a separate space never
    /// sees another's visits.
    public func historyVisits(
        in space: Space, matching search: String = "", before: Date? = nil
    ) async -> [HistoryVisit] {
        guard let store = history?.store else { return [] }
        return await store.visits(
            matching: search, before: before, limit: Self.historyPageSize, in: space.dataStoreID
        )
    }
}

/// How much Clear History… clears, as in Safari.
public enum HistoryClearRange: String, CaseIterable, Identifiable, Sendable {
    case lastHour, today, todayAndYesterday, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lastHour: "The last hour"
        case .today: "Today"
        case .todayAndYesterday: "Today and yesterday"
        case .all: "All history"
        }
    }

    /// Where the cleared visits start, or nil for all of them.
    public func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .lastHour: now.addingTimeInterval(-60 * 60)
        case .today: calendar.startOfDay(for: now)
        case .todayAndYesterday: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case .all: nil
        }
    }
}

extension BrowserStore {
    /// The spaces whose history is `space`'s: itself, and any sharing its
    /// sign-ins (one data store), in sidebar order.
    public func spacesSharingHistory(with space: Space) -> [Space] {
        spaces.filter { $0.dataStoreID == space.dataStoreID }
    }

    /// Deletes these visits from `space`'s history.
    public func deleteHistory(visits ids: [Int64], in space: Space) async {
        let dataStoreID = space.dataStoreID
        await history?.perform { await $0.delete(visits: ids, in: dataStoreID) }
    }

    /// Deletes every visit to `site` (as `HistoryVisit.site`) from `space`'s
    /// history.
    public func deleteHistory(fromSite site: String, in space: Space) async {
        let dataStoreID = space.dataStoreID
        await history?.perform { await $0.deleteAll(fromSite: site, in: dataStoreID) }
    }

    /// Clear History…: the visits in `range`, from `space`'s history (and so
    /// from every space sharing it). All history erases the file itself.
    /// Sign-ins, open tabs, and their back and forward lists stay.
    public func clearHistory(_ range: HistoryClearRange, in space: Space, now: Date = .now) async {
        let dataStoreID = space.dataStoreID
        let start = range.start(now: now)
        await history?.perform { store in
            if let start {
                await store.deleteVisits(from: start, to: .distantFuture, in: dataStoreID)
            } else {
                await store.removeAll(in: dataStoreID)
            }
        }
    }
}
