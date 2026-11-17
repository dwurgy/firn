import Foundation

// Send to My Mac, Send to My iPhone (docs/SYNC-PLAN.md, step 6): one
// deliberate send of the tab on screen to another of your devices, where it
// opens where new tabs go, without being switched to. Each send is its own
// sealed record, deleted from iCloud once it's opened; unopened ones expire.

/// A tab sent to one device, as its `SentTab` record holds it. Only the
/// address and title travel: never the page's state, sign-ins, or history.
public struct SentTab: Codable, Equatable, Sendable {
    /// A random id: its record's name.
    public var id: String
    /// The device it's for (`SyncState.deviceID`).
    public var toDeviceID: String
    /// The kind of device it came from, for the note ("From iPhone").
    public var from: SyncedDevice.Kind
    public var url: URL
    public var title: String
    /// Its space, in iCloud's terms.
    public var spaceID: UUID
    public var sentAt: Date

    /// Unopened sends are deleted after this long, by any device.
    public static let expiresAfter: TimeInterval = 7 * 24 * 60 * 60

    public var recordID: SyncRecordID { SyncRecordID(kind: .sentTab, name: id) }

    /// The same send as it should be trusted, or nil: web addresses only,
    /// no longer than an open tab's may be, the title cut.
    func checked() -> SentTab? {
        guard WebAddress.isWebURL(url), url.absoluteString.count <= SyncedDevice.urlLimit,
              UUID(uuidString: id) != nil else { return nil }
        var tab = self
        tab.title = SyncedDevice.cleanTitle(title)
        return tab
    }

    func isExpired(at now: Date) -> Bool { now.timeIntervalSince(sentAt) > Self.expiresAfter }

    /// The note as sent tabs arrive: "From iPhone", "3 tabs from Mac", or,
    /// from more than one kind of device, "3 tabs from your devices".
    public static func arrivalNote(for tabs: [SentTab]) -> String? {
        guard let first = tabs.first else { return nil }
        let kinds = Set(tabs.map(\.from))
        let source = kinds.count == 1 ? first.from.plainName : "your devices"
        return tabs.count == 1 ? "From \(source)" : "\(tabs.count) tabs from \(source)"
    }
}

extension SyncedDevice.Kind {
    /// "Mac", "iPhone", or "iPad".
    public var plainName: String {
        switch self {
        case .mac: "Mac"
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        }
    }
}

/// Another device a tab can be sent to.
public struct SendTarget: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: SyncedDevice.Kind
    /// Its name in a list of several: a Mac's own name, else "My iPhone"
    /// (two iPhones, which can't read their names, are numbered).
    public var name: String

    /// The menu's words: "Send to My Mac" when it's the only device,
    /// "Send to…" with each device's `name` when there are several. Nil
    /// with none (the item doesn't show).
    public static func menuTitle(for targets: [SendTarget]) -> String? {
        switch targets.count {
        case 0: nil
        case 1: "Send to My \(targets[0].kind.plainName)"
        default: "Send to…"
        }
    }
}

extension SyncState {
    /// Tabs sent to this device, not yet opened, by id.
    public var waitingSentTabs: [SentTab] {
        inbox.values.sorted { $0.sentAt != $1.sentAt ? $0.sentAt < $1.sentAt : $0.id < $1.id }
    }

    /// The other devices a tab can go to: those sent from in the last 14
    /// days, the most recently sent first.
    public func sendTargets(at now: Date) -> [SendTarget] {
        let cutoff = now.addingTimeInterval(-SyncedDevice.staleAfter)
        let devices = devices.values
            .filter { $0.id != deviceID && $0.sentAt > cutoff }
            .sorted { $0.sentAt != $1.sentAt ? $0.sentAt > $1.sentAt : $0.id < $1.id }
        var counts: [String: Int] = [:]
        return devices.map { device in
            var name = (device.kind == .mac ? device.name : nil) ?? "My \(device.kind.plainName)"
            counts[name, default: 0] += 1
            if let count = counts[name], count > 1 { name += " (\(count))" }
            return SendTarget(id: device.id, kind: device.kind, name: name)
        }
    }

    /// Takes in a send from iCloud: kept if it's for this device and not
    /// opened here before. Returns whether it's expired (anyone deletes those).
    mutating func receive(_ tab: SentTab, at now: Date) -> Bool {
        if tab.isExpired(at: now) {
            inbox[tab.id] = nil
            return true
        }
        if tab.toDeviceID == deviceID, opened[tab.id] == nil { inbox[tab.id] = tab }
        return false
    }

    /// Holds a send of this device's until iCloud has it (`item(for:)`
    /// gives it to the engine as it goes up).
    public mutating func queueSend(_ tab: SentTab) { outbox[tab.id] = tab }

    /// iCloud has this send (or it's gone): no longer held.
    public mutating func sendWentUp(_ id: SyncRecordID) {
        guard id.kind == .sentTab else { return }
        outbox[id.name] = nil
    }

    /// Sends that never reached iCloud in 7 days (offline all week) are
    /// dropped: they'd be deleted on arrival anyway.
    public mutating func dropExpiredSends(at now: Date) {
        outbox = outbox.filter { !$0.value.isExpired(at: now) }
    }

    /// Forgets opened sends once they'd have expired anyway.
    mutating func forgetOpened(at now: Date) {
        opened = opened.filter { now.timeIntervalSince($0.value) <= SentTab.expiresAfter + 24 * 60 * 60 }
    }
}

/// What came in when sent tabs were opened.
public struct SentTabsArrival: Sendable {
    /// The new tabs' ids, in the order they were sent.
    public var tabIDs: [UUID] = []
    /// The note to show ("From iPhone"), nil if nothing opened.
    public var note: String?
    /// The kind of device they came from, when it's one kind (the note's symbol).
    public var from: SyncedDevice.Kind?
    /// Records to delete from iCloud: the ones opened, and expired ones.
    public var deletes: [SyncRecordID] = []
}

extension BrowserStore {
    /// The tab to send: its address and title, from its space. Nil for a
    /// page that isn't a web page (nothing to send).
    public func sentTab(_ tab: Tab, to target: SendTarget, from kind: SyncedDevice.Kind, state: SyncState) -> SentTab? {
        guard let url = tab.url else { return nil }
        return SentTab(
            id: UUID().uuidString, toDeviceID: target.id, from: kind, url: url,
            title: tab.savedTitle, spaceID: state.remoteSpace(tab.spaceID), sentAt: now()
        ).checked()
    }

    /// Opens the tabs sent to this device: each where new tabs go in its
    /// space (or the space on screen, if this device doesn't have it), never
    /// switched to. The app calls it whenever Firn is in front and tabs are
    /// waiting, and deletes the returned records from iCloud.
    public func openSentTabs(_ state: inout SyncState) -> SentTabsArrival {
        let stamp = now()
        var arrival = SentTabsArrival()
        var arrived: [SentTab] = []
        for sent in state.waitingSentTabs {
            state.inbox[sent.id] = nil
            arrival.deletes.append(sent.recordID)
            guard !sent.isExpired(at: stamp) else { continue }
            state.opened[sent.id] = sent.sentAt
            let local = state.localSpace(sent.spaceID)
            let spaceID = spaces.contains { $0.id == local } ? local : activeSpaceID
            let tab = Tab(spaceID: spaceID, url: sent.url, title: sent.title, lastActiveAt: stamp)
            add(tab, below: nil, inBackground: true)
            arrival.tabIDs.append(tab.id)
            arrived.append(sent)
        }
        state.forgetOpened(at: stamp)
        arrival.note = SentTab.arrivalNote(for: arrived)
        let kinds = Set(arrived.map(\.from))
        arrival.from = kinds.count == 1 ? kinds.first : nil
        return arrival
    }
}
