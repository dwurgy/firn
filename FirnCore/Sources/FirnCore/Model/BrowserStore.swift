import Foundation
import Observation

/// Firn's tabs and spaces, and the one place they change. Views read from
/// here and call its methods; nothing in here touches WebKit.
@MainActor
@Observable
public final class BrowserStore {
    /// How many tiles a space's Basecamp holds.
    public nonisolated static let basecampLimit = 12

    public internal(set) var spaces: [Space]
    /// Every group in every space. A group sits in the tab list where its
    /// tabs are, so this list's own order means nothing.
    public internal(set) var groups: [TabGroup] = []
    /// Every tab in every space; each list (Basecamp, a group, the tab list)
    /// keeps this order. A group's tabs always sit side by side in it, so
    /// this one order also places the groups among the loose tabs.
    public internal(set) var tabs: [Tab] = []
    /// Every split view in every space. Its two tabs sit side by side in
    /// `tabs`, left first, in the same group if any.
    public internal(set) var splits: [SplitGroup] = []
    public internal(set) var activeSpaceID: UUID
    public internal(set) var activeTabID: UUID? {
        // Showing another tab answers the save prompt with "Not now",
        // and closes the list of saved logins.
        didSet {
            if let offer = passwordOffer, !onScreenTabIDs.contains(offer.tabID) { passwordOffer = nil }
            if let offer = fillOffer, !onScreenTabIDs.contains(offer.tabID) { fillOffer = nil }
        }
    }
    /// The link preview over the tab on screen, if one is open. Showing
    /// another tab or space closes it.
    public internal(set) var lookout: Lookout?
    /// The offer to save a password just used on the tab on screen, if
    /// there is one; answered with `savePasswordOffer()`,
    /// `dismissPasswordOffer()`, or `neverSavePasswordsForOffer()`.
    public internal(set) var passwordOffer: PasswordOffer?
    /// The saved logins offered under a sign-in field just clicked on a tab
    /// on screen, if any; answered with `fill(username:)` or `dismissFillOffer()`.
    public internal(set) var fillOffer: FillOffer?
    /// Where new tabs go in a space's tab list (a setting; the app keeps it).
    /// Tabs taken out of a group, ungrouped, or taken off Basecamp go there too.
    public var newTabPlacement: NewTabPlacement = .bottom
    /// How long an everyday tab can go unseen before it drifts (a setting;
    /// the app keeps it).
    public var driftAfter: DriftAfter = .sevenDays
    /// The spaces with tabs tidied away since the overflow was last opened
    /// there (the overflow button shows a dot).
    var unseenTidiedSpaces: Set<UUID> = []
    /// Drifted tabs are deleted this many calendar days after they drift.
    static let driftedKeptDays = 30
    /// The days Firn was used, as "yyyy-MM-dd" in the Mac's calendar, oldest
    /// first: only as many as the longest setting needs.
    var usedDays: [String] = []
    static let usedDaysKept = 30
    /// What ⇧⌘T can bring back, oldest first, each in its own space. Kept
    /// only while Firn runs, like a browser's closed-tab list.
    var closed: [ClosedItem] = []
    /// How many closed tabs and groups are kept, across all spaces.
    static let closedLimit = 30
    /// The tab each space last had on screen, so switching back finds it.
    var lastTabBySpace: [UUID: UUID] = [:]

    @ObservationIgnored let makePage: @MainActor (_ dataStoreID: UUID) -> any PageController
    @ObservationIgnored let removeData: @MainActor (_ dataStoreID: UUID) -> Void
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let passwords: PasswordStore?
    @ObservationIgnored let history: HistoryRecorder?
    /// Names new groups (see `GroupNaming`); nil leaves them "New Group".
    /// Set by the app: `GroupNaming.onDevice` (David, 2026-11-06).
    @ObservationIgnored public var groupNamer: (any GroupNamer)?
    /// How long a new group waits for its tabs' titles before it's named
    /// with what it has (a page may never have a title).
    @ObservationIgnored var groupNameWait: Duration = .seconds(4)
    /// New groups not named yet, and whether the namer's been asked. Not
    /// saved: a group still waiting at quit keeps its default name.
    /// Observed, so the apps can show a group is being named (`isNaming`).
    var unnamedGroups: [UUID: GroupNaming.State] = [:]
    @ObservationIgnored var windowID = UUID()
    /// What each tab looked like when last saved, so a record's last-changed
    /// time only moves when the record really changed.
    @ObservationIgnored var savedRecords: [UUID: TabRecord] = [:]
    @ObservationIgnored var savedGroupRecords: [UUID: GroupRecord] = [:]
    @ObservationIgnored var savedSplitRecords: [UUID: SplitRecord] = [:]

    /// - Parameters:
    ///   - makePage: Makes a page for a data store; `BrowserEngine.makePage` in the app.
    ///   - removeData: Erases a data store no space uses any more;
    ///     `BrowserEngine.removeData` in the app.
    ///   - passwords: Where saved passwords are kept; `PasswordStore.keychain`
    ///     in the app. Without one, Firn never offers to save a password.
    ///   - history: Where visits are recorded; `HistoryStore.standard` in the
    ///     app. Without one, nothing is.
    ///   - now: The clock, replaceable in tests.
    public init(
        spaces: [Space],
        makePage: @escaping @MainActor (_ dataStoreID: UUID) -> any PageController,
        removeData: @escaping @MainActor (_ dataStoreID: UUID) -> Void = { _ in },
        passwords: PasswordStore? = nil,
        history: HistoryStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        precondition(!spaces.isEmpty, "Firn always has at least one space")
        self.spaces = spaces
        self.activeSpaceID = spaces[0].id
        self.makePage = makePage
        self.removeData = removeData
        self.passwords = passwords
        self.history = history.map(HistoryRecorder.init)
        self.now = now
        renumberSpaces()
    }

    /// Picks up where the saved session left off, or starts with
    /// `defaultSpaces` if there's none. Only the tab on screen loads; the
    /// rest rest until shown. Tabs with a place in `pagePlaces` (see
    /// `PagePlacesFile`) come back with their history.
    public convenience init(
        restoring session: Session?,
        pagePlaces: [UUID: PagePlace] = [:],
        defaultSpaces: [Space],
        makePage: @escaping @MainActor (_ dataStoreID: UUID) -> any PageController,
        removeData: @escaping @MainActor (_ dataStoreID: UUID) -> Void = { _ in },
        passwords: PasswordStore? = nil,
        history: HistoryStore? = nil,
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
            spaces: saved.isEmpty ? defaultSpaces : saved, makePage: makePage, removeData: removeData,
            passwords: passwords, history: history, now: now
        )
        if let session { restore(session, pagePlaces: pagePlaces) }
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
    static func rows(_ list: [Tab], skipping splitID: UUID? = nil) -> [Tab] {
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

    /// The current space's tabs, most recently used first, as ⌃Tab shows
    /// them (`TabSwitcher`): the tab on screen, then the rest by when they
    /// were last left (ties in sidebar order). Basecamp tiles, grouped tabs
    /// (folded ones too), and loose tabs count; tidied ones don't. A split
    /// counts once, as its half used last.
    public var recentRows: [Tab] {
        let ranked = (basecampTabs + openTabs).enumerated().sorted { a, b in
            let aOnScreen = a.element.id == activeTabID, bOnScreen = b.element.id == activeTabID
            if aOnScreen != bOnScreen { return aOnScreen }
            if a.element.lastActiveAt != b.element.lastActiveAt {
                return a.element.lastActiveAt > b.element.lastActiveAt
            }
            return a.offset < b.offset
        }
        return Self.rows(ranked.map(\.element))
    }

    public var canAddToBasecamp: Bool { basecampTabs.count < Self.basecampLimit }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    func list(_ place: Tab.Place, in spaceID: UUID? = nil) -> [Tab] {
        let spaceID = spaceID ?? activeSpaceID
        return tabs.filter { $0.spaceID == spaceID && $0.place == place }
    }

    /// The list a tab sits in: its space's Basecamp, its group, its space's
    /// loose tabs, or its space's drifted tabs.
    func siblings(of tab: Tab) -> [Tab] {
        if let groupID = tab.groupID { return tabs.filter { $0.groupID == groupID } }
        let list = list(tab.place, in: tab.spaceID)
        return tab.place == .open ? list.filter { $0.groupID == nil } : list
    }

    /// A space's tab list: each group once, where its tabs are, and the
    /// loose tabs (each split once, as its left half). Halves of `skipping`
    /// are left out (a split being moved).
    func items(in spaceID: UUID, skipping splitID: UUID? = nil) -> [TabListItem] {
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
    func arrivalIndex(in spaceID: UUID) -> Int {
        let isListed = { (tab: Tab) in tab.spaceID == spaceID && tab.place == .open }
        switch newTabPlacement {
        case .top: return tabs.firstIndex(where: isListed) ?? tabs.count
        case .bottom: return tabs.lastIndex(where: isListed).map { $0 + 1 } ?? tabs.count
        }
    }

    /// Puts a tab (already out of `tabs`) at `position` in `list` (0-based;
    /// the count, or more, means the end). With an empty list it goes back
    /// to `fallback`.
    func insert(_ tab: Tab, at position: Int, in list: [Tab], fallback: Int? = nil) {
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
    func insertInTabList(_ moving: [Tab], at position: Int, fallback: Int) {
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
enum ClosedItem {
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

/// Where the address bar sits: Firn's two looks (CLAUDE.md, "two looks, never more").
public enum AddressBarPlace: String, CaseIterable, Sendable {
    case sidebar, top
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
