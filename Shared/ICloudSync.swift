import CloudKit
import FirnCore
import os
#if os(macOS)
import AppKit
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
    /// What syncs so far: spaces, and groups with their tabs (step 4; a
    /// device that synced only spaces catches up: see `begin`). History
    /// joins in step 6.
    static let kinds: Set<SyncKind> = [.space, .group, .tab]

    /// What turning sync on does, in plain words, under the switch on the
    /// Mac and the iPhone (and the welcome's step, later). Keep it literally
    /// true: when history (step 6), "On your Mac" (step 5), or passwords
    /// (step 8) start syncing, change these words in the same commit.
    static func whatSyncs(on device: String) -> [String] {
        [
            "Your spaces, and your groups with the tabs in them, stay the same on your Mac, iPhone, and iPad. Make, rename, or close one anywhere, and the others follow.",
            "Tabs outside a group, Basecamp, history, and settings stay on this \(device). So do sign-ins and passwords: a separate space starts signed out on your other devices.",
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
    /// A record came sealed with a key this device doesn't have.
    private var otherKeySeen = false

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

    /// The switch, turned off; also when the person signs out of iCloud or
    /// into another account, or deletes Firn's data in iCloud's settings.
    /// What's on this device stays; only what sync kept goes.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        if let engine { Task { await engine.cancelOperations() } }
        engine = nil
        seal = nil
        firstFetch?.cancel()
        firstFetch = nil
        held = SyncChanges()
        saved = SyncSaved()
        file.remove()
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
        if saved.state.firstSyncDone { takeChanges() } else { fetchFirst() }
        save()
    }

    // MARK: - This device's changes

    /// Takes what changed here since the last look (after each session save).
    func takeChanges() {
        guard engine != nil else { return }
        send(store.takeSyncChanges(into: &saved.state))
        save()
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
        guard let engine else { return }
        saved.state.finishFirstSync()
        var changes = held
        held = SyncChanges()
        let taken = store.takeSyncChanges(into: &saved.state)
        changes.saves = (changes.saves + taken.saves).compactMap { saved.state.item(for: $0.id) }
        changes.deletes += taken.deletes
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        queue(changes)
        save()
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
        apply(saves: saves, deletes: deletes)
    }

    private func apply(saves: [SyncItem], deletes: [SyncRecordID]) {
        guard !saves.isEmpty || !deletes.isEmpty else { return save() }
        let applied = store.applySync(saves: saved.waiting + saves, deletes: deletes, to: &saved.state)
        saved.waiting = applied.waiting
        send(applied.toSend)
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
        guard let id = Self.syncID(recordID), Self.kinds.contains(id.kind), let seal,
              let item = saved.state.item(for: id), let sealed = try? seal.seal(item) else { return nil }
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
                turnOff()
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
                    turnOff()
                    return
                }
            }
        case let .fetchedRecordZoneChanges(changes):
            received(changes)
        case let .sentRecordZoneChanges(sent):
            self.sent(sent)
        case .didFetchChanges:
            if otherKeySeen { checkKey() }
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
