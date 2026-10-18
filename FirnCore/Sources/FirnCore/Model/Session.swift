import Foundation

/// Everything Firn remembers between launches: spaces, tabs, and the window.
/// Saved as JSON (see `SessionFile`). Every record has a stable id and a
/// last-changed time, so it can be synced one day; nothing syncs now.
public struct Session: Codable, Equatable, Sendable {
    /// Goes up when the format changes in a way older code can't read.
    public static let currentVersion = 1

    public var version: Int
    public var spaces: [Space]
    public var tabs: [TabRecord]
    public var window: WindowRecord

    public init(version: Int = currentVersion, spaces: [Space], tabs: [TabRecord], window: WindowRecord) {
        self.version = version
        self.spaces = spaces
        self.tabs = tabs
        self.window = window
    }
}

/// A tab as saved: where it was, not its page.
public struct TabRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var place: Tab.Place
    public var url: URL?
    public var title: String
    public var homeURL: URL?
    /// Its position among all tabs (each space's lists keep this order).
    public var order: Int
    public var lastActiveAt: Date
    public var openerTabID: UUID?
    public var lastChangedAt: Date

    public init(
        id: UUID, spaceID: UUID, place: Tab.Place, url: URL?, title: String, homeURL: URL?,
        order: Int, lastActiveAt: Date, openerTabID: UUID?, lastChangedAt: Date
    ) {
        self.id = id
        self.spaceID = spaceID
        self.place = place
        self.url = url
        self.title = title
        self.homeURL = homeURL
        self.order = order
        self.lastActiveAt = lastActiveAt
        self.openerTabID = openerTabID
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
    public var sidebarWidth: Double
    public var sidebarCollapsed: Bool

    public init(id: UUID, activeSpaceID: UUID, activeTabID: UUID?, sidebarWidth: Double, sidebarCollapsed: Bool) {
        self.id = id
        self.activeSpaceID = activeSpaceID
        self.activeTabID = activeTabID
        self.sidebarWidth = sidebarWidth
        self.sidebarCollapsed = sidebarCollapsed
    }
}
