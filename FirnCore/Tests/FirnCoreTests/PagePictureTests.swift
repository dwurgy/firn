import CoreGraphics
import Foundation
import Testing
@testable import FirnCore

/// The iPhone's saved page pictures: one per tab, kept out of backups, and
/// gone with their tab or space.
@MainActor
struct PagePictureTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "FirnTests-\(UUID().uuidString)")
    }

    /// A small solid picture, as a page's snapshot would be.
    private func picture(width: Int = 60, height: Int = 120) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func aPictureComesBackAfterSaving() throws {
        let store = PagePictureStore(folder: tempFolder())
        let id = UUID()
        #expect(store.load(for: id) == nil)
        try store.save(picture(), for: id)
        let loaded = try #require(store.load(for: id))
        #expect(loaded.width == 60 && loaded.height == 120)
        #expect(store.savedTabIDs() == [id])
    }

    @Test func theFolderIsKeptOutOfBackups() throws {
        let store = PagePictureStore(folder: tempFolder())
        try store.save(picture(), for: UUID())
        let values = try store.folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func aDamagedOrOversizedFileIsntRead() throws {
        let store = PagePictureStore(folder: tempFolder())
        let damaged = UUID(), huge = UUID()
        try store.save(picture(), for: damaged)
        try Data("not a picture".utf8).write(to: store.file(for: damaged))
        #expect(store.load(for: damaged) == nil)
        try Data(count: PagePictureStore.maxBytes + 1).write(to: store.file(for: huge))
        #expect(store.load(for: huge) == nil)
    }

    @Test func pruningKeepsOnlyTheGivenTabs() throws {
        let store = PagePictureStore(folder: tempFolder())
        let kept = UUID(), closed = UUID()
        try store.save(picture(), for: kept)
        try store.save(picture(), for: closed)
        try Data("other".utf8).write(to: store.folder.appending(path: "notes.txt"))
        store.prune(keeping: [kept])
        #expect(store.savedTabIDs() == [kept])
        // Files that aren't pictures are left alone.
        #expect(FileManager.default.fileExists(atPath: store.folder.appending(path: "notes.txt").path(percentEncoded: false)))
    }

    /// The done test's "close a tab and its picture is gone too", and a
    /// deleted space's pictures with it.
    @Test func theSaverRemovesClosedTabsAndDeletedSpacesPictures() async throws {
        let dir = tempFolder()
        let pictures = PagePictureStore(folder: dir.appending(path: "Page Pictures"))
        let store = BrowserStore(restoring: nil, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) })
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let work = store.addSpace(name: "Work", color: "sage")
        store.selectSpace(work)
        let c = store.openTab(url("c"))
        for tab in [a, b, c] { try pictures.save(picture(), for: tab.id) }

        let saver = SessionSaver(
            file: SessionFile(url: dir.appending(path: "session.json")), delay: .seconds(60),
            snapshot: { store.session(sidebarWidth: 260, sidebarCollapsed: false) },
            pictures: pictures
        )
        saver.start()
        try await waitUntil { pictures.savedTabIDs() == [a.id, b.id, c.id] }

        store.close(b)
        store.deleteSpace(work)
        saver.saveNow()
        try await waitUntil { pictures.savedTabIDs() == [a.id] }
        #expect(pictures.savedTabIDs() == [a.id])
    }

    /// Pruning runs off the main thread; give it a moment.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
