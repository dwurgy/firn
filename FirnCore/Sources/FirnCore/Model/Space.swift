import Foundation

/// A space: its own browser, with its own tabs and website data
/// (CLAUDE.md, How spaces work). Spaces are ordered by their place in
/// `BrowserStore.spaces`; `order` mirrors it for saving.
public struct Space: Identifiable, Codable, Hashable, Sendable {
    public static let defaultName = "New Space"

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
    /// The sites where this space doesn't block ads and trackers
    /// (`BlockingSite`), in the order they were added. Its own, even when
    /// it shares sign-ins with another space.
    public var blockingOffSites: [String] = []
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

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, color, order, dataStoreID, blockingOffSites, lastChangedAt
    }

    /// Spaces saved before blocking could be turned off for a site have no list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        order = try container.decode(Int.self, forKey: .order)
        dataStoreID = try container.decode(UUID.self, forKey: .dataStoreID)
        let sites = try container.decodeIfPresent([String].self, forKey: .blockingOffSites) ?? []
        blockingOffSites = BlockingSite.clean(sites)
        lastChangedAt = try container.decode(Date.self, forKey: .lastChangedAt)
    }

    /// Whether ads and trackers are blocked on `url` in this space.
    public func blocksContent(on url: URL) -> Bool {
        guard let host = BlockingSite.host(of: url) else { return true }
        return !blockingOffSites.contains { BlockingSite.covers($0, host: host) }
    }

    /// A name fit to show, by the same rules as a group's: one line,
    /// trimmed, not too long; nil if nothing's left.
    static func cleanName(_ name: String) -> String? {
        TabGroup.cleanName(name)
    }
}

/// A site where blocking can be turned off: an address's host, lowercased,
/// without "www.". It covers its subdomains too, so turning it off on
/// example.com also covers shop.example.com.
public enum BlockingSite {
    /// How many sites a space keeps; the oldest goes past this.
    static let limit = 500

    /// The site for an http or https address; nil for anything else.
    public static func of(_ url: URL) -> String? {
        guard let host = host(of: url) else { return nil }
        return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }

    static func host(of url: URL) -> String? {
        guard WebAddress.isWebURL(url), let host = url.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty else { return nil }
        return host
    }

    static func covers(_ site: String, host: String) -> Bool {
        host == site || host.hasSuffix("." + site)
    }

    /// Drops anything that isn't a plain host (a damaged or edited file), and repeats.
    static func clean(_ sites: [String]) -> [String] {
        var seen = Set<String>()
        let kept = sites.filter { site in
            guard let url = URL(string: "https://\(site)/"), of(url) == site else { return false }
            return seen.insert(site).inserted
        }
        return Array(kept.suffix(limit))
    }
}
