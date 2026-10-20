import Foundation
import Observation

/// Firn's tabs and spaces, and the one place they change. Views read from
/// here and call its methods; nothing in here touches WebKit.
@MainActor
@Observable
public final class BrowserStore {
    /// How many tiles a space's Basecamp holds.
    public static let basecampLimit = 12

    public private(set) var spaces: [Space]
    /// Every group in every space, in order.
    public private(set) var groups: [TabGroup] = []
    /// Every tab in every space; each list (Basecamp, a group, the loose
    /// tabs) keeps this order.
    public private(set) var tabs: [Tab] = []
    public private(set) var activeSpaceID: UUID
    public private(set) var activeTabID: UUID?

    @ObservationIgnored private let makePage: @MainActor (_ dataStoreID: UUID) -> any PageController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var windowID = UUID()
    /// What each tab looked like when last saved, so a record's last-changed
    /// time only moves when the record really changed.
    @ObservationIgnored private var savedRecords: [UUID: TabRecord] = [:]
    @ObservationIgnored private var savedGroupRecords: [UUID: GroupRecord] = [:]

    /// - Parameters:
    ///   - makePage: Makes a page for a data store; `BrowserEngine.makePage` in the app.
    ///   - now: The clock, replaceable in tests.
    public init(
        spaces: [Space],
        makePage: @escaping @MainActor (_ dataStoreID: UUID) -> any PageController,
        now: @escaping () -> Date = Date.init
    ) {
        precondition(!spaces.isEmpty, "Firn always has at least one space")
        self.spaces = spaces
        self.activeSpaceID = spaces[0].id
        self.makePage = makePage
        self.now = now
    }

    /// Picks up where the saved session left off, or starts with
    /// `defaultSpaces` if there's none. Only the tab on screen loads; the
    /// rest rest until shown.
    public convenience init(
        restoring session: Session?,
        defaultSpaces: [Space],
        makePage: @escaping @MainActor (_ dataStoreID: UUID) -> any PageController,
        now: @escaping () -> Date = Date.init
    ) {
        var seen = Set<UUID>()
        let saved = (session?.spaces ?? [])
            .sorted { $0.order < $1.order }
            .filter { seen.insert($0.id).inserted }
        self.init(spaces: saved.isEmpty ? defaultSpaces : saved, makePage: makePage, now: now)
        if let session { restore(session) }
    }

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    /// The current space's Basecamp tiles, in order.
    public var basecampTabs: [Tab] { list(.basecamp) }
    /// The current space's groups, in order.
    public var tabGroups: [TabGroup] { groups.filter { $0.spaceID == activeSpaceID } }
    /// The current space's loose tabs (everyday tabs in no group), in order.
    public var looseTabs: [Tab] { list(.open).filter { $0.groupID == nil } }
    /// All the current space's everyday tabs: each group's, then the loose ones.
    public var openTabs: [Tab] { tabGroups.flatMap(tabs(in:)) + looseTabs }

    /// A group's tabs, in order.
    public func tabs(in group: TabGroup) -> [Tab] {
        tabs.filter { $0.groupID == group.id }
    }

    /// What the current space's sidebar shows, top to bottom: Basecamp, the
    /// tabs of each unfolded group, then the loose tabs.
    public var sidebarTabs: [Tab] {
        basecampTabs + tabGroups.filter { !$0.folded }.flatMap(tabs(in:)) + looseTabs
    }

    public var canAddToBasecamp: Bool { basecampTabs.count < Self.basecampLimit }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    private func list(_ place: Tab.Place, in spaceID: UUID? = nil) -> [Tab] {
        let spaceID = spaceID ?? activeSpaceID
        return tabs.filter { $0.spaceID == spaceID && $0.place == place }
    }

    /// The list a tab sits in: its space's Basecamp, its group, its space's
    /// loose tabs, or its space's archived tabs.
    private func siblings(of tab: Tab) -> [Tab] {
        if let groupID = tab.groupID { return tabs.filter { $0.groupID == groupID } }
        let list = list(tab.place, in: tab.spaceID)
        return tab.place == .open ? list.filter { $0.groupID == nil } : list
    }

    /// Where a loose tab goes at the top of its space's loose tabs.
    private func topOfLooseTabs(in spaceID: UUID) -> Int {
        tabs.firstIndex { $0.spaceID == spaceID && $0.place == .open && $0.groupID == nil } ?? tabs.count
    }

    /// Puts a tab (already out of `tabs`) at `position` in `list` (0-based;
    /// the count, or more, means the end).
    private func insert(_ tab: Tab, at position: Int, in list: [Tab]) {
        let target: Int
        if position < list.count, let before = tabs.firstIndex(where: { $0.id == list[max(position, 0)].id }) {
            target = before
        } else if let last = list.last, let after = tabs.firstIndex(where: { $0.id == last.id }) {
            target = after + 1
        } else {
            target = tabs.count
        }
        tabs.insert(tab, at: target)
    }

    // MARK: - Opening and closing

    /// Opens `url` in a new tab and shows it, or with `inBackground` stays
    /// put; the tab then loads the first time it's shown. (Pages loaded before
    /// they've ever been on screen took seconds to appear when shown.) With an `opener`, the tab joins the opener's
    /// space below it (after any tabs it opened before); otherwise it goes at
    /// the end of the current space.
    @discardableResult
    public func openTab(_ url: URL, opener: Tab? = nil, inBackground: Bool = false) -> Tab {
        let tab = Tab(
            spaceID: opener?.spaceID ?? activeSpaceID, url: url,
            openerTabID: opener?.id, lastActiveAt: now()
        )
        add(tab, below: opener, inBackground: inBackground)
        return tab
    }

    /// Takes in a page a tab's page opened (a link meant for a new window, or
    /// a popup). It already exists and stays connected to its opener, so it
    /// is shown as is; it shares the opener's space and data store.
    @discardableResult
    func adopt(_ page: any PageController, opener: Tab, inBackground: Bool) -> Tab {
        let tab = Tab(
            spaceID: opener.spaceID, url: nil,
            openerTabID: opener.id, lastActiveAt: now(), page: page
        )
        connect(page, to: tab)
        add(tab, below: opener, inBackground: inBackground)
        return tab
    }

    /// Links from a loose tab open right below it; links from a Basecamp
    /// tile or a grouped tab open at the top of the loose tabs (joining a
    /// group is a choice, so links don't fill one up). Either way, several
    /// links from one tab stay in the order they were opened.
    private func add(_ tab: Tab, below opener: Tab?, inBackground: Bool) {
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            var position = opener.place == .open && opener.groupID == nil
                ? index + 1
                : topOfLooseTabs(in: opener.spaceID)
            while position < tabs.count, tabs[position].openerTabID == opener.id { position += 1 }
            tabs.insert(tab, at: position)
        } else {
            tabs.append(tab)
        }
        if !inBackground { select(tab) }
    }

    /// Closes a tab. An everyday tab goes away (a group whose last tab it
    /// was ends with it); a Basecamp tile lets its page go and rests in its
    /// place until clicked. If it was on screen, `next` is shown if it's
    /// still there; otherwise, for an everyday tab, the one below it in its
    /// group or the loose tabs (or above, if it was last); failing that, the
    /// tab in this space that was on screen most recently.
    public func close(_ tab: Tab, showing next: Tab? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let siblings = siblings(of: tab)
        let position = tab.place == .open ? siblings.firstIndex { $0.id == tab.id } : nil
        tab.sleep()
        if tab.place != .basecamp {
            tabs.remove(at: index)
            endIfEmpty(tab.groupID)
        }

        guard activeTabID == tab.id else { return }
        activeTabID = nil
        let remaining = siblings.filter { $0.id != tab.id }
        if let next, next.id != tab.id, tabs.contains(where: { $0.id == next.id }) {
            select(next)
        } else if let position, !remaining.isEmpty {
            select(remaining[min(position, remaining.count - 1)])
        } else {
            selectMostRecent()
        }
    }

    /// Shows the awake tab in this space that was on screen most recently, if any.
    private func selectMostRecent() {
        if let recent = tabs
            .filter({ $0.spaceID == activeSpaceID && !$0.isResting })
            .max(by: { $0.lastActiveAt < $1.lastActiveAt }) {
            select(recent)
        }
    }

    // MARK: - Basecamp

    /// Adds a tab to the end of its space's Basecamp, if there's room (taking
    /// it out of its group). Its address becomes its home.
    @discardableResult
    public func addToBasecamp(_ tab: Tab) -> Bool {
        guard tab.place != .basecamp, list(.basecamp, in: tab.spaceID).count < Self.basecampLimit,
              let index = tabs.firstIndex(where: { $0.id == tab.id }),
              let home = tab.url else { return false }
        tabs.remove(at: index)
        let groupID = tab.groupID
        tab.place = .basecamp
        tab.homeURL = home
        tab.groupID = nil
        tabs.append(tab)
        endIfEmpty(groupID)
        return true
    }

    /// An awake tile becomes a loose tab at the top of the list, so its page
    /// isn't lost. A resting one has nothing open to keep, so it goes.
    public func removeFromBasecamp(_ tab: Tab) {
        guard tab.place == .basecamp, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        guard !tab.isResting else { return }
        tab.place = .open
        tab.homeURL = nil
        tabs.insert(tab, at: topOfLooseTabs(in: tab.spaceID))
    }

    /// Takes a Basecamp tile back to its home address, and shows it.
    public func goHome(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }), tab.homeURL != nil else { return }
        tab.goHome()
        select(tab)
    }

    // MARK: - Groups

    /// Starts a group with an everyday tab (taking it out of any group it
    /// was in). The group goes below the space's other groups, just above
    /// the loose tabs.
    @discardableResult
    public func newGroup(with tab: Tab) -> TabGroup? {
        guard tab.place == .open, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let group = TabGroup(spaceID: tab.spaceID)
        let last = groups.lastIndex { $0.spaceID == tab.spaceID }
        groups.insert(group, at: last.map { $0 + 1 } ?? groups.count)
        let oldGroupID = tab.groupID
        tabs.remove(at: index)
        tab.groupID = group.id
        tabs.append(tab)
        endIfEmpty(oldGroupID)
        return group
    }

    /// A tab dropped onto another: it joins the other's group, just after
    /// it, or the two start a new group together (the other first).
    public func group(_ tab: Tab, with other: Tab) {
        guard tab.id != other.id, tab.spaceID == other.spaceID, tab.place == .open, other.place == .open,
              tabs.contains(where: { $0.id == other.id }) else { return }
        let group = other.groupID.flatMap { id in groups.first { $0.id == id } } ?? newGroup(with: other)
        guard let group else { return }
        let others = tabs(in: group).filter { $0.id != tab.id }
        let position = others.firstIndex { $0.id == other.id }.map { $0 + 1 } ?? others.count
        move(tab, into: group, at: position)
    }

    /// Moves an everyday tab into a group of its space, at `position` among
    /// the group's tabs (0-based; the count means the end). A group it
    /// leaves empty ends.
    public func move(_ tab: Tab, into group: TabGroup, at position: Int) {
        guard tab.place == .open, tab.spaceID == group.spaceID, groups.contains(where: { $0.id == group.id }),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let oldGroupID = tab.groupID
        tabs.remove(at: index)
        tab.groupID = group.id
        insert(tab, at: position, in: tabs(in: group))
        if oldGroupID != group.id { endIfEmpty(oldGroupID) }
    }

    /// Takes a tab out of its group, to `position` among the loose tabs (the
    /// top, unless dragged somewhere). A group it leaves empty ends.
    public func takeOutOfGroup(_ tab: Tab, to position: Int = 0) {
        guard let groupID = tab.groupID, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.groupID = nil
        insert(tab, at: position, in: siblings(of: tab))
        endIfEmpty(groupID)
    }

    /// Where a dragged everyday tab lands: `position` among a group's tabs,
    /// or among the loose tabs when `group` is nil (0-based, not counting
    /// the tab itself; the count means the end). A group it leaves empty ends.
    public func move(_ tab: Tab, toGroup group: TabGroup?, at position: Int) {
        guard tab.place == .open else { return }
        if let group {
            move(tab, into: group, at: position)
        } else if tab.groupID != nil {
            takeOutOfGroup(tab, to: position)
        } else {
            move(tab, to: position)
        }
    }

    /// Renames a group. A name that's blank once tidied changes nothing.
    public func rename(_ group: TabGroup, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }),
              let name = TabGroup.cleanName(name) else { return }
        groups[index].name = name
    }

    public func setFolded(_ group: TabGroup, _ folded: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].folded = folded
    }

    /// Moves a group to `position` among its space's groups (0-based; the
    /// count means the end).
    public func move(_ group: TabGroup, to position: Int) {
        guard let from = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let moving = groups.remove(at: from)
        let list = groups.filter { $0.spaceID == moving.spaceID }
        let target: Int
        if position < list.count, let before = groups.firstIndex(where: { $0.id == list[max(position, 0)].id }) {
            target = before
        } else if let last = list.last, let after = groups.firstIndex(where: { $0.id == last.id }) {
            target = after + 1
        } else {
            target = groups.count
        }
        groups.insert(moving, at: target)
    }

    /// Ends a group but keeps its tabs: they go to the top of the loose
    /// tabs, in the group's order.
    public func ungroup(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let members = tabs(in: group)
        tabs.removeAll { $0.groupID == group.id }
        for tab in members { tab.groupID = nil }
        tabs.insert(contentsOf: members, at: topOfLooseTabs(in: group.spaceID))
        groups.remove(at: index)
    }

    /// Closes a group and all its tabs. If one of them was on screen, the
    /// tab seen most recently takes its place.
    public func close(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let members = tabs(in: group)
        let wasShowing = members.contains { $0.id == activeTabID }
        for tab in members { tab.sleep() }
        tabs.removeAll { $0.groupID == group.id }
        groups.remove(at: index)
        if wasShowing {
            activeTabID = nil
            selectMostRecent()
        }
    }

    /// A group with no tabs left ends.
    private func endIfEmpty(_ groupID: UUID?) {
        guard let groupID, !tabs.contains(where: { $0.groupID == groupID }) else { return }
        groups.removeAll { $0.id == groupID }
    }

    // MARK: - What pages ask for

    private func connect(_ page: any PageController, to tab: Tab) {
        page.onRequest = { [weak self, weak tab] request in
            guard let self, let tab else { return }
            self.handle(request, from: tab)
        }
    }

    func handle(_ request: PageRequest, from tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }), !tab.isResting else { return }
        switch request {
        case let .openPage(page, inBackground):
            adopt(page, opener: tab, inBackground: inBackground)
        case let .openURL(url, inBackground):
            openTab(url, opener: tab, inBackground: inBackground)
        case .close:
            // A popup that's done (a sign-in, say) hands back to its opener.
            close(tab, showing: tabs.first { $0.id == tab.openerTabID })
        }
    }

    // MARK: - Switching

    public func select(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        activeTab?.lastActiveAt = now()
        wake(tab)
        tab.lastActiveAt = now()
        activeTabID = tab.id
    }

    /// Makes the tab's page, in its own space's data store, if it has none.
    private func wake(_ tab: Tab) {
        let dataStoreID = spaces.first { $0.id == tab.spaceID }?.dataStoreID ?? activeSpace.dataStoreID
        tab.wake {
            let page = makePage(dataStoreID)
            connect(page, to: tab)
            return page
        }
    }

    /// Shows the tab at `position` (0-based) in the sidebar, top to bottom;
    /// past the end means the last one.
    public func selectTab(at position: Int) {
        let visible = sidebarTabs
        guard !visible.isEmpty, position >= 0 else { return }
        select(visible[min(position, visible.count - 1)])
    }

    /// Shows the next tab in the sidebar (or the previous one with `by: -1`),
    /// wrapping around.
    public func selectTab(by offset: Int) {
        let visible = sidebarTabs
        guard !visible.isEmpty else { return }
        guard let current = visible.firstIndex(where: { $0.id == activeTabID }) else {
            return select(visible[0])
        }
        let count = visible.count
        select(visible[((current + offset) % count + count) % count])
    }

    // MARK: - Reordering

    /// Moves a tab to `position` in its own list (Basecamp, its group, or the
    /// loose tabs; 0-based, the count means the end). Other lists and other
    /// spaces keep their places.
    public func move(_ tab: Tab, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: from)
        insert(tab, at: position, in: siblings(of: tab))
    }

    // MARK: - Saving and restoring

    /// The session as it is now, for `SessionSaver`. The window's sidebar
    /// lives in the app, so it's passed in.
    public func session(sidebarWidth: Double, sidebarCollapsed: Bool) -> Session {
        let stamp = now()
        let records = tabs.enumerated().map { order, tab in
            var record = TabRecord(
                id: tab.id, spaceID: tab.spaceID, place: tab.place, url: tab.url,
                title: tab.savedTitle, icon: tab.icon, homeURL: tab.homeURL, groupID: tab.groupID, order: order,
                lastActiveAt: tab.lastActiveAt, openerTabID: tab.openerTabID, lastChangedAt: stamp
            )
            if let saved = savedRecords[tab.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groupRecords = groups.enumerated().map { order, group in
            var record = GroupRecord(
                id: group.id, spaceID: group.spaceID, name: group.name, order: order,
                folded: group.folded, lastChangedAt: stamp
            )
            if let saved = savedGroupRecords[group.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedGroupRecords = Dictionary(groupRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let window = WindowRecord(
            id: windowID, activeSpaceID: activeSpaceID, activeTabID: activeTabID,
            sidebarWidth: sidebarWidth, sidebarCollapsed: sidebarCollapsed
        )
        return Session(spaces: spaces, groups: groupRecords, tabs: records, window: window)
    }

    /// The saved file is Firn's own, but it's checked as if it weren't: only
    /// web addresses come back, tabs and groups must belong to a space, ids
    /// are unique, Basecamp holds no more than its limit, icons are small
    /// PNGs, group names are tidy, and only everyday tabs sit in a group of
    /// their own space. Groups left with no tabs are dropped.
    private func restore(_ session: Session) {
        let spaceIDs = Set(spaces.map(\.id))
        var seenGroups = Set<UUID>()
        let restoredGroups = session.groups.sorted { $0.order < $1.order }.compactMap { record -> TabGroup? in
            guard spaceIDs.contains(record.spaceID), seenGroups.insert(record.id).inserted else { return nil }
            return TabGroup(
                id: record.id, spaceID: record.spaceID,
                name: TabGroup.cleanName(record.name) ?? TabGroup.defaultName, folded: record.folded
            )
        }
        let groupSpaces = Dictionary(restoredGroups.map { ($0.id, $0.spaceID) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var basecampCounts: [UUID: Int] = [:]
        tabs = session.tabs.sorted { $0.order < $1.order }.compactMap { record in
            guard spaceIDs.contains(record.spaceID), seen.insert(record.id).inserted else { return nil }
            let url = record.url.flatMap(Self.webURL)
            let home = record.homeURL.flatMap(Self.webURL)
            guard url != nil || home != nil else { return nil }
            var place = record.place
            if place == .basecamp {
                basecampCounts[record.spaceID, default: 0] += 1
                if basecampCounts[record.spaceID]! > Self.basecampLimit { place = .open }
            }
            let groupID = record.groupID.flatMap { id in
                place == .open && groupSpaces[id] == record.spaceID ? id : nil
            }
            return Tab(
                id: record.id, spaceID: record.spaceID, place: place, url: url ?? home,
                title: record.title, icon: record.icon.flatMap { SiteIcon.isValidStored($0) ? $0 : nil },
                homeURL: place == .open ? nil : home, groupID: groupID,
                openerTabID: record.openerTabID, lastActiveAt: record.lastActiveAt
            )
        }
        let usedGroups = Set(tabs.compactMap(\.groupID))
        groups = restoredGroups.filter { usedGroups.contains($0.id) }
        savedRecords = Dictionary(session.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        savedGroupRecords = Dictionary(session.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        windowID = session.window.id
        if spaceIDs.contains(session.window.activeSpaceID) { activeSpaceID = session.window.activeSpaceID }
        if let id = session.window.activeTabID,
           let tab = tabs.first(where: { $0.id == id && $0.spaceID == activeSpaceID }) {
            select(tab)
        }
    }

    private static func webURL(_ url: URL) -> URL? {
        WebAddress.isWebURL(url) ? url : nil
    }
}
