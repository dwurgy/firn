import CloudKit
import FirnCore
import os
#if os(macOS)
import AppKit
import SystemConfiguration
#else
import UIKit
#endif

/// iCloud sync's engine, in both apps (docs/SYNC-PLAN.md, step 3): Apple's
/// `CKSyncEngine` in Firn's own zone of the person's private iCloud database.
/// Every record holds one field, its fields sealed on this device
/// (`SyncSeal`) with the key in iCloud Keychain (`SyncKeychain`); CloudKit
/// sees only a record type, a random id, and sealed bytes.
///
/// Off, and sending nothing, until "Sync with iCloud" is on. The first time,
/// it fetches first and sends after, so a space of the same name joins
/// before anything of this device's goes up. After that, this device's
/// changes are taken whenever the session saves (`takeChanges`).
///
/// FirnCore does the deciding (`BrowserStore.takeSyncChanges`/`applySync`);
/// this only carries sealed bytes to and from iCloud.
@MainActor
final class ICloudSync {
    /// The "Sync with iCloud" switch (Settings, step 3, part 3).
    static let enabledKey = "syncWithICloud"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    /// What syncs so far: spaces, each device's open tabs for "On your
    /// Mac" (step 5), and tabs sent on purpose (step 6). Groups and tabs synced briefly (step 4), then stayed
    /// on each device (David, 2026-11-16): a device that sent them takes
    /// them out of iCloud again (see `begin`). History joins in step 7.
    static let kinds: Set<SyncKind> = [.space, .device, .sentTab]

    /// What turning sync on does, in plain words, under the switch on the
    /// Mac and the iPhone (and the welcome's step, later). Keep it literally
    /// true: when "On your Mac" (step 5), Send to (step 6), history (step 7),
    /// Basecamp between Macs (step 8), or passwords (step 10) start syncing,
    /// change these words in the same commit.
    static func whatSyncs(on device: String) -> [String] {
        [
            "Your spaces stay the same on your Mac, iPhone, and iPad. Make, rename, or delete one anywhere, and the others follow.",
            "Your open tabs' addresses and titles can be found from your other devices' command bars, in the same space. You can also send a tab to another of your devices, where it opens.",
            "Tabs, groups, Basecamp, history, and settings stay on this \(device). So do sign-ins and passwords: a separate space starts signed out on your other devices.",
            "Everything is encrypted on this \(device) before it goes to your iCloud, so only your devices can read it.",
        ]
    }

    private static let containerID = "iCloud.com.firnbrowser.firn"
    private static let zoneID = CKRecordZone.ID(zoneName: "Firn", ownerName: CKCurrentUserDefaultName)
    /// The one field every record has: its sealed bytes. Also in CloudKit's
    /// own encrypted fields, so people with Advanced Data Protection get both.
    private static let field = "sealed"
    private nonisolated static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "sync")

    private let store: BrowserStore
    private let file: SyncFile
    private var saved = SyncSaved()
    private var engine: CKSyncEngine?
    private var seal: SyncSeal?
    private var starting = false
    /// The first sync: this device's changes, held until its fetch is done.
    private var held = SyncChanges()
    private var firstFetch: Task<Void, Never>?
    private var firstFetchFailedAt: Date?
    /// A record came sealed with a key this device doesn't have.
    private var otherKeySeen = false
    /// This device's open tabs as last sent (step 5), and when.
    private var deviceSent: (tabs: [SyncedDevice.OpenTab], at: Date)?
    /// A send waiting out the 30 seconds since the last one.
    private var deviceSendLater: Task<Void, Never>?
    private var frontObservers: [any NSObjectProtocol] = []
    /// When this device last fetched on coming to the front.
    private var frontFetchedAt: Date?
    /// The other devices a tab can be sent to, as last told to the app.
    private var targets: [SendTarget] = []

    /// Tabs sent here just opened (step 6): the app shows its note.
    var onArrival: ((SentTabsArrival) -> Void)?
    /// The devices a tab can be sent to changed (none while sync is off).
    var onTargetsChange: (([SendTarget]) -> Void)?

    init(store: BrowserStore, file: SyncFile = .standard) {
        self.store = store
        self.file = file
    }

    // MARK: - On and off

    /// Starts syncing if the switch is on (at launch).
    func start() {
        guard Self.isOn, engine == nil, !starting else { return }
        starting = true
        Task {
            defer { starting = false }
            guard let seal = await Self.readKey(makingOne: true), Self.isOn else { return }
            saved = file.load()
            begin(with: seal)
        }
    }

    /// Whether this device can sync: signed in to iCloud, and iCloud allowed
    /// (Screen Time or a managed device can forbid it). Settings asks before
    /// offering the switch, and again when the account changes.
    enum Availability { case available, signedOut, unavailable }

    static func availability() async -> Availability {
        // Can't tell yet (offline at launch, say): let the switch be tried;
        // the engine waits for the account by itself.
        guard let status = try? await CKContainer(identifier: containerID).accountStatus() else { return .available }
        switch status {
        case .available, .couldNotDetermine, .temporarilyUnavailable: return .available
        case .noAccount: return .signedOut
        case .restricted: return .unavailable
        @unknown default: return .available
        }
    }

    /// The switch, turned on (step 3, part 3).
    func turnOn() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        start()
    }

    /// The switch, turned off: this device's open tabs leave iCloud (so the
    /// other devices stop offering them), then sync stops.
    func turnOff() {
        if engine != nil, saved.systemFields[Self.recordID(saved.state.deviceRecordID).recordName] != nil {
            let recordID = Self.recordID(saved.state.deviceRecordID)
            let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
            Task.detached(priority: .utility) {
                do {
                    try await database.deleteRecord(withID: recordID)
                } catch {
                    // Offline, say: the other devices stop showing it after 14 days.
                    Self.log.error("This device's tabs couldn't be taken out of iCloud")
                }
            }
        }
        stop()
    }

    /// Sync stops: from the switch, and when the person signs out of iCloud
    /// or into another account, or deletes Firn's data in iCloud's settings.
    /// What's on this device stays; only what sync kept goes.
    private func stop() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        if let engine { Task { await engine.cancelOperations() } }
        engine = nil
        deviceSendLater?.cancel()
        deviceSendLater = nil
        deviceSent = nil
        for observer in frontObservers { NotificationCenter.default.removeObserver(observer) }
        frontObservers = []
        frontFetchedAt = nil
        seal = nil
        firstFetch?.cancel()
        firstFetch = nil
        held = SyncChanges()
        saved = SyncSaved()
        file.remove()
        publishTargets()
    }

    private func begin(with seal: SyncSeal) {
        self.seal = seal
        // Sealed with another key last time (iCloud Keychain kept another
        // device's), or a kind that starts syncing now: everything this
        // device has goes again, and everything is fetched again (records
        // that couldn't be opened, or kinds that were passed over, before).
        let keyChanged = saved.keyID != nil && saved.keyID != seal.keyID
        let sendAgain = saved.state.firstSyncDone && (keyChanged || !saved.kinds.isSuperset(of: Self.kinds))
        if keyChanged || sendAgain { saved.engineState = nil }
        let dropped = saved.kinds.subtracting(Self.kinds)
        saved.keyID = seal.keyID
        saved.kinds = Self.kinds

        let serialization = saved.engineState.flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        let configuration = CKSyncEngine.Configuration(
            database: CKContainer(identifier: Self.containerID).privateCloudDatabase,
            stateSerialization: serialization, delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        Self.registerForPushes()

        if sendAgain {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            queue(SyncChanges(saves: [], deletes: []), andAgain: saved.state.recordIDs(of: Self.kinds))
        }
        if !dropped.isEmpty { takeOut(dropped, from: engine) }
        saved.state.dropExpiredSends(at: .now)
        watchFront()
        if saved.state.firstSyncDone { takeChanges() } else { fetchFirst() }
        save()
    }

    /// Kinds that no longer sync (groups and tabs, David, 2026-11-16): the
    /// records this device put in iCloud go, so nothing lingers there.
    private func takeOut(_ kinds: Set<SyncKind>, from engine: CKSyncEngine) {
        let names = saved.systemFields.keys.filter { name in
            Self.syncID(CKRecord.ID(recordName: name, zoneID: Self.zoneID)).map { kinds.contains($0.kind) } ?? false
        }
        for name in names { saved.systemFields[name] = nil }
        engine.state.add(pendingRecordZoneChanges: names.map {
            .deleteRecord(CKRecord.ID(recordName: $0, zoneID: Self.zoneID))
        })
    }

    // MARK: - This device's changes

    /// Takes what changed here since the last look (after each session save).
    func takeChanges() {
        guard engine != nil else { return }
        send(store.takeSyncChanges(into: &saved.state))
        sendDevice()
        save()
    }

    // MARK: - This device's open tabs ("On your Mac", step 5)

    /// Sends this device's open tabs when the pages open changed, at most
    /// every 30 seconds; a title change alone waits. Leaving the front sends
    /// whatever changed, and at least once a day, so an idle device doesn't
    /// go stale on the others. Only after the first sync, so a quit during
    /// it can't leave a record under an id that's then forgotten.
    private func sendDevice(leavingFront: Bool = false) {
        guard let engine, saved.state.firstSyncDone else { return }
        let tabs = currentDevice().tabs
        let pages = { (tabs: [SyncedDevice.OpenTab]) in Set(tabs.map { "\($0.spaceID) \($0.url.absoluteString)" }) }
        let changed: Bool
        if let sent = deviceSent {
            changed = leavingFront
                ? sent.tabs != tabs || Date.now.timeIntervalSince(sent.at) > 24 * 60 * 60
                : pages(sent.tabs) != pages(tabs)
        } else {
            changed = true
        }
        guard changed else { return }
        if !leavingFront, let sent = deviceSent, Date.now.timeIntervalSince(sent.at) < Self.deviceSendGap {
            guard deviceSendLater == nil else { return }
            let wait = Self.deviceSendGap - Date.now.timeIntervalSince(sent.at)
            deviceSendLater = Task {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                deviceSendLater = nil
                sendDevice()
            }
            return
        }
        deviceSendLater?.cancel()
        deviceSendLater = nil
        deviceSent = (tabs, .now)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(saved.state.deviceRecordID))])
        if leavingFront { Task { try? await engine.sendChanges() } }
    }

    private static let deviceSendGap: TimeInterval = 30

    /// This device's record as it is now (built again as it's sent).
    private func currentDevice() -> SyncedDevice {
        store.deviceRecord(kind: Self.deviceKind, name: Self.deviceName, state: saved.state)
    }

    /// Leaving the front sends this device's tabs; coming to the front
    /// looks for sent tabs and opens any waiting.
    private func watchFront() {
        guard frontObservers.isEmpty else { return }
        #if os(macOS)
        let leaving = NSApplication.didResignActiveNotification
        let coming = NSApplication.didBecomeActiveNotification
        #else
        let leaving = UIApplication.didEnterBackgroundNotification
        let coming = UIApplication.didBecomeActiveNotification
        #endif
        let center = NotificationCenter.default
        frontObservers = [
            center.addObserver(forName: leaving, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sendDevice(leavingFront: true) }
            },
            center.addObserver(forName: coming, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cameToFront() }
            },
        ]
    }

    private static var isInFront: Bool {
        #if os(macOS)
        NSApp.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    // MARK: - Sent tabs (Send to My Mac, step 6)

    /// The other devices a tab can be sent to now.
    private func currentTargets() -> [SendTarget] {
        guard engine != nil, saved.state.firstSyncDone else { return [] }
        return saved.state.sendTargets(at: .now)
    }

    /// Tells the app when the devices to send to change, for its menus.
    private func publishTargets() {
        let now = currentTargets()
        guard now != targets else { return }
        targets = now
        onTargetsChange?(now)
    }

    /// Sends a tab to another device: held in the sync file until iCloud
    /// has it, and sent at once (it's a deliberate act, not a background one).
    /// Whether it's on its way (the app says so).
    @discardableResult
    func send(_ tab: FirnCore.Tab, to target: SendTarget) -> Bool {
        guard let engine, saved.state.firstSyncDone,
              let sent = store.sentTab(tab, to: target, from: Self.deviceKind, state: saved.state) else { return false }
        saved.state.queueSend(sent)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.recordID(sent.recordID))])
        save()
        Task { try? await engine.sendChanges() }
        return true
    }

    /// Back in front: anything waiting opens, then a quick look for more
    /// (pushes can be missed), at most once a minute.
    private func cameToFront() {
        publishTargets()
        openArrivals()
        guard let engine, saved.state.firstSyncDone,
              frontFetchedAt.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true else { return }
        frontFetchedAt = .now
        Task { try? await engine.fetchChanges() }
    }

    /// Opens the tabs sent here, only while Firn is in front (else the next
    /// time it is), and deletes them from iCloud so they never open twice.
    private func openArrivals() {
        guard engine != nil, saved.state.firstSyncDone, !saved.state.waitingSentTabs.isEmpty,
              Self.isInFront else { return }
        let arrival = store.openSentTabs(&saved.state)
        queue(SyncChanges(saves: [], deletes: arrival.deletes))
        save()
        if !arrival.tabIDs.isEmpty { onArrival?(arrival) }
    }

    private static var deviceKind: SyncedDevice.Kind {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    /// A Mac's own name ("David's Mac mini"), shown on the other devices only
    /// when there are two Macs. An iPhone or iPad can't read theirs.
    private static var deviceName: String? {
        #if os(macOS)
        SCDynamicStoreCopyComputerName(nil, nil) as String?
        #else
        nil
        #endif
    }

    /// The other devices' tabs open in the space on screen, for the command
    /// bar. None while sync is off.
    func otherDeviceTabs() -> [DeviceTab] {
        guard engine != nil, saved.state.firstSyncDone else { return [] }
        return store.otherDeviceTabs(in: saved.state, thisDevice: Self.deviceKind)
    }

    /// Sends now, or holds until the first sync's fetch is done.
    private func send(_ changes: SyncChanges) {
        if saved.state.firstSyncDone {
            queue(changes)
        } else {
            held.saves += changes.saves
            held.deletes += changes.deletes
            fetchFirst()
        }
    }

    private func queue(_ changes: SyncChanges, andAgain again: [SyncRecordID] = []) {
        guard let engine else { return }
        let saves = (changes.saves.map(\.id) + again).filter { Self.kinds.contains($0.kind) }
        let deletes = changes.deletes.filter { Self.kinds.contains($0.kind) }
        let pending: [CKSyncEngine.PendingRecordZoneChange] =
            saves.map { .saveRecord(Self.recordID($0)) } + deletes.map { .deleteRecord(Self.recordID($0)) }
        guard !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    // MARK: - The first sync

    private func fetchFirst() {
        guard firstFetch == nil, let engine, !saved.state.firstSyncDone else { return }
        firstFetch = Task {
            do {
                try await engine.fetchChanges()
            } catch {
                // Offline, most likely: tried again with the next change.
                Self.log.error("The first sync's fetch failed")
                firstFetchFailedAt = .now
                firstFetch = nil
                return
            }
            firstFetch = nil
            guard engine === self.engine else { return }
            finishFirstSync()
        }
    }

    /// Everything from iCloud is here: from now on spaces arrive as new,
    /// and this device's changes go up, in today's terms (a space that
    /// joined goes by iCloud's id; one that gave way is gone).
    private func finishFirstSync() {
        guard let engine, !saved.state.firstSyncDone else { return }
        store.finishFirstSync(&saved.state)
        var changes = held
        held = SyncChanges()
        let taken = store.takeSyncChanges(into: &saved.state)
        changes.saves = (changes.saves + taken.saves).compactMap { saved.state.item(for: $0.id) }
        changes.deletes += taken.deletes
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        queue(changes)
        sendDevice()
        save()
        publishTargets()
        openArrivals()
    }

    // MARK: - Other devices' changes

    private func received(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var saves: [SyncItem] = []
        var deletes: [SyncRecordID] = []
        for modification in changes.modifications {
            let record = modification.record
            guard let id = Self.syncID(record.recordID), id.kind.rawValue == record.recordType else { continue }
            saved.systemFields[record.recordID.recordName] = Self.systemFields(of: record)
            guard Self.kinds.contains(id.kind), let item = open(record, as: id) else { continue }
            saves.append(item)
        }
        for deletion in changes.deletions {
            guard let id = Self.syncID(deletion.recordID) else { continue }
            saved.systemFields[deletion.recordID.recordName] = nil
            if Self.kinds.contains(id.kind) { deletes.append(id) }
        }
        saved.state.forgetDevices(sentBefore: Date.now.addingTimeInterval(-SyncedDevice.staleAfter))
        apply(saves: saves, deletes: deletes)
        publishTargets()
        openArrivals()
    }

    private func apply(saves: [SyncItem], deletes: [SyncRecordID]) {
        guard !saves.isEmpty || !deletes.isEmpty else { return save() }
        send(store.applySync(saves: saves, deletes: deletes, to: &saved.state))
        save()
    }

    /// A record's item, or nil if it can't be opened. Everything opened is
    /// checked again as it's applied (FirnCore).
    private func open(_ record: CKRecord, as id: SyncRecordID) -> SyncItem? {
        guard let seal, let sealed = record.encryptedValues[Self.field] as? Data else { return nil }
        do {
            return try seal.open(SyncRecord(id: id, sealed: sealed))
        } catch SyncSeal.Failure.otherKey {
            otherKeySeen = true
        } catch {
            Self.log.error("A synced record couldn't be opened")
        }
        return nil
    }

    // MARK: - What went up

    private func sent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in sent.savedRecords {
            // A tab this device sent is iCloud's now, kept there until the
            // other device opens it: no need to remember it here.
            if let id = Self.syncID(record.recordID), id.kind == .sentTab {
                saved.state.sendWentUp(id)
                continue
            }
            saved.systemFields[record.recordID.recordName] = Self.systemFields(of: record)
        }
        var again: [SyncRecordID] = []
        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            guard let id = Self.syncID(recordID) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device saved it first: theirs comes in (latest
                // change wins), and ours goes again over it only if ours
                // is the newer.
                guard let server = failure.error.serverRecord else { continue }
                saved.systemFields[recordID.recordName] = Self.systemFields(of: server)
                if let theirs = open(server, as: id) {
                    apply(saves: [theirs], deletes: [])
                    if saved.state.item(for: id) != theirs { again.append(id) }
                } else if !otherKeySeen {
                    again.append(id)
                }
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                again.append(id)
            case .unknownItem:
                // Gone from iCloud since this device last saw it: made anew.
                saved.systemFields[recordID.recordName] = nil
                again.append(id)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break // The engine tries these again by itself.
            default:
                Self.log.error("A synced record couldn't be saved: \(failure.error.code.rawValue)")
            }
        }
        for recordID in sent.deletedRecordIDs { saved.systemFields[recordID.recordName] = nil }
        queue(SyncChanges(), andAgain: again)
        save()
    }

    // MARK: - The key

    /// iCloud Keychain may have kept another device's key: read it again,
    /// and if it changed, seal and send everything again with it.
    private func checkKey() {
        otherKeySeen = false
        Task {
            guard let fresh = await Self.readKey(makingOne: false), let current = seal,
                  fresh.keyID != current.keyID, let engine else { return }
            Self.log.info("The sync key changed; sending everything again")
            await engine.cancelOperations()
            guard engine === self.engine else { return }
            self.engine = nil
            firstFetch?.cancel()
            firstFetch = nil
            begin(with: fresh)
        }
    }

    /// The key in iCloud Keychain, read off the main thread.
    private static func readKey(makingOne: Bool) async -> SyncSeal? {
        let data = await Task.detached(priority: .utility) { () -> Data? in
            do {
                return makingOne ? try SyncKeychain.key() : try SyncKeychain.read()
            } catch {
                let status = (error as? SyncKeychain.Failure)?.status ?? 0
                log.error("The sync key couldn't be read: \(status)")
                return nil
            }
        }.value
        return data.flatMap(SyncSeal.init(keyData:))
    }

    // MARK: - Saving

    /// Only once the first sync is done: if Firn quits during it, the next
    /// launch simply starts it again.
    private func save() {
        guard engine != nil, saved.state.firstSyncDone else { return }
        do {
            try file.save(saved)
        } catch {
            Self.log.error("The sync file couldn't be saved")
        }
    }

    // MARK: - Records

    /// A record's name in iCloud: its kind and id (`Space.<uuid>`), so its
    /// kind is known from a pending change alone.
    private static func recordID(_ id: SyncRecordID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(id.kind.rawValue).\(id.name)", zoneID: zoneID)
    }

    private static func syncID(_ recordID: CKRecord.ID) -> SyncRecordID? {
        guard recordID.zoneID.zoneName == zoneID.zoneName else { return nil }
        let parts = recordID.recordName.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let kind = SyncKind(rawValue: String(parts[0])) else { return nil }
        return SyncRecordID(kind: kind, name: String(parts[1]))
    }

    /// The record to send, sealed now from what this device knows.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let id = Self.syncID(recordID), Self.kinds.contains(id.kind), let seal else { return nil }
        // This device's open tabs, as they are now; never another device's.
        let item = id == saved.state.deviceRecordID ? .device(currentDevice()) : saved.state.item(for: id)
        guard let item, let sealed = try? seal.seal(item) else { return nil }
        let record = savedRecord(named: recordID.recordName)
            ?? CKRecord(recordType: id.kind.rawValue, recordID: recordID)
        record.encryptedValues[Self.field] = sealed.sealed
        return record
    }

    /// A record from its saved system fields (its change tag and such).
    private func savedRecord(named name: String) -> CKRecord? {
        guard let data = saved.systemFields[name],
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// Silent pushes, so other devices' changes arrive without waiting; the
    /// engine handles them itself.
    private static func registerForPushes() {
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    // MARK: - Events

    fileprivate func handle(_ event: CKSyncEngine.Event, from engine: CKSyncEngine) {
        guard engine === self.engine else { return }
        switch event {
        case let .stateUpdate(update):
            saved.engineState = try? JSONEncoder().encode(update.stateSerialization)
            save()
        case let .accountChange(change):
            switch change.changeType {
            case .signIn: break
            case .signOut, .switchAccounts:
                Self.log.info("iCloud account changed; sync turned off")
                stop()
            @unknown default: break
            }
        case let .fetchedDatabaseChanges(changes):
            for deletion in changes.deletions where deletion.zoneID.zoneName == Self.zoneID.zoneName {
                if deletion.reason == .encryptedDataReset {
                    // iCloud's own encrypted fields were reset (Advanced Data
                    // Protection's recovery): everything goes up again.
                    saved.systemFields = [:]
                    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                    queue(SyncChanges(), andAgain: saved.state.recordIDs(of: Self.kinds))
                } else {
                    // Deleted in iCloud's settings: nothing is put back.
                    Self.log.info("Firn's iCloud data was deleted; sync turned off")
                    stop()
                    return
                }
            }
        case let .fetchedRecordZoneChanges(changes):
            received(changes)
        case let .sentRecordZoneChanges(sent):
            self.sent(sent)
        case .didFetchChanges:
            if otherKeySeen { checkKey() }
            // The first fetch failed (offline at launch, say) and the engine
            // has fetched on its own since: finish the first sync now rather
            // than waiting for a change on this device.
            // At most once a minute after a failure, so it can't spin offline.
            if !saved.state.firstSyncDone,
               firstFetchFailedAt.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true {
                fetchFirst()
            }
        default:
            break
        }
    }
}

extension ICloudSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, from: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        // A record that's no longer here is left out, and the engine drops it.
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.record(for: recordID)
        }
    }
}

extension SyncedDevice.Kind {
    /// Its symbol in menus and the arrival note: an iPhone, an iPad, or a
    /// Mac laptop (both apps).
    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }
}
