import Foundation

// "On your Mac" and "On your iPhone" (docs/SYNC-PLAN.md, step 5): each
// device keeps one sealed record of its open tabs in iCloud, and the command
// bar finds the other devices' tabs in the space on screen. A closed tab
// simply drops off the next send, so there are no per-tab deletes to arrive
// out of order.

/// One device's open tabs, as its `Device` record holds them.
public struct SyncedDevice: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case mac, iPhone, iPad
    }

    /// One open tab: its address, title, and space (by iCloud's id).
    public struct OpenTab: Codable, Equatable, Sendable {
        public var url: URL
        public var title: String
        public var spaceID: UUID

        public init(url: URL, title: String, spaceID: UUID) {
            self.url = url
            self.title = title
            self.spaceID = spaceID
        }
    }

    /// A random id for this install of Firn (`SyncState.deviceID`).
    public var id: String
    public var kind: Kind
    /// A Mac's own name ("David's Mac mini"), shown only when there are two
    /// Macs. Nil on an iPhone or iPad, which can't read theirs.
    public var name: String?
    public var sentAt: Date
    /// The most recently used first.
    public var tabs: [OpenTab]

    public init(id: String, kind: Kind, name: String?, sentAt: Date, tabs: [OpenTab]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sentAt = sentAt
        self.tabs = tabs
    }

    /// The most tabs a record holds: the most recently used ones.
    public static let tabLimit = 150
    /// A device not sent from in this long stops showing.
    public static let staleAfter: TimeInterval = 14 * 24 * 60 * 60
    /// What a record's fields may take before sealing: under `SyncSeal`'s
    /// 64 KB with room for the seal itself.
    static let fieldsBudget = 60 * 1024
    /// Longer titles are cut, and longer addresses left out, so 150 tabs
    /// almost always fit (the budget drops the oldest if they don't).
    static let titleLimit = 200
    static let urlLimit = 2048
    static let nameLimit = 64

    /// The same record as it should be trusted: web addresses only, titles
    /// cut, at most `tabLimit` tabs, a sane name. Everything from another
    /// device passes through this.
    func checked() -> SyncedDevice {
        var device = self
        device.name = name.flatMap(Self.cleanName)
        device.tabs = tabs.lazy
            .filter { WebAddress.isWebURL($0.url) && $0.url.absoluteString.count <= Self.urlLimit }
            .prefix(Self.tabLimit)
            .map { OpenTab(url: $0.url, title: Self.cleanTitle($0.title), spaceID: $0.spaceID) }
        return device
    }

    static func cleanTitle(_ title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isNewline }
        return title.count > titleLimit ? String(title.prefix(titleLimit)) : title
    }

    static func cleanName(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline }
        guard !name.isEmpty else { return nil }
        return name.count > nameLimit ? String(name.prefix(nameLimit)) : name
    }

    /// The command bar's words for it: "On your Mac", "On your iPhone", or
    /// "On your iPad". With two Macs, each goes by its own name.
    func label(macCount: Int) -> String {
        switch kind {
        case .mac:
            if macCount > 1, let name { "On \(name)" } else { "On your Mac" }
        case .iPhone: "On your iPhone"
        case .iPad: "On your iPad"
        }
    }
}

/// A tab open on another device, as the command bar offers it. Picking it
/// opens this device's own copy.
public struct DeviceTab: Identifiable, Equatable, Sendable {
    public var url: URL
    public var title: String
    /// "On your iPhone", "On David's Mac mini", …
    public var deviceLabel: String
    public var deviceID: String
    /// The site's icon, if a tab in this space already has one for that
    /// site (icons never travel, and fetching one would be new traffic).
    public var icon: Data?

    public var id: String { "\(deviceID) \(url.absoluteString)" }

    /// The title, or where it is when it has none.
    public var shownTitle: String { title.isEmpty ? WebAddress.site(of: url) : title }
}

extension BrowserStore {
    /// This device's record to send now: its loose and grouped tabs, the
    /// most recently used first (never Basecamp tiles, tidied-away tabs, or
    /// Lookouts), at most `SyncedDevice.tabLimit`, in iCloud's terms.
    public func deviceRecord(kind: SyncedDevice.Kind, name: String?, state: SyncState) -> SyncedDevice {
        let open = tabs.filter { $0.place == .open }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
            .compactMap { tab -> SyncedDevice.OpenTab? in
                guard let url = tab.url else { return nil }
                return SyncedDevice.OpenTab(url: url, title: tab.savedTitle, spaceID: state.remoteSpace(tab.spaceID))
            }
        var device = SyncedDevice(
            id: state.deviceID, kind: kind, name: kind == .mac ? name : nil, sentAt: now(), tabs: open
        ).checked()
        // Long addresses could still push it past what a record may hold:
        // the least recently used go first.
        let encoder = JSONEncoder()
        while !device.tabs.isEmpty, let size = try? encoder.encode(device).count, size > SyncedDevice.fieldsBudget {
            device.tabs.removeLast(max(1, device.tabs.count / 10))
        }
        return device
    }

    /// The other devices' tabs open in the space on screen, for
    /// `commandRows`: only spaces this device has (translated through
    /// `state`, so a space that joined still matches), only devices sent
    /// from in the last 14 days, the most recently sent device first.
    public func otherDeviceTabs(in state: SyncState, thisDevice: SyncedDevice.Kind) -> [DeviceTab] {
        let cutoff = now().addingTimeInterval(-SyncedDevice.staleAfter)
        let devices = state.devices.values
            .filter { $0.id != state.deviceID && $0.sentAt > cutoff }
            .sorted { $0.sentAt > $1.sentAt }
        let macs = devices.filter { $0.kind == .mac }.count + (thisDevice == .mac ? 1 : 0)
        let space = activeSpace.id
        // Icons this space already has, by site; never another space's.
        var icons: [String: Data] = [:]
        for tab in tabs where tab.spaceID == space {
            if let host = tab.url?.host(), icons[host] == nil, let icon = tab.icon { icons[host] = icon }
        }
        return devices.flatMap { device in
            let label = device.label(macCount: macs)
            return device.tabs
                .filter { state.localSpace($0.spaceID) == space }
                .map {
                    DeviceTab(url: $0.url, title: $0.title, deviceLabel: label, deviceID: device.id,
                              icon: $0.url.host().flatMap { icons[$0] })
                }
        }
    }
}
