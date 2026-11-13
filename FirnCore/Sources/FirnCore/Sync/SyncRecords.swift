import Foundation

// What goes to iCloud when sync is on (docs/SYNC-PLAN.md): only the fields
// below, each record sealed on the device (`SyncSeal`). Things that belong
// to one device (where a group sits in the list, whether it's folded, which
// tab is on screen, a space's blocking and "Never save" lists, loose tabs,
// Basecamp) never go in a record.

/// The kinds of records Firn keeps in iCloud. The raw values are CloudKit's
/// record types: visible to Apple, but they say nothing personal.
public enum SyncKind: String, Codable, Sendable, CaseIterable {
    case space = "Space"
    case group = "TabGroup"
    case tab = "Tab"
    case visit = "Visit"
}

/// One record's address in iCloud: its kind and its name (a random id that
/// says nothing).
public struct SyncRecordID: Hashable, Codable, Sendable {
    public var kind: SyncKind
    public var name: String

    public init(kind: SyncKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// A record as it travels: its address and its sealed fields.
public struct SyncRecord: Equatable, Sendable {
    public var id: SyncRecordID
    public var sealed: Data

    public init(id: SyncRecordID, sealed: Data) {
        self.id = id
        self.sealed = sealed
    }
}

/// A space: its own browser on every device. Its data store id comes with
/// it, so a separate space is still separate (and signed out) on a new
/// device, and a shared one still shares.
public struct SyncedSpace: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: String
    public var order: Int
    public var dataStoreID: UUID
    /// When a synced field last changed (not the space's own `lastChangedAt`,
    /// which per-device things can move too).
    public var changedAt: Date

    public init(id: UUID, name: String, color: String, order: Int, dataStoreID: UUID, changedAt: Date) {
        self.id = id
        self.name = name
        self.color = color
        self.order = order
        self.dataStoreID = dataStoreID
        self.changedAt = changedAt
    }
}

/// A group kept by hand: its name. Where it sits and whether it's folded
/// stay on each device.
public struct SyncedGroup: Codable, Equatable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var name: String
    public var changedAt: Date

    public init(id: UUID, spaceID: UUID, name: String, changedAt: Date) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.changedAt = changedAt
    }
}

/// A tab in a group. With no group, it says the tab left its group on the
/// device that sent it (ungrouped, or taken out), so other devices keep it
/// as a loose tab of their own rather than closing it.
public struct SyncedTab: Codable, Equatable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var groupID: UUID?
    public var url: URL
    public var title: String
    /// Its place among its group's tabs.
    public var order: Int
    public var changedAt: Date

    public init(id: UUID, spaceID: UUID, groupID: UUID?, url: URL, title: String, order: Int, changedAt: Date) {
        self.id = id
        self.spaceID = spaceID
        self.groupID = groupID
        self.url = url
        self.title = title
        self.order = order
        self.changedAt = changedAt
    }
}

/// A history visit from the last 30 days (`HistoryStore.syncedFor`).
public struct SyncedVisit: Codable, Equatable, Sendable {
    /// The visit's sync id (its own; history's row numbers are per device).
    public var id: String
    public var dataStoreID: UUID
    public var url: URL
    public var title: String
    public var visitedAt: Date

    public init(id: String, dataStoreID: UUID, url: URL, title: String, visitedAt: Date) {
        self.id = id
        self.dataStoreID = dataStoreID
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }
}

/// Any one record's fields.
public enum SyncItem: Equatable, Sendable {
    case space(SyncedSpace)
    case group(SyncedGroup)
    case tab(SyncedTab)
    case visit(SyncedVisit)

    public var id: SyncRecordID {
        switch self {
        case let .space(space): SyncRecordID(kind: .space, name: space.id.uuidString)
        case let .group(group): SyncRecordID(kind: .group, name: group.id.uuidString)
        case let .tab(tab): SyncRecordID(kind: .tab, name: tab.id.uuidString)
        case let .visit(visit): SyncRecordID(kind: .visit, name: visit.id)
        }
    }
}

/// What changed on this device since the last look: records to save and
/// records to delete from iCloud.
public struct SyncChanges: Equatable, Sendable {
    public var saves: [SyncItem] = []
    public var deletes: [SyncRecordID] = []

    public init(saves: [SyncItem] = [], deletes: [SyncRecordID] = []) {
        self.saves = saves
        self.deletes = deletes
    }

    public var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
}
