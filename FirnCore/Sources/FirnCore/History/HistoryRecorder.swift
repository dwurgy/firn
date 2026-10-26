import Foundation

/// Turns what tabs' pages report (`PageController.onVisit`) into visits in
/// `HistoryStore`: a new visit for each new address, and its title once
/// known. Reloading, or a jump to a #section, isn't a new visit.
@MainActor
final class HistoryRecorder {
    let store: HistoryStore
    /// Each tab's latest visit, to fill in its title or tell a reload. A few
    /// bytes a tab, kept until quit.
    private var current: [UUID: Visit] = [:]
    /// The work handed to the store, one after another, so a title never
    /// arrives before its visit.
    private var queue: Task<Void, Never>?

    private struct Visit {
        let url: URL
        let dataStoreID: UUID
        var title: String
        let id: Task<Int64?, Never>
    }

    init(store: HistoryStore) {
        self.store = store
    }

    /// `tab`'s page, in `dataStoreID`'s store, is on `url`, titled `title`
    /// ("" until known).
    func visited(_ url: URL, title: String, tab: UUID, in dataStoreID: UUID) {
        guard WebAddress.isWebURL(url) else {
            current[tab] = nil
            return
        }
        if var visit = current[tab], visit.dataStoreID == dataStoreID,
           Self.withoutFragment(visit.url) == Self.withoutFragment(url) {
            guard !title.isEmpty, title != visit.title else { return }
            visit.title = title
            current[tab] = visit
            let (store, id, previous) = (store, visit.id, queue)
            queue = Task {
                await previous?.value
                if let id = await id.value { await store.setTitle(title, ofVisit: id, in: dataStoreID) }
            }
            return
        }
        let (store, previous) = (store, queue)
        let id = Task {
            await previous?.value
            return await store.record(url, title: title, in: dataStoreID)
        }
        queue = Task { _ = await id.value }
        current[tab] = Visit(url: url, dataStoreID: dataStoreID, title: title, id: id)
    }

    /// Hands `work` (a delete) to the store after everything before it, so a
    /// visit still being saved can't land after the history was cleared.
    func perform(_ work: @escaping @Sendable (HistoryStore) async -> Void) async {
        let (store, previous) = (store, queue)
        let task = Task {
            await previous?.value
            await work(store)
        }
        queue = task
        await task.value
    }

    /// Waits for everything handed to the store so far (for tests).
    func settled() async {
        await queue?.value
    }

    private static func withoutFragment(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment != nil else { return url }
        parts.fragment = nil
        return parts.url ?? url
    }
}
