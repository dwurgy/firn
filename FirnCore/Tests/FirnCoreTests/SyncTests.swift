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
        mac.store.finishFirstSync(&mac.state)
        phone.store.finishFirstSync(&phone.state)
        return (mac, phone)
    }

    /// A Mac already syncing, and a phone turning sync on with its own spaces.
    func firstSync(phoneSpaces: [Space]) -> (SyncDevice, SyncDevice) {
        let mac = SyncDevice(spaces: [personal], clock: clock)
        mac.store.finishFirstSync(&mac.state)
        let phone = SyncDevice(spaces: phoneSpaces, clock: clock)
        return (mac, phone)
    }

    /// Sends one device's changes to the other, sealed and opened on the
    /// way, and returns what the receiver had of its own to send.
    @discardableResult
    func send(from sender: SyncDevice, to receiver: SyncDevice) -> SyncChanges {
        let changes = sender.store.takeSyncChanges(into: &sender.state)
        let seal = SyncSeal(keyData: key)!
        let saves = changes.saves.map { try! seal.open(try! seal.seal($0)) }
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
        let item = SyncItem.space(SyncedSpace(id: UUID(), name: "Trip", color: "sage", order: 0,
                                              dataStoreID: UUID(), changedAt: clock.time))
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
        let record = try seal.seal(.space(SyncedSpace(id: UUID(), name: "Trip", color: "sage", order: 0,
                                                      dataStoreID: UUID(), changedAt: clock.time)))
        var moved = record
        moved.id.name = UUID().uuidString
        #expect(throws: SyncSeal.Failure.unreadable) { try seal.open(moved) }
        var retyped = record
        retyped.id.kind = .visit
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
        let fromPhone = send(from: mac, to: phone)
        // One space: the phone's own, under the Mac's name and color, its
        // data store (sign-ins, history, passwords) untouched.
        #expect(phone.store.spaces.map(\.id) == [phonePersonal.id])
        #expect(phone.space.name == "Personal" && phone.space.color == "glacier")
        #expect(phone.space.dataStoreID == phonePersonal.dataStoreID)
        #expect(phone.erased.ids.isEmpty)
        // Groups and tabs stay on each device.
        #expect(phone.group(named: "Trip") == nil)
        #expect(phone.store.tabs.contains { $0.url == url("b") && $0.spaceID == phonePersonal.id })
        // Nothing of the phone's own id goes up.
        #expect(fromPhone.saves.allSatisfy { $0.id.name != phonePersonal.id.uuidString })
        #expect(phone.state.item(for: SyncRecordID(kind: .space, name: phonePersonal.id.uuidString)) == nil)
        phone.store.finishFirstSync(&phone.state)

        // From now on each side's edits reach the other in its own terms.
        phone.store.updateSpace(phone.space, name: "Home", color: phone.space.color)
        send(from: phone, to: mac)
        #expect(mac.store.spaces.count == 1 && mac.space.name == "Home")
        #expect(mac.space.dataStoreID == personal.dataStoreID && mac.erased.ids.isEmpty)
        mac.store.updateSpace(mac.space, name: "Later", color: "sand")
        send(from: mac, to: phone)
        #expect(phone.store.spaces.map(\.id) == [phonePersonal.id] && phone.space.name == "Later")
        #expect(phone.space.dataStoreID == phonePersonal.dataStoreID && phone.erased.ids.isEmpty)
    }

    @Test func anUntouchedSpaceGivesWay() throws {
        let untouched = Space(name: "New Space", color: "glacier", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [untouched])
        let fromPhone = send(from: mac, to: phone)
        phone.store.finishFirstSync(&phone.state)
        #expect(phone.store.spaces.map(\.id) == [personal.id])
        // What was held to send is taken again once it gave way (the app's
        // `finishFirstSync`): nothing of the untouched space goes up.
        #expect(fromPhone.saves.compactMap { phone.state.item(for: $0.id) }.isEmpty)
        #expect(phone.state.item(for: SyncRecordID(kind: .space, name: untouched.id.uuidString)) == nil)
    }

    /// The first fetch can come in several batches: an untouched space
    /// still joins its match if that arrives after another space.
    @Test func anUntouchedSpaceWaitsForTheWholeFirstFetch() throws {
        let phonePersonal = Space(name: "Personal", color: "sage", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [phonePersonal])
        mac.store.addSpace(name: "Work", color: "sand")
        let changes = mac.store.takeSyncChanges(into: &mac.state)
        let seal = SyncSeal(keyData: key)!
        let opened = changes.saves.map { try! seal.open(try! seal.seal($0)) }
        let isPersonal = { (item: SyncItem) in item.id.name == personal.id.uuidString }
        _ = phone.store.applySync(saves: opened.filter { !isPersonal($0) }, deletes: [], to: &phone.state)
        _ = phone.store.applySync(saves: opened.filter(isPersonal), deletes: [], to: &phone.state)
        phone.store.finishFirstSync(&phone.state)
        #expect(phone.store.spaces.contains { $0.id == phonePersonal.id && $0.dataStoreID == phonePersonal.dataStoreID })
        #expect(phone.store.spaces.count == 2)
        #expect(phone.erased.ids.isEmpty)
    }

    @Test func aSpaceInUseArrivesOnTheOtherDevice() throws {
        let work = Space(name: "Work", color: "sand", order: 0, dataStoreID: UUID())
        let (mac, phone) = firstSync(phoneSpaces: [work])
        makeGroup("Desk", "a", on: phone)
        let fromPhone = send(from: mac, to: phone)
        #expect(Set(phone.store.spaces.map(\.id)) == [work.id, personal.id])
        phone.store.finishFirstSync(&phone.state)
        let seal = SyncSeal(keyData: key)!
        _ = mac.store.applySync(saves: fromPhone.saves.map { try! seal.open(try! seal.seal($0)) },
                                deletes: fromPhone.deletes, to: &mac.state)
        #expect(mac.store.spaces.contains { $0.id == work.id && $0.dataStoreID == work.dataStoreID })
        #expect(mac.group(named: "Desk") == nil)
    }

    @Test func afterTheFirstSyncSpacesNeverJoin() {
        let (mac, phone) = devices()
        let macWork = mac.store.addSpace(name: "Work", color: "sand")
        let phoneWork = phone.store.addSpace(name: "Work", color: "sage")
        send(from: mac, to: phone)
        #expect(phone.store.spaces.count == 3)
        #expect(Set(phone.store.spaces.map(\.id)) == [personal.id, macWork.id, phoneWork.id])
    }

    // MARK: - What stays on each device

    /// Groups, tabs, and Basecamp never sync (David, 2026-11-16).
    @Test func groupsTabsAndBasecampNeverSync() {
        let (mac, phone) = devices()
        makeGroup("Trip", "a", "b", on: mac)
        _ = mac.store.addToBasecamp(mac.store.openTab(url("c")))
        mac.store.openTab(url("d"))
        #expect(mac.store.takeSyncChanges(into: &mac.state).isEmpty)
        #expect(phone.store.tabs.isEmpty && phone.store.groups.isEmpty)
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
        phone.store.finishFirstSync(&phone.state)
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
        send(from: mac, to: phone)
        mac.store.deleteSpace(work)
        send(from: mac, to: phone)
        #expect(phone.store.spaces.map(\.id) == [personal.id])
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
        let space = SyncedSpace(id: UUID(), name: "Trip", color: "sage", order: 0, dataStoreID: UUID(),
                                changedAt: Date(timeIntervalSinceReferenceDate: 1000.25))
        saved.state.spaces[space.id] = space
        saved.kinds = [.space]
        try file.save(saved)
        #expect(file.load() == saved)

        // A file from when groups and tabs synced still opens, their parts passed over.
        var old = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        var state = try #require(old["state"] as? [String: Any])
        state["groups"] = [:] as [String: Any]
        state["tabs"] = [:] as [String: Any]
        state["announced"] = [] as [Any]
        old["state"] = state
        old["waiting"] = [] as [Any]
        old["kinds"] = ["Space", "TabGroup", "Tab"]
        try JSONSerialization.data(withJSONObject: old).write(to: file.url)
        var expected = saved
        expected.kinds = [.space, .group, .tab]
        #expect(file.load() == expected)

        try Data("not json".utf8).write(to: file.url)
        #expect(file.load() == SyncSaved())
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
    }
}
