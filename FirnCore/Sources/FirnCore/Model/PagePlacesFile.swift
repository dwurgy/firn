import Foundation
import os

/// Where a tab's page was when Firn last saved: its back and forward
/// history and scroll position (WebKit's own bytes, opaque to Firn), and
/// the address it was at. A restarted tab picks up there, so Back works.
public struct PagePlace: Equatable, Sendable {
    public var url: URL
    public var state: Data

    /// A place larger than this isn't kept (a page that piled up history);
    /// its tab loads its address fresh, as it would without one.
    static let maxBytes = 256 * 1024

    init?(url: URL, state: Data) {
        guard state.count <= Self.maxBytes, !url.isFileURL else { return nil }
        self.url = url
        self.state = state
    }
}

/// The places file: `Firn/page-places.plist` next to the session, binary.
/// Kept apart from `session.json` so the session stays small and readable,
/// and a damaged places file never costs the session: it's ignored, and
/// the next save replaces it. Never leaves the device.
public struct PagePlacesFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/Firn/page-places.plist` (in the container).
    public static var standard: PagePlacesFile {
        PagePlacesFile(url: URL.applicationSupportDirectory.appending(path: "Firn/page-places.plist"))
    }

    static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "page places")

    /// The saved places by tab id; empty if there are none or the file
    /// can't be read. Places too large or for files are dropped.
    public func load() -> [UUID: PagePlace] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let saved = try? PropertyListDecoder().decode([String: Stored].self, from: data) else {
            Self.log.error("The page places couldn't be read")
            return [:]
        }
        var places: [UUID: PagePlace] = [:]
        for (key, stored) in saved {
            guard let id = UUID(uuidString: key), let place = PagePlace(url: stored.url, state: stored.state) else { continue }
            places[id] = place
        }
        return places
    }

    /// Writes all the places at once (atomically), replacing what was there.
    public func save(_ places: [UUID: PagePlace]) throws {
        let stored = Dictionary(uniqueKeysWithValues: places.map { ($0.key.uuidString, Stored(url: $0.value.url, state: $0.value.state)) })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(stored).write(to: url, options: .atomic)
    }

    /// On disk without `PagePlace`'s checks, so they run again on reading.
    private struct Stored: Codable {
        var url: URL
        var state: Data
    }
}
