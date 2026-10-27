import Foundation
import Observation

/// One file a page sent to the Downloads folder. Engine-neutral: the engine
/// fills it in, and views only ever see this.
@MainActor
@Observable
public final class Download: Identifiable {
    public enum State: Equatable, Sendable {
        case downloading, finished, failed, cancelled
    }

    public let id = UUID()
    /// The store of the space it came from, so each space sees only its own.
    public let dataStoreID: UUID
    /// The name it's saved under, once known.
    public internal(set) var fileName: String?
    /// Where it's saved, once known.
    public internal(set) var fileURL: URL?
    public internal(set) var state = State.downloading
    /// From 0 to 1; nil while the size isn't known.
    public internal(set) var progress: Double?

    /// Stops the download in the engine. Cleared once it ends.
    @ObservationIgnored var stop: (@MainActor () -> Void)?

    init(dataStoreID: UUID) {
        self.dataStoreID = dataStoreID
    }

    /// Stops it and removes the unfinished file.
    public func cancel() {
        guard state == .downloading else { return }
        stop?()
        end(.cancelled)
    }

    /// Ends it. A failed download's unfinished file is removed (a cancelled
    /// one's is removed by the engine once it lets go); it's only ever one
    /// Firn made itself, since the name was checked as free before saving.
    func end(_ state: State) {
        guard self.state == .downloading else { return }
        self.state = state
        stop = nil
        if state == .failed, let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        Downloads.shared.release(self)
    }
}

/// Every download since Firn opened. Not saved: the list is forgotten on
/// quit (the files stay).
@MainActor
@Observable
public final class Downloads {
    public static let shared = Downloads()

    public private(set) var all: [Download] = []
    /// The download that started last, so the window can show it starting.
    public private(set) var latest: Download?
    /// Names given to downloads still in progress, so two at once never
    /// share one.
    @ObservationIgnored private var reserved: Set<URL> = []

    /// A space's downloads, newest first.
    public func list(for dataStoreID: UUID) -> [Download] {
        all.filter { $0.dataStoreID == dataStoreID }.reversed()
    }

    /// Takes the space's ended downloads off its list.
    public func clear(_ dataStoreID: UUID) {
        all.removeAll { $0.dataStoreID == dataStoreID && $0.state != .downloading }
    }

    func start(dataStoreID: UUID) -> Download {
        let download = Download(dataStoreID: dataStoreID)
        all.append(download)
        latest = download
        return download
    }

    /// Picks where `download` is saved: the Downloads folder, under a clean
    /// name no other file (or download in progress) has. Nil if there's no
    /// Downloads folder to save to.
    func destination(for download: Download, suggestedName: String) -> URL? {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }
        let name = DownloadName.unique(DownloadName.clean(suggestedName)) { name in
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            return reserved.contains(url) || FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        reserved.insert(url)
        download.fileName = name
        download.fileURL = url
        return url
    }

    /// A place picked in a save panel, which already asked before replacing
    /// a file there. Nil if a download in progress is headed there too.
    func destination(for download: Download, chosen url: URL) -> URL? {
        guard !reserved.contains(url) else { return nil }
        // WebKit won't write over a file; the person chose to replace it.
        try? FileManager.default.removeItem(at: url)
        reserved.insert(url)
        download.fileName = url.lastPathComponent
        download.fileURL = url
        return url
    }

    fileprivate func release(_ download: Download) {
        if let url = download.fileURL { reserved.remove(url) }
    }
}
