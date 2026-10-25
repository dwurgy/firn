import Foundation

public enum ArcImportError: Error, Equatable {
    /// Bigger than any real sidebar file; not read at all.
    case tooLarge
    /// Not JSON: a damaged file, so none of it is trusted.
    case damaged
    /// JSON, but not Arc's sidebar as Firn knows it: "Firn doesn't
    /// recognize this file," never a guess.
    case notRecognized
}

/// Arc's sidebar (`StorableSidebar.json` in Arc's folder), read and turned
/// into what Firn would make of it, nothing changed yet (CLAUDE.md, Arc
/// import plan in `docs/HISTORY.md`).
///
/// Each Arc space becomes a Firn space. Its profile's favorites become its
/// Basecamp (past 12, the rest a group "Favorites"), its pinned folders
/// become groups (nested folders flattened into their top folder), and
/// pinned tabs outside any folder a group "Pinned". Unpinned tabs stay
/// behind. Spaces on the same Arc profile share sign-ins.
///
/// The file is untrusted: it's read with limits, and a tree with loops or
/// missing ids is walked without trusting it.
public struct ArcImportPlan: Sendable {
    public struct Site: Hashable, Sendable {
        public let url: URL
        public let title: String
    }

    public struct Group: Hashable, Sendable {
        public let name: String
        public let sites: [Site]
    }

    public struct Space: Hashable, Sendable {
        public let name: String
        /// Spaces with the same profile share one data store; Arc's own
        /// description of the profile, not shown.
        let profile: String
        public let basecamp: [Site]
        /// In Arc's order; "Favorites" (if any) first.
        public let groups: [Group]
    }

    /// Far more than any real sidebar file, small enough to read at once.
    static let sizeLimit = 50_000_000
    static let itemLimit = 100_000
    static let spaceLimit = 50
    static let addressLimit = 2048
    static let titleLimit = 500
    /// Deeper folders than this are left out (a loop or a damaged file).
    static let depthLimit = 32

    public let spaces: [Space]
    /// Skipped: favorites and pinned tabs whose address isn't an http or
    /// https website (a file, an Arc page, or something damaged).
    public let skipped: Int

    /// How many different sign-ins the spaces will have: one per Arc profile.
    public var profileCount: Int { Set(spaces.map(\.profile)).count }
    /// The names of spaces that will share sign-ins (same Arc profile), in
    /// Arc's order; spaces on a profile of their own aren't listed.
    public var sharingSignIns: [[String]] {
        var order: [String] = []
        var names: [String: [String]] = [:]
        for space in spaces {
            if names[space.profile] == nil { order.append(space.profile) }
            names[space.profile, default: []].append(space.name)
        }
        return order.compactMap { names[$0] }.filter { $0.count > 1 }
    }
    public var tabCount: Int { spaces.reduce(0) { $0 + $1.basecamp.count + $1.groups.reduce(0) { $0 + $1.sites.count } } }

    public init(_ data: Data) throws {
        guard data.count <= Self.sizeLimit else { throw ArcImportError.tooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ArcImportError.damaged }
        guard let containers = ((root as? [String: Any])?["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let main = containers.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }),
              let spaceList = main["spaces"] as? [Any],
              let itemList = main["items"] as? [Any]
        else { throw ArcImportError.notRecognized }
        guard itemList.count <= Self.itemLimit * 2 else { throw ArcImportError.tooLarge }

        // Arc's lists alternate an id and its record; only the records matter.
        var items: [String: [String: Any]] = [:]
        for case let item as [String: Any] in itemList {
            if let id = item["id"] as? String, items[id] == nil { items[id] = item }
        }
        // topAppsContainerIDs alternates a profile and its favorites' container.
        var favoritesByProfile: [String: String] = [:]
        let topApps = main["topAppsContainerIDs"] as? [Any] ?? []
        for (profile, id) in zip(topApps, topApps.dropFirst()) {
            if let id = id as? String, !(profile is String) {
                favoritesByProfile[Self.profileKey(profile)] = favoritesByProfile[Self.profileKey(profile)] ?? id
            }
        }

        var skipped = 0
        func site(_ item: [String: Any]) -> Site? {
            guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
            guard let address = tab["savedURL"] as? String, address.utf8.count <= Self.addressLimit,
                  let url = URL(string: address), WebAddress.isWebURL(url) else {
                skipped += 1
                return nil
            }
            // A tab renamed in Arc keeps its new name as the item's title.
            let named = (item["title"] as? String).flatMap(Self.cleanTitle)
            let title = named ?? (tab["savedTitle"] as? String).flatMap(Self.cleanTitle) ?? ""
            return Site(url: url, title: title)
        }
        func children(of id: String) -> [[String: Any]] {
            (items[id]?["childrenIds"] as? [Any] ?? []).compactMap { ($0 as? String).flatMap { items[$0] } }
        }
        // Every web tab under an item, in order, folders flattened. Each item
        // once, however the file links them.
        var visited = Set<String>()
        func sites(under item: [String: Any], depth: Int = 0) -> [Site] {
            guard depth <= Self.depthLimit, let id = item["id"] as? String, visited.insert(id).inserted else { return [] }
            if let one = site(item) { return [one] }
            return children(of: id).flatMap { sites(under: $0, depth: depth + 1) }
        }

        // A profile's favorites, read once however many spaces use it.
        var favoritesCache: [String: [Site]] = [:]
        func favorites(of profile: String) -> [Site] {
            if let cached = favoritesCache[profile] { return cached }
            visited.removeAll()
            let found = favoritesByProfile[profile].map { id in children(of: id).flatMap { sites(under: $0) } } ?? []
            favoritesCache[profile] = found
            return found
        }

        var spaces: [Space] = []
        for case let record as [String: Any] in spaceList where spaces.count < Self.spaceLimit {
            guard record["id"] is String else { continue }
            let profile = Self.profileKey(record["profile"] ?? ["default": true])
            let favorites = favorites(of: profile)

            var groups: [Group] = []
            if favorites.count > BrowserStore.basecampLimit {
                groups.append(Group(name: "Favorites", sites: Array(favorites.dropFirst(BrowserStore.basecampLimit))))
            }
            // containerIDs alternates "pinned" or "unpinned" and its container.
            let containerIDs = record["containerIDs"] as? [Any] ?? []
            let pinnedID = zip(containerIDs, containerIDs.dropFirst())
                .first { ($0.0 as? String) == "pinned" }?.1 as? String
            visited.removeAll()
            var loose: [Site] = []
            var looseAt: Int?
            for item in pinnedID.map(children(of:)) ?? [] {
                let found = sites(under: item)
                if (item["data"] as? [String: Any])?["tab"] != nil {
                    guard let one = found.first else { continue }
                    looseAt = looseAt ?? groups.count
                    loose.append(one)
                } else if !found.isEmpty {
                    let name = (item["title"] as? String).flatMap(TabGroup.cleanName) ?? TabGroup.defaultName
                    groups.append(Group(name: name, sites: found))
                }
            }
            if let looseAt { groups.insert(Group(name: "Pinned", sites: loose), at: looseAt) }

            spaces.append(Space(
                name: (record["title"] as? String).flatMap(FirnCore.Space.cleanName) ?? FirnCore.Space.defaultName,
                profile: profile,
                basecamp: Array(favorites.prefix(BrowserStore.basecampLimit)),
                groups: groups
            ))
        }
        guard !spaces.isEmpty else { throw ArcImportError.notRecognized }
        self.spaces = spaces
        self.skipped = skipped
    }

    /// A profile as text, so equal profiles compare equal however the file
    /// orders their keys.
    private static func profileKey(_ profile: Any) -> String {
        guard JSONSerialization.isValidJSONObject(profile),
              let data = try? JSONSerialization.data(withJSONObject: profile, options: .sortedKeys) else { return "default" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func cleanTitle(_ title: String) -> String? {
        let line = title.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : String(line.prefix(titleLimit))
    }
}
