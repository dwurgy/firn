import Foundation
import Testing
@testable import FirnCore

struct DownloadNameTests {
    @Test func plainNamesStayAsTheyAre() {
        #expect(DownloadName.clean("Report 2026.pdf") == "Report 2026.pdf")
        #expect(DownloadName.clean("café menu.jpg") == "café menu.jpg")
    }

    @Test func folderSeparatorsCantClimbOut() {
        #expect(DownloadName.clean("../../Library/evil.plist") == "-..-Library-evil.plist")
        #expect(DownloadName.clean("a/b\\c:d.txt") == "a-b-c-d.txt")
    }

    @Test func hiddenAndEmptyNamesGetAPlainOne() {
        #expect(DownloadName.clean(".zshrc") == "zshrc")
        #expect(DownloadName.clean("...") == "Download")
        #expect(DownloadName.clean("  ") == "Download")
        #expect(DownloadName.clean("") == "Download")
        #expect(DownloadName.clean("notes.txt. . ") == "notes.txt")
    }

    @Test func invisibleCharactersCantDisguiseTheType() {
        // Right-to-left override: would read as "photoppa.jpg".
        #expect(DownloadName.clean("photo\u{202E}gpj.app") == "photogpj.app")
        #expect(DownloadName.clean("in\u{200B}voice\n.pdf") == "invoice.pdf")
        #expect(DownloadName.clean("a\u{0}b.txt") == "ab.txt")
    }

    @Test func longNamesKeepTheirExtension() {
        let name = DownloadName.clean(String(repeating: "é", count: 300) + ".pdf")
        #expect(name.utf8.count <= DownloadName.maxBytes)
        #expect(name.hasSuffix("é.pdf"))
    }

    @Test func takenNamesGetANumber() {
        let taken: Set = ["a.pdf", "a 2.pdf", "notes", "x.tar.gz"]
        #expect(DownloadName.unique("a.pdf") { taken.contains($0) } == "a 3.pdf")
        #expect(DownloadName.unique("b.pdf") { taken.contains($0) } == "b.pdf")
        #expect(DownloadName.unique("notes") { taken.contains($0) } == "notes 2")
        #expect(DownloadName.unique("x.tar.gz") { taken.contains($0) } == "x 2.tar.gz")
    }

    @Test func onlyWebAndPageMadeFilesDownload() {
        #expect(DownloadPolicy.allows(URL(string: "https://example.com/a.zip")!))
        #expect(DownloadPolicy.allows(URL(string: "blob:https://example.com/1234")!))
        #expect(DownloadPolicy.allows(URL(string: "data:text/plain,hi")!))
        #expect(!DownloadPolicy.allows(URL(string: "file:///etc/passwd")!))
        #expect(!DownloadPolicy.allows(URL(string: "javascript:alert(1)")!))
    }
}

@MainActor
struct DownloadsListTests {
    @Test func eachSpaceSeesOnlyItsOwnAndClearKeepsRunningOnes() {
        let downloads = Downloads()
        let work = UUID(), home = UUID()
        let first = downloads.start(dataStoreID: work)
        let second = downloads.start(dataStoreID: work)
        _ = downloads.start(dataStoreID: home)
        #expect(downloads.list(for: work).map(\.id) == [second.id, first.id])
        first.state = .finished
        downloads.clear(work)
        #expect(downloads.list(for: work).map(\.id) == [second.id])
        #expect(downloads.list(for: home).count == 1)
    }
}
