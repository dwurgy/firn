import Foundation

/// Everything Firn remembers between launches: spaces, groups, tabs, and the window.
/// Saved as JSON (see `SessionFile`). Every record has a stable id and a
/// last-changed time, so it can be synced one day; nothing syncs now.
public struct Session: Codable, Equatable, Sendable {
    /// Goes up when the format changes in a way older code can't read.
    public static let currentVersion = 1

    public var version: Int
    public var spaces: [Space]
    /// Missing in files from before groups, which simply had none.
    public var groups: [GroupRecord]
    /// Missing in files from before split view, which simply had none.
    public var splits: [SplitRecord]
    public var tabs: [TabRecord]
    public var window: WindowRecord
    /// The days Firn was used, as "yyyy-MM-dd", for drifting. Missing in
    /// files from before Archived.
    public var usedDays: [String]
    /// The spaces whose overflow has newly tidied tabs not yet looked at.
    /// Missing in files from before Tidied away.
    public var unseenTidiedSpaceIDs: [UUID]

    public init(
        version: Int = currentVersion, spaces: [Space], groups: [GroupRecord] = [], splits: [SplitRecord] = [], tabs: [TabRecord], window: WindowRecord,
        usedDays: [String] = [], unseenTidiedSpaceIDs: [UUID] = []
    ) {
        self.version = version
        self.spaces = spaces
        self.groups = groups
        self.splits = splits
        self.tabs = tabs
        self.window = window
        self.usedDays = usedDays
        self.unseenTidiedSpaceIDs = unseenTidiedSpaceIDs
    }

    private enum CodingKeys: String, CodingKey { case version, spaces, groups, splits, tabs, window, usedDays, unseenTidiedSpaceIDs }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        spaces = try container.decode([Space].self, forKey: .spaces)
        groups = try container.decodeIfPresent([GroupRecord].self, forKey: .groups) ?? []
        splits = try container.decodeIfPresent([SplitRecord].self, forKey: .splits) ?? []
        tabs = try container.decode([TabRecord].self, forKey: .tabs)
        window = try container.decode(WindowRecord.self, forKey: .window)
        usedDays = try container.decodeIfPresent([String].self, forKey: .usedDays) ?? []
        unseenTidiedSpaceIDs = try container.decodeIfPresent([UUID].self, forKey: .unseenTidiedSpaceIDs) ?? []
    }
}

/// A group as saved.
public struct GroupRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var name: String
    /// Its position among all groups (each space's groups keep this order).
    public var order: Int
    public var folded: Bool
    public var lastChangedAt: Date

    public init(id: UUID, spaceID: UUID, name: String, order: Int, folded: Bool, lastChangedAt: Date) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.order = order
        self.folded = folded
        self.lastChangedAt = lastChangedAt
    }

    /// The same group, ignoring when it last changed.
    func sameContent(as other: GroupRecord) -> Bool {
        var other = other
        other.lastChangedAt = lastChangedAt
        return self == other
    }
}

/// A split view as saved; its tabs say they're in it.
public struct SplitRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var leftFraction: Double
    public var lastChangedAt: Date

    public init(id: UUID, spaceID: UUID, leftFraction: Double, lastChangedAt: Date) {
        self.id = id
        self.spaceID = spaceID
        self.leftFraction = leftFraction
        self.lastChangedAt = lastChangedAt
    }

    /// The same split, ignoring when it last changed.
    func sameContent(as other: SplitRecord) -> Bool {
        var other = other
        other.lastChangedAt = lastChangedAt
        return self == other
    }
}

/// A tab as saved: where it was, not its page.
public struct TabRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var place: Tab.Place
    public var url: URL?
    public var title: String
    /// The site's icon, a small PNG. Missing in files from before 3c.
    public var icon: Data?
    public var homeURL: URL?
    /// The group it's kept in, if any. Missing in files from before groups.
    public var groupID: UUID?
    /// The split view it's half of. Missing in files from before split view.
    public var splitID: UUID?
    /// Its position among all tabs (each space's lists keep this order).
    public var order: Int
    public var lastActiveAt: Date
    public var openerTabID: UUID?
    /// When a drifted tab drifted. Missing in files from before Drifted tabs.
    public var driftedAt: Date?
    public var lastChangedAt: Date

    public init(
        id: UUID, spaceID: UUID, place: Tab.Place, url: URL?, title: String, icon: Data? = nil, homeURL: URL?,
        groupID: UUID? = nil, splitID: UUID? = nil, order: Int, lastActiveAt: Date, openerTabID: UUID?, driftedAt: Date? = nil,
        lastChangedAt: Date
    ) {
        self.id = id
        self.spaceID = spaceID
        self.place = place
        self.url = url
        self.title = title
        self.icon = icon
        self.homeURL = homeURL
        self.groupID = groupID
        self.splitID = splitID
        self.order = order
        self.lastActiveAt = lastActiveAt
        self.openerTabID = openerTabID
        self.driftedAt = driftedAt
        self.lastChangedAt = lastChangedAt
    }

    /// The same tab, ignoring when it last changed.
    func sameContent(as other: TabRecord) -> Bool {
        var other = other
        other.lastChangedAt = lastChangedAt
        return self == other
    }
}

/// The window: which space and tab are showing, and how the sidebar sits.
public struct WindowRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var activeSpaceID: UUID
    public var activeTabID: UUID?
    /// The tab each other space last had on screen, by space id. Missing in
    /// files from before spaces.
    public var spaceTabIDs: [UUID: UUID]
    public var sidebarWidth: Double
    public var sidebarCollapsed: Bool

    public init(
        id: UUID, activeSpaceID: UUID, activeTabID: UUID?, spaceTabIDs: [UUID: UUID] = [:],
        sidebarWidth: Double, sidebarCollapsed: Bool
    ) {
        self.id = id
        self.activeSpaceID = activeSpaceID
        self.activeTabID = activeTabID
        self.spaceTabIDs = spaceTabIDs
        self.sidebarWidth = sidebarWidth
        self.sidebarCollapsed = sidebarCollapsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, activeSpaceID, activeTabID, spaceTabIDs, sidebarWidth, sidebarCollapsed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        activeSpaceID = try container.decode(UUID.self, forKey: .activeSpaceID)
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        spaceTabIDs = try container.decodeIfPresent([UUID: UUID].self, forKey: .spaceTabIDs) ?? [:]
        sidebarWidth = try container.decode(Double.self, forKey: .sidebarWidth)
        sidebarCollapsed = try container.decode(Bool.self, forKey: .sidebarCollapsed)
    }
}
