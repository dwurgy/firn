import Foundation
import Testing
@testable import FirnCore

/// "On your Mac" and "On your iPhone" (docs/SYNC-PLAN.md, step 5): each
/// device's open tabs in one sealed record, found in the command bar in the
/// space on screen only.
@MainActor
struct DeviceTabsTests {
    let clock = TestClock()
    let key = SyncSeal.makeKeyData()
    let personal = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())
    let work = Space(name: "Work", color: "sand", order: 1, dataStoreID: UUID())

    func url(_ name: String) -> URL { URL(string: "https://\(name).example/")! }

    /// A Mac and a phone already syncing Personal and Work.
    func devices() -> (SyncDevice, SyncDevice) {
        let mac = SyncDevice(spaces: [personal, work], clock: clock)
        let phone = SyncDevice(spaces: [personal, work], clock: clock)
        sendSpaces(from: mac, to: phone)
        sendSpaces(from: phone, to: mac)
        mac.store.finishFirstSync(&mac.state)
        phone.store.finishFirstSync(&phone.state)
        return (mac, phone)
    }

    func sendSpaces(from sender: SyncDevice, to receiver: SyncDevice) {
        let changes = sender.store.takeSyncChanges(into: &sender.state)
        let seal = SyncSeal(keyData: key)!
        let saves = changes.saves.map { try! seal.open(try! seal.seal($0)) }
        receiver.store.applySync(saves: saves, deletes: changes.deletes, to: &receiver.state)
    }

    /// Sends a device's open tabs, sealed and opened on the way.
    @discardableResult
    func sendTabs(from sender: SyncDevice, as kind: SyncedDevice.Kind, named name: String? = nil, to receiver: SyncDevice) throws -> SyncedDevice {
        let record = sender.store.deviceRecord(kind: kind, name: name, state: sender.state)
        let seal = SyncSeal(keyData: key)!
        let sealed = try seal.seal(.device(record))
        #expect(sealed.sealed.count <= SyncSeal.sealedLimit)
        receiver.store.applySync(saves: [try seal.open(sealed)], deletes: [], to: &receiver.state)
        return record
    }

    @discardableResult
    func open(_ host: String, title: String, on device: SyncDevice) -> Tab {
        let tab = device.store.openTab(url(host))
        (tab.page as? FakePage)?.title = title
        return tab
    }

    func rows(_ text: String, on device: SyncDevice, history: [HistoryPage] = []) -> [CommandRow] {
        device.store.commandRows(
            for: text, searchEngine: .google, history: history,
            otherDevices: device.store.otherDeviceTabs(in: device.state, thisDevice: .mac)
        )
    }

    func deviceTabs(in rows: [CommandRow]) -> [DeviceTab] {
        rows.compactMap { if case let .otherDevice(tab) = $0 { tab } else { nil } }
    }

    // MARK: - The record

    @Test func onlyLooseAndGroupedTabsGoTheMostRecentFirst() throws {
        let (_, phone) = devices()
        let tile = open("tile", title: "Tile", on: phone)
        #expect(phone.store.addToBasecamp(tile))
        let tidied = open("tidied", title: "Tidied", on: phone)
        let grouped = open("grouped", title: "Grouped", on: phone)
        _ = phone.store.newGroup(with: grouped)
        open("loose", title: "Loose", on: phone)
        phone.store.drift(tidied)
        phone.store.openLookout(url("lookout"))

        let record = phone.store.deviceRecord(kind: .iPhone, name: "Ignored", state: phone.state)
        #expect(record.tabs.map(\.url.host) == ["loose.example", "grouped.example"])
        #expect(record.tabs.map(\.title) == ["Loose", "Grouped"])
        #expect(record.id == phone.state.deviceID)
        // An iPhone's name never goes: it can't read its own.
        #expect(record.name == nil)
    }

    @Test func atMost150TabsTheMostRecentlyUsed() throws {
        let (mac, phone) = devices()
        for index in 0..<160 {
            open("site\(index)", title: String(repeating: "Long title ", count: 40), on: phone)
        }
        let record = try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(record.tabs.count == SyncedDevice.tabLimit)
        #expect(record.tabs.first?.url.host == "site159.example")
        #expect(record.tabs.allSatisfy { $0.title.count <= SyncedDevice.titleLimit })
    }

    @Test func longAddressesNeverPushARecordPastWhatItMayHold() throws {
        let (mac, phone) = devices()
        let long = String(repeating: "a", count: 2000)
        for index in 0..<150 { phone.store.openTab(URL(string: "https://site\(index).example/\(long)")!) }
        let record = try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(!record.tabs.isEmpty && record.tabs.count < 150)
        #expect(try JSONEncoder().encode(record).count <= SyncedDevice.fieldsBudget)
    }

    // MARK: - The space filter

    @Test func aTabIsFoundOnlyInItsOwnSpace() throws {
        let (mac, phone) = devices()
        phone.store.selectSpace(phone.store.spaces[1])
        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)

        #expect(deviceTabs(in: rows("trail", on: mac)).isEmpty)  // Mac in Personal
        mac.store.selectSpace(mac.store.spaces[1])
        let found = deviceTabs(in: rows("trail", on: mac))
        #expect(found.map(\.title) == ["Trail map"])
        #expect(found.first?.deviceLabel == "On your iPhone")
    }

    @Test func aSpaceThatJoinedStillMatches() throws {
        // The phone's own Personal joined the Mac's on the first sync.
        let mac = SyncDevice(spaces: [personal], clock: clock)
        mac.store.finishFirstSync(&mac.state)
        let phonesOwn = Space(name: "Personal", color: "sage", order: 0, dataStoreID: UUID())
        let phone = SyncDevice(spaces: [phonesOwn], clock: clock)
        sendSpaces(from: mac, to: phone)
        phone.store.finishFirstSync(&phone.state)
        #expect(phone.space.id == phonesOwn.id)

        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(deviceTabs(in: rows("trail", on: mac)).count == 1)
        // And the other way.
        open("cabin", title: "Cabin", on: mac)
        try sendTabs(from: mac, as: .mac, to: phone)
        #expect(phone.store.otherDeviceTabs(in: phone.state, thisDevice: .iPhone).map(\.title) == ["Cabin"])
    }

    @Test func aSpaceThisDeviceDoesntHaveNeverShows() throws {
        let (mac, phone) = devices()
        let trip = phone.store.addSpace(name: "Trip", color: "sage")
        phone.store.selectSpace(trip)
        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        for space in mac.store.spaces {
            mac.store.selectSpace(space)
            #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).isEmpty)
        }
    }

    // MARK: - Staying fresh

    @Test func aClosedTabDropsOffTheNextSend() throws {
        let (mac, phone) = devices()
        let tab = open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(deviceTabs(in: rows("trail", on: mac)).count == 1)
        phone.store.close(tab)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(deviceTabs(in: rows("trail", on: mac)).isEmpty)
    }

    @Test func aDeletedRecordAndAStaleDeviceStopShowing() throws {
        let (mac, phone) = devices()
        open("trail", title: "Trail map", on: phone)
        let record = try sendTabs(from: phone, as: .iPhone, to: mac)
        clock.time += SyncedDevice.staleAfter + 60
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).isEmpty)

        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).count == 1)
        mac.store.applySync(saves: [], deletes: [SyncItem.device(record).id], to: &mac.state)
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).isEmpty)
    }

    @Test func staleDevicesAreForgottenAndComeBackWithTheirNextSend() throws {
        let (mac, phone) = devices()
        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        let sentAt = try #require(mac.state.devices.values.first?.sentAt)

        mac.state.forgetDevices(sentBefore: sentAt)
        #expect(mac.state.devices.count == 1)
        mac.state.forgetDevices(sentBefore: sentAt.addingTimeInterval(1))
        #expect(mac.state.devices.isEmpty)

        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).count == 1)
        #expect(mac.state.deviceRecordID == SyncRecordID(kind: .device, name: mac.state.deviceID))
    }

    @Test func aSiteIconComesOnlyFromThisSpacesOwnTabs() throws {
        let (mac, phone) = devices()
        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).first?.icon == nil)

        // Work has the site, with its icon: Personal still gets no icon.
        mac.store.selectSpace(mac.store.spaces[1])
        let there = mac.store.openTab(URL(string: "https://trail.example/other")!)
        (there.page as? FakePage)?.icon = Data([1, 2, 3])
        mac.store.selectSpace(mac.store.spaces[0])
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).first?.icon == nil)

        let here = mac.store.openTab(URL(string: "https://trail.example/else")!)
        (here.page as? FakePage)?.icon = Data([4, 5])
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).first?.icon == Data([4, 5]))
    }

    @Test func aDevicesOwnRecordComingBackIsIgnored() throws {
        let (mac, _) = devices()
        open("trail", title: "Trail map", on: mac)
        let own = mac.store.deviceRecord(kind: .mac, name: nil, state: mac.state)
        mac.store.applySync(saves: [.device(own)], deletes: [], to: &mac.state)
        #expect(mac.state.devices.isEmpty)
    }

    // MARK: - What arrives is checked

    @Test func onlyWebAddressesAndTidyTitlesArrive() throws {
        let (mac, _) = devices()
        let space = mac.space.id
        let hostile = SyncedDevice(
            id: UUID().uuidString, kind: .iPhone, name: "Should go", sentAt: clock.time,
            tabs: [
                .init(url: URL(string: "javascript:alert(1)")!, title: "Script", spaceID: space),
                .init(url: URL(string: "file:///etc/passwd")!, title: "File", spaceID: space),
                .init(url: url("fine"), title: "  Fine\nline  " + String(repeating: "x", count: 900), spaceID: space),
            ] + (0..<300).map { .init(url: url("more\($0)"), title: "More", spaceID: space) }
        )
        let seal = SyncSeal(keyData: key)!
        let opened = try seal.open(try seal.seal(.device(hostile)))
        mac.store.applySync(saves: [opened], deletes: [], to: &mac.state)

        let kept = try #require(mac.state.devices[hostile.id])
        #expect(kept.tabs.count == SyncedDevice.tabLimit)
        #expect(kept.tabs.allSatisfy { WebAddress.isWebURL($0.url) })
        #expect(kept.tabs[0].title.hasPrefix("Fineline"))
        #expect(kept.tabs[0].title.count == SyncedDevice.titleLimit)
    }

    @Test func aRecordCantPassAsAnotherDevice() throws {
        let seal = SyncSeal(keyData: key)!
        let device = SyncedDevice(id: "a", kind: .mac, name: nil, sentAt: clock.time, tabs: [])
        var sealed = try seal.seal(.device(device))
        sealed.id.name = "b"
        #expect(throws: SyncSeal.Failure.unreadable) { try seal.open(sealed) }
    }

    // MARK: - The command bar's rows

    @Test func atMostTwoRowsAfterThisSpacesTabsAndBeforeHistory() throws {
        let (mac, phone) = devices()
        for index in 0..<4 { open("trail\(index)", title: "Trail \(index)", on: phone) }
        try sendTabs(from: phone, as: .iPhone, to: mac)
        open("trailhead", title: "Trailhead", on: mac)
        open("other", title: "Elsewhere", on: mac)  // so Trailhead isn't on screen
        let page = HistoryPage(url: url("trails"), title: "Trails of Oregon", site: "trails.example", lastVisitedAt: clock.time, score: 1)

        let found = rows("trail", on: mac, history: [page])
        let kinds = found.map { row -> String in
            switch row {
            case .tab: "tab"
            case .otherDevice: "device"
            case .history: "history"
            default: "other"
            }
        }
        #expect(kinds.filter { $0 != "other" } == ["tab", "device", "device", "history"])
        // The most recently used of the phone's first.
        #expect(deviceTabs(in: found).map(\.title) == ["Trail 3", "Trail 2"])
    }

    @Test func aPageOpenHereIsntOfferedAgainNorWithNothingTyped() throws {
        let (mac, phone) = devices()
        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        #expect(rows("", on: mac).isEmpty)
        open("trail", title: "Trail map", on: mac)
        open("other", title: "Elsewhere", on: mac)
        #expect(deviceTabs(in: rows("trail", on: mac)).isEmpty)
    }

    @Test func aPageOnTwoDevicesIsOfferedOnce() throws {
        let (mac, phone) = devices()
        let pad = SyncDevice(spaces: [personal, work], clock: clock)
        open("trail", title: "Trail map", on: phone)
        open("trail", title: "Trail map", on: pad)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        try sendTabs(from: pad, as: .iPad, to: mac)
        // The iPad sent last, so it's the one named.
        #expect(deviceTabs(in: rows("trail", on: mac)).map(\.deviceLabel) == ["On your iPad"])
    }

    // MARK: - Names

    @Test func twoMacsGoByTheirOwnNames() throws {
        let (mac, phone) = devices()
        let other = SyncDevice(spaces: [personal, work], clock: clock)
        open("trail", title: "Trail map", on: other)
        try sendTabs(from: other, as: .mac, named: "Studio Mac", to: mac)
        try sendTabs(from: other, as: .mac, named: "Studio Mac", to: phone)
        #expect(mac.store.otherDeviceTabs(in: mac.state, thisDevice: .mac).first?.deviceLabel == "On Studio Mac")
        // One Mac seen from a phone is just "your Mac".
        #expect(phone.store.otherDeviceTabs(in: phone.state, thisDevice: .iPhone).first?.deviceLabel == "On your Mac")
    }

    // MARK: - Kept between launches

    @Test func theDevicesSurviveBeingSavedAndOldFilesStillOpen() throws {
        let (mac, phone) = devices()
        open("trail", title: "Trail map", on: phone)
        try sendTabs(from: phone, as: .iPhone, to: mac)
        let data = try JSONEncoder().encode(mac.state)
        #expect(try JSONDecoder().decode(SyncState.self, from: data) == mac.state)

        // A sync file from before this step: no device id or devices.
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["deviceID"] = nil
        old["devices"] = nil
        let back = try JSONDecoder().decode(SyncState.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(back.devices.isEmpty)
        #expect(back.firstSyncDone && !back.deviceID.isEmpty)
        #expect(back.item(for: SyncRecordID(kind: .space, name: personal.id.uuidString)) != nil)
    }
}
