import Foundation
import os

/// What sync keeps between launches (docs/SYNC-PLAN.md, step 3), in one file
/// next to the session: this device's `SyncState`, the sync engine's own
/// state (CloudKit's, saved as the app hands it over), and records still
/// waiting for their space or group. Only there while sync is on.
public struct SyncSaved: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = Self.currentVersion
    public var state = SyncState()
    /// The engine's state, as opaque bytes (CloudKit's own encoding).
    public var engineState: Data?
    public var waiting: [SyncItem] = []

    public init() {}
}

/// `~/Library/Application Support/Firn/sync.json` (in the container). It
/// holds what the session file does for spaces and groups, and never leaves
/// the device.
public struct SyncFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: SyncFile {
        SyncFile(url: URL.applicationSupportDirectory.appending(path: "Firn/sync.json"))
    }

    /// What was saved, or a fresh start. Everything in it can be had from
    /// iCloud again, so a file that can't be read (damaged, or from a newer
    /// Firn) is dropped, and the engine fetches everything anew.
    public func load() -> SyncSaved {
        guard let data = try? Data(contentsOf: url) else { return SyncSaved() }
        if let saved = try? Self.decoder.decode(SyncSaved.self, from: data),
           saved.version <= SyncSaved.currentVersion {
            return saved
        }
        Self.log.error("The sync file couldn't be read; starting sync afresh")
        remove()
        return SyncSaved()
    }

    /// Writes the whole file at once (atomically).
    public func save(_ saved: SyncSaved) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(saved).write(to: url, options: .atomic)
    }

    /// Gone when sync is turned off.
    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "sync")

    // Dates as Foundation's own numbers, not ISO 8601, which drops the
    // fractions of a second "latest change wins" compares.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
