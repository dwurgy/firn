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
    /// Every group in every space. A group sits in the tab list where its
    /// tabs are, so this list's own order means nothing.
    public private(set) var groups: [TabGroup] = []
    /// Every tab in every space; each list (Basecamp, a group, the tab list)
    /// keeps this order. A group's tabs always sit side by side in it, so
    /// this one order also places the groups among the loose tabs.
    public private(set) var tabs: [Tab] = []
    public private(set) var activeSpaceID: UUID
    public private(set) var activeTabID: UUID?
    /// Where new tabs go in a space's tab list (a setting; the app keeps it).
    /// Tabs taken out of a group, ungrouped, or taken off Basecamp go there too.
    public var newTabPlacement: NewTabPlacement = .bottom
    /// What ⇧⌘T can bring back, oldest first, each in its own space. Kept
    /// only while Firn runs, like a browser's closed-tab list.
    private var closed: [ClosedItem] = []
    /// How many closed tabs and groups are kept, across all spaces.
    static let closedLimit = 30

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
    /// The current space's tab list below Basecamp, top to bottom: groups
    /// and loose tabs in one order.
    public var tabListItems: [TabListItem] { items(in: activeSpaceID) }
    /// The current space's groups, in order.
    public var tabGroups: [TabGroup] {
        tabListItems.compactMap { if case let .group(group) = $0 { group } else { nil } }
    }
    /// The current space's loose tabs (everyday tabs in no group), in order.
    public var looseTabs: [Tab] { list(.open).filter { $0.groupID == nil } }
    /// All the current space's everyday tabs, grouped or not, in order.
    public var openTabs: [Tab] { list(.open) }

    /// A group's tabs, in order.
    public func tabs(in group: TabGroup) -> [Tab] {
        tabs.filter { $0.groupID == group.id }
    }

    /// The tab rows the current space's sidebar shows, top to bottom:
    /// Basecamp, then the tab list (folded groups hide theirs).
    public var sidebarTabs: [Tab] {
        let folded = Set(groups.filter(\.folded).map(\.id))
        return basecampTabs + openTabs.filter { $0.groupID.map { !folded.contains($0) } ?? true }
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

    /// A space's tab list: each group once, where its tabs are, and the
    /// loose tabs.
    private func items(in spaceID: UUID) -> [TabListItem] {
        var seen = Set<UUID>()
        return list(.open, in: spaceID).compactMap { tab in
            guard let groupID = tab.groupID else { return .tab(tab) }
            guard seen.insert(groupID).inserted, let group = groups.first(where: { $0.id == groupID }) else { return nil }
            return .group(group)
        }
    }

    /// Where tabs arriving in a space's tab list go: the top (above any
    /// group) or the bottom (below every group), as set.
    private func arrivalIndex(in spaceID: UUID) -> Int {
        let isListed = { (tab: Tab) in tab.spaceID == spaceID && tab.place == .open }
        switch newTabPlacement {
        case .top: return tabs.firstIndex(where: isListed) ?? tabs.count
        case .bottom: return tabs.lastIndex(where: isListed).map { $0 + 1 } ?? tabs.count
        }
    }

    /// The same place, counted in the tab list (each group as one).
    private var arrivalPosition: Int { newTabPlacement == .top ? 0 : .max }

    /// Puts a tab (already out of `tabs`) at `position` in `list` (0-based;
    /// the count, or more, means the end). With an empty list it goes back
    /// to `fallback`.
    private func insert(_ tab: Tab, at position: Int, in list: [Tab], fallback: Int? = nil) {
        let target: Int
        if position < list.count, let before = tabs.firstIndex(where: { $0.id == list[max(position, 0)].id }) {
            target = before
        } else if let last = list.last, let after = tabs.firstIndex(where: { $0.id == last.id }) {
            target = after + 1
        } else {
            target = min(fallback ?? tabs.count, tabs.count)
        }
        tabs.insert(tab, at: target)
    }

    /// Puts tabs (already out of `tabs`, all loose or all one group's) at
    /// `position` in their space's tab list (0-based, counting each group
    /// as one; the count, or more, means the end). Never splits a group.
    private func insertInTabList(_ moving: [Tab], at position: Int, fallback: Int) {
        guard let spaceID = moving.first?.spaceID else { return }
        let items = items(in: spaceID)
        func indexes(of item: TabListItem) -> [Int] {
            tabs.indices.filter { index in
                switch item {
                case let .tab(tab): tabs[index].id == tab.id
                case let .group(group): tabs[index].groupID == group.id
                }
            }
        }
        let target: Int
        if position < items.count, let before = indexes(of: items[max(position, 0)]).first {
            target = before
        } else if let last = items.last, let after = indexes(of: last).last {
            target = after + 1
        } else {
            target = min(fallback, tabs.count)
        }
        tabs.insert(contentsOf: moving, at: target)
    }

    // MARK: - Opening and closing

    /// Opens `url` in a new tab and shows it, or with `inBackground` stays
    /// put; the tab then loads the first time it's shown. (Pages loaded before
    /// they've ever been on screen took seconds to appear when shown.) With
    /// an `opener`, the tab joins the opener's space (see `add`); otherwise
    /// it goes at the top or bottom of the current space's tab list, as set.
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

    /// Links from an everyday tab open right below it, in its group if it
    /// has one (as in Dia); links from a Basecamp tile open at the top or
    /// bottom of the tab list, as set. Either way, several links from one
    /// tab stay in the order they were opened.
    private func add(_ tab: Tab, below opener: Tab?, inBackground: Bool) {
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            var position: Int
            if opener.place == .open {
                tab.groupID = opener.groupID
                position = index + 1
            } else {
                position = arrivalIndex(in: opener.spaceID)
            }
            // Past the links it opened before, staying in the same list.
            while position < tabs.count, tabs[position].openerTabID == opener.id,
                  tabs[position].groupID == tab.groupID {
                position += 1
            }
            tabs.insert(tab, at: position)
        } else {
            tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
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
        close(tab, showing: next, remembering: true)
    }

    /// `remembering`: whether ⇧⌘T can bring it back (not a popup that
    /// closed itself).
    private func close(_ tab: Tab, showing next: Tab?, remembering: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let siblings = siblings(of: tab)
        let position = tab.place == .open ? siblings.firstIndex { $0.id == tab.id } : nil
        if remembering { rememberClosing(tab) }
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

    /// An awake tile becomes a loose tab where new tabs go, so its page
    /// isn't lost. A resting one has nothing open to keep, so it goes.
    public func removeFromBasecamp(_ tab: Tab) {
        guard tab.place == .basecamp, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        guard !tab.isResting else { return }
        tab.place = .open
        tab.homeURL = nil
        tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
    }

    /// Takes a Basecamp tile back to its home address, and shows it.
    public func goHome(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }), tab.homeURL != nil else { return }
        tab.goHome()
        select(tab)
    }

    // MARK: - Groups

    /// Starts a group with an everyday tab, where the tab already is. A tab
    /// taken from another group starts its new one just below that group.
    @discardableResult
    public func newGroup(with tab: Tab) -> TabGroup? {
        guard tab.place == .open, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let group = TabGroup(spaceID: tab.spaceID)
        groups.append(group)
        let oldGroupID = tab.groupID
        tab.groupID = group.id
        if let oldGroupID {
            tabs.remove(at: index)
            let below = tabs.lastIndex { $0.groupID == oldGroupID }.map { $0 + 1 } ?? index
            tabs.insert(tab, at: below)
            endIfEmpty(oldGroupID)
        }
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
        insert(tab, at: position, in: tabs(in: group), fallback: index)
        if oldGroupID != group.id { endIfEmpty(oldGroupID) }
    }

    /// Takes a tab out of its group, to `position` in the tab list (where
    /// new tabs go, unless dragged somewhere). A group it leaves empty ends.
    public func takeOutOfGroup(_ tab: Tab, to position: Int? = nil) {
        guard let groupID = tab.groupID, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.groupID = nil
        insertInTabList([tab], at: position ?? arrivalPosition, fallback: index)
        endIfEmpty(groupID)
    }

    /// Where a dragged everyday tab lands: `position` among a group's tabs,
    /// or in the tab list when `group` is nil (0-based, not counting the tab
    /// itself, and counting each group as one; the count means the end). A
    /// group it leaves empty ends.
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

    /// Moves a group, with all its tabs, to `position` in its space's tab
    /// list (0-based, not counting the group itself, and counting each
    /// group as one; the count means the end).
    public func move(_ group: TabGroup, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.groupID == group.id }) else { return }
        let members = tabs(in: group)
        tabs.removeAll { $0.groupID == group.id }
        insertInTabList(members, at: position, fallback: from)
    }

    /// Ends a group but keeps its tabs: they go where new tabs go, in the
    /// group's order.
    public func ungroup(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let members = tabs(in: group)
        tabs.removeAll { $0.groupID == group.id }
        for tab in members { tab.groupID = nil }
        tabs.insert(contentsOf: members, at: arrivalIndex(in: group.spaceID))
        groups.remove(at: index)
    }

    /// Closes a group and all its tabs. If one of them was on screen, the
    /// tab seen most recently takes its place.
    public func close(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let members = tabs(in: group)
        let wasShowing = members.contains { $0.id == activeTabID }
        // So the tab on screen is the one shown again if the group comes back.
        if wasShowing { activeTab?.lastActiveAt = now() }
        rememberClosing(groups[index], members: members)
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

    // MARK: - Reopening

    /// What ⇧⌘T would bring back in the current space, if anything.
    public var nextToReopen: ReopenKind? {
        switch closed.last(where: { $0.spaceID == activeSpaceID }) {
        case .tab: .tab
        case .group: .group
        case nil: nil
        }
    }

    /// Brings back the tab or group closed most recently in the current
    /// space, where it was, and shows it. A tab goes back into its group
    /// if the group is still there (or loose, where it was, if not); a
    /// group comes back whole, open, showing the tab last on screen.
    /// Closed tabs come back asleep, so they load again from their address.
    public func reopenClosed() {
        guard let index = closed.lastIndex(where: { $0.spaceID == activeSpaceID }) else { return }
        switch closed.remove(at: index) {
        case let .tab(tab, position):
            if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
                insert(tab, at: position, in: tabs(in: group), fallback: arrivalIndex(in: tab.spaceID))
                setFolded(group, false)
            } else {
                tab.groupID = nil
                insertInTabList([tab], at: position, fallback: arrivalIndex(in: tab.spaceID))
            }
            select(tab)
        case let .group(group, members, position):
            guard !groups.contains(where: { $0.id == group.id }) else { return }
            var group = group
            group.folded = false
            groups.append(group)
            insertInTabList(members, at: position, fallback: arrivalIndex(in: group.spaceID))
            if let recent = members.max(by: { $0.lastActiveAt < $1.lastActiveAt }) { select(recent) }
        }
    }

    /// Remembers an everyday tab about to close. The last tab of a group
    /// ends the group, so the group is remembered instead, whole.
    private func rememberClosing(_ tab: Tab) {
        guard tab.place == .open, tab.url != nil else { return }
        if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
            let members = tabs(in: group)
            if members.count == 1 { return rememberClosing(group, members: members) }
            remember(.tab(tab, position: members.firstIndex { $0.id == tab.id } ?? members.count))
        } else {
            remember(.tab(tab, position: tabListPosition(of: tab.id, in: tab.spaceID)))
        }
    }

    private func rememberClosing(_ group: TabGroup, members: [Tab]) {
        let members = members.filter { $0.url != nil }
        guard !members.isEmpty else { return }
        remember(.group(group, members, position: tabListPosition(of: group.id, in: group.spaceID)))
    }

    private func remember(_ item: ClosedItem) {
        closed.append(item)
        if closed.count > Self.closedLimit { closed.removeFirst(closed.count - Self.closedLimit) }
    }

    /// Where a loose tab or group sits in its space's tab list (each group
    /// counting as one).
    private func tabListPosition(of id: UUID, in spaceID: UUID) -> Int {
        let items = items(in: spaceID)
        return items.firstIndex { $0.id == id } ?? items.count
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
            close(tab, showing: tabs.first { $0.id == tab.openerTabID }, remembering: false)
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

    /// Moves a tab to `position` in its own list (Basecamp, its group, or,
    /// for a loose tab, the tab list, counting each group as one; 0-based,
    /// the count means the end). Other lists and other spaces keep their
    /// places.
    public func move(_ tab: Tab, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: from)
        if tab.place == .open, tab.groupID == nil {
            insertInTabList([tab], at: position, fallback: from)
        } else {
            insert(tab, at: position, in: siblings(of: tab), fallback: from)
        }
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
    /// their own space. Groups left with no tabs are dropped, and a group's
    /// tabs are put back together where its first one is.
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
        tabs = Self.keepingGroupsTogether(tabs)
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

    /// The same tabs, with each group's tabs side by side where its first one is.
    private static func keepingGroupsTogether(_ tabs: [Tab]) -> [Tab] {
        let members = Dictionary(grouping: tabs.filter { $0.groupID != nil }, by: { $0.groupID! })
        var placed = Set<UUID>()
        return tabs.flatMap { tab -> [Tab] in
            guard let groupID = tab.groupID else { return [tab] }
            return placed.insert(groupID).inserted ? members[groupID] ?? [] : []
        }
    }

    private static func webURL(_ url: URL) -> URL? {
        WebAddress.isWebURL(url) ? url : nil
    }
}

/// What ⇧⌘T brings back next: a tab, or a whole group.
public enum ReopenKind: Sendable {
    case tab, group
}

/// A closed tab or group ⇧⌘T can bring back, and where it was: a tab's
/// place among its group's tabs (or in the tab list, if loose), or a
/// group's place in the tab list. The tabs are the closed ones, asleep.
@MainActor
private enum ClosedItem {
    case tab(Tab, position: Int)
    case group(TabGroup, [Tab], position: Int)

    /// Each only ever comes back in its own space, so nothing crosses
    /// between spaces.
    var spaceID: UUID {
        switch self {
        case let .tab(tab, _): tab.spaceID
        case let .group(group, _, _): group.spaceID
        }
    }
}

/// Where new tabs go in the tab list.
public enum NewTabPlacement: String, CaseIterable, Sendable {
    case top, bottom
}

/// One thing in a space's tab list: a group (shown as one card) or a loose tab.
@MainActor
public enum TabListItem: @MainActor Identifiable {
    case group(TabGroup)
    case tab(Tab)

    public var id: UUID {
        switch self {
        case let .group(group): group.id
        case let .tab(tab): tab.id
        }
    }
}
