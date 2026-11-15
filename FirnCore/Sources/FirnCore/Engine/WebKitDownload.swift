import Foundation
import WebKit
#if os(macOS)
import CoreServices
#endif

/// Follows one WKDownload and keeps its `Download` up to date. The page
/// that started it may close (a popup that only downloaded does), so this
/// keeps itself alive until the download ends.
@MainActor
final class WebKitDownload: NSObject, WKDownloadDelegate {
    private let download: Download
    private let webKitDownload: WKDownload
    private var progressObservation: NSKeyValueObservation?
    /// Where a save panel said to put it; nil means the Downloads folder.
    private let chosenURL: URL?
    /// Held while the download runs; WebKit holds its delegate weakly.
    private var keepAlive: WebKitDownload?

    @discardableResult
    static func follow(_ webKitDownload: WKDownload, dataStoreID: UUID, to chosenURL: URL? = nil) -> Download {
        let download = Downloads.shared.start(dataStoreID: dataStoreID)
        let follower = WebKitDownload(download: download, webKitDownload: webKitDownload, chosenURL: chosenURL)
        follower.keepAlive = follower
        webKitDownload.delegate = follower
        download.stop = { [weak follower] in follower?.stop() }
        return download
    }

    private init(download: Download, webKitDownload: WKDownload, chosenURL: URL?) {
        self.download = download
        self.webKitDownload = webKitDownload
        self.chosenURL = chosenURL
        super.init()
        progressObservation = webKitDownload.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let known = progress.totalUnitCount > 0
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, self.download.state == .downloading else { return }
                self.download.progress = known ? min(max(fraction, 0), 1) : nil
            }
        }
    }

    /// The place picked in a save panel, or else the Downloads folder under
    /// a name checked by `DownloadName`. Nil (no folder) cancels it.
    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String
    ) async -> URL? {
        guard self.download.state == .downloading, let url = chosenURL.map({
            Downloads.shared.destination(for: self.download, chosen: $0)
        }) ?? Downloads.shared.destination(for: self.download, suggestedName: suggestedFilename) else {
            finish(.failed)
            return nil
        }
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        #if os(macOS)
        guard let url = self.download.fileURL else { return done() }
        Task {
            // WebKit's own download process saves the file under its own
            // sandbox, and macOS marks it as never runnable ("hard"
            // quarantine): a downloaded app then "can't be opened". Firn
            // writes the file again itself, so it carries Firn's mark, under
            // which a downloaded app opens after Gatekeeper's usual check.
            if Quarantine.isHard(url) {
                _ = await Task.detached { Quarantine.rewrite(url) }.value
            }
            guard self.download.state == .downloading else { return }
            done()
        }
        #else
        done()
        #endif
    }

    private func done() {
        markQuarantined()
        self.download.progress = 1
        finish(.finished)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        // Cancelling (by Firn) also lands here; the download is already marked.
        finish(.failed)
    }

    /// The unfinished file is removed once WebKit has let go of it.
    private func stop() {
        let url = download.fileURL
        webKitDownload.cancel { _ in
            if let url { try? FileManager.default.removeItem(at: url) }
        }
        finish(.cancelled)
    }

    private func finish(_ state: Download.State) {
        download.end(state)
        progressObservation = nil
        keepAlive = nil
    }

    /// Marks the file as downloaded from the web, so macOS checks it
    /// (Gatekeeper) and asks before an app in it first opens. WebKit's own
    /// network process writes the file, so the mark isn't added on its own.
    /// The address it came from is left out: it would sit in the file's
    /// metadata wherever the file goes.
    private func markQuarantined() {
        #if os(macOS)
        guard var url = download.fileURL else { return }
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: "Firn",
        ]
        try? url.setResourceValues(values)
        #endif
    }
}

#if os(macOS)
/// A downloaded file's quarantine mark, and writing a file again from
/// Firn's own process so it takes Firn's mark.
enum Quarantine {
    private static let name = "com.apple.quarantine"
    /// "Hard" quarantine: macOS won't run anything in the file at all.
    private static let hard: UInt32 = 0x0004

    /// The mark's flags (hex), or nil if the file has none.
    static func flags(_ url: URL) -> String? {
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &bytes, size, 0, 0) == size else { return nil }
        return String(decoding: bytes, as: UTF8.self).split(separator: ";").first.map(String.init)
    }

    static func isHard(_ url: URL) -> Bool {
        guard let flags = flags(url), let value = UInt32(flags, radix: 16) else { return false }
        return value & hard != 0
    }

    /// Copies the file's bytes (never its marks) into a new hidden file
    /// beside it, then puts that in its place. On any failure the original
    /// stays as it was. Returns whether it was replaced.
    static func rewrite(_ url: URL) -> Bool {
        let fresh = url.deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString).firn-download", directoryHint: .notDirectory)
        let freshPath = fresh.path(percentEncoded: false)
        do {
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            guard FileManager.default.createFile(atPath: freshPath, contents: nil) else { return false }
            let writer = try FileHandle(forWritingTo: fresh)
            defer { try? writer.close() }
            while let chunk = try reader.read(upToCount: 4 << 20), !chunk.isEmpty {
                try writer.write(contentsOf: chunk)
            }
            try writer.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: fresh)
            return false
        }
        // rename(2), not FileManager's replace, which would carry the old
        // file's marks over.
        guard rename(freshPath, url.path(percentEncoded: false)) == 0 else {
            try? FileManager.default.removeItem(at: fresh)
            return false
        }
        return true
    }
}
#endif
