import Foundation
import Testing
@testable import FirnCore

@MainActor
struct PinsAndSessionTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())

    private func makeStore(restoring session: Session? = nil, now: @escaping () -> Date = Date.init) -> BrowserStore {
        BrowserStore(restoring: session, defaultSpaces: [space], makePage: { FakePage(dataStoreID: $0) }, now: now)
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    private func hosts(_ tabs: [FirnCore.Tab]) -> [String] {
        tabs.map { $0.url?.host() ?? "" }
    }

    private func save(_ store: BrowserStore) -> Session {
        store.session(sidebarWidth: 300, sidebarCollapsed: true)
    }

    // MARK: - Pins and Basecamp

    @Test func pinningMovesATabToThePinsWithItsAddressAsHome() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.pin(a)
        #expect(hosts(store.pinnedTabs) == ["a.example"])
        #expect(hosts(store.openTabs) == ["b.example"])
        #expect(a.homeURL == url("a"))
        #expect(hosts(store.sidebarTabs) == ["a.example", "b.example"])
    }

    @Test func closingAPinRestsItAndShowsTheLastTabSeen() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        store.pin(b)
        store.close(b)
        #expect(store.pinnedTabs.map(\.id) == [b.id])
        #expect(b.isResting)
        #expect(store.activeTabID == a.id)
        store.select(b)
        #expect(b.page?.url == url("b"))
    }

    @Test func goingHomeLoadsTheHomeAddress() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.addToBasecamp(a)
        a.page?.load(url("elsewhere"))
        #expect(a.isAwayFromHome)
        store.goHome(a)
        #expect(a.page?.url == url("a"))
        #expect(!a.isAwayFromHome)
    }

    @Test func goingHomeWhileRestingWakesAtHome() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.pin(a)
        a.page?.load(url("elsewhere"))
        store.close(a)
        store.goHome(a)
        #expect(a.page?.url == url("a"))
        #expect(store.activeTabID == a.id)
    }

    @Test func basecampHoldsTwelve() {
        let store = makeStore()
        for n in 0..<BrowserStore.basecampLimit {
            #expect(store.addToBasecamp(store.openTab(url("t\(n)"))))
        }
        let extra = store.openTab(url("extra"))
        #expect(!store.canAddToBasecamp)
        #expect(!store.addToBasecamp(extra))
        #expect(extra.place == .open)
    }

    @Test func unpinningAnAwakeTabKeepsItAtTheTopOfTheTabs() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.pin(a)
        store.unpin(a)
        #expect(hosts(store.openTabs) == ["a.example", "b.example"])
        #expect(a.homeURL == nil)
    }

    @Test func unpinningARestingTabRemovesIt() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        store.pin(a)
        store.close(a)
        store.unpin(a)
        #expect(store.pinnedTabs.isEmpty)
        #expect(hosts(store.openTabs) == ["b.example"])
    }

    @Test func linksFromAPinOpenAtTheTopOfTheTabs() {
        let store = makeStore()
        store.openTab(url("a"))
        let pin = store.openTab(url("pin"))
        store.pin(pin)
        store.openTab(url("b"), opener: pin, inBackground: true)
        store.openTab(url("c"), opener: pin, inBackground: true)
        #expect(hosts(store.openTabs) == ["b.example", "c.example", "a.example"])
    }

    @Test func movingStaysWithinItsOwnList() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        store.openTab(url("c"))
        store.pin(a)
        store.pin(b)
        store.move(b, to: 0)
        #expect(hosts(store.pinnedTabs) == ["b.example", "a.example"])
        #expect(hosts(store.openTabs) == ["c.example"])
    }

    // MARK: - Saving and restoring

    @Test func aSavedSessionComesBackAsItWas() {
        let store = makeStore()
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let c = store.openTab(url("c"))
        store.addToBasecamp(a)
        store.pin(b)
        (c.page as? FakePage)?.title = "Page C"
        store.select(b)

        let restored = makeStore(restoring: save(store))
        #expect(hosts(restored.basecampTabs) == ["a.example"])
        #expect(hosts(restored.pinnedTabs) == ["b.example"])
        #expect(hosts(restored.openTabs) == ["c.example"])
        #expect(restored.openTabs.first?.title == "Page C")
        #expect(restored.pinnedTabs.first?.homeURL == url("b"))
        #expect(restored.activeTabID == b.id)
        #expect(save(restored).window == save(store).window)
    }

    @Test func onlyTheShownTabLoadsAfterRestoring() {
        let store = makeStore()
        store.openTab(url("a"))
        let b = store.openTab(url("b"))
        let restored = makeStore(restoring: save(store))
        #expect(restored.tabs.filter { !$0.isResting }.map(\.id) == [b.id])
    }

    @Test func lastChangedOnlyMovesWhenATabChanges() {
        var clock = Date(timeIntervalSince1970: 1000)
        let store = makeStore(now: { clock })
        store.openTab(url("a"))
        let b = store.openTab(url("b"), inBackground: true)
        let first = save(store)
        clock += 60
        store.pin(b) // Stays last, so a's order doesn't change.
        let second = save(store)
        let changed = Dictionary(uniqueKeysWithValues: second.tabs.map { ($0.url!.host()!, $0.lastChangedAt) })
        #expect(changed["a.example"] == first.tabs[0].lastChangedAt)
        #expect(changed["b.example"] == clock)
    }

    @Test func restoringRefusesWhatShouldntBeThere() {
        let store = makeStore()
        store.openTab(url("a"))
        var session = save(store)
        let good = session.tabs[0]
        func record(_ url: String?, space: UUID? = nil, id: UUID = UUID(), place: Tab.Place = .open) -> TabRecord {
            TabRecord(
                id: id, spaceID: space ?? good.spaceID, place: place, url: url.flatMap(URL.init(string:)),
                title: "", homeURL: nil, order: 9, lastActiveAt: .now, openerTabID: nil, lastChangedAt: .now
            )
        }
        session.tabs += [
            record("javascript:alert(1)"),
            record("file:///etc/passwd"),
            record(nil),
            record("https://other-space.example", space: UUID()),
            record("https://duplicate.example", id: good.id),
        ]
        session.tabs += (0...BrowserStore.basecampLimit).map { record("https://tile\($0).example", place: .basecamp) }
        for index in session.tabs.indices { session.tabs[index].order = index }
        let restored = makeStore(restoring: session)
        #expect(restored.basecampTabs.count == BrowserStore.basecampLimit)
        #expect(hosts(restored.openTabs) == ["a.example", "tile12.example"])
    }

    @Test func noSessionStartsWithTheDefaultSpace() {
        let store = makeStore()
        #expect(store.spaces == [space])
        #expect(store.tabs.isEmpty)
    }

    // MARK: - The file

    private func temporaryFile() -> SessionFile {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FirnTests-\(UUID().uuidString)")
        return SessionFile(url: folder.appending(path: "session.json"))
    }

    @Test func theFileRoundTrips() throws {
        // The file keeps dates to the second.
        let file = temporaryFile()
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        let space = Space(name: "Work", icon: "leaf", color: "sage", order: 0, dataStoreID: UUID(), lastChangedAt: second)
        let store = BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) }, now: { second })
        store.openTab(url("a"))
        let session = save(store)
        try file.save(session)
        #expect(file.load() == session)
    }

    @Test func aDamagedFileIsSetAsideNotLost() throws {
        let file = temporaryFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        #expect(file.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.path()))
        #expect(try Data(contentsOf: file.brokenURL) == Data("not json".utf8))
    }

    @Test func aMissingFileIsAFreshStart() {
        #expect(temporaryFile().load() == nil)
    }

    @Test func theSaverWritesAfterAChange() async throws {
        let file = temporaryFile()
        let store = makeStore()
        let saver = SessionSaver(file: file, delay: .milliseconds(10)) { self.save(store) }
        saver.start()
        #expect(file.load() == nil)
        store.openTab(url("a"))
        for _ in 0..<100 where file.load() == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(file.load()?.tabs.first?.url == url("a"))
    }
}
