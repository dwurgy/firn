import CryptoKit
import Foundation

/// Seals records before they leave the device, and opens them when they
/// arrive (David, 2026-11-13): CloudKit's own field encryption is end-to-end
/// only with Advanced Data Protection, so Firn encrypts each record itself
/// with one key per iCloud account, kept in iCloud Keychain (end-to-end for
/// everyone). iCloud only ever holds sealed bytes.
///
/// AES-GCM, with the record's kind and name bound in as authenticated data,
/// so a sealed record can't be passed off as another one. Everything opened
/// is still treated as untrusted: it's checked again when it's applied.
public struct SyncSeal: Sendable {
    /// The key's size: 256 bits.
    public static let keySize = 32
    /// Sealed records larger than this are refused unopened (a record holds
    /// a name or an address; real ones are far smaller).
    static let sealedLimit = 64 * 1024
    /// The first byte of every sealed record, so the format can change.
    static let formatVersion: UInt8 = 1

    private let key: SymmetricKey

    /// nil unless `keyData` is exactly a 256-bit key.
    public init?(keyData: Data) {
        guard keyData.count == Self.keySize else { return nil }
        key = SymmetricKey(data: keyData)
    }

    /// A new random key, for an iCloud account that has none yet.
    public static func makeKeyData() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public enum Failure: Error, Equatable {
        /// Too large, an unknown format, the wrong key, or tampered with.
        case unreadable
        /// Opened, but its fields aren't what a record of its kind holds.
        case malformed
    }

    public func seal(_ item: SyncItem) throws -> SyncRecord {
        let id = item.id
        let fields: Data
        let encoder = JSONEncoder()
        switch item {
        case let .space(space): fields = try encoder.encode(space)
        case let .group(group): fields = try encoder.encode(group)
        case let .tab(tab): fields = try encoder.encode(tab)
        case let .visit(visit): fields = try encoder.encode(visit)
        }
        let box = try AES.GCM.seal(fields, using: key, authenticating: Self.binding(id))
        guard let combined = box.combined else { throw Failure.unreadable }
        return SyncRecord(id: id, sealed: Data([Self.formatVersion]) + combined)
    }

    public func open(_ record: SyncRecord) throws -> SyncItem {
        let sealed = record.sealed
        guard sealed.count <= Self.sealedLimit, sealed.first == Self.formatVersion else { throw Failure.unreadable }
        let fields: Data
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst())
            fields = try AES.GCM.open(box, using: key, authenticating: Self.binding(record.id))
        } catch {
            throw Failure.unreadable
        }
        let decoder = JSONDecoder()
        let item: SyncItem
        do {
            switch record.id.kind {
            case .space: item = .space(try decoder.decode(SyncedSpace.self, from: fields))
            case .group: item = .group(try decoder.decode(SyncedGroup.self, from: fields))
            case .tab: item = .tab(try decoder.decode(SyncedTab.self, from: fields))
            case .visit: item = .visit(try decoder.decode(SyncedVisit.self, from: fields))
            }
        } catch {
            throw Failure.malformed
        }
        // The fields must name the record they came in.
        guard item.id == record.id else { throw Failure.malformed }
        return item
    }

    private static func binding(_ id: SyncRecordID) -> Data {
        Data("\(id.kind.rawValue)/\(id.name)".utf8)
    }
}
