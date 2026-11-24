import FirnCore
import SwiftUI

// A card's move in the grid (`GridCards`, `OverviewGridCards.swift`), in
// the store's terms. The collection view says what moved and where; this
// carries it out.

/// Where a card can be put down in the grid: a run of loose tabs and
/// folded groups (keyed by the open group just before it, nil at the
/// top), or an open group's tabs.
enum GridCollection: Hashable, Sendable {
    case loose(after: UUID?)
    case tabs(UUID)
}

/// A finished reorder in Firn's own terms: what moved, into which
/// collection, and before which item (nil: at the end).
struct GridMove {
    let sources: [UUID]
    let collection: GridCollection
    let before: UUID?
    /// Folded groups that sit in a run as one cell, so a drop at a run's
    /// end lands after them too (`OverviewGridRun.runs`).
    var inRun: @MainActor (TabGroup) -> Bool = { _ in false }

    /// Carries the move out in the store: a tab among loose tabs, into or
    /// out of a folder, or a folder among the loose tabs and folders.
    /// Positions follow the store's rules (not counting what moves, each
    /// group counting as one).
    @MainActor func apply(to store: BrowserStore) {
        for id in sources {
            if let group = store.tabGroups.first(where: { $0.id == id }) {
                move(group, in: store)
            } else if let tab = store.openTabs.first(where: { $0.id == id }) {
                move(tab, in: store)
            } else if let tile = store.basecampTabs.first(where: { $0.id == id }) {
                moveOut(tile, in: store)
            }
        }
    }

    /// A Basecamp tile let go among the tabs: an everyday tab right there,
    /// in the list or in an open group.
    @MainActor private func moveOut(_ tile: FirnCore.Tab, in store: BrowserStore) {
        if case let .tabs(groupID) = collection {
            guard let group = store.tabGroups.first(where: { $0.id == groupID }) else { return }
            let members = store.tabs(in: group).map(\.id)
            store.removeFromBasecamp(tile, toGroup: group,
                                     at: before.flatMap { members.firstIndex(of: $0) } ?? members.count)
        } else if let at = listPosition(without: tile.id, in: store) {
            store.removeFromBasecamp(tile, toGroup: nil, at: at)
        }
    }

    /// The space's list, groups as one, without the thing that moves.
    @MainActor private func top(without id: UUID, in store: BrowserStore) -> [UUID] {
        store.tabListItems.map(\.id).filter { $0 != id }
    }

    /// Where a drop into a loose run lands in the
    /// space's list, or nil if that place is gone.
    @MainActor private func listPosition(without id: UUID, in store: BrowserStore) -> Int? {
        let top = top(without: id, in: store)
        switch collection {
        case let .loose(after):
            if let before { return top.firstIndex(of: before) }
            // The run's end: just before the next group after the run.
            let start = after.flatMap { top.firstIndex(of: $0).map { $0 + 1 } } ?? 0
            let items = store.tabListItems.filter { $0.id != id }
            var end = start
            while end < items.count {
                switch items[end] {
                case .tab: end += 1
                case let .group(group) where inRun(group): end += 1
                case .group: return end
                }
            }
            return end
        case .tabs:
            return nil
        }
    }

    @MainActor private func move(_ tab: FirnCore.Tab, in store: BrowserStore) {
        if case let .tabs(groupID) = collection {
            guard let group = store.tabGroups.first(where: { $0.id == groupID }) else { return }
            let members = store.tabs(in: group).map(\.id).filter { $0 != tab.id }
            let at = before.flatMap { members.firstIndex(of: $0) } ?? members.count
            store.move(tab, toGroup: group, at: at)
        } else if let at = listPosition(without: tab.id, in: store) {
            store.move(tab, toGroup: nil, at: at)
        }
    }

    /// A folder moves among the loose tabs and folders; put down among
    /// another folder's tabs, it stays where it was (folders never nest).
    @MainActor private func move(_ group: TabGroup, in store: BrowserStore) {
        guard let at = listPosition(without: group.id, in: store) else { return }
        store.move(group, to: at)
    }
}
