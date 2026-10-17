import Foundation

/// A space: its own browser, with its own tabs and website data
/// (CLAUDE.md, How spaces work). Phase 2 has a single built-in space.
public struct Space: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Firn's own line icon, by name.
    public var icon: String
    /// One of Firn's space colors, by name ("glacier", "sand", …).
    public var color: String
    public var order: Int
    /// The website data store this space's pages use. Spaces that share
    /// sign-ins share this id.
    public var dataStoreID: UUID
    public var lastChangedAt: Date

    public init(
        id: UUID = UUID(), name: String, icon: String, color: String,
        order: Int, dataStoreID: UUID, lastChangedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.order = order
        self.dataStoreID = dataStoreID
        self.lastChangedAt = lastChangedAt
    }
}
