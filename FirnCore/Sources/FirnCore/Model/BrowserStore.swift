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
    /// Every split view in every space. Its two tabs sit side by side in
    /// `tabs`, left first, in the same group if any.
    public private(set) var splits: [SplitGroup] = []
    public private(set) var activeSpaceID: UUID
    public private(set) var activeTabID: UUID?
    /// The link preview over the tab on screen, if one is open. Showing
    /// another tab or space closes it.
    public private(set) var lookout: Lookout?
    /// Where new tabs go in a space's tab list (a setting; the app keeps it).
    /// Tabs taken out of a group, ungrouped, or taken off Basecamp go there too.
    public var newTabPlacement: NewTabPlacement = .bottom
    /// How long an everyday tab can go unseen before it drifts (a setting;
    /// the app keeps it).
    public var driftAfter: DriftAfter = .sevenDays
    /// The spaces with tabs tidied away since the overflow was last opened
    /// there (the overflow button shows a dot).
    private var unseenTidiedSpaces: Set<UUID> = []
    /// Drifted tabs are deleted this many calendar days after they drift.
    static let driftedKeptDays = 30
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
    @ObservationIgnored private var savedSplitRecords: [UUID: SplitRecord] = [:]

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
        closeLookout()
        for id in onScreenTabIDs { tabs.first { $0.id == id }?.lastActiveAt = now() }
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
        if lookout?.spaceID == space.id { closeLookout() }
        let onScreen = onScreenTabIDs
        for tab in tabs where tab.spaceID == space.id && !tab.isResting {
            tab.sleep()
            if onScreen.contains(tab.id) { wake(tab) }
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
        splits.removeAll { $0.spaceID == deleted.id }
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
    /// The current space's drifted tabs, the most recently drifted first.
    public var driftedTabs: [Tab] { list(.drifted).reversed() }
    /// Whether tabs were tidied away in this space since its overflow was
    /// last opened.
    public var hasUnseenTidied: Bool {
        unseenTidiedSpaces.contains(activeSpaceID) && !driftedTabs.isEmpty
    }

    /// The overflow was opened: this space's tidied tabs have been seen.
    public func markTidiedSeen() {
        unseenTidiedSpaces.remove(activeSpaceID)
    }

    /// A group's tabs, in order.
    public func tabs(in group: TabGroup) -> [Tab] {
        tabs.filter { $0.groupID == group.id }
    }

    /// A group's rows, in order: a split shows as one, its left half
    /// standing for both.
    public func rows(in group: TabGroup) -> [Tab] {
        Self.rows(tabs(in: group))
    }

    /// Tabs as the sidebar's rows: each split once, as its first half.
    /// Halves of `skipping` are left out (a split being moved).
    private static func rows(_ list: [Tab], skipping splitID: UUID? = nil) -> [Tab] {
        var seen = Set<UUID>()
        return list.filter { tab in
            guard let id = tab.splitID else { return true }
            return id != splitID && seen.insert(id).inserted
        }
    }

    /// The tab rows the current space's sidebar shows, top to bottom:
    /// Basecamp, then the tab list (folded groups hide theirs).
    public var sidebarTabs: [Tab] {
        let folded = Set(groups.filter(\.folded).map(\.id))
        return basecampTabs + openTabs.filter { $0.groupID.map { !folded.contains($0) } ?? true }
    }

    /// The sidebar's rows, top to bottom, as ⌘1–9 and ⌃Tab count them: like
    /// `sidebarTabs`, but each split once, as its left half.
    public var sidebarRows: [Tab] { Self.rows(sidebarTabs) }

    public var canAddToBasecamp: Bool { basecampTabs.count < Self.basecampLimit }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    private func list(_ place: Tab.Place, in spaceID: UUID? = nil) -> [Tab] {
        let spaceID = spaceID ?? activeSpaceID
        return tabs.filter { $0.spaceID == spaceID && $0.place == place }
    }

    /// The list a tab sits in: its space's Basecamp, its group, its space's
    /// loose tabs, or its space's drifted tabs.
    private func siblings(of tab: Tab) -> [Tab] {
        if let groupID = tab.groupID { return tabs.filter { $0.groupID == groupID } }
        let list = list(tab.place, in: tab.spaceID)
        return tab.place == .open ? list.filter { $0.groupID == nil } : list
    }

    /// A space's tab list: each group once, where its tabs are, and the
    /// loose tabs (each split once, as its left half). Halves of `skipping`
    /// are left out (a split being moved).
    private func items(in spaceID: UUID, skipping splitID: UUID? = nil) -> [TabListItem] {
        var seen = Set<UUID>()
        return list(.open, in: spaceID).compactMap { tab in
            guard let groupID = tab.groupID else {
                if let id = tab.splitID, id == splitID || !seen.insert(id).inserted { return nil }
                return .tab(tab)
            }
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
        } else if let last = list.last, let after = lastIndex(withSplitOf: last) {
            target = after + 1
        } else {
            target = min(fallback ?? tabs.count, tabs.count)
        }
        tabs.insert(tab, at: target)
    }

    /// Puts tabs (already out of `tabs`, all loose or all one group's) at
    /// `position` in their space's tab list (0-based, counting each group
    /// and split as one; the count, or more, means the end). Never splits
    /// a group, or a split (the other half of a moving one is skipped).
    private func insertInTabList(_ moving: [Tab], at position: Int, fallback: Int) {
        guard let spaceID = moving.first?.spaceID else { return }
        let items = items(in: spaceID, skipping: moving.count == 1 ? moving[0].splitID : nil)
        func indexes(of item: TabListItem) -> [Int] {
            tabs.indices.filter { index in
                switch item {
                case let .tab(tab): tabs[index].id == tab.id || (tab.splitID != nil && tabs[index].splitID == tab.splitID)
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

    /// Opens a copy of an everyday tab right below it (below its split, if
    /// it's in one), in its group if it has one, and shows it. The copy loads its address fresh (back/forward
    /// history isn't copied) and stays in the same space and data store.
    @discardableResult
    public func duplicate(_ tab: Tab) -> Tab? {
        guard tab.place == .open, let url = tab.url, let index = lastIndex(withSplitOf: tab) else { return nil }
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
    /// has one (as in Dia), and below its split if it's in one; links from a Basecamp tile open at the top or
    /// bottom of the tab list, as set. Either way, several links from one
    /// tab stay in the order they were opened.
    private func add(_ tab: Tab, below opener: Tab?, inBackground: Bool) {
        if let opener, let index = lastIndex(withSplitOf: opener) {
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
    /// place until clicked. A split it was in ends. If it was on screen,
    /// `next` is shown if it's still there, or else the other half of its
    /// split; otherwise, for an everyday tab, the one below it in its
    /// group or the loose tabs (or above, if it was last); failing that, the
    /// tab in this space that was on screen most recently.
    public func close(_ tab: Tab, showing next: Tab? = nil) {
        close(tab, showing: next, remembering: true)
    }

    /// Close on a tile's menu: it leaves Basecamp altogether, rather than
    /// resting there. ⇧⌘T brings it back to its place among the tiles.
    public func closeTile(_ tab: Tab) {
        guard tab.place == .basecamp else { return }
        close(tab, showing: nil, remembering: true, leavingBasecamp: true)
    }

    /// `remembering`: whether ⇧⌘T can bring it back (not a popup that
    /// closed itself). `leavingBasecamp`: a tile goes, rather than resting.
    private func close(_ tab: Tab, showing next: Tab?, remembering: Bool, leavingBasecamp: Bool = false) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        let partner = endSplit(of: tab)
        let next = next ?? partner
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let siblings = siblings(of: tab)
        let position = tab.place == .open ? siblings.firstIndex { $0.id == tab.id } : nil
        if remembering {
            if leavingBasecamp { rememberClosingTile(tab) } else { rememberClosing(tab) }
        }
        tab.sleep()
        if tab.place != .basecamp || leavingBasecamp {
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

    // MARK: - Groups

    /// Starts a group with an everyday tab, where the tab already is. A tab
    /// taken from another group starts its new one just below that group.
    /// The other half of its split comes too.
    @discardableResult
    public func newGroup(with tab: Tab) -> TabGroup? {
        guard tab.place == .open, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let group = TabGroup(spaceID: tab.spaceID, name: freeGroupName(in: tab.spaceID))
        groups.append(group)
        movingSplit(of: tab) {
            let oldGroupID = tab.groupID
            tab.groupID = group.id
            if let oldGroupID {
                tabs.remove(at: index)
                let below = tabs.lastIndex { $0.groupID == oldGroupID }.map { $0 + 1 } ?? index
                tabs.insert(tab, at: below)
                endIfEmpty(oldGroupID)
            }
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
    /// leaves empty ends. The other half of its split comes too.
    public func move(_ tab: Tab, into group: TabGroup, at position: Int) {
        guard tab.place == .open, tab.spaceID == group.spaceID, groups.contains(where: { $0.id == group.id }),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        movingSplit(of: tab) {
            let oldGroupID = tab.groupID
            tabs.remove(at: index)
            tab.groupID = group.id
            insert(tab, at: position, in: Self.rows(tabs(in: group), skipping: tab.splitID), fallback: index)
            if oldGroupID != group.id { endIfEmpty(oldGroupID) }
        }
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
    /// The other half of its split comes too.
    public func takeOutOfGroup(_ tab: Tab, to position: Int? = nil) {
        guard let groupID = tab.groupID, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        movingSplit(of: tab) {
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
        keepSplitsTogether()
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
        for tab in members {
            _ = endSplit(of: tab)
            tab.sleep()
        }
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

    // MARK: - Split view

    /// The split view a tab is half of, if any.
    public func split(of tab: Tab) -> SplitGroup? {
        guard let splitID = tab.splitID else { return nil }
        return splits.first { $0.id == splitID }
    }

    /// A split's two tabs, left then right.
    public func tabs(in split: SplitGroup) -> [Tab] {
        tabs.filter { $0.splitID == split.id }
    }

    /// The other half of a tab's split, if it's in one.
    public func splitPartner(of tab: Tab) -> Tab? {
        guard let splitID = tab.splitID else { return nil }
        return tabs.first { $0.splitID == splitID && $0.id != tab.id }
    }

    /// Shows `incoming` beside `anchor`, on `side`, in split view, with
    /// `incoming` the one in use. `anchor` stays where it is, and `incoming`
    /// joins it there, in its group. A Basecamp tile is never moved: a copy
    /// of its page goes in the tab list instead (for `anchor`, where new
    /// tabs go). A tidied-away tab comes back. If `anchor` was already in a
    /// split, its other half leaves, right below the new pair (so dropping
    /// a tab on one half replaces that half); a split `incoming` was in ends.
    @discardableResult
    public func openSplit(_ incoming: Tab, beside anchor: Tab, on side: SplitSide = .right) -> SplitGroup? {
        guard incoming.id != anchor.id, incoming.spaceID == anchor.spaceID,
              tabs.contains(where: { $0.id == incoming.id }), tabs.contains(where: { $0.id == anchor.id })
        else { return nil }
        // Already a pair: only the sides can change.
        if let split = split(of: anchor), incoming.splitID == split.id {
            let pair = tabs(in: split)
            if (side == .left) != (pair.first?.id == incoming.id), let from = tabs.firstIndex(where: { $0.id == incoming.id }) {
                tabs.remove(at: from)
                let at = tabs.firstIndex { $0.id == anchor.id }!
                tabs.insert(incoming, at: side == .left ? at : at + 1)
            }
            select(incoming)
            return split
        }
        let anchor = everyday(anchor, at: arrivalIndex(in: anchor.spaceID))
        let displaced = endSplit(of: anchor)
        _ = endSplit(of: incoming)
        let incoming = everyday(incoming, at: nil)
        if let from = tabs.firstIndex(where: { $0.id == incoming.id }) { tabs.remove(at: from) }
        let oldGroupID = incoming.groupID
        incoming.groupID = anchor.groupID
        let at = tabs.firstIndex { $0.id == anchor.id }!
        tabs.insert(incoming, at: side == .left ? at : at + 1)
        if oldGroupID != anchor.groupID { endIfEmpty(oldGroupID) }
        let split = SplitGroup(spaceID: anchor.spaceID)
        splits.append(split)
        anchor.splitID = split.id
        incoming.splitID = split.id
        // The displaced half goes right below the new pair.
        if let displaced, let from = tabs.firstIndex(where: { $0.id == displaced.id }) {
            tabs.remove(at: from)
            tabs.insert(displaced, at: lastIndex(withSplitOf: anchor)! + 1)
        }
        select(incoming)
        return split
    }

    /// Whether `tab` can be dragged onto the page to open it in split view:
    /// not what's already on screen, not a split (it's two pages already),
    /// and not while a Lookout is open over the page.
    public func canDropOnPage(_ tab: Tab) -> Bool {
        guard lookout == nil, let active = activeTab, active.spaceID == tab.spaceID else { return false }
        return tab.splitID == nil && !onScreenTabIDs.contains(tab.id)
    }

    /// Opens `tab` on `side` of the page: beside the tab on screen, or, in
    /// a split, in place of that half (the other half stays).
    @discardableResult
    public func dropOnPage(_ tab: Tab, on side: SplitSide) -> SplitGroup? {
        guard canDropOnPage(tab), let active = activeTab else { return nil }
        var anchor = active
        if let split = split(of: active) {
            let pair = tabs(in: split)
            guard pair.count == 2 else { return nil }
            anchor = side == .left ? pair[1] : pair[0]
        }
        return openSplit(tab, beside: anchor, on: side)
    }

    /// An everyday tab for a split: the tab itself (a drifted one comes back
    /// first), or for a Basecamp tile, a copy of its page, placed at
    /// `index` (or nowhere yet, if nil).
    private func everyday(_ tab: Tab, at index: Int?) -> Tab {
        switch tab.place {
        case .open:
            return tab
        case .drifted:
            bringBack(tab)
            return tab
        case .basecamp:
            let copy = Tab(spaceID: tab.spaceID, url: tab.url, title: tab.title, icon: tab.icon, lastActiveAt: now())
            if let index { tabs.insert(copy, at: min(index, tabs.count)) }
            return copy
        }
    }

    /// Ends a split view. Its two tabs stay right where they are, as
    /// ordinary tabs.
    public func closeSplit(_ split: SplitGroup) {
        guard let first = tabs.first(where: { $0.splitID == split.id }) else { return }
        // Both were on screen, so neither should drift straight away.
        if onScreenTabIDs.contains(first.id) {
            for id in onScreenTabIDs { tabs.first { $0.id == id }?.lastActiveAt = now() }
        }
        _ = endSplit(of: first)
    }

    /// Sets how much of the width the left page takes (kept within
    /// `SplitGroup.fractionRange`).
    public func setLeftFraction(of split: SplitGroup, to fraction: Double) {
        guard let index = splits.firstIndex(where: { $0.id == split.id }) else { return }
        splits[index].leftFraction = SplitGroup.clamped(fraction)
    }

    /// Ends the split a tab is in, if any, and returns its other half.
    private func endSplit(of tab: Tab) -> Tab? {
        guard let splitID = tab.splitID else { return nil }
        let partner = splitPartner(of: tab)
        tab.splitID = nil
        partner?.splitID = nil
        splits.removeAll { $0.id == splitID }
        return partner
    }

    /// Where a tab is in `tabs`, or the second half of its split if that's
    /// further down.
    private func lastIndex(withSplitOf tab: Tab) -> Int? {
        tabs.lastIndex { $0.id == tab.id || (tab.splitID != nil && $0.splitID == tab.splitID) }
    }

    /// Moves a tab with `change`, then brings the other half of its split
    /// back beside it, on the same side and in the same group.
    private func movingSplit(of tab: Tab, _ change: () -> Void) {
        let partner = splitPartner(of: tab)
        let partnerOnLeft = partner.map { partner in
            (tabs.firstIndex { $0.id == partner.id } ?? 0) < (tabs.firstIndex { $0.id == tab.id } ?? 0)
        } ?? false
        change()
        if let partner, let from = tabs.firstIndex(where: { $0.id == partner.id }) {
            let oldGroupID = partner.groupID
            tabs.remove(at: from)
            partner.groupID = tab.groupID
            if let at = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs.insert(partner, at: partnerOnLeft ? at : at + 1)
            } else {
                tabs.insert(partner, at: min(from, tabs.count))
            }
            if oldGroupID != tab.groupID { endIfEmpty(oldGroupID) }
        }
        keepSplitsTogether()
    }

    /// Puts each split's halves back side by side, in the first one's group,
    /// if something landed between them.
    private func keepSplitsTogether() {
        for split in splits {
            let pair = tabs(in: split)
            guard pair.count == 2, let first = tabs.firstIndex(where: { $0.id == pair[0].id }),
                  let second = tabs.firstIndex(where: { $0.id == pair[1].id }),
                  second != first + 1 || pair[1].groupID != pair[0].groupID else { continue }
            let oldGroupID = pair[1].groupID
            tabs.remove(at: second)
            pair[1].groupID = pair[0].groupID
            tabs.insert(pair[1], at: first + 1)
            if oldGroupID != pair[0].groupID { endIfEmpty(oldGroupID) }
        }
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
        reopen(at: index)
    }

    /// The current space's closed tabs and groups, the most recent first,
    /// for the overflow's Recently closed.
    public var recentlyClosed: [ClosedEntry] {
        closed.filter { $0.spaceID == activeSpaceID }.reversed().map { item in
            switch item {
            case let .tab(tab, _, _):
                ClosedEntry(id: tab.id, kind: .tab, title: tab.title, icon: tab.icon)
            case let .group(group, _, _):
                ClosedEntry(id: group.id, kind: .group, title: group.name, icon: nil)
            }
        }
    }

    /// Brings back one item from Recently closed, as ⇧⌘T would.
    public func reopen(_ entry: ClosedEntry) {
        guard let index = closed.lastIndex(where: { $0.spaceID == activeSpaceID && $0.id == entry.id }) else { return }
        reopen(at: index)
    }

    private func reopen(at index: Int) {
        switch closed.remove(at: index) {
        case let .tab(tab, position, _) where tab.place == .basecamp:
            // A closed tile goes back among the tiles; with no room left,
            // it comes back as an everyday tab where new tabs go.
            let tiles = list(.basecamp, in: tab.spaceID)
            if tiles.count < Self.basecampLimit {
                insert(tab, at: position, in: tiles)
            } else {
                tab.place = .open
                tab.homeURL = nil
                tab.lastActiveAt = now()
                tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
            }
            select(tab)
        case let .tab(tab, position, listPosition):
            tab.place = .open
            tab.driftedAt = nil
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
        keepSplitsTogether()
    }

    /// Remembers an everyday or drifted tab about to close. The last tab of a group
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
            // A drifted tab comes back where new tabs go.
            let position = tab.place == .drifted && newTabPlacement == .top
                ? 0 : tabListPosition(of: tab.id, in: tab.spaceID)
            remember(.tab(tab, position: position, listPosition: position))
        }
    }

    /// Remembers a tile leaving Basecamp, and its place among the tiles.
    private func rememberClosingTile(_ tab: Tab) {
        guard tab.homeURL ?? tab.url != nil else { return }
        let tiles = list(.basecamp, in: tab.spaceID)
        let position = tiles.firstIndex { $0.id == tab.id } ?? tiles.count
        remember(.tab(tab, position: position, listPosition: position))
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
        case let .openInLookout(url):
            // Only over the tab on screen: a page out of sight can't be clicked.
            guard tab.id == activeTabID else { return }
            openLookout(url)
        case .close:
            // A popup that's done (a sign-in, say) hands back to its opener.
            close(tab, showing: tabs.first { $0.id == tab.openerTabID }, remembering: false)
        }
    }

    // MARK: - Lookout

    /// Opens `url` in a Lookout over the tab on screen, in the current
    /// space's data store. There's one at a time; a new one replaces it.
    public func openLookout(_ url: URL) {
        guard WebAddress.isWebURL(url) else { return }
        closeLookout()
        let page = makePage(activeSpace.dataStoreID)
        let lookout = Lookout(spaceID: activeSpaceID, page: page, openedURL: url)
        page.onRequest = { [weak self] request in
            self?.handle(request, fromLookout: lookout.id)
        }
        self.lookout = lookout
        page.load(url)
    }

    /// Lets the Lookout's page go.
    public func closeLookout() {
        guard let lookout else { return }
        self.lookout = nil
        lookout.page.onRequest = nil
        lookout.page.stopLoading()
    }

    /// Turns the Lookout into a tab where new tabs go, and shows it. The same
    /// page carries on, so nothing reloads and Back still works.
    @discardableResult
    public func keepLookout() -> Tab? {
        guard let lookout else { return nil }
        self.lookout = nil
        let tab = Tab(spaceID: lookout.spaceID, url: lookout.openedURL, lastActiveAt: now(), page: lookout.page)
        connect(lookout.page, to: tab)
        add(tab, below: nil, inBackground: false)
        return tab
    }

    private func handle(_ request: PageRequest, fromLookout id: UUID) {
        guard let lookout, lookout.id == id else { return }
        switch request {
        case let .openInLookout(url):
            lookout.page.load(url)
        case let .openURL(url, inBackground):
            openTab(url, inBackground: inBackground)
        case let .openPage(page, inBackground):
            // A popup (a sign-in, say) reports back to the page that opened it,
            // so that page is kept as a tab first and the popup opens below it.
            guard let opener = keepLookout() else { return }
            adopt(page, opener: opener, inBackground: inBackground)
        case .close:
            closeLookout()
        }
    }

    // MARK: - Drifting

    /// Counts today as a day Firn was used, deletes drifted tabs past the
    /// 30-day cutoff, and returns every loose tab that hasn't been on screen
    /// for the set number of used days, in every space, top to bottom. Days
    /// away from Firn don't count. Never drifted: Basecamp tiles, grouped
    /// tabs, the tab on screen, and tabs in split view. (Later, also a tab
    /// playing sound.) The app drifts them with `drift(_:)`, one by one, so
    /// it can show each go.
    public func idleTabs() -> [Tab] {
        let today = Self.day(of: now())
        if !usedDays.contains(today) {
            usedDays = Array((usedDays + [today]).sorted().suffix(Self.usedDaysKept))
        }
        deleteExpiredDriftedTabs()
        guard let limit = driftAfter.days else { return [] }
        return tabs.filter { tab in
            guard tab.place == .open, tab.groupID == nil, tab.splitID == nil, tab.id != activeTabID else { return false }
            let lastSeen = Self.day(of: tab.lastActiveAt)
            return usedDays.count { $0 > lastSeen } >= limit
        }
    }

    /// Drifts one loose tab away to its space's overflow ("Tidied away"). Its page lets go,
    /// so it costs nothing; it keeps its address, title, and icon.
    public func drift(_ tab: Tab) {
        guard tab.place == .open, tab.groupID == nil, tab.splitID == nil, tab.id != activeTabID,
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.sleep()
        tab.place = .drifted
        tab.driftedAt = now()
        tabs.append(tab)
        unseenTidiedSpaces.insert(tab.spaceID)
        lastTabBySpace = lastTabBySpace.filter { $0.value != tab.id }
    }

    /// Brings back all of the current space's tidied-away tabs where new
    /// tabs go, in the order they were tidied, leaving the tab on screen as
    /// it is. They count as just seen, so they don't drift straight back.
    public func restoreAllDrifted() {
        let back = list(.drifted)
        guard !back.isEmpty else { return }
        let ids = Set(back.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        let stamp = now()
        for tab in back {
            tab.place = .open
            tab.driftedAt = nil
            tab.lastActiveAt = stamp
        }
        tabs.insert(contentsOf: back, at: arrivalIndex(in: activeSpaceID))
        unseenTidiedSpaces.remove(activeSpaceID)
    }

    /// Drifts every idle tab at once (when there's nothing to watch).
    public func driftIdleTabs() {
        for tab in idleTabs() { drift(tab) }
    }

    /// Drifted tabs go for good 30 calendar days after they drifted (unlike
    /// drifting itself, which counts days Firn was used).
    private func deleteExpiredDriftedTabs() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let expired = Set(tabs.filter { tab in
            guard tab.place == .drifted, let driftedAt = tab.driftedAt else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: driftedAt), to: today).day ?? 0
            return days >= Self.driftedKeptDays
        }.map(\.id))
        guard !expired.isEmpty else { return }
        tabs.removeAll { expired.contains($0.id) }
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

    /// Shows a tab. A drifted one comes back first, where new tabs go. A
    /// tab in split view shows with its other half, and is the one in use.
    public func select(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        closeLookout()
        bringBack(tab)
        for id in onScreenTabIDs { tabs.first { $0.id == id }?.lastActiveAt = now() }
        wake(tab)
        if let partner = splitPartner(of: tab) { wake(partner) }
        tab.lastActiveAt = now()
        activeTabID = tab.id
    }

    /// A drifted tab comes back where new tabs go.
    private func bringBack(_ tab: Tab) {
        guard tab.place == .drifted, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.place = .open
        tab.driftedAt = nil
        tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
    }

    /// The tab on screen and, in split view, its other half.
    private var onScreenTabIDs: Set<UUID> {
        guard let activeTab else { return [] }
        return Set([activeTab.id] + (splitPartner(of: activeTab).map { [$0.id] } ?? []))
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

    /// Shows the tab at `position` (0-based) in the sidebar's rows, top to
    /// bottom (a split is one row; its left half shows in use); past the end
    /// means the last one.
    public func selectTab(at position: Int) {
        let visible = sidebarRows
        guard !visible.isEmpty, position >= 0 else { return }
        select(visible[min(position, visible.count - 1)])
    }

    /// Shows the next tab in the sidebar (or the previous one with `by: -1`),
    /// wrapping around.
    public func selectTab(by offset: Int) {
        let visible = sidebarRows
        guard !visible.isEmpty else { return }
        let splitID = activeTab?.splitID
        guard let current = visible.firstIndex(where: { $0.id == activeTabID || (splitID != nil && $0.splitID == splitID) })
        else {
            return select(visible[0])
        }
        let count = visible.count
        select(visible[((current + offset) % count + count) % count])
    }

    // MARK: - Reordering

    /// Moves a tab to `position` in its own list (Basecamp, its group, or,
    /// for a loose tab, the tab list, counting each group as one; 0-based,
    /// counting each split as one, the count means the end). Other lists and other spaces keep their
    /// places. The other half of its split comes too.
    public func move(_ tab: Tab, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        movingSplit(of: tab) {
            tabs.remove(at: from)
            if tab.place == .open, tab.groupID == nil {
                insertInTabList([tab], at: position, fallback: from)
            } else {
                insert(tab, at: position, in: Self.rows(siblings(of: tab), skipping: tab.splitID), fallback: from)
            }
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
                title: tab.savedTitle, icon: tab.icon, homeURL: tab.homeURL, groupID: tab.groupID,
                splitID: tab.splitID, order: order,
                lastActiveAt: tab.lastActiveAt, openerTabID: tab.openerTabID, driftedAt: tab.driftedAt,
                lastChangedAt: stamp
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
        let splitRecords = splits.map { split in
            var record = SplitRecord(
                id: split.id, spaceID: split.spaceID, leftFraction: split.leftFraction, lastChangedAt: stamp
            )
            if let saved = savedSplitRecords[split.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedSplitRecords = Dictionary(splitRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let window = WindowRecord(
            id: windowID, activeSpaceID: activeSpaceID, activeTabID: activeTabID,
            spaceTabIDs: lastTabBySpace.filter { $0.key != activeSpaceID },
            sidebarWidth: sidebarWidth, sidebarCollapsed: sidebarCollapsed
        )
        return Session(
            spaces: spaces, groups: groupRecords, splits: splitRecords, tabs: records, window: window, usedDays: usedDays,
            unseenTidiedSpaceIDs: unseenTidiedSpaces.sorted { $0.uuidString < $1.uuidString }
        )
    }

    /// The saved file is Firn's own, but it's checked as if it weren't: only
    /// web addresses come back, tabs and groups must belong to a space, ids
    /// are unique, Basecamp holds no more than its limit, icons are small
    /// PNGs, group names are tidy, and only everyday tabs sit in a group of
    /// their own space. Groups left with no tabs are dropped, and a group's
    /// tabs are put back together where its first one is. A split view
    /// comes back only with exactly two everyday tabs of its own space; they
    /// go side by side where its first one is, in that one's group.
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
        var seenSplits = Set<UUID>()
        let savedSplits = session.splits.compactMap { record -> SplitGroup? in
            guard spaceIDs.contains(record.spaceID), seenSplits.insert(record.id).inserted else { return nil }
            return SplitGroup(id: record.id, spaceID: record.spaceID, leftFraction: record.leftFraction)
        }
        let splitSpaces = Dictionary(savedSplits.map { ($0.id, $0.spaceID) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var basecampCounts: [UUID: Int] = [:]
        let restoredAt = now()
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
                splitID: record.splitID.flatMap { id in place == .open && splitSpaces[id] == record.spaceID ? id : nil },
                openerTabID: record.openerTabID, lastActiveAt: record.lastActiveAt,
                // Tabs from before Drifted tabs (or with a time still to
                // come) start their 30 days now.
                driftedAt: place == .drifted ? min(record.driftedAt ?? restoredAt, restoredAt) : nil
            )
        }
        // Only pairs make a split; both halves go in the first one's group.
        let halves = Dictionary(grouping: tabs.filter { $0.splitID != nil }, by: { $0.splitID! })
        for (_, members) in halves {
            if members.count == 2 {
                members[1].groupID = members[0].groupID
            } else {
                for tab in members { tab.splitID = nil }
            }
        }
        splits = savedSplits.filter { halves[$0.id]?.count == 2 }
        tabs = Self.keepingGroupsTogether(tabs)
        keepSplitsTogether()
        let usedGroups = Set(tabs.compactMap(\.groupID))
        groups = restoredGroups.filter { usedGroups.contains($0.id) }
        savedRecords = Dictionary(session.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        savedGroupRecords = Dictionary(session.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        savedSplitRecords = Dictionary(session.splits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        usedDays = Self.cleanDays(session.usedDays)
        unseenTidiedSpaces = Set(session.unseenTidiedSpaceIDs).intersection(spaceIDs)
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

/// A closed tab or group, as Recently closed shows it.
public struct ClosedEntry: Identifiable, Sendable {
    public enum Kind: Sendable { case tab, group }
    public let id: UUID
    public let kind: Kind
    public let title: String
    public let icon: Data?
}

/// A closed tab or group ⇧⌘T can bring back, and where it was: a tab's
/// place among its group's tabs (or in the tab list, if loose) and its
/// group's place in the tab list (where it goes if the group is gone), or a
/// group's place in the tab list. The tabs are the closed ones, asleep.
@MainActor
private enum ClosedItem {
    case tab(Tab, position: Int, listPosition: Int)
    case group(TabGroup, [Tab], position: Int)

    var id: UUID {
        switch self {
        case let .tab(tab, _, _): tab.id
        case let .group(group, _, _): group.id
        }
    }

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

/// How long an everyday tab can go unseen before it drifts, counted in
/// days Firn was used.
public enum DriftAfter: String, CaseIterable, Sendable {
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
