import Foundation
import Observation

extension BrowserStore {
    // MARK: - Saving and restoring

    /// Where each tab's page is or was, for the places file: only tabs the
    /// session keeps (not files), and only places small enough to keep.
    public func pagePlaces() -> [UUID: PagePlace] {
        var places: [UUID: PagePlace] = [:]
        for tab in tabs where tab.url?.isFileURL != true {
            places[tab.id] = tab.savedPlace
        }
        return places
    }

    /// The session as it is now, for `SessionSaver`. The window's sidebar
    /// lives in the app, so it's passed in.
    public func session(sidebarWidth: Double, sidebarCollapsed: Bool) -> Session {
        let stamp = now()
        // Files opened from Finder can't be read again after a restart (see `OpenedFiles`).
        let records = tabs.filter { $0.url?.isFileURL != true }.enumerated().map { order, tab in
            var record = TabRecord(
                id: tab.id, spaceID: tab.spaceID, place: tab.place, url: tab.url,
                title: tab.savedTitle, icon: tab.icon, homeURL: tab.homeURL, groupID: tab.groupID,
                splitID: tab.splitID, order: order,
                lastActiveAt: tab.lastActiveAt, openerTabID: tab.openerTabID, driftedAt: tab.driftedAt,
                lastChangedAt: stamp
            )
            if let saved = savedRecords[tab.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groupRecords = groups.enumerated().map { order, group in
            var record = GroupRecord(
                id: group.id, spaceID: group.spaceID, name: group.name, order: order,
                folded: group.folded, tidies: group.tidies ? true : nil, lastChangedAt: stamp
            )
            if let saved = savedGroupRecords[group.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedGroupRecords = Dictionary(groupRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let splitRecords = splits.map { split in
            var record = SplitRecord(
                id: split.id, spaceID: split.spaceID, leftFraction: split.leftFraction, lastChangedAt: stamp
            )
            if let saved = savedSplitRecords[split.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedSplitRecords = Dictionary(splitRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let window = WindowRecord(
            id: windowID, activeSpaceID: activeSpaceID, activeTabID: activeTabID,
            spaceTabIDs: lastTabBySpace.filter { $0.key != activeSpaceID },
            sidebarWidth: sidebarWidth, sidebarCollapsed: sidebarCollapsed
        )
        return Session(
            spaces: spaces, groups: groupRecords, splits: splitRecords, tabs: records, window: window, usedDays: usedDays,
            unseenTidiedSpaceIDs: unseenTidiedSpaces.sorted { $0.uuidString < $1.uuidString }
        )
    }

    /// The saved file is Firn's own, but it's checked as if it weren't: only
    /// web addresses come back, tabs and groups must belong to a space, ids
    /// are unique, Basecamp holds no more than its limit, icons are small
    /// PNGs, group names are tidy, and only everyday tabs sit in a group of
    /// their own space. Groups left with no tabs are dropped, and a group's
    /// tabs are put back together where its first one is. A split view
    /// comes back only with exactly two everyday tabs of its own space; they
    /// go side by side where its first one is, in that one's group.
    /// Each tab with a place in `pagePlaces` at its own address gets its
    /// history back, before any page wakes.
    func restore(_ session: Session, pagePlaces: [UUID: PagePlace]) {
        let spaceIDs = Set(spaces.map(\.id))
        var seenGroups = Set<UUID>()
        let restoredGroups = session.groups.sorted { $0.order < $1.order }.compactMap { record -> TabGroup? in
            guard spaceIDs.contains(record.spaceID), seenGroups.insert(record.id).inserted else { return nil }
            return TabGroup(
                id: record.id, spaceID: record.spaceID,
                name: TabGroup.cleanName(record.name) ?? TabGroup.defaultName, folded: record.folded,
                tidies: record.tidies ?? false
            )
        }
        let groupSpaces = Dictionary(restoredGroups.map { ($0.id, $0.spaceID) }, uniquingKeysWith: { first, _ in first })
        var seenSplits = Set<UUID>()
        let savedSplits = session.splits.compactMap { record -> SplitGroup? in
            guard spaceIDs.contains(record.spaceID), seenSplits.insert(record.id).inserted else { return nil }
            return SplitGroup(id: record.id, spaceID: record.spaceID, leftFraction: record.leftFraction)
        }
        let splitSpaces = Dictionary(savedSplits.map { ($0.id, $0.spaceID) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var basecampCounts: [UUID: Int] = [:]
        let restoredAt = now()
        tabs = session.tabs.sorted { $0.order < $1.order }.compactMap { record in
            guard spaceIDs.contains(record.spaceID), seen.insert(record.id).inserted else { return nil }
            let url = record.url.flatMap(Self.webURL)
            let home = record.homeURL.flatMap(Self.webURL)
            guard url != nil || home != nil else { return nil }
            var place = record.place
            if place == .basecamp {
                basecampCounts[record.spaceID, default: 0] += 1
                if basecampCounts[record.spaceID]! > Self.basecampLimit { place = .open }
            }
            let groupID = record.groupID.flatMap { id in
                place == .open && groupSpaces[id] == record.spaceID ? id : nil
            }
            return Tab(
                id: record.id, spaceID: record.spaceID, place: place, url: url ?? home,
                title: record.title, icon: record.icon.flatMap { SiteIcon.isValidStored($0) ? $0 : nil },
                homeURL: place == .basecamp ? home : nil, groupID: groupID,
                splitID: record.splitID.flatMap { id in place == .open && splitSpaces[id] == record.spaceID ? id : nil },
                openerTabID: record.openerTabID, lastActiveAt: record.lastActiveAt,
                // Tabs from before Drifted tabs (or with a time still to
                // come) start their 30 days now.
                driftedAt: place == .drifted ? min(record.driftedAt ?? restoredAt, restoredAt) : nil
            )
        }
        for tab in tabs {
            if let place = pagePlaces[tab.id] { tab.rest(at: place) }
        }
        // Only pairs make a split; both halves go in the first one's group.
        let halves = Dictionary(grouping: tabs.filter { $0.splitID != nil }, by: { $0.splitID! })
        for (_, members) in halves {
            if members.count == 2 {
                members[1].groupID = members[0].groupID
            } else {
                for tab in members { tab.splitID = nil }
            }
        }
        splits = savedSplits.filter { halves[$0.id]?.count == 2 }
        tabs = Self.keepingGroupsTogether(tabs)
        keepSplitsTogether()
        let usedGroups = Set(tabs.compactMap(\.groupID))
        groups = restoredGroups.filter { usedGroups.contains($0.id) }
        savedRecords = Dictionary(session.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        savedGroupRecords = Dictionary(session.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        savedSplitRecords = Dictionary(session.splits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        usedDays = Self.cleanDays(session.usedDays)
        unseenTidiedSpaces = Set(session.unseenTidiedSpaceIDs).intersection(spaceIDs)
        windowID = session.window.id
        if spaceIDs.contains(session.window.activeSpaceID) { activeSpaceID = session.window.activeSpaceID }
        let tabSpaces = Dictionary(tabs.map { ($0.id, $0.spaceID) }, uniquingKeysWith: { first, _ in first })
        lastTabBySpace = session.window.spaceTabIDs.filter { tabSpaces[$0.value] == $0.key }
        if let id = session.window.activeTabID,
           let tab = tabs.first(where: { $0.id == id && $0.spaceID == activeSpaceID }) {
            show(tab)
        }
    }

    /// The same tabs, with each group's tabs side by side where its first one is.
    static func keepingGroupsTogether(_ tabs: [Tab]) -> [Tab] {
        let members = Dictionary(grouping: tabs.filter { $0.groupID != nil }, by: { $0.groupID! })
        var placed = Set<UUID>()
        return tabs.flatMap { tab -> [Tab] in
            guard let groupID = tab.groupID else { return [tab] }
            return placed.insert(groupID).inserted ? members[groupID] ?? [] : []
        }
    }

    static func webURL(_ url: URL) -> URL? {
        WebAddress.isWebURL(url) ? url : nil
    }
}
