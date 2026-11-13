import Foundation

// iCloud sync's side of the store (docs/SYNC-PLAN.md, step 2): what this
// device changed, and applying what other devices changed. Spaces, groups
// kept by hand, and their tabs sync; loose tabs, Basecamp, a group's place
// in the list, and folding stay on each device.

extension BrowserStore {
    // MARK: - Sending

    /// Takes this device's changes since the last look into `state` and
    /// returns what to send. The app calls it whenever it saves the session.
    public func takeSyncChanges(into state: inout SyncState) -> SyncChanges {
        let stamp = now()
        let fields = syncFields()
        var changes = SyncChanges()

        // Tabs said to have left their group last time: their records go now.
        for id in state.announced.sorted(by: Self.byID) where state.tabs[id]?.groupID == nil {
            if state.tabs.removeValue(forKey: id) != nil { changes.deletes.append(Self.recordID(.tab, id)) }
        }
        state.announced = []

        Self.takeEdits(fields.spaces, seen: state.seen.spaces, into: &state.spaces, at: stamp, as: SyncItem.space, &changes)
        Self.takeEdits(fields.groups, seen: state.seen.groups, into: &state.groups, at: stamp, as: SyncItem.group, &changes)
        Self.takeEdits(fields.tabs, seen: state.seen.tabs, into: &state.tabs, at: stamp, as: SyncItem.tab, &changes)

        // Gone from here since the last look.
        for id in state.seen.tabs.keys.sorted(by: Self.byID) where fields.tabs[id] == nil {
            guard var record = state.tabs[id] else { continue }
            if tabs.contains(where: { $0.id == id }) {
                // Still here, out of its group: other devices keep it loose.
                record.groupID = nil
                record.changedAt = stamp
                state.tabs[id] = record
                state.announced.insert(id)
                changes.saves.append(.tab(record))
            } else {
                state.tabs[id] = nil
                changes.deletes.append(Self.recordID(.tab, id))
            }
        }
        for id in state.seen.groups.keys.sorted(by: Self.byID) where fields.groups[id] == nil {
            if state.groups.removeValue(forKey: id) != nil { changes.deletes.append(Self.recordID(.group, id)) }
        }
        for id in state.seen.spaces.keys.sorted(by: Self.byID) where fields.spaces[id] == nil {
            if state.spaces.removeValue(forKey: id) != nil { changes.deletes.append(Self.recordID(.space, id)) }
        }

        state.seen = fields
        // In iCloud's terms: a joined space goes by its iCloud id.
        return SyncChanges(saves: changes.saves.map(state.toCloud), deletes: changes.deletes.map(state.toCloud))
    }

    /// The fields that sync, as they are here now: every space, groups kept
    /// by hand (not ones a link made that still tidy away), and their tabs.
    func syncFields() -> SyncState.Fields {
        var fields = SyncState.Fields()
        for (index, space) in spaces.enumerated() {
            fields.spaces[space.id] = SyncedSpace(
                id: space.id, name: space.name, color: space.color, order: index,
                dataStoreID: space.dataStoreID, changedAt: .distantPast
            )
        }
        for group in groups where !group.tidies {
            fields.groups[group.id] = SyncedGroup(id: group.id, spaceID: group.spaceID, name: group.name, changedAt: .distantPast)
            let members = tabs.filter { $0.groupID == group.id && $0.place == .open }
            for (index, tab) in members.enumerated() {
                guard let url = tab.url.flatMap(Self.webURL) else { continue }
                fields.tabs[tab.id] = SyncedTab(
                    id: tab.id, spaceID: tab.spaceID, groupID: group.id, url: url,
                    title: Self.syncTitle(tab.savedTitle), order: index, changedAt: .distantPast
                )
            }
        }
        return fields
    }

    /// Fields edited here since the last look become records, stamped now.
    private static func takeEdits<T: SyncedFields>(
        _ fields: [UUID: T], seen: [UUID: T], into records: inout [UUID: T], at stamp: Date,
        as wrap: (T) -> SyncItem, _ changes: inout SyncChanges
    ) {
        for id in fields.keys.sorted(by: byID) {
            guard var item = fields[id], seen[id] != item else { continue }
            item.changedAt = stamp
            if let record = records[id], record.sameFields(as: item) { continue }
            records[id] = item
            changes.saves.append(wrap(item))
        }
    }

    // MARK: - Receiving

    /// Applies records from other devices: saves (spaces first, then groups,
    /// then tabs) and deletes. This device's own changes are taken first,
    /// and returned to send. Visits are history's (`HistoryStore`), not the
    /// store's, and are passed over here.
    public func applySync(saves: [SyncItem], deletes: [SyncRecordID], to state: inout SyncState) -> SyncApplied {
        var toSend = takeSyncChanges(into: &state)
        var waiting: [SyncItem] = []
        var spaceSaves: [SyncedSpace] = []
        var groupSaves: [SyncedGroup] = []
        var tabSaves: [SyncedTab] = []
        for item in saves {
            switch item {
            case let .space(space): spaceSaves.append(space)
            case let .group(group): groupSaves.append(group)
            case let .tab(tab): tabSaves.append(tab)
            case .visit: break
            }
        }
        // Spaces first, so groups and tabs can be put in this device's terms.
        for space in spaceSaves.sorted(by: { $0.order < $1.order }) {
            if !state.firstSyncDone { join(space, in: &state) }
            apply(state.fromCloud(space), to: &state)
        }
        if !state.firstSyncDone { giveWay(in: &state) }
        // A space that joined goes by iCloud's id now, and one that gave way
        // is gone: what was taken to send is taken again in today's terms.
        toSend.saves = toSend.saves.compactMap { state.item(for: $0.id) }

        for group in groupSaves where !apply(state.fromCloud(group), to: &state) { waiting.append(.group(group)) }
        // Tabs leaving a group go last first: each lands just below what's
        // left of it, so a whole group ungrouped keeps its order.
        let joining = tabSaves.filter { $0.groupID != nil }.sorted { $0.order < $1.order }
        let leaving = tabSaves.filter { $0.groupID == nil }.sorted { $0.order > $1.order }
        for tab in joining + leaving where !apply(state.fromCloud(tab), to: &state) { waiting.append(.tab(tab)) }

        let deleted = { (kind: SyncKind) in deletes.filter { $0.kind == kind }.compactMap { UUID(uuidString: $0.name) } }
        for id in deleted(.tab) { applyTabDelete(id, to: &state) }
        for id in deleted(.group) { applyGroupDelete(id, to: &state) }
        for id in deleted(.space) { applySpaceDelete(state.localSpace(id), to: &state) }

        // What's here now came in: it isn't an edit of this device's.
        state.seen = syncFields()
        return SyncApplied(toSend: toSend, waiting: waiting)
    }

    /// Whether an incoming change is newer than the record this device has.
    /// (Two changes stamped in the very same instant are near impossible.)
    private static func isNewer(_ incoming: Date, than known: Date?) -> Bool {
        incoming > (known ?? .distantPast)
    }

    private func apply(_ incoming: SyncedSpace, to state: inout SyncState) {
        state.arrived.insert(incoming.id)
        guard Self.isNewer(incoming.changedAt, than: state.spaces[incoming.id]?.changedAt) else { return }
        var record = incoming
        let position = min(max(incoming.order, 0), spaces.count)
        if let index = spaces.firstIndex(where: { $0.id == incoming.id }) {
            var space = spaces.remove(at: index)
            record.name = Space.cleanName(incoming.name) ?? space.name
            record.color = Self.syncColor(incoming.color) ?? space.color
            let oldDataStoreID = space.dataStoreID
            space.name = record.name
            space.color = record.color
            space.dataStoreID = incoming.dataStoreID
            space.lastChangedAt = now()
            spaces.insert(space, at: min(position, spaces.count))
            if oldDataStoreID != incoming.dataStoreID { moved(space, from: oldDataStoreID) }
        } else {
            record.name = Space.cleanName(incoming.name) ?? Space.defaultName
            record.color = Self.syncColor(incoming.color) ?? "glacier"
            spaces.insert(
                Space(id: incoming.id, name: record.name, color: record.color, order: position,
                      dataStoreID: incoming.dataStoreID, lastChangedAt: now()),
                at: position
            )
        }
        renumberSpaces()
        state.spaces[incoming.id] = record
    }

    /// The first sync (David, 2026-11-13): a space of this device's that
    /// never synced joins an arriving one of the same name. It keeps its id,
    /// tabs, groups, Basecamp, and data store here (so its sign-ins, history,
    /// and saved passwords stay), and goes by the other's ids in iCloud.
    private func join(_ incoming: SyncedSpace, in state: inout SyncState) {
        guard state.joinedSpaces[incoming.id] == nil, !spaces.contains(where: { $0.id == incoming.id }),
              let name = Space.cleanName(incoming.name) else { return }
        let joined = Set(state.joinedSpaces.values)
        guard let local = spaces.first(where: {
            !state.arrived.contains($0.id) && !joined.contains($0.id)
                && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) else { return }
        // Its data store is kept by iCloud's id for it. If either id already
        // stands for another (spaces that share sign-ins on one device but
        // not the other), it doesn't join, and arrives as a new space.
        if let kept = state.joinedStores[incoming.dataStoreID] {
            guard kept == local.dataStoreID else { return }
        } else if incoming.dataStoreID != local.dataStoreID {
            guard !spaces.contains(where: { $0.dataStoreID == incoming.dataStoreID }),
                  state.remoteStore(local.dataStoreID) == local.dataStoreID else { return }
            state.joinedStores[incoming.dataStoreID] = local.dataStoreID
        }
        state.joinedSpaces[incoming.id] = local.id
        // Its record so far was this device's own and never went up: iCloud's
        // name, color, and order come in fresh.
        state.spaces[local.id] = nil
    }

    /// The first sync: a space of this device's that never synced, with no
    /// tabs, tiles, or groups, gives way once others have arrived.
    private func giveWay(in state: inout SyncState) {
        guard spaces.contains(where: { state.arrived.contains($0.id) }) else { return }
        let joined = Set(state.joinedSpaces.values)
        for space in spaces where !state.arrived.contains(space.id) && !joined.contains(space.id) {
            guard spaces.count > 1, !tabs.contains(where: { $0.spaceID == space.id }),
                  !groups.contains(where: { $0.spaceID == space.id }) else { continue }
            state.spaces[space.id] = nil
            deleteSpace(space)
        }
    }

    /// A space stopped sharing on another device: its pages start again in
    /// its new data store, signed out, and the old one goes if no space uses it.
    private func moved(_ space: Space, from oldDataStoreID: UUID) {
        if lookout?.spaceID == space.id { closeLookout() }
        let onScreen = onScreenTabIDs
        for tab in tabs where tab.spaceID == space.id {
            tab.sleep()
            tab.forgetPlace()
            if onScreen.contains(tab.id) { wake(tab) }
        }
        releaseIfUnused(oldDataStoreID)
    }

    /// False if its space hasn't arrived yet.
    private func apply(_ incoming: SyncedGroup, to state: inout SyncState) -> Bool {
        guard spaces.contains(where: { $0.id == incoming.spaceID }) else { return false }
        guard Self.isNewer(incoming.changedAt, than: state.groups[incoming.id]?.changedAt) else { return true }
        var record = incoming
        if let index = groups.firstIndex(where: { $0.id == incoming.id }) {
            guard groups[index].spaceID == incoming.spaceID else { return true }
            record.name = TabGroup.cleanName(incoming.name) ?? groups[index].name
            groups[index].name = record.name
            groups[index].tidies = false
            unnamedGroups[incoming.id] = nil
        } else {
            record.name = TabGroup.cleanName(incoming.name) ?? TabGroup.defaultName
            // It shows once its first tab arrives.
            groups.append(TabGroup(id: incoming.id, spaceID: incoming.spaceID, name: record.name))
        }
        state.groups[incoming.id] = record
        return true
    }

    /// False if its group hasn't arrived yet.
    private func apply(_ incoming: SyncedTab, to state: inout SyncState) -> Bool {
        guard let url = Self.webURL(incoming.url) else { return true }
        let local = tabs.first { $0.id == incoming.id }
        guard let groupID = incoming.groupID else {
            // It left its group on the other device: it's loose here too,
            // and its record is on its way out.
            guard Self.isNewer(incoming.changedAt, than: state.tabs[incoming.id]?.changedAt) else { return true }
            if let local, local.groupID != nil, local.spaceID == incoming.spaceID { takeOutOfGroup(local) }
            state.tabs[incoming.id] = nil
            return true
        }
        guard let group = groups.first(where: { $0.id == groupID }), group.spaceID == incoming.spaceID else {
            return false
        }
        guard Self.isNewer(incoming.changedAt, than: state.tabs[incoming.id]?.changedAt) else { return true }
        var record = incoming
        record.url = url
        record.title = Self.syncTitle(incoming.title)
        state.tabs[incoming.id] = record

        // Its place among the group's tabs here, by their records' order.
        let members = tabs(in: group).filter { $0.id != incoming.id }
        let position = members.filter { (state.tabs[$0.id]?.order ?? .max) < incoming.order }.count
        if let local {
            guard local.spaceID == incoming.spaceID, local.place == .open else { return true }
            local.follow(url, title: record.title, onScreen: onScreenTabIDs.contains(local.id))
            let current = tabs(in: group).firstIndex { $0.id == local.id }
            if local.groupID != groupID || current != position { move(local, into: group, at: position) }
        } else {
            let tab = Tab(
                id: incoming.id, spaceID: incoming.spaceID, place: .open, url: url, title: record.title,
                groupID: groupID, lastActiveAt: incoming.changedAt
            )
            insert(tab, at: position, in: members, fallback: arrivalIndex(in: incoming.spaceID))
        }
        return true
    }

    /// A tab closed on another device closes here too, if its record had a
    /// group (one whose record said it was loose was only tidying up).
    private func applyTabDelete(_ id: UUID, to state: inout SyncState) {
        guard let record = state.tabs.removeValue(forKey: id), record.groupID != nil,
              let tab = tabs.first(where: { $0.id == id }), tab.spaceID == record.spaceID,
              tab.place == .open else { return }
        close(tab)
    }

    /// A group gone on another device: its tabs stay here, loose, until
    /// that device's word on each arrives (closed, or kept loose). Nothing
    /// is lost if the word comes late, or never.
    private func applyGroupDelete(_ id: UUID, to state: inout SyncState) {
        state.groups[id] = nil
        guard let group = groups.first(where: { $0.id == id }) else { return }
        ungroup(group)
    }

    /// A space deleted on another device goes here too, with its tabs and
    /// groups, and its data store once no space uses it. The last space
    /// stays: Firn always has one.
    private func applySpaceDelete(_ id: UUID, to state: inout SyncState) {
        state.spaces[id] = nil
        state.arrived.remove(id)
        state.joinedSpaces = state.joinedSpaces.filter { $0.value != id }
        state.groups = state.groups.filter { $0.value.spaceID != id }
        state.tabs = state.tabs.filter { $0.value.spaceID != id }
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        deleteSpace(space)
    }

    // MARK: - Checking what comes in

    /// A space color's name, as Firn's are ("glacier", "sand", …): a short
    /// lowercase word, or nil.
    static func syncColor(_ color: String) -> String? {
        guard (1...20).contains(color.count), color.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return nil }
        return color
    }

    static func syncTitle(_ title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.count > HistoryStore.titleLimit ? String(title.prefix(HistoryStore.titleLimit)) : title
    }

    private static func recordID(_ kind: SyncKind, _ id: UUID) -> SyncRecordID {
        SyncRecordID(kind: kind, name: id.uuidString)
    }

    private static func byID(_ a: UUID, _ b: UUID) -> Bool { a.uuidString < b.uuidString }
}
