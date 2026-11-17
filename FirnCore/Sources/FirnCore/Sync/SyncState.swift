import Foundation

/// What a device knows about sync, kept between launches (by the app's sync
/// engine, step 3): the records as iCloud has them, and what this device's
/// own fields looked like at its last look.
///
/// Only this device's own edits become changes to send: a field is sent
/// when it changed here since the last look, never because it differs from
/// a record that came in. So a record that arrives and can't be followed
/// (the page someone is looking at isn't pulled away) is never sent back,
/// and two devices never answer each other forever.
///
/// Latest change wins, per record, by `changedAt`. Each change is stamped
/// when this device first sees it, so the app takes changes whenever it
/// saves the session.
public struct SyncState: Codable, Equatable, Sendable {
    /// The records as iCloud has them, as far as this device knows.
    /// (Sync files from when groups and tabs synced still open: the fields
    /// they had are passed over.)
    var spaces: [UUID: SyncedSpace] = [:]
    /// This device's own fields at its last look (their times mean nothing).
    var seen = Fields()

    // The first sync (David, 2026-11-13): a space of this device's joins
    // another device's space of the same name. It keeps its own id and data
    // store here, so its sign-ins, history, and saved passwords stay; the
    // two below translate at iCloud's edge. Everything above is in this
    // device's own terms; what goes out and comes in is in iCloud's.

    /// iCloud's id for a joined space → this device's.
    var joinedSpaces: [UUID: UUID] = [:]
    /// iCloud's data store id for a joined space → this device's.
    var joinedStores: [UUID: UUID] = [:]
    /// Spaces whose records came from iCloud (this device's ids).
    var arrived: Set<UUID> = []
    /// Spaces join, and an untouched one gives way, only until the engine's
    /// first fetch is done (nothing of this device's goes up before then).
    public private(set) var firstSyncDone = false

    /// This install's own id: its `Device` record's name (step 5). A random
    /// id that says nothing.
    public private(set) var deviceID = UUID().uuidString
    /// The other devices' records, by their ids, as they arrived (checked).
    public internal(set) var devices: [String: SyncedDevice] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case spaces, seen, joinedSpaces, joinedStores, arrived, firstSyncDone, deviceID, devices
    }

    /// Anything a sync file from an older Firn lacks starts fresh, so the
    /// file still opens (and a dropped file would lose the first sync's joins).
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try values.decodeIfPresent([UUID: SyncedSpace].self, forKey: .spaces) ?? [:]
        seen = try values.decodeIfPresent(Fields.self, forKey: .seen) ?? Fields()
        joinedSpaces = try values.decodeIfPresent([UUID: UUID].self, forKey: .joinedSpaces) ?? [:]
        joinedStores = try values.decodeIfPresent([UUID: UUID].self, forKey: .joinedStores) ?? [:]
        arrived = try values.decodeIfPresent(Set<UUID>.self, forKey: .arrived) ?? []
        firstSyncDone = try values.decodeIfPresent(Bool.self, forKey: .firstSyncDone) ?? false
        deviceID = try values.decodeIfPresent(String.self, forKey: .deviceID) ?? UUID().uuidString
        devices = try values.decodeIfPresent([String: SyncedDevice].self, forKey: .devices) ?? [:]
    }

    /// The engine's first fetch is done: from now on spaces arrive as new.
    /// (The app calls `BrowserStore.finishFirstSync`, which lets untouched
    /// spaces give way first.)
    public mutating func finishFirstSync() { firstSyncDone = true }

    /// This device's own `Device` record's address in iCloud.
    public var deviceRecordID: SyncRecordID { SyncRecordID(kind: .device, name: deviceID) }

    /// Forgets other devices not sent from since `date` (they no longer
    /// show), so the sync file doesn't keep every device ever used. One that
    /// comes back simply arrives again with its next send.
    public mutating func forgetDevices(sentBefore date: Date) {
        devices = devices.filter { $0.value.sentAt >= date }
    }

    /// The fields that sync, as they are on a device right now.
    struct Fields: Codable, Equatable, Sendable {
        var spaces: [UUID: SyncedSpace] = [:]
    }

    /// Every record this device would hand iCloud now, for a first upload
    /// or after iCloud lost them (the engine asks for records by iCloud's
    /// id). Nil for a space that joined another: it goes by that one's id.
    public func item(for id: SyncRecordID) -> SyncItem? {
        guard let uuid = UUID(uuidString: id.name) else { return nil }
        switch id.kind {
        case .space:
            let local = localSpace(uuid)
            guard remoteSpace(local) == uuid else { return nil }
            return spaces[local].map { .space(toCloud($0)) }
        case .group, .tab, .visit, .device: return nil
        }
    }

    /// Every record of these kinds this device knows, by iCloud's id: to
    /// send all again after the key changed, or when a kind starts syncing.
    public func recordIDs(of kinds: Set<SyncKind>) -> [SyncRecordID] {
        var ids: [SyncRecordID] = []
        if kinds.contains(.space) {
            ids += spaces.keys.map { toCloud(SyncRecordID(kind: .space, name: $0.uuidString)) }
        }
        return ids.filter { item(for: $0) != nil }
    }

    // MARK: - iCloud's terms and this device's

    func localSpace(_ id: UUID) -> UUID { joinedSpaces[id] ?? id }
    func remoteSpace(_ id: UUID) -> UUID { joinedSpaces.first { $0.value == id }?.key ?? id }
    func localStore(_ id: UUID) -> UUID { joinedStores[id] ?? id }
    func remoteStore(_ id: UUID) -> UUID { joinedStores.first { $0.value == id }?.key ?? id }

    func toCloud(_ space: SyncedSpace) -> SyncedSpace {
        var space = space
        space.id = remoteSpace(space.id)
        space.dataStoreID = remoteStore(space.dataStoreID)
        return space
    }



    func toCloud(_ item: SyncItem) -> SyncItem {
        switch item {
        case let .space(space): .space(toCloud(space))
        // A device's record is made in iCloud's terms (`deviceRecord`).
        case .visit, .device: item
        }
    }

    func toCloud(_ id: SyncRecordID) -> SyncRecordID {
        guard id.kind == .space, let uuid = UUID(uuidString: id.name) else { return id }
        return SyncRecordID(kind: .space, name: remoteSpace(uuid).uuidString)
    }

    func fromCloud(_ space: SyncedSpace) -> SyncedSpace {
        var space = space
        space.id = localSpace(space.id)
        space.dataStoreID = localStore(space.dataStoreID)
        return space
    }
}

/// A synced record kept per id, with a time that doesn't count as a field.
protocol SyncedFields: Equatable, Sendable {
    var id: UUID { get }
    var changedAt: Date { get set }
}

extension SyncedSpace: SyncedFields {}

extension SyncedFields {
    /// The same fields, whenever they changed.
    func sameFields(as other: Self) -> Bool {
        var other = other
        other.changedAt = changedAt
        return self == other
    }
}
