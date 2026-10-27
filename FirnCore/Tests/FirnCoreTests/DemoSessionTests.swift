import Foundation
import Testing
@testable import FirnCore

@MainActor
struct DemoSessionTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15))!

    private func restored() -> (Session, BrowserStore) {
        let session = DemoSession.make(now: now).session
        let store = BrowserStore(
            restoring: session, defaultSpaces: [], makePage: { FakePage(dataStoreID: $0) }, now: { [now] in now }
        )
        return (session, store)
    }

    @Test func threeSeparateSpacesWithNewDataStoresEachTime() {
        let first = DemoSession.make(now: now).session
        let second = DemoSession.make(now: now).session
        #expect(first.spaces.map(\.name) == ["Personal", "Work", "Trip"])
        #expect(first.spaces.map(\.color) == ["sage", "glacier", "ochre"])
        #expect(Set(first.spaces.map(\.dataStoreID)).count == 3)
        #expect(Set(first.spaces.map(\.dataStoreID)).isDisjoint(with: second.spaces.map(\.dataStoreID)))
    }

    @Test func restoresWhole() {
        let (session, store) = restored()
        #expect(store.tabs.count == session.tabs.count)
        #expect(store.groups.map(\.name) == ["Weekend cooking", "Launch", "Sisters"])
        let personal = session.spaces[0].id
        let basecamp = { (space: UUID) in store.tabs.filter { $0.spaceID == space && $0.place == .basecamp }.map(\.title) }
        #expect(basecamp(personal) == ["Gmail", "GitHub", "YouTube", "Apple Music"])
        #expect(basecamp(session.spaces[1].id) == ["Google Calendar", "Slack", "Notion"])
        #expect(basecamp(session.spaces[2].id).isEmpty)
        #expect(store.tabs.filter { $0.place == .drifted }.allSatisfy { $0.spaceID == personal })
        #expect(store.tabs.count { $0.place == .drifted } == 3)
        #expect(store.activeSpaceID == personal)
        #expect(store.activeTab?.url?.host() == "www.snowpeak.com")
    }

    @Test func nothingDriftsOrExpiresAtLaunch() {
        let (session, store) = restored()
        #expect(store.idleTabs().isEmpty)
        #expect(store.tabs.count == session.tabs.count)
    }

    @Test func everyPageIsHttpsWithAnIcon() {
        // A tab on screen at launch loads, so it gets its icon from the page.
        let session = DemoSession.make(now: Date()).session
        let window = session.window
        let onScreen = Set(([window.activeTabID] + Array(window.spaceTabIDs.values)).compactMap { id in
            session.tabs.first { $0.id == id }?.url?.host()
        })
        for page in DemoSession.allPages {
            #expect(page.url.scheme == "https", "\(page.url)")
            let host = page.url.host() ?? ""
            #expect(onScreen.contains(host) || !DemoSession.iconAddresses(for: host).isEmpty, "\(host)")
            #expect(DemoSession.iconAddresses(for: host).allSatisfy { $0.scheme == "https" })
        }
    }

    @Test func historyIsTwoWeeksInTheSpacesOwnStores() {
        let (session, visits) = DemoSession.make(now: now)
        let stores = Set(session.spaces.map(\.dataStoreID))
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        #expect(visits.count > 100)
        #expect(visits.allSatisfy { $0.time < now && $0.time > twoWeeksAgo })
        #expect(visits.allSatisfy { stores.contains($0.dataStoreID) })
        // Each space's history holds only its own pages.
        for space in session.spaces {
            let own = Set(session.tabs.filter { $0.spaceID == space.id }.compactMap(\.url))
            #expect(visits.filter { $0.dataStoreID == space.dataStoreID }.allSatisfy { own.contains($0.url) })
        }
    }
}
