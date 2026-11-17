import Foundation

// iCloud sync's side of the store (docs/SYNC-PLAN.md, step 2): what this
// device changed, and applying what other devices changed. Only spaces sync;
// groups, tabs, and Basecamp stay on each device (David, 2026-11-16: a
// general sync).

extension BrowserStore {
    // MARK: - Sending

    /// Takes this device's changes since the last look into `state` and
    /// returns what to send. The app calls it whenever it saves the session.
    public func takeSyncChanges(into state: inout SyncState) -> SyncChanges {
        let stamp = now()
        let fields = syncFields()
        var changes = SyncChanges()

        Self.takeEdits(fields.spaces, seen: state.seen.spaces, into: &state.spaces, at: stamp, as: SyncItem.space, &changes)
        for id in state.seen.spaces.keys.sorted(by: Self.byID) where fields.spaces[id] == nil {
            if state.spaces.removeValue(forKey: id) != nil { changes.deletes.append(Self.recordID(.space, id)) }
        }

        state.seen = fields
        // In iCloud's terms: a joined space goes by its iCloud id.
        return SyncChanges(saves: changes.saves.map(state.toCloud), deletes: changes.deletes.map(state.toCloud))
    }

    /// The fields that sync, as they are here now: every space.
    func syncFields() -> SyncState.Fields {
        var fields = SyncState.Fields()
        for (index, space) in spaces.enumerated() {
            fields.spaces[space.id] = SyncedSpace(
                id: space.id, name: space.name, color: space.color, order: index,
                dataStoreID: space.dataStoreID, changedAt: .distantPast
            )
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

    /// Applies records from other devices: saves and deletes. This device's
    /// own changes are taken first, and returned to send. Other devices'
    /// records are kept in `state` for the command bar. Visits are
    /// history's (`HistoryStore`), not the store's, and are passed over here,
    /// as are groups and tabs (they no longer sync; any left in iCloud or a
    /// sync file from before are ignored).
    public func applySync(saves: [SyncItem], deletes: [SyncRecordID], to state: inout SyncState) -> SyncChanges {
        var toSend = takeSyncChanges(into: &state)
        var spaceSaves: [SyncedSpace] = []
        let stamp = now()
        for item in Self.latest(saves, without: deletes) {
            switch item {
            case let .space(space): spaceSaves.append(space)
            // Another device's open tabs, for the command bar (never this
            // device's own, coming back).
            case let .device(device) where device.id != state.deviceID: state.devices[device.id] = device.checked()
            // A tab sent to this device waits to be opened; an expired one,
            // for any device, is deleted.
            case let .sentTab(tab):
                if state.receive(tab, at: stamp) { toSend.deletes.append(tab.recordID) }
            case .device, .visit: break
            }
        }
        for space in spaceSaves.sorted(by: { $0.order < $1.order }) {
            if !state.firstSyncDone { join(space, in: &state) }
            apply(state.fromCloud(space), to: &state)
        }
        // A space that joined goes by iCloud's id now: what was taken to
        // send is taken again in today's terms.
        toSend.saves = toSend.saves.compactMap { state.item(for: $0.id) }

        let deleted = { (kind: SyncKind) in deletes.filter { $0.kind == kind }.compactMap { UUID(uuidString: $0.name) } }
        for id in deleted(.space) { applySpaceDelete(state.localSpace(id), to: &state) }
        for id in deletes where id.kind == .device { state.devices[id.name] = nil }
        for id in deletes where id.kind == .sentTab {
            state.inbox[id.name] = nil
            state.outbox[id.name] = nil
        }

        // What's here now came in: it isn't an edit of this device's.
        state.seen = syncFields()
        return toSend
    }

    /// The engine's whole first fetch is in (the app calls this then, not
    /// after each batch): untouched spaces of this device's give way now,
    /// so one whose same-named match came in a later batch still joined it.
    /// Afterward, what was held to send is taken again in today's terms
    /// (`SyncState.item(for:)`), as one that gave way is gone.
    public func finishFirstSync(_ state: inout SyncState) {
        guard !state.firstSyncDone else { return }
        giveWay(in: &state)
        state.finishFirstSync()
    }

    /// One of each record, the one that came last, and none that are being
    /// deleted.
    static func latest(_ saves: [SyncItem], without deletes: [SyncRecordID]) -> [SyncItem] {
        var taken = Set(deletes)
        var kept: [SyncItem] = []
        for item in saves.reversed() where taken.insert(item.id).inserted {
            kept.append(item)
        }
        return kept.reversed()
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

    /// A space deleted on another device goes here too, with its tabs and
    /// groups, and its data store once no space uses it. The last space
    /// stays: Firn always has one.
    private func applySpaceDelete(_ id: UUID, to state: inout SyncState) {
        state.spaces[id] = nil
        state.arrived.remove(id)
        state.joinedSpaces = state.joinedSpaces.filter { $0.value != id }
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
