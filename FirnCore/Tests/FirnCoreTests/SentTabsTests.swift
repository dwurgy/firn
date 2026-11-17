import Foundation
import Testing
@testable import FirnCore

/// Send to My Mac, Send to My iPhone (docs/SYNC-PLAN.md, step 6): a sealed
/// record for one device, opened where new tabs go there, then deleted.
@MainActor
struct SentTabsTests {
    let clock = TestClock()
    let key = SyncSeal.makeKeyData()
    let personal = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())
    let work = Space(name: "Work", color: "sand", order: 1, dataStoreID: UUID())
    var seal: SyncSeal { SyncSeal(keyData: key)! }

    func url(_ name: String) -> URL { URL(string: "https://\(name).example/")! }

    /// A Mac and a phone syncing Personal and Work, each knowing the other.
    func devices() throws -> (SyncDevice, SyncDevice) {
        let mac = SyncDevice(spaces: [personal, work], clock: clock)
        let phone = SyncDevice(spaces: [personal, work], clock: clock)
        try deliver(mac.store.takeSyncChanges(into: &mac.state).saves, to: phone)
        try deliver(phone.store.takeSyncChanges(into: &phone.state).saves, to: mac)
        mac.store.finishFirstSync(&mac.state)
        phone.store.finishFirstSync(&phone.state)
        try deliver([.device(mac.store.deviceRecord(kind: .mac, name: "David's Mac mini", state: mac.state))], to: phone)
        try deliver([.device(phone.store.deviceRecord(kind: .iPhone, name: nil, state: phone.state))], to: mac)
        return (mac, phone)
    }

    /// Sealed and opened on the way, as iCloud would carry them.
    @discardableResult
    func deliver(_ items: [SyncItem], deletes: [SyncRecordID] = [], to device: SyncDevice) throws -> SyncChanges {
        let saves = try items.map { try seal.open(try seal.seal($0)) }
        return device.store.applySync(saves: saves, deletes: deletes, to: &device.state)
    }

    /// The phone sends the tab on screen to the Mac.
    func send(_ host: String, title: String = "Trail map", from phone: SyncDevice) throws -> SentTab {
        let tab = phone.store.openTab(url(host))
        (tab.page as? FakePage)?.title = title
        let target = try #require(phone.state.sendTargets(at: clock.time).first)
        return try #require(phone.store.sentTab(tab, to: target, from: .iPhone, state: phone.state))
    }

    // MARK: - Sending and arriving

    @Test func aSentTabOpensWhereNewTabsGoWithoutBeingShown() throws {
        let (mac, phone) = try devices()
        phone.store.selectSpace(phone.store.spaces[1])
        let sent = try send("trail", from: phone)
        try deliver([.sentTab(sent)], to: mac)
        #expect(mac.state.waitingSentTabs.map(\.id) == [sent.id])

        let onScreen = mac.store.activeTabID
        let arrival = mac.store.openSentTabs(&mac.state)
        let tab = try #require(mac.store.tabs.first { $0.id == arrival.tabIDs.first })
        #expect(tab.url == url("trail"))
        #expect(tab.title == "Trail map")
        #expect(tab.spaceID == work.id)  // its own space, though the Mac is in Personal
        #expect(tab.place == .open)
        #expect(mac.store.activeTabID == onScreen)
        #expect(mac.store.activeSpaceID == personal.id)
        #expect(arrival.note == "From iPhone")
        #expect(arrival.deletes == [sent.recordID])
        #expect(mac.state.waitingSentTabs.isEmpty)
    }

    @Test func aSendOpensOnlyOnceEvenIfFetchedAgain() throws {
        let (mac, phone) = try devices()
        let sent = try send("trail", from: phone)
        try deliver([.sentTab(sent)], to: mac)
        _ = mac.store.openSentTabs(&mac.state)
        // Fetched again before its delete went through.
        try deliver([.sentTab(sent)], to: mac)
        #expect(mac.state.waitingSentTabs.isEmpty)
        #expect(mac.store.openSentTabs(&mac.state).tabIDs.isEmpty)
    }

    @Test func aSendForAnotherDeviceIsLeftAlone() throws {
        let (mac, phone) = try devices()
        var sent = try send("trail", from: phone)
        sent.toDeviceID = UUID().uuidString
        let changes = try deliver([.sentTab(sent)], to: mac)
        #expect(mac.state.waitingSentTabs.isEmpty)
        #expect(!changes.deletes.contains(sent.recordID))
    }

    @Test func aDeleteFromICloudTakesItBack() throws {
        let (mac, phone) = try devices()
        let sent = try send("trail", from: phone)
        try deliver([.sentTab(sent)], to: mac)
        try deliver([], deletes: [sent.recordID], to: mac)
        #expect(mac.state.waitingSentTabs.isEmpty)
    }

    @Test func aSpaceThisDeviceLacksOpensInTheSpaceOnScreen() throws {
        let (mac, phone) = try devices()
        var sent = try send("trail", from: phone)
        sent.spaceID = UUID()
        try deliver([.sentTab(sent)], to: mac)
        mac.store.selectSpace(mac.store.spaces[1])
        let arrival = mac.store.openSentTabs(&mac.state)
        #expect(mac.store.tabs.first { $0.id == arrival.tabIDs.first }?.spaceID == work.id)
    }

    @Test func aSpaceThatJoinedStillMatches() throws {
        // The phone's own Personal joined the Mac's on the first sync.
        let mac = SyncDevice(spaces: [personal], clock: clock)
        try deliver(mac.store.takeSyncChanges(into: &mac.state).saves, to: SyncDevice(spaces: [personal], clock: clock))
        mac.store.finishFirstSync(&mac.state)
        let phonesOwn = Space(name: "Personal", color: "sage", order: 0, dataStoreID: UUID())
        let phone = SyncDevice(spaces: [phonesOwn], clock: clock)
        try deliver([.space(SyncedSpace(id: personal.id, name: "Personal", color: "glacier", order: 0,
                                        dataStoreID: personal.dataStoreID, changedAt: clock.tick()))], to: phone)
        phone.store.finishFirstSync(&phone.state)
        #expect(phone.space.id == phonesOwn.id)
        try deliver([.device(mac.store.deviceRecord(kind: .mac, name: nil, state: mac.state))], to: phone)

        let sent = try send("trail", from: phone)
        #expect(sent.spaceID == personal.id)  // in iCloud's terms
        try deliver([.sentTab(sent)], to: mac)
        let arrival = mac.store.openSentTabs(&mac.state)
        #expect(mac.store.tabs.first { $0.id == arrival.tabIDs.first }?.spaceID == personal.id)
    }

    // MARK: - Expiry

    @Test func anExpiredSendIsDeletedByAnyDeviceAndNeverOpens() throws {
        let (mac, phone) = try devices()
        var sent = try send("trail", from: phone)
        sent.toDeviceID = UUID().uuidString  // for a device no longer used
        clock.time += SentTab.expiresAfter + 60
        let changes = try deliver([.sentTab(sent)], to: mac)
        #expect(changes.deletes.contains(sent.recordID))
        #expect(mac.state.waitingSentTabs.isEmpty)
    }

    @Test func oneThatExpiredWhileWaitingIsDeletedNotOpened() throws {
        let (mac, phone) = try devices()
        let sent = try send("trail", from: phone)
        try deliver([.sentTab(sent)], to: mac)
        clock.time += SentTab.expiresAfter + 60
        let arrival = mac.store.openSentTabs(&mac.state)
        #expect(arrival.tabIDs.isEmpty)
        #expect(arrival.note == nil)
        #expect(arrival.deletes == [sent.recordID])
    }

    // MARK: - What may be sent

    @Test func onlyWebPagesAreSent() throws {
        let (_, phone) = try devices()
        let target = try #require(phone.state.sendTargets(at: clock.time).first)
        let file = phone.store.openTab(URL(fileURLWithPath: "/tmp/page.html"))
        #expect(phone.store.sentTab(file, to: target, from: .iPhone, state: phone.state) == nil)
    }

    @Test func aHostileSendIsRefusedAsItOpens() throws {
        let (_, phone) = try devices()
        var sent = try send("trail", from: phone)
        sent.url = URL(string: "javascript:alert(1)")!
        let sealed = try seal.seal(.sentTab(sent))
        #expect(throws: SyncSeal.Failure.malformed) { try seal.open(sealed) }
    }

    @Test func aLongTitleIsCut() throws {
        let (_, phone) = try devices()
        let sent = try send("trail", title: String(repeating: "Long ", count: 100), from: phone)
        #expect(sent.title.count <= SyncedDevice.titleLimit)
    }

    // MARK: - The menu's words

    @Test func oneDeviceGoesByItsPlainName() throws {
        let (mac, phone) = try devices()
        #expect(SendTarget.menuTitle(for: phone.state.sendTargets(at: clock.time)) == "Send to My Mac")
        #expect(SendTarget.menuTitle(for: mac.state.sendTargets(at: clock.time)) == "Send to My iPhone")
        #expect(SendTarget.menuTitle(for: []) == nil)
    }

    @Test func severalDevicesAreListedByName() throws {
        let (mac, _) = try devices()
        let other = { (kind: SyncedDevice.Kind, name: String?) in
            SyncedDevice(id: UUID().uuidString, kind: kind, name: name, sentAt: clock.tick(), tabs: [])
        }
        mac.state.devices["a"] = other(.mac, "Studio")
        mac.state.devices["b"] = other(.iPhone, nil)
        mac.state.devices["c"] = other(.iPad, nil)
        let targets = mac.state.sendTargets(at: clock.time)
        #expect(SendTarget.menuTitle(for: targets) == "Send to…")
        // The most recently sent first; two iPhones numbered.
        #expect(targets.map(\.name) == ["My iPad", "My iPhone", "Studio", "My iPhone (2)"])
    }

    @Test func aStaleDeviceIsNotOffered() throws {
        let (_, phone) = try devices()
        clock.time += SyncedDevice.staleAfter + 60
        #expect(phone.state.sendTargets(at: clock.time).isEmpty)
    }

    @Test func theNoteSaysWhereTabsCameFrom() throws {
        let tab = { (kind: SyncedDevice.Kind) in
            SentTab(id: UUID().uuidString, toDeviceID: "x", from: kind, url: url("a"), title: "", spaceID: UUID(), sentAt: .now)
        }
        #expect(SentTab.arrivalNote(for: [tab(.mac)]) == "From Mac")
        #expect(SentTab.arrivalNote(for: [tab(.iPad), tab(.iPad), tab(.iPad)]) == "3 tabs from iPad")
        #expect(SentTab.arrivalNote(for: [tab(.mac), tab(.iPhone)]) == "2 tabs from your devices")
        #expect(SentTab.arrivalNote(for: []) == nil)
    }

    @Test func waitingSendsSurviveARestart() throws {
        let (mac, phone) = try devices()
        let sent = try send("trail", from: phone)
        try deliver([.sentTab(sent)], to: mac)
        let decoded = try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(mac.state))
        #expect(decoded.waitingSentTabs == [sent])
    }
}
