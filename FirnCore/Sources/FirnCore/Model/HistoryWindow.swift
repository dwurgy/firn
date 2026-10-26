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
