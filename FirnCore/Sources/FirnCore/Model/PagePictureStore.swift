import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// One picture of each tab's page, saved so the iPhone's overview can show
/// it after iOS has ended Firn in the background (the Mac keeps its
/// pictures in memory only). A JPEG per tab, named by the tab's id, in
/// `Firn/Page Pictures/` in Firn's own container:
///
/// - never leaves the device: the folder is kept out of backups;
/// - on iOS, each file is locked by the system while the phone is locked
///   (`completeUnlessOpen`: Firn can still write one as it goes to the
///   background, but nothing can read it until the phone is unlocked);
/// - a tab's picture goes when the tab does (`prune`, after each session
///   save), and so do a deleted space's.
///
/// Every call is plain file work, safe off the main thread; pictures are
/// encoded and written there, never on it.
public struct PagePictureStore: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    /// `~/Library/Application Support/Firn/Page Pictures/` (in the container).
    public static var standard: PagePictureStore {
        PagePictureStore(folder: URL.applicationSupportDirectory.appending(path: "Firn/Page Pictures", directoryHint: .isDirectory))
    }

    static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "page pictures")

    /// How much JPEG squeezes: small files, still sharp on a card.
    static let quality = 0.7
    /// A picture larger than this on disk isn't read (it can't be Firn's).
    static let maxBytes = 4 * 1024 * 1024

    func file(for tabID: UUID) -> URL {
        folder.appending(path: tabID.uuidString + ".jpg")
    }

    /// Saves `image` as the tab's picture, replacing the last one.
    public func save(_ image: CGImage, for tabID: UUID) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: Self.quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try makeFolder()
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtectionUnlessOpen)
        #endif
        try (data as Data).write(to: file(for: tabID), options: options)
    }

    /// The tab's picture, or nil if it has none (or it can't be read, for
    /// instance while the phone is locked).
    public func load(for tabID: UUID) -> CGImage? {
        let url = file(for: tabID)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maxBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The ids of the tabs that have a picture.
    public func savedTabIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return Set(names.compactMap { name in
            guard name.hasSuffix(".jpg") else { return nil }
            return UUID(uuidString: String(name.dropLast(4)))
        })
    }

    /// Removes one tab's picture, if it has one.
    public func remove(for tabID: UUID) {
        try? FileManager.default.removeItem(at: file(for: tabID))
    }

    /// Removes every picture whose tab isn't in `tabIDs`: closed tabs, and
    /// a deleted space's.
    public func prune(keeping tabIDs: Set<UUID>) {
        for id in savedTabIDs().subtracting(tabIDs) { remove(for: id) }
    }

    /// Creates the folder the first time, kept out of backups so pictures
    /// of pages never leave the device.
    private func makeFolder() throws {
        guard !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = folder
        try folder.setResourceValues(values)
    }
}
