import Foundation
import Observation

extension BrowserStore {
    // MARK: - Reopening

    /// What ⇧⌘T would bring back in the current space, if anything.
    public var nextToReopen: ReopenKind? {
        switch closed.last(where: { $0.spaceID == activeSpaceID }) {
        case .tab: .tab
        case .group: .group
        case nil: nil
        }
    }

    /// Brings back the tab or group closed most recently in the current
    /// space, where it was, and shows it. A tab goes back into its group
    /// if the group is still there (or loose, where it was, if not); a
    /// group comes back whole, open, showing the tab last on screen.
    /// Closed tabs come back asleep, so they load again from their address.
    public func reopenClosed() {
        guard let index = closed.lastIndex(where: { $0.spaceID == activeSpaceID }) else { return }
        reopen(at: index)
    }

    /// The current space's closed tabs and groups, the most recent first,
    /// for the overflow's Recently closed.
    public var recentlyClosed: [ClosedEntry] {
        closed.filter { $0.spaceID == activeSpaceID }.reversed().map { item in
            switch item {
            case let .tab(tab, _, _):
                ClosedEntry(id: tab.id, kind: .tab, title: tab.title, icon: tab.icon)
            case let .group(group, _, _):
                ClosedEntry(id: group.id, kind: .group, title: group.name, icon: nil)
            }
        }
    }

    /// Brings back one item from Recently closed, as ⇧⌘T would.
    public func reopen(_ entry: ClosedEntry) {
        guard let index = closed.lastIndex(where: { $0.spaceID == activeSpaceID && $0.id == entry.id }) else { return }
        reopen(at: index)
    }

    func reopen(at index: Int) {
        switch closed.remove(at: index) {
        case let .tab(tab, position, _) where tab.place == .basecamp:
            // A closed tile goes back among the tiles; with no room left,
            // it comes back as an everyday tab where new tabs go.
            let tiles = list(.basecamp, in: tab.spaceID)
            if tiles.count < Self.basecampLimit {
                insert(tab, at: position, in: tiles)
            } else {
                tab.place = .open
                tab.homeURL = nil
                tab.lastActiveAt = now()
                tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
            }
            select(tab)
        case let .tab(tab, position, listPosition):
            tab.place = .open
            tab.driftedAt = nil
            if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
                insert(tab, at: position, in: tabs(in: group), fallback: arrivalIndex(in: tab.spaceID))
            } else {
                tab.groupID = nil
                insertInTabList([tab], at: listPosition, fallback: arrivalIndex(in: tab.spaceID))
            }
            select(tab)
        case let .group(group, members, position):
            guard !groups.contains(where: { $0.id == group.id }) else { return }
            var group = group
            group.folded = false
            groups.append(group)
            insertInTabList(members, at: position, fallback: arrivalIndex(in: group.spaceID))
            if let recent = members.max(by: { $0.lastActiveAt < $1.lastActiveAt }) { select(recent) }
        }
        keepSplitsTogether()
    }

    /// Remembers an everyday or drifted tab about to close. The last tab of a group
    /// ends the group, so the group is remembered instead, whole.
    func rememberClosing(_ tab: Tab) {
        guard tab.place != .basecamp, tab.url != nil else { return }
        if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
            let members = tabs(in: group)
            if members.count == 1 { return rememberClosing(group, members: members) }
            remember(.tab(
                tab, position: members.firstIndex { $0.id == tab.id } ?? members.count,
                listPosition: tabListPosition(of: groupID, in: tab.spaceID)
            ))
        } else {
            // A drifted tab comes back where new tabs go.
            let position = tab.place == .drifted && newTabPlacement == .top
                ? 0 : tabListPosition(of: tab.id, in: tab.spaceID)
            remember(.tab(tab, position: position, listPosition: position))
        }
    }

    /// Remembers a tile leaving Basecamp, and its place among the tiles.
    func rememberClosingTile(_ tab: Tab) {
        guard tab.homeURL ?? tab.url != nil else { return }
        let tiles = list(.basecamp, in: tab.spaceID)
        let position = tiles.firstIndex { $0.id == tab.id } ?? tiles.count
        remember(.tab(tab, position: position, listPosition: position))
    }

    func rememberClosing(_ group: TabGroup, members: [Tab]) {
        let members = members.filter { $0.url != nil }
        guard !members.isEmpty else { return }
        remember(.group(group, members, position: tabListPosition(of: group.id, in: group.spaceID)))
    }

    func remember(_ item: ClosedItem) {
        closed.append(item)
        if closed.count > Self.closedLimit { closed.removeFirst(closed.count - Self.closedLimit) }
    }

    /// Where a loose tab or group sits in its space's tab list (each group
    /// counting as one).
    func tabListPosition(of id: UUID, in spaceID: UUID) -> Int {
        let items = items(in: spaceID)
        return items.firstIndex { $0.id == id } ?? items.count
    }
}
