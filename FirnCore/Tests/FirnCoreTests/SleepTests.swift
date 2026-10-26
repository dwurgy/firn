import Foundation
import Testing
@testable import FirnCore

/// Sleeping tabs: a page out of sight for an hour lets go of its memory,
/// and picks up where it was when shown again.
@MainActor
struct SleepTests {
    private let space = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    private final class Clock {
        var date = Date(timeIntervalSinceReferenceDate: 0)
        func advance(minutes: Double) { date += minutes * 60 }
    }

    private func makeStore(_ clock: Clock) -> BrowserStore {
        BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) }, now: { clock.date })
    }

    private func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    @Test func aTabOutOfSightForAnHourSleeps() async {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        clock.advance(minutes: 59)
        await store.sleepIdleTabs()
        #expect(!a.isResting)
        clock.advance(minutes: 1)
        await store.sleepIdleTabs()
        #expect(a.isResting)
        #expect(a.url == url("a"))
        #expect(a.title == "a.example")
    }

    @Test func wakingPicksUpWhereItWas() async {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        (a.page as? FakePage)?.url = url("a/page-two")
        store.openTab(url("b"))
        clock.advance(minutes: 60)
        await store.sleepIdleTabs()
        store.select(a)
        #expect((a.page as? FakePage)?.resumedFrom == url("a/page-two"))
    }

    @Test func theTabOnScreenAndItsSplitPartnerStayAwake() async throws {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        let b = store.openTab(url("b"))
        try #require(store.openSplit(a, beside: b) != nil)
        store.select(b)
        clock.advance(minutes: 120)
        await store.sleepIdleTabs(memoryIsShort: true)
        #expect(!a.isResting && !b.isResting)
    }

    @Test func basecampTilesStayAwake() async {
        let clock = Clock()
        let store = makeStore(clock)
        let tile = store.openTab(url("mail"))
        store.addToBasecamp(tile)
        store.openTab(url("b"))
        clock.advance(minutes: 120)
        await store.sleepIdleTabs()
        #expect(!tile.isResting)
    }

    @Test func aPageInUseStaysAwake() async {
        let clock = Clock()
        let store = makeStore(clock)
        let call = store.openTab(url("call"))
        (call.page as? FakePage)?.inUse = true
        store.openTab(url("b"))
        clock.advance(minutes: 120)
        await store.sleepIdleTabs()
        #expect(!call.isResting)
    }

    @Test func shortOfMemoryAnyTabOutOfSightSleeps() async {
        let clock = Clock()
        let store = makeStore(clock)
        let a = store.openTab(url("a"))
        store.openTab(url("b"))
        clock.advance(minutes: 1)
        await store.sleepIdleTabs(memoryIsShort: true)
        #expect(a.isResting)
    }

    @Test func stoppingSharingForgetsASleepingTabsPlace() async {
        let clock = Clock()
        let store = makeStore(clock)
        let shared = store.addSpace(name: "Work", color: "sand", sharingWith: space)
        let a = store.openTab(url("a"))
        (a.page as? FakePage)?.url = url("a/page-two")
        store.openTab(url("b"))
        clock.advance(minutes: 60)
        await store.sleepIdleTabs()
        store.stopSharing(shared)
        store.select(a)
        #expect((a.page as? FakePage)?.resumedFrom == nil)
        #expect(a.page?.url == url("a/page-two"))
    }
}
