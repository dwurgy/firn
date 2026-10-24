import Foundation
import Testing
@testable import FirnCore

/// Web page files opened from Finder or another app (Firn as the default browser).
@MainActor
struct OpenedFilesTests {
    @Test func onlyWebPageFilesAreTakenIn() {
        let page = URL(fileURLWithPath: "/tmp/firn-test/Recipe.HTML")
        #expect(OpenedFiles.accept(page))
        #expect(OpenedFiles.contains(page))
        #expect(OpenedFiles.contains(URL(fileURLWithPath: "/tmp/firn-test/./Recipe.HTML")))
        #expect(!OpenedFiles.accept(URL(fileURLWithPath: "/tmp/firn-test/notes.txt")))
        #expect(!OpenedFiles.accept(URL(string: "https://example.com/page.html")!))
        #expect(!OpenedFiles.contains(URL(fileURLWithPath: "/tmp/firn-test/other.html")))
    }

    @Test func aFileShowsItsName() {
        #expect(WebAddress.site(of: URL(fileURLWithPath: "/Users/someone/Recipe.html")) == "Recipe.html")
    }

    @Test func fileTabsArentSaved() {
        let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())
        let store = BrowserStore(restoring: nil, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) })
        store.openTab(URL(string: "https://a.example")!)
        store.openTab(URL(fileURLWithPath: "/tmp/firn-test/Recipe.html"))
        let saved = store.session(sidebarWidth: 260, sidebarCollapsed: false).tabs
        #expect(saved.map { $0.url?.host() } == ["a.example"])
    }
}
