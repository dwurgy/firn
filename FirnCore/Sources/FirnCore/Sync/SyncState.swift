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
    var spaces: [UUID: SyncedSpace] = [:]
    var groups: [UUID: SyncedGroup] = [:]
    var tabs: [UUID: SyncedTab] = [:]
    /// This device's own fields at its last look (their times mean nothing).
    var seen = Fields()
    /// Tabs this device said had left their group; their records go at the
    /// first look after iCloud has the word (`sent`). Deleting sooner would
    /// let CloudKit drop the word unsent (a save followed by a delete of the
    /// same record goes as the delete alone), and other devices would close
    /// those tabs instead of keeping them loose.
    var announced: Set<UUID> = []
    /// Announced tabs whose loose record iCloud has. Optional so sync files
    /// from before it still open.
    var sentLoose: Set<UUID>?

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

    public init() {}

    /// The engine's first fetch is done: from now on spaces arrive as new.
    /// (The app calls `BrowserStore.finishFirstSync`, which lets untouched
    /// spaces give way first.)
    public mutating func finishFirstSync() { firstSyncDone = true }

    /// iCloud saved this record, as sent (the app passes each saved tab
    /// record, opened). A loose tab's word is out, so its record can go.
    public mutating func sent(_ item: SyncItem) {
        guard case let .tab(tab) = item, tab.groupID == nil, announced.contains(tab.id) else { return }
        sentLoose = (sentLoose ?? []).union([tab.id])
    }

    /// The fields that sync, as they are on a device right now.
    struct Fields: Codable, Equatable, Sendable {
        var spaces: [UUID: SyncedSpace] = [:]
        var groups: [UUID: SyncedGroup] = [:]
        var tabs: [UUID: SyncedTab] = [:]
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
        case .group: return groups[uuid].map { .group(toCloud($0)) }
        case .tab: return tabs[uuid].map { .tab(toCloud($0)) }
        case .visit: return nil
        }
    }

    /// Every record of these kinds this device knows, by iCloud's id: to
    /// send all again after the key changed, or when a kind starts syncing.
    public func recordIDs(of kinds: Set<SyncKind>) -> [SyncRecordID] {
        var ids: [SyncRecordID] = []
        if kinds.contains(.space) {
            ids += spaces.keys.map { toCloud(SyncRecordID(kind: .space, name: $0.uuidString)) }
        }
        if kinds.contains(.group) { ids += groups.keys.map { SyncRecordID(kind: .group, name: $0.uuidString) } }
        if kinds.contains(.tab) { ids += tabs.keys.map { SyncRecordID(kind: .tab, name: $0.uuidString) } }
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

    func toCloud(_ group: SyncedGroup) -> SyncedGroup {
        var group = group
        group.spaceID = remoteSpace(group.spaceID)
        return group
    }

    func toCloud(_ tab: SyncedTab) -> SyncedTab {
        var tab = tab
        tab.spaceID = remoteSpace(tab.spaceID)
        return tab
    }

    func toCloud(_ item: SyncItem) -> SyncItem {
        switch item {
        case let .space(space): .space(toCloud(space))
        case let .group(group): .group(toCloud(group))
        case let .tab(tab): .tab(toCloud(tab))
        case .visit: item
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

    func fromCloud(_ group: SyncedGroup) -> SyncedGroup {
        var group = group
        group.spaceID = localSpace(group.spaceID)
        return group
    }

    func fromCloud(_ tab: SyncedTab) -> SyncedTab {
        var tab = tab
        tab.spaceID = localSpace(tab.spaceID)
        return tab
    }
}

/// A synced record kept per id, with a time that doesn't count as a field.
protocol SyncedFields: Equatable, Sendable {
    var id: UUID { get }
    var changedAt: Date { get set }
}

extension SyncedSpace: SyncedFields {}
extension SyncedGroup: SyncedFields {}
extension SyncedTab: SyncedFields {}

extension SyncedFields {
    /// The same fields, whenever they changed.
    func sameFields(as other: Self) -> Bool {
        var other = other
        other.changedAt = changedAt
        return self == other
    }
}

/// What came in and what it means to send.
public struct SyncApplied: Equatable, Sendable {
    /// This device's own changes, taken before applying what came in.
    public var toSend: SyncChanges
    /// Records that can't be placed yet (their space or group hasn't
    /// arrived); hand them in again with the next batch.
    public var waiting: [SyncItem]
}
