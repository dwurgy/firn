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
    /// How long an everyday tab can go unseen before it's archived (a
    /// setting; the app keeps it).
    public var archiveAfter: ArchiveAfter = .sevenDays
    /// The days Firn was used, as "yyyy-MM-dd" in the Mac's calendar, oldest
    /// first: only as many as the longest setting needs.
    private var usedDays: [String] = []
    static let usedDaysKept = 30
    /// What ⇧⌘T can bring back, oldest first, each in its own space. Kept
    /// only while Firn runs, like a browser's closed-tab list.
    private var closed: [ClosedItem] = []
    /// How many closed tabs and groups are kept, across all spaces.
    static let closedLimit = 30
    /// The tab each space last had on screen, so switching back finds it.
    private var lastTabBySpace: [UUID: UUID] = [:]

    @ObservationIgnored private let makePage: @MainActor (_ dataStoreID: UUID) -> any PageController
    @ObservationIgnored private let removeData: @MainActor (_ dataStoreID: UUID) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var windowID = UUID()
    /// What each tab looked like when last saved, so a record's last-changed
    /// time only moves when the record really changed.
    @ObservationIgnored private var savedRecords: [UUID: TabRecord] = [:]
    @ObservationIgnored private var savedGroupRecords: [UUID: GroupRecord] = [:]

    /// - Parameters:
    ///   - makePage: Makes a page for a data store; `BrowserEngine.makePage` in the app.
    ///   - removeData: Erases a data store no space uses any more;
    ///     `BrowserEngine.removeData` in the app.
    ///   - now: The clock, replaceable in tests.
    public init(
        spaces: [Space],
        makePage: @escaping @MainActor (_ dataStoreID: UUID) -> any PageController,
        removeData: @escaping @MainActor (_ dataStoreID: UUID) -> Void = { _ in },
        now: @escaping () -> Date = Date.init
    ) {
        precondition(!spaces.isEmpty, "Firn always has at least one space")
        self.spaces = spaces
        self.activeSpaceID = spaces[0].id
        self.makePage = makePage
        self.removeData = removeData
        self.now = now
        renumberSpaces()
    }

    /// Picks up where the saved session left off, or starts with
    /// `defaultSpaces` if there's none. Only the tab on screen loads; the
    /// rest rest until shown.
    public convenience init(
        restoring session: Session?,
        defaultSpaces: [Space],
        makePage: @escaping @MainActor (_ dataStoreID: UUID) -> any PageController,
        removeData: @escaping @MainActor (_ dataStoreID: UUID) -> Void = { _ in },
        now: @escaping () -> Date = Date.init
    ) {
        var seen = Set<UUID>()
        let saved = (session?.spaces ?? [])
            .sorted { $0.order < $1.order }
            .filter { seen.insert($0.id).inserted }
            .map { space in
                var space = space
                space.name = Space.cleanName(space.name) ?? Space.defaultName
                return space
            }
        self.init(
            spaces: saved.isEmpty ? defaultSpaces : saved, makePage: makePage, removeData: removeData, now: now
        )
        if let session { restore(session) }
    }

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    // MARK: - Spaces

    /// Makes a space and shows it. It starts with no tabs and, unless it
    /// shares another space's sign-ins, its own empty data store: signed
    /// out of everything.
    @discardableResult
    public func addSpace(name: String, icon: String, color: String, sharingWith other: Space? = nil) -> Space {
        let shared = other.flatMap { other in spaces.first { $0.id == other.id } }
        let space = Space(
            name: Space.cleanName(name) ?? Space.defaultName, icon: icon, color: color,
            order: spaces.count, dataStoreID: shared?.dataStoreID ?? UUID(), lastChangedAt: now()
        )
        spaces.append(space)
        selectSpace(space)
        return space
    }

    /// Shows a space, on the tab it last had on screen (or the awake tab it
    /// showed most recently, or none).
    public func selectSpace(_ space: Space) {
        guard space.id != activeSpaceID, spaces.contains(where: { $0.id == space.id }) else { return }
        activeTab?.lastActiveAt = now()
        lastTabBySpace[activeSpaceID] = activeTabID
        activeSpaceID = space.id
        activeTabID = nil
        if let id = lastTabBySpace[space.id], let tab = tabs.first(where: { $0.id == id && $0.spaceID == space.id }) {
            select(tab)
        } else {
            selectMostRecent()
        }
    }

    /// Shows the space at `position` (0-based); past the end means the last one.
    public func selectSpace(at position: Int) {
        guard position >= 0 else { return }
        selectSpace(spaces[min(position, spaces.count - 1)])
    }

    /// Shows the next space (or the previous one with `by: -1`), wrapping around.
    public func selectSpace(by offset: Int) {
        guard let current = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let count = spaces.count
        selectSpace(spaces[((current + offset) % count + count) % count])
    }

    /// Changes a space's name, icon, and color. An empty name keeps the old one.
    public func updateSpace(_ space: Space, name: String, icon: String, color: String) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        var updated = spaces[index]
        updated.name = Space.cleanName(name) ?? updated.name
        updated.icon = icon
        updated.color = color
        guard updated != spaces[index] else { return }
        updated.lastChangedAt = now()
        spaces[index] = updated
    }

    /// Moves a space to `position` among the spaces (0-based; the count means the end).
    public func moveSpace(_ space: Space, to position: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let moving = spaces.remove(at: from)
        spaces.insert(moving, at: min(max(position, 0), spaces.count))
        renumberSpaces()
    }

    /// The other spaces that share this space's sign-ins, cookies, and site data.
    public func spacesSharingData(with space: Space) -> [Space] {
        guard let dataStoreID = spaces.first(where: { $0.id == space.id })?.dataStoreID else { return [] }
        return spaces.filter { $0.id != space.id && $0.dataStoreID == dataStoreID }
    }

    /// Gives a shared space a new, empty data store of its own: it starts
    /// fresh and signed out, and the spaces it shared with keep theirs.
    /// Its tabs let their pages go; the one on screen loads again at once.
    public func stopSharing(_ space: Space) {
        guard !spacesSharingData(with: space).isEmpty,
              let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[index].dataStoreID = UUID()
        spaces[index].lastChangedAt = now()
        for tab in tabs where tab.spaceID == space.id && !tab.isResting {
            tab.sleep()
            if tab.id == activeTabID { wake(tab) }
        }
    }

    /// Deletes a space: its tabs, its groups, what ⇧⌘T could bring back in
    /// it, and, if no other space shares it, its sign-ins, cookies, and site
    /// data. The last space can't be deleted. If it's on screen, the space
    /// below it (or above, if it's last) is shown first.
    public func deleteSpace(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let deleted = spaces[index]
        if deleted.id == activeSpaceID {
            selectSpace(spaces[index + 1 < spaces.count ? index + 1 : index - 1])
        }
        for tab in tabs where tab.spaceID == deleted.id { tab.sleep() }
        tabs.removeAll { $0.spaceID == deleted.id }
        groups.removeAll { $0.spaceID == deleted.id }
        closed.removeAll { $0.spaceID == deleted.id }
        lastTabBySpace[deleted.id] = nil
        spaces.remove(at: index)
        renumberSpaces()
        if !spaces.contains(where: { $0.dataStoreID == deleted.dataStoreID }) {
            removeData(deleted.dataStoreID)
        }
    }

    /// Keeps each space's `order` matching its place in `spaces`.
    private func renumberSpaces() {
        for index in spaces.indices where spaces[index].order != index {
            spaces[index].order = index
            spaces[index].lastChangedAt = now()
        }
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
    /// The current space's archived tabs, the most recently archived first.
    public var archivedTabs: [Tab] { list(.archived).reversed() }

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

    /// Opens a copy of an everyday tab right below it, in its group if it has
    /// one, and shows it. The copy loads its address fresh (back/forward
    /// history isn't copied) and stays in the same space and data store.
    @discardableResult
    public func duplicate(_ tab: Tab) -> Tab? {
        guard tab.place == .open, let url = tab.url,
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let copy = Tab(
            spaceID: tab.spaceID, url: url, title: tab.title, icon: tab.icon,
            groupID: tab.groupID, lastActiveAt: now()
        )
        tabs.insert(copy, at: index + 1)
        select(copy)
        return copy
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

    /// Shows the awake tab in this space that was on screen most recently, if
    /// any, preferring one the sidebar shows. A tab hidden in a folded group
    /// opens its group, so the tab on screen never vanishes.
    private func selectMostRecent() {
        let awake = tabs.filter { $0.spaceID == activeSpaceID && !$0.isResting }
        let shown = Set(sidebarTabs.map(\.id))
        let byRecent = { (a: Tab, b: Tab) in a.lastActiveAt < b.lastActiveAt }
        guard let recent = awake.filter({ shown.contains($0.id) }).max(by: byRecent) ?? awake.max(by: byRecent)
        else { return }
        if let group = groups.first(where: { $0.id == recent.groupID }), group.folded { setFolded(group, false) }
        select(recent)
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
        let group = TabGroup(spaceID: tab.spaceID, name: freeGroupName(in: tab.spaceID))
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

    /// Moves an everyday tab to the end of a group (right-click › Move to
    /// Group). A folded group opens if the tab is the one on screen, so it
    /// doesn't vanish.
    public func move(_ tab: Tab, toEndOf group: TabGroup) {
        guard tab.groupID != group.id else { return }
        move(tab, into: group, at: tabs(in: group).count)
        if tab.groupID == group.id, tab.id == activeTabID,
           groups.first(where: { $0.id == group.id })?.folded == true {
            setFolded(group, false)
        }
    }

    /// Takes a tab out of its group: to `position` in the tab list when
    /// dragged, otherwise right below the group, so it doesn't fly off to
    /// where new tabs go (David, 2026-10-19). A group it leaves empty ends.
    public func takeOutOfGroup(_ tab: Tab, to position: Int? = nil) {
        guard let groupID = tab.groupID, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.groupID = nil
        if let position {
            insertInTabList([tab], at: position, fallback: index)
        } else {
            // Right below what's left of the group (or where it was).
            let below = tabs.lastIndex { $0.groupID == groupID }.map { $0 + 1 } ?? index
            tabs.insert(tab, at: below)
        }
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

    /// Ends a group but keeps its tabs, right where the card was, in the
    /// group's order.
    public func ungroup(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        // Its tabs stay right where the card was.
        for tab in tabs(in: group) { tab.groupID = nil }
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

    /// "New Group", or "New Group 2", 3, … if this space already has one,
    /// so Move to Group never lists two the same (until groups name
    /// themselves). The lowest number not in use, as Finder does.
    private func freeGroupName(in spaceID: UUID) -> String {
        let taken = Set(groups.filter { $0.spaceID == spaceID }.map(\.name))
        var name = TabGroup.defaultName
        var number = 2
        while taken.contains(name) {
            name = "\(TabGroup.defaultName) \(number)"
            number += 1
        }
        return name
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
        case let .tab(tab, position, listPosition):
            tab.place = .open
            if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
                insert(tab, at: position, in: tabs(in: group), fallback: arrivalIndex(in: tab.spaceID))
                setFolded(group, false)
            } else {
                tab.groupID = nil
                insertInTabList([tab], at: listPosition, fallback: arrivalIndex(in: tab.spaceID))
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

    /// Remembers an everyday or archived tab about to close. The last tab of a group
    /// ends the group, so the group is remembered instead, whole.
    private func rememberClosing(_ tab: Tab) {
        guard tab.place != .basecamp, tab.url != nil else { return }
        if let groupID = tab.groupID, let group = groups.first(where: { $0.id == groupID }) {
            let members = tabs(in: group)
            if members.count == 1 { return rememberClosing(group, members: members) }
            remember(.tab(
                tab, position: members.firstIndex { $0.id == tab.id } ?? members.count,
                listPosition: tabListPosition(of: groupID, in: tab.spaceID)
            ))
        } else {
            // An archived tab comes back where new tabs go.
            let position = tab.place == .archived && newTabPlacement == .top
                ? 0 : tabListPosition(of: tab.id, in: tab.spaceID)
            remember(.tab(tab, position: position, listPosition: position))
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

    // MARK: - Archiving

    /// Counts today as a day Firn was used, then archives every loose tab
    /// that hasn't been on screen for the set number of those days. Days
    /// away from Firn don't count. Never archived: Basecamp tiles, grouped
    /// tabs, and the tab on screen. (Later, also a tab playing sound or in
    /// split view.) Archived tabs let their pages go, so they cost nothing;
    /// they keep their address, title, and icon until closed.
    public func archiveIdleTabs() {
        let today = Self.day(of: now())
        if !usedDays.contains(today) {
            usedDays = Array((usedDays + [today]).sorted().suffix(Self.usedDaysKept))
        }
        guard let limit = archiveAfter.days else { return }
        let idle = tabs.filter { tab in
            guard tab.place == .open, tab.groupID == nil, tab.id != activeTabID else { return false }
            let lastSeen = Self.day(of: tab.lastActiveAt)
            return usedDays.count { $0 > lastSeen } >= limit
        }
        guard !idle.isEmpty else { return }
        let ids = Set(idle.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        for tab in idle {
            tab.sleep()
            tab.place = .archived
        }
        tabs.append(contentsOf: idle)
        lastTabBySpace = lastTabBySpace.filter { !ids.contains($0.value) }
    }

    /// A date's day in the Mac's calendar, as "yyyy-MM-dd" (which sorts by date).
    private static func day(of date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Keeps only well-formed days, each once, in order.
    private static func cleanDays(_ days: [String]) -> [String] {
        let wellFormed = days.filter { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil }
        return Array(Set(wellFormed).sorted().suffix(usedDaysKept))
    }

    // MARK: - Switching

    /// Shows a tab. An archived one comes back first, where new tabs go.
    public func select(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if tab.place == .archived {
            tabs.remove(at: index)
            tab.place = .open
            tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
        }
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
            spaceTabIDs: lastTabBySpace.filter { $0.key != activeSpaceID },
            sidebarWidth: sidebarWidth, sidebarCollapsed: sidebarCollapsed
        )
        return Session(spaces: spaces, groups: groupRecords, tabs: records, window: window, usedDays: usedDays)
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
                homeURL: place == .basecamp ? home : nil, groupID: groupID,
                openerTabID: record.openerTabID, lastActiveAt: record.lastActiveAt
            )
        }
        tabs = Self.keepingGroupsTogether(tabs)
        let usedGroups = Set(tabs.compactMap(\.groupID))
        groups = restoredGroups.filter { usedGroups.contains($0.id) }
        savedRecords = Dictionary(session.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        savedGroupRecords = Dictionary(session.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        usedDays = Self.cleanDays(session.usedDays)
        windowID = session.window.id
        if spaceIDs.contains(session.window.activeSpaceID) { activeSpaceID = session.window.activeSpaceID }
        let tabSpaces = Dictionary(tabs.map { ($0.id, $0.spaceID) }, uniquingKeysWith: { first, _ in first })
        lastTabBySpace = session.window.spaceTabIDs.filter { tabSpaces[$0.value] == $0.key }
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
/// place among its group's tabs (or in the tab list, if loose) and its
/// group's place in the tab list (where it goes if the group is gone), or a
/// group's place in the tab list. The tabs are the closed ones, asleep.
@MainActor
private enum ClosedItem {
    case tab(Tab, position: Int, listPosition: Int)
    case group(TabGroup, [Tab], position: Int)

    /// Each only ever comes back in its own space, so nothing crosses
    /// between spaces.
    var spaceID: UUID {
        switch self {
        case let .tab(tab, _, _): tab.spaceID
        case let .group(group, _, _): group.spaceID
        }
    }
}

/// Where new tabs go in the tab list.
public enum NewTabPlacement: String, CaseIterable, Sendable {
    case top, bottom
}

/// How long an everyday tab can go unseen before it's archived, counted in
/// days Firn was used.
public enum ArchiveAfter: String, CaseIterable, Sendable {
    case oneDay, sevenDays, thirtyDays, never

    public var days: Int? {
        switch self {
        case .oneDay: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        case .never: nil
        }
    }
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
