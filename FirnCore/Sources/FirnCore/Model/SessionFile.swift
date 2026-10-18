import Foundation
import Observation
import os

/// Where the session lives on disk: one JSON file in Firn's own Application
/// Support folder (inside the app's sandbox container). It holds the
/// addresses and titles of open tabs, as every browser's session file does;
/// it never leaves the Mac.
public struct SessionFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/Firn/session.json` (in the container).
    public static var standard: SessionFile {
        let support = URL.applicationSupportDirectory
        return SessionFile(url: support.appending(path: "Firn/session.json"))
    }

    /// Where an unreadable file is set aside, rather than overwritten.
    var brokenURL: URL {
        url.deletingLastPathComponent().appending(path: "session.broken.json")
    }

    /// The saved session, or nil if there's none. A file that can't be read
    /// (damaged, or from a newer Firn) is moved to `session.broken.json` so
    /// it's never silently lost, and Firn starts fresh.
    public func load() -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let session = try? Self.decoder.decode(Session.self, from: data),
           session.version <= Session.currentVersion {
            return session
        }
        Self.log.error("The saved session couldn't be read; set it aside and started fresh")
        let manager = FileManager.default
        try? manager.removeItem(at: brokenURL)
        try? manager.moveItem(at: url, to: brokenURL)
        return nil
    }

    /// Writes the whole file at once (atomically), so a crash mid-save
    /// leaves the previous version, never half a file.
    public func save(_ session: Session) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(session).write(to: url, options: .atomic)
    }

    static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "session")

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Saves the session about a second after anything in it changes, and on
/// request (at quit). It notices changes through Observation, so nothing
/// runs while Firn sits idle.
@MainActor
public final class SessionSaver {
    private let file: SessionFile
    private let delay: Duration
    private let snapshot: @MainActor () -> Session
    private var pendingSave: Task<Void, Never>?
    private var lastSaved: Session?

    /// - Parameter snapshot: The session as it is now. Whatever it reads is
    ///   watched; a change to any of it schedules a save.
    public init(file: SessionFile, delay: Duration = .seconds(1), snapshot: @escaping @MainActor () -> Session) {
        self.file = file
        self.delay = delay
        self.snapshot = snapshot
    }

    /// Starts watching, without saving: what's on disk is already current.
    public func start() {
        lastSaved = watchedSnapshot()
    }

    /// Saves right away if anything changed (at quit, say).
    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let session = watchedSnapshot()
        guard session != lastSaved else { return }
        do {
            try file.save(session)
            lastSaved = session
        } catch {
            SessionFile.log.error("The session couldn't be saved")
        }
    }

    private func changed() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    /// Takes the snapshot and watches what it read; the first change after
    /// this schedules a save, which takes (and watches) a fresh one.
    private func watchedSnapshot() -> Session {
        withObservationTracking(snapshot) { [weak self] in
            Task { @MainActor in self?.changed() }
        }
    }
}
