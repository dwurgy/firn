import FirnCore
import SwiftUI

// TestFlight's grid on iOS 27: iOS's own hold menu and iOS's own drag to
// reorder (docs/IOS-PLAN.md, "Plan: iOS's own menus and drag", step 1).
// SwiftUI's `.reorderable()` (new in iOS 27) gives the system's lift, the
// gap that opens as cards make room, and the landing, across rows and
// columns, which the list's own drag (up and down only) never could; and
// it hands off from `.contextMenu` as Safari's grid does. So no UIKit
// collection view is needed. On iOS 26, and in the list, Firn's own menu
// and drag stay: the two are never mixed on the same card.

/// Where a card can be put down in the grid: a run of loose tabs (keyed
/// by the group just before it, nil at the top), a folder's name line (a
/// collection of one, so a folder itself can be moved), or an open
/// folder's tabs.
enum GridCollection: Hashable, Sendable {
    case loose(after: UUID?)
    case line(UUID)
    case tabs(UUID)
}

/// One card, or a folder's name line, as the reorder sees it.
struct GridEntry: Identifiable {
    let id: UUID
    /// Its place in its own list, for VoiceOver's moves.
    let index: Int
    let tab: FirnCore.Tab?
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
            }
        }
    }

    /// The space's list, groups as one, without the thing that moves.
    @MainActor private func top(without id: UUID, in store: BrowserStore) -> [UUID] {
        store.tabListItems.map(\.id).filter { $0 != id }
    }

    /// Where a drop into a loose run or onto a folder's line lands in the
    /// space's list, or nil if that place is gone.
    @MainActor private func listPosition(without id: UUID, in store: BrowserStore) -> Int? {
        let top = top(without: id, in: store)
        switch collection {
        case let .line(group):
            guard let at = top.firstIndex(of: group) else { return nil }
            return before == nil ? at + 1 : at
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

/// The grid's reorder container, on iOS 27 only, around the whole list
/// (Basecamp has none of it yet: step 2).
struct GridReorderContainer: ViewModifier {
    let on: Bool
    let enabled: Bool
    /// What iOS's drag is carrying, as it changes (empty once it lands).
    let dragging: (Set<UUID>) -> Void
    let move: (GridMove) -> Void

    func body(content: Content) -> some View {
        if on, #available(iOS 27, *) {
            content.onDragSessionUpdated { session in
                // Through the landing too: the X comes back once it's down.
                switch session.phase {
                case .ended, .dataTransferCompleted: dragging([])
                default: dragging(Set(session.draggedItemIDs(for: UUID.self)))
                }
            }
            .reorderContainer(for: GridEntry.self, in: GridCollection.self, isEnabled: enabled) { difference in
                let before: UUID? = switch difference.destination.position {
                case let .before(id): id
                case .end: nil
                }
                move(GridMove(sources: difference.sources, collection: difference.destination.collectionID,
                              before: before))
            }
        } else {
            content
        }
    }
}

/// iOS's own hold menu, from the same choices as Firn's (`HoldMenuItem`):
/// the same words and symbols, sections set apart by lines, Move to Group
/// a submenu. Close rows in iOS's destructive red, as every app's (David,
/// 2026-11-17). The choices are made only as the menu opens.
struct SystemHoldMenu: View {
    let sections: () -> [[HoldMenuItem]]
    /// Told as the menu opens and closes.
    var opened: (Bool) -> Void = { _ in }

    var body: some View {
        let sections = sections()
        ForEach(sections.indices, id: \.self) { s in
            Section {
                ForEach(sections[s].indices, id: \.self) { i in
                    Self.item(sections[s][i])
                }
            }
        }
        .onAppear { opened(true) }
        .onDisappear { opened(false) }
    }

    @ViewBuilder private static func item(_ item: HoldMenuItem) -> some View {
        if !item.children.isEmpty {
            if let symbol = item.systemImage {
                Menu(item.title, systemImage: symbol) { children(item) }
            } else {
                Menu(item.title) { children(item) }
            }
        } else if let symbol = item.systemImage {
            Button(item.title, systemImage: symbol, role: item.closes ? .destructive : nil, action: item.action)
        } else {
            Button(item.title, role: item.closes ? .destructive : nil, action: item.action)
        }
    }

    private static func children(_ item: HoldMenuItem) -> some View {
        ForEach(item.children.indices, id: \.self) { i in
            Button(item.children[i].title, action: item.children[i].action)
        }
    }
}

extension View {
    /// iOS's hold menu on a grid card or a folder's name line, lifting it
    /// in the shape given, and the same shape for the drag that can follow.
    @ViewBuilder func systemHoldMenu(_ on: Bool, shape: some Shape,
                                     opened: @escaping (Bool) -> Void = { _ in },
                                     sections: @escaping () -> [[HoldMenuItem]]) -> some View {
        if on {
            contentShape(.contextMenuPreview, shape)
                .contentShape(.dragPreview, shape)
                .contextMenu { SystemHoldMenu(sections: sections, opened: opened) }
        } else {
            self
        }
    }
}

/// The drag's lift for a grid card: its picture only, the title under it
/// left out, the same shape iOS's menu lifts (as Safari's).
struct GridDragShape: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.contentShape(.dragPreview, OverviewRow.gridPictureShape)
        } else {
            content
        }
    }
}
