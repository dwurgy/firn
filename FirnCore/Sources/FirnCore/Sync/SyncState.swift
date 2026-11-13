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
    /// next look, once the word is out.
    var announced: Set<UUID> = []

    public init() {}

    /// The fields that sync, as they are on a device right now.
    struct Fields: Codable, Equatable, Sendable {
        var spaces: [UUID: SyncedSpace] = [:]
        var groups: [UUID: SyncedGroup] = [:]
        var tabs: [UUID: SyncedTab] = [:]
    }

    /// Every record this device would hand iCloud now, for a first upload
    /// or after iCloud lost them (the engine asks for records by id).
    public func item(for id: SyncRecordID) -> SyncItem? {
        guard let uuid = UUID(uuidString: id.name) else { return nil }
        switch id.kind {
        case .space: return spaces[uuid].map(SyncItem.space)
        case .group: return groups[uuid].map(SyncItem.group)
        case .tab: return tabs[uuid].map(SyncItem.tab)
        case .visit: return nil
        }
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
