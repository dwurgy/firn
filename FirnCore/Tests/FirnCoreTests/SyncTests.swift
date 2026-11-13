import Foundation
import Testing
@testable import FirnCore

/// A clock the test moves by hand, shared by both devices.
@MainActor
final class TestClock {
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    func tick() -> Date {
        time += 1
        return time
    }
}

/// One device: its store and what it knows about sync.
@MainActor
final class SyncDevice {
    final class Erased { var ids: [UUID] = [] }
    let store: BrowserStore
    var state = SyncState()
    let erased = Erased()

    init(spaces: [Space], clock: TestClock) {
        let erased = erased
        store = BrowserStore(
            spaces: spaces, makePage: { FakePage(dataStoreID: $0) },
            removeData: { erased.ids.append($0) }, now: { clock.tick() }
        )
    }

    var space: Space { store.spaces[0] }

    func group(named name: String) -> TabGroup? { store.groups.first { $0.name == name } }

    func hosts(in group: TabGroup) -> [String] { store.tabs(in: group).map { $0.url?.host()?.replacingOccurrences(of: ".example", with: "") ?? "" } }
}

@MainActor
struct SyncTests {
    let clock = TestClock()
    let key = SyncSeal.makeKeyData()
    let personal = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())

    func url(_ name: String) -> URL { URL(string: "https://\(name).example")! }

    func devices() -> (SyncDevice, SyncDevice) {
        let mac = SyncDevice(spaces: [personal], clock: clock)
        let phone = SyncDevice(spaces: [personal], clock: clock)
        // Each device's first look; they agree on the one space.
        send(from: mac, to: phone)
        send(from: phone, to: mac)
        mac.state.finishFirstSync()
        phone.state.finishFirstSync()
        return (mac, phone)
    }

    /// A Mac already syncing, and a phone turning sync on with its own spaces.
    func firstSync(phoneSpaces: [Space]) -> (SyncDevice, SyncDevice) {
        let mac = SyncDevice(spaces: [personal], clock: clock)
        mac.state.finishFirstSync()
        let phone = SyncDevice(spaces: phoneSpaces, clock: clock)
        return (mac, phone)
    }

    /// Sends one device's changes to the other, sealed and opened on the
    /// way, and returns what the receiver had of its own to send.
    @discardableResult
    func send(from sender: SyncDevice, to receiver: SyncDevice, deletesFirst: Bool = false) -> SyncApplied {
        let changes = sender.store.takeSyncChanges(into: &sender.state)
        let seal = SyncSeal(keyData: key)!
        let saves = changes.saves.map { try! seal.open(try! seal.seal($0)) }
        if deletesFirst {
            _ = receiver.store.applySync(saves: [], deletes: changes.deletes, to: &receiver.state)
            return receiver.store.applySync(saves: saves, deletes: [], to: &receiver.state)
        }
        return receiver.store.applySync(saves: saves, deletes: changes.deletes, to: &receiver.state)
    }

    /// A kept group of tabs named a, b, … on `device`.
    @discardableResult
    func makeGroup(_ name: String, _ hosts: String..., on device: SyncDevice) -> TabGroup {
        let tabs = hosts.map { device.store.openTab(url($0)) }
        let group = device.store.newGroup(with: tabs[0])!
        for tab in tabs.dropFirst() { device.store.move(tab, toEndOf: group) }
        device.store.rename(group, to: name)
        return device.group(named: name)!
    }

    // MARK: - The seal

    @Test func sealedRecordsOpenOnlyWithTheSameKey() throws {
        let seal = try #require(SyncSeal(keyData: key))
        let item = SyncItem.group(SyncedGroup(id: UUID(), spaceID: UUID(), name: "Trip", changedAt: clock.time))
        let record = try seal.seal(item)
        #expect(try seal.open(record) == item)
        // The name is nowhere in what iCloud holds.
        #expect(record.sealed.range(of: Data("Trip".utf8)) == nil)
        let other = try #require(SyncSeal(keyData: SyncSeal.makeKeyData()))
        // Another key's record is told apart from a damaged one, by its key id.
        #expect(throws: SyncSeal.Failure.otherKey) { try other.open(record) }
        #expect(SyncSeal.keyID(of: record) == seal.keyID)
        #expect(seal.keyID.count == 8 && seal.keyID != other.keyID)
        #expect(try #require(SyncSeal(keyData: key)).keyID == seal.keyID)
    }

    @Test func aSealedRecordCantPassAsAnother() throws {
        let seal = try #require(SyncSeal(keyData: key))
        let record = try seal.seal(.group(SyncedGroup(id: UUID(), spaceID: UUID(), name: "Trip", changedAt: clock.time)))
        var moved = record
        moved.id.name = UUID().uuidString
        #expect(throws: SyncSeal.Failure.unreadable) { try seal.open(moved) }
        var retyped = record
        retyped.id.kind = .space
        #expect(throws: SyncSeal.Failure.unreadable) { try seal.open(retyped) }
        var tampered = record
        tampered.sealed[tampered.sealed.count - 1] ^= 1
        #expect(throws: SyncSeal.Failure.unreadable) { try seal.open(tampered) }
        #expect(throws: SyncSeal.Failure.unreadable) {
            try seal.open(SyncRecord(id: record.id, sealed: Data(repeating: 1, count: 100_000)))
        }
    }

    @Test func keysAreExactly256Bits() {
        #expect(SyncSeal(keyData: Data(count: 16)) == nil)
        #expect(SyncSeal.makeKeyData().count == 32)
        #expect(SyncSeal.makeKeyData() != SyncSeal.makeKeyData())
    }

    // MARK: - The first sync

    @Test func aSpaceWithTheSameNameJoinsAndKeepsItsSignIns() throws {
        let phonePersonal = Space(name: "personal", color: "sage", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [phonePersonal])
        makeGroup("Trip", "a", on: mac)
        phone.store.openTab(url("b"))
        let fromPhone = send(from: mac, to: phone).toSend
        // One space: the phone's own, under the Mac's name and color, its
        // data store (sign-ins, history, passwords) untouched.
        #expect(phone.store.spaces.map(\.id) == [phonePersonal.id])
        #expect(phone.space.name == "Personal" && phone.space.color == "glacier")
        #expect(phone.space.dataStoreID == phonePersonal.dataStoreID)
        #expect(phone.erased.ids.isEmpty)
        #expect(phone.hosts(in: try #require(phone.group(named: "Trip"))) == ["a"])
        #expect(phone.store.tabs.contains { $0.url == url("b") && $0.spaceID == phonePersonal.id })
        // Nothing of the phone's own id goes up.
        #expect(fromPhone.saves.allSatisfy { $0.id.name != phonePersonal.id.uuidString })
        #expect(phone.state.item(for: SyncRecordID(kind: .space, name: phonePersonal.id.uuidString)) == nil)
        phone.state.finishFirstSync()

        // From now on each side's edits reach the other in its own terms.
        phone.store.updateSpace(phone.space, name: "Home", color: phone.space.color)
        makeGroup("Work", "c", on: phone)
        send(from: phone, to: mac)
        #expect(mac.store.spaces.count == 1 && mac.space.name == "Home")
        #expect(mac.space.dataStoreID == personal.dataStoreID && mac.erased.ids.isEmpty)
        #expect(mac.group(named: "Work")?.spaceID == personal.id)
        makeGroup("Later", "d", on: mac)
        send(from: mac, to: phone)
        #expect(phone.group(named: "Later")?.spaceID == phonePersonal.id)
        #expect(phone.space.dataStoreID == phonePersonal.dataStoreID && phone.erased.ids.isEmpty)
    }

    @Test func anUntouchedSpaceGivesWay() throws {
        let untouched = Space(name: "New Space", color: "glacier", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [untouched])
        let fromPhone = send(from: mac, to: phone).toSend
        #expect(phone.store.spaces.map(\.id) == [personal.id])
        #expect(fromPhone.isEmpty)
        #expect(phone.state.item(for: SyncRecordID(kind: .space, name: untouched.id.uuidString)) == nil)
    }

    @Test func aSpaceInUseArrivesOnTheOtherDevice() throws {
        let work = Space(name: "Work", color: "sand", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [work])
        makeGroup("Desk", "a", on: phone)
        let fromPhone = send(from: mac, to: phone).toSend
        #expect(Set(phone.store.spaces.map(\.id)) == [work.id, personal.id])
        phone.state.finishFirstSync()
        let seal = SyncSeal(keyData: key)!
        _ = mac.store.applySync(saves: fromPhone.saves.map { try! seal.open(try! seal.seal($0)) },
                                deletes: fromPhone.deletes, to: &mac.state)
        #expect(mac.store.spaces.contains { $0.id == work.id && $0.dataStoreID == work.dataStoreID })
        #expect(mac.group(named: "Desk")?.spaceID == work.id)
    }

    @Test func afterTheFirstSyncSpacesNeverJoin() {
        let (mac, phone) = devices()
        let macWork = mac.store.addSpace(name: "Work", color: "sand")
        let phoneWork = phone.store.addSpace(name: "Work", color: "sage")
        send(from: mac, to: phone)
        #expect(phone.store.spaces.count == 3)
        #expect(Set(phone.store.spaces.map(\.id)) == [personal.id, macWork.id, phoneWork.id])
    }

    // MARK: - Groups

    @Test func aGroupMadeOnOneDeviceAppearsOnTheOther() throws {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", "b", "c", on: mac)
        send(from: mac, to: phone)
        let group = try #require(phone.group(named: "Trip"))
        #expect(phone.hosts(in: group) == ["a", "b", "c"])
        #expect(phone.store.tabListItems.count == 1)
        // Nothing comes back: it arrived, it wasn't edited there.
        #expect(phone.store.takeSyncChanges(into: &phone.state).isEmpty)
    }

    @Test func renamingOnThePhoneRenamesOnTheMac() throws {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", on: mac)
        send(from: mac, to: phone)
        phone.store.rename(try #require(phone.group(named: "Trip")), to: "Japan")
        send(from: phone, to: mac)
        #expect(mac.group(named: "Japan") != nil)
        #expect(mac.store.groups.count == 1)
    }

    @Test func theLatestRenameWins() throws {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", on: mac)
        send(from: mac, to: phone)
        mac.store.rename(try #require(mac.group(named: "Trip")), to: "Mac's")
        _ = mac.store.takeSyncChanges(into: &mac.state) // stamped first
        phone.store.rename(try #require(phone.group(named: "Trip")), to: "Phone's")
        let phoneChanges = send(from: mac, to: phone).toSend
        // The mac's change came in after the phone's later rename: the phone's stays.
        #expect(phone.group(named: "Phone's") != nil)
        let seal = SyncSeal(keyData: key)!
        _ = mac.store.applySync(saves: phoneChanges.saves.map { try! seal.open(try! seal.seal($0)) },
                                deletes: phoneChanges.deletes, to: &mac.state)
        #expect(mac.group(named: "Phone's") != nil)
    }

    @Test func foldingAndPlaceStayOnEachDevice() throws {
        let (mac, phone) = devices()
        let trip = makeGroup("Trip", "a", on: mac)
        makeGroup("Home", "b", on: mac)
        send(from: mac, to: phone)
        mac.store.setFolded(trip, true)
        mac.store.move(trip, to: 1)
        #expect(mac.store.takeSyncChanges(into: &mac.state).isEmpty)
    }

    @Test func looseTabsAndBasecampNeverSync() {
        let (mac, phone) = devices()
        let tab = mac.store.openTab(url("a"))
        _ = mac.store.addToBasecamp(mac.store.openTab(url("b")))
        _ = tab
        #expect(mac.store.takeSyncChanges(into: &mac.state).isEmpty)
        #expect(phone.store.tabs.isEmpty)
    }

    @Test func aGroupALinkMadeSyncsOnlyOnceKept() throws {
        let (mac, phone) = devices()
        let opener = mac.store.openTab(url("a"))
        mac.store.add(FirnCore.Tab(spaceID: personal.id, url: url("b"), lastActiveAt: clock.time), below: opener, inBackground: true)
        let group = try #require(mac.store.groups.first)
        #expect(group.tidies)
        #expect(mac.store.takeSyncChanges(into: &mac.state).isEmpty)
        mac.store.rename(group, to: "Kept")
        send(from: mac, to: phone)
        #expect(phone.hosts(in: try #require(phone.group(named: "Kept"))) == ["a", "b"])
    }

    @Test func theOrderInsideAGroupSyncs() throws {
        let (mac, phone) = devices()
        let group = makeGroup("Trip", "a", "b", "c", on: mac)
        send(from: mac, to: phone)
        let c = try #require(mac.store.tabs.first { $0.url?.host()?.replacingOccurrences(of: ".example", with: "") == "c" })
        mac.store.move(c, into: group, at: 0)
        send(from: mac, to: phone)
        #expect(phone.hosts(in: try #require(phone.group(named: "Trip"))) == ["c", "a", "b"])
    }

    @Test func ungroupingLeavesTheTabsLooseEverywhere() throws {
        let (mac, phone) = devices()
        let group = makeGroup("Trip", "a", "b", on: mac)
        send(from: mac, to: phone)
        mac.store.ungroup(group)
        send(from: mac, to: phone)
        #expect(phone.store.groups.isEmpty)
        #expect(phone.store.looseTabs.map { $0.url?.host()?.replacingOccurrences(of: ".example", with: "") } == ["a", "b"])
        // The mac tidies up the records; the phone keeps its loose tabs.
        send(from: mac, to: phone)
        #expect(phone.store.looseTabs.count == 2)
        #expect(mac.state.tabs.isEmpty && phone.state.tabs.isEmpty)
    }

    @Test func ungroupingWorksWhicheverWordArrivesFirst() throws {
        let (mac, phone) = devices()
        let group = makeGroup("Trip", "a", "b", on: mac)
        send(from: mac, to: phone)
        mac.store.ungroup(group)
        send(from: mac, to: phone, deletesFirst: true)
        #expect(phone.store.looseTabs.count == 2)
        send(from: mac, to: phone)
        #expect(phone.store.looseTabs.count == 2)
    }

    @Test func closingAGroupClosesItsTabsEverywhere() throws {
        for deletesFirst in [false, true] {
            let (mac, phone) = devices()
            let group = makeGroup("Trip", "a", "b", on: mac)
            send(from: mac, to: phone)
            mac.store.close(group)
            send(from: mac, to: phone, deletesFirst: deletesFirst)
            #expect(phone.store.tabs.isEmpty)
            #expect(phone.store.groups.isEmpty)
        }
    }

    @Test func aGroupDeletedFirstLeavesTabsUntilTheirWordComes() throws {
        let (mac, phone) = devices()
        let group = makeGroup("Trip", "a", "b", on: mac)
        send(from: mac, to: phone)
        mac.store.close(group)
        let changes = mac.store.takeSyncChanges(into: &mac.state)
        let groupDelete = changes.deletes.filter { $0.kind == .group }
        _ = phone.store.applySync(saves: [], deletes: groupDelete, to: &phone.state)
        // Loose for now, and the phone doesn't announce anything about them.
        #expect(phone.store.looseTabs.count == 2)
        #expect(phone.store.takeSyncChanges(into: &phone.state).isEmpty)
        _ = phone.store.applySync(saves: [], deletes: changes.deletes, to: &phone.state)
        #expect(phone.store.tabs.isEmpty)
    }

    @Test func closingAGroupedTabClosesItEverywhere() throws {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", "b", on: mac)
        send(from: mac, to: phone)
        mac.store.close(try #require(mac.store.tabs.first { $0.url?.host()?.replacingOccurrences(of: ".example", with: "") == "a" }))
        send(from: mac, to: phone)
        #expect(phone.hosts(in: try #require(phone.group(named: "Trip"))) == ["b"])
    }

    @Test func aTabThatArrivesBeforeItsGroupWaits() throws {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", on: mac)
        let changes = mac.store.takeSyncChanges(into: &mac.state)
        let tabs = changes.saves.filter { if case .tab = $0 { true } else { false } }
        let groups = changes.saves.filter { if case .group = $0 { true } else { false } }
        let first = phone.store.applySync(saves: tabs, deletes: [], to: &phone.state)
        #expect(first.waiting == tabs)
        #expect(phone.store.tabs.isEmpty)
        _ = phone.store.applySync(saves: groups + first.waiting, deletes: [], to: &phone.state)
        #expect(phone.hosts(in: try #require(phone.group(named: "Trip"))) == ["a"])
    }

    @Test func aPageSomeoneIsLookingAtIsNeverPulledAway() throws {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", on: mac)
        send(from: mac, to: phone)
        let onPhone = try #require(phone.store.tabs.first)
        phone.store.select(onPhone)
        _ = phone.store.takeSyncChanges(into: &phone.state)
        let onMac = try #require(mac.store.tabs.first)
        onMac.page?.load(url("elsewhere"))
        send(from: mac, to: phone)
        #expect(onPhone.url?.host()?.replacingOccurrences(of: ".example", with: "") == "a")
        // And the phone doesn't send its own address back.
        #expect(phone.store.takeSyncChanges(into: &phone.state).isEmpty)
        // A tab not on screen follows.
        phone.store.select(phone.store.openTab(url("z")))
        onMac.page?.load(url("further"))
        send(from: mac, to: phone)
        #expect(onPhone.url?.host()?.replacingOccurrences(of: ".example", with: "") == "further")
    }

    @Test func onlyWebAddressesArrive() throws {
        let (mac, phone) = devices()
        let group = makeGroup("Trip", "a", on: mac)
        send(from: mac, to: phone)
        let bad = SyncedTab(id: UUID(), spaceID: personal.id, groupID: group.id,
                            url: URL(string: "javascript:alert(1)")!, title: "x", order: 1, changedAt: clock.tick())
        _ = phone.store.applySync(saves: [.tab(bad)], deletes: [], to: &phone.state)
        #expect(phone.store.tabs.count == 1)
    }

    // MARK: - Spaces

    @Test func aSpaceMadeOnTheMacAppearsOnThePhoneStillSeparate() throws {
        let (mac, phone) = devices()
        let work = mac.store.addSpace(name: "Work", color: "sage")
        send(from: mac, to: phone)
        let arrived = try #require(phone.store.spaces.first { $0.id == work.id })
        #expect(arrived.name == "Work" && arrived.color == "sage")
        #expect(arrived.dataStoreID == work.dataStoreID)
        #expect(arrived.dataStoreID != personal.dataStoreID)
        #expect(phone.store.spaces.map(\.name) == ["Personal", "Work"])
        // Arriving doesn't switch spaces on the phone.
        #expect(phone.store.activeSpaceID == personal.id)
    }

    @Test func everythingCanBeSentAgainByICloudsIDs() throws {
        let phonePersonal = Space(name: "Personal", color: "sand", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [phonePersonal])
        let work = mac.store.addSpace(name: "Work", color: "sage")
        send(from: mac, to: phone)
        phone.state.finishFirstSync()
        // The phone's own Personal joined the Mac's: it goes by iCloud's id.
        let ids = Set(phone.state.recordIDs(of: [.space]))
        #expect(ids == Set([personal.id, work.id].map { SyncRecordID(kind: .space, name: $0.uuidString) }))
        #expect(phone.state.recordIDs(of: [.group, .tab]).isEmpty)
    }

    @Test func aSharedSpaceStillShares() throws {
        let (mac, phone) = devices()
        let shared = mac.store.addSpace(name: "Also Personal", color: "sand", sharingWith: personal)
        send(from: mac, to: phone)
        #expect(phone.store.spaces.first { $0.id == shared.id }?.dataStoreID == personal.dataStoreID)
    }

    @Test func aStrangeColorFallsBack() {
        let (_, phone) = devices()
        let odd = SyncedSpace(id: UUID(), name: "  Odd\n", color: "<script>", order: 5,
                              dataStoreID: UUID(), changedAt: clock.tick())
        _ = phone.store.applySync(saves: [.space(odd)], deletes: [], to: &phone.state)
        let arrived = phone.store.spaces.first { $0.id == odd.id }
        #expect(arrived?.color == "glacier")
        #expect(arrived?.name == "Odd")
    }

    @Test func deletingASpaceDeletesItEverywhere() throws {
        let (mac, phone) = devices()
        let work = mac.store.addSpace(name: "Work", color: "sage")
        makeGroup("Trip", "a", on: mac)
        send(from: mac, to: phone)
        #expect(phone.store.tabs.count == 1)
        mac.store.deleteSpace(work)
        send(from: mac, to: phone)
        #expect(phone.store.spaces.map(\.id) == [personal.id])
        #expect(phone.store.tabs.isEmpty)
        #expect(phone.erased.ids == [work.dataStoreID])
    }

    @Test func stoppingSharingOnTheMacMovesThePhonesSpaceToo() throws {
        let (mac, phone) = devices()
        let shared = mac.store.addSpace(name: "Also", color: "sand", sharingWith: personal)
        send(from: mac, to: phone)
        mac.store.stopSharing(shared)
        send(from: mac, to: phone)
        let moved = try #require(phone.store.spaces.first { $0.id == shared.id })
        #expect(moved.dataStoreID != personal.dataStoreID)
        #expect(moved.dataStoreID == mac.store.spaces.first { $0.id == shared.id }?.dataStoreID)
        // Personal still uses the old one: nothing erased.
        #expect(phone.erased.ids.isEmpty)
    }

    @Test func theStateSurvivesBeingSaved() throws {
        let (mac, _) = devices()
        makeGroup("Trip", "a", on: mac)
        _ = mac.store.takeSyncChanges(into: &mac.state)
        let data = try JSONEncoder().encode(mac.state)
        let back = try JSONDecoder().decode(SyncState.self, from: data)
        #expect(back == mac.state)
        #expect(back.item(for: SyncRecordID(kind: .space, name: personal.id.uuidString)) != nil)
    }
}

@Suite struct SyncFileTests {
    @Test func savedSyncComesBackExactly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SyncFile(url: folder.appending(path: "sync.json"))
        #expect(file.load() == SyncSaved())

        var saved = SyncSaved()
        saved.engineState = Data([1, 2, 3])
        // A fraction of a second must survive: latest change wins by it.
        saved.waiting = [.group(SyncedGroup(id: UUID(), spaceID: UUID(), name: "Trip",
                                            changedAt: Date(timeIntervalSinceReferenceDate: 1000.25)))]
        try file.save(saved)
        #expect(file.load() == saved)

        try Data("not json".utf8).write(to: file.url)
        #expect(file.load() == SyncSaved())
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
    }
}
