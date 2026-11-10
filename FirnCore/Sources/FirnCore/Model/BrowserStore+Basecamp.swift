import Foundation
import Observation

extension BrowserStore {
    // MARK: - Basecamp

    /// Adds a tab to its space's Basecamp, if there's room (taking it out of
    /// its group and split): at `position` among the tiles when dragged
    /// there (0-based; the count means the end), otherwise at the end. Its
    /// address becomes its home.
    @discardableResult
    public func addToBasecamp(_ tab: Tab, at position: Int? = nil) -> Bool {
        let tiles = list(.basecamp, in: tab.spaceID)
        guard tab.place != .basecamp, tiles.count < Self.basecampLimit,
              tabs.contains(where: { $0.id == tab.id }),
              let home = tab.url else { return false }
        _ = endSplit(of: tab)
        tabs.removeAll { $0.id == tab.id }
        let groupID = tab.groupID
        tab.place = .basecamp
        tab.homeURL = home
        tab.groupID = nil
        insert(tab, at: position ?? tiles.count, in: tiles)
        endIfEmpty(groupID)
        return true
    }

    /// Adds a site (picked in the welcome) as a new tile at the end of the
    /// current space's Basecamp, resting until it's clicked, if there's room
    /// and no tile there already has the same site. Its icon, if it has one,
    /// shows straight away, so Basecamp doesn't fetch it again.
    @discardableResult
    public func addBasecampTile(_ url: URL, title: String, icon: Data?) -> Tab? {
        let tiles = list(.basecamp)
        guard WebAddress.isWebURL(url), tiles.count < Self.basecampLimit,
              !tiles.contains(where: { Self.sameSite($0.homeURL, url) }) else { return nil }
        let tab = Tab(
            spaceID: activeSpaceID, place: .basecamp, url: url, title: title,
            icon: icon.flatMap { SiteIcon.isValidStored($0) ? $0 : nil }, homeURL: url, lastActiveAt: now()
        )
        insert(tab, at: tiles.count, in: tiles)
        return tab
    }

    /// The current space's tile for this site (by host, without "www."), if it has one.
    public func basecampTile(for url: URL) -> Tab? {
        list(.basecamp).first { Self.sameSite($0.homeURL, url) }
    }

    static func sameSite(_ a: URL?, _ b: URL?) -> Bool {
        func site(_ url: URL?) -> String? {
            guard let host = url?.host(percentEncoded: false)?.lowercased() else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        guard let a = site(a) else { return false }
        return a == site(b)
    }

    /// A tile becomes a loose tab where new tabs go, so nothing is lost.
    /// Even a resting one stays (it loads when clicked); only Close removes
    /// a tile. It counts as just seen, so it isn't tidied away straight after.
    public func removeFromBasecamp(_ tab: Tab) {
        guard tab.place == .basecamp, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.place = .open
        tab.homeURL = nil
        tab.lastActiveAt = now()
        tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
    }

    /// A tile dragged out of Basecamp becomes an everyday tab right where it
    /// was let go: `position` among `group`'s tabs, or in the tab list when
    /// `group` is nil (as `move(_:toGroup:at:)`). Even a resting one stays,
    /// since it was put there on purpose; it loads when clicked. It counts
    /// as just seen, so it isn't tidied away straight after.
    public func removeFromBasecamp(_ tab: Tab, toGroup group: TabGroup?, at position: Int) {
        guard tab.place == .basecamp, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let group, group.spaceID != tab.spaceID || !groups.contains(where: { $0.id == group.id }) { return }
        tabs.remove(at: index)
        tab.place = .open
        tab.homeURL = nil
        tab.lastActiveAt = now()
        if let group {
            tab.groupID = group.id
            insert(tab, at: position, in: Self.rows(tabs(in: group)), fallback: index)
            keep(group)
        } else {
            insertInTabList([tab], at: position, fallback: index)
        }
    }

    /// Takes a Basecamp tile back to its home address, and shows it.
    public func goHome(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }), tab.homeURL != nil else { return }
        tab.goHome()
        select(tab)
    }
}
