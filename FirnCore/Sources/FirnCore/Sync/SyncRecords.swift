import Foundation

// What goes to iCloud when sync is on (docs/SYNC-PLAN.md): only the fields
// below, each record sealed on the device (`SyncSeal`). Things that belong
// to one device (groups, tabs, Basecamp, a space's blocking and "Never
// save" lists) never go in a record.

/// The kinds of records Firn keeps in iCloud. The raw values are CloudKit's
/// record types: visible to Apple, but they say nothing personal.
public enum SyncKind: String, Codable, Sendable, CaseIterable {
    case space = "Space"
    /// Groups and their tabs synced briefly (step 4), then stayed on each
    /// device (David, 2026-11-16). The record types stay in iCloud's schema
    /// (they can't be removed); Firn only takes its own out again.
    case group = "TabGroup"
    case tab = "Tab"
    case visit = "Visit"
    /// One device's open tabs, for "On your Mac" (step 5).
    case device = "Device"
    /// A tab sent to one device, deleted once it's opened (step 6).
    case sentTab = "SentTab"
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
public enum SyncItem: Codable, Equatable, Sendable {
    case space(SyncedSpace)
    case visit(SyncedVisit)
    case device(SyncedDevice)
    case sentTab(SentTab)

    public var id: SyncRecordID {
        switch self {
        case let .space(space): SyncRecordID(kind: .space, name: space.id.uuidString)
        case let .visit(visit): SyncRecordID(kind: .visit, name: visit.id)
        case let .device(device): SyncRecordID(kind: .device, name: device.id)
        case let .sentTab(tab): tab.recordID
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
