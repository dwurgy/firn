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
    /// Every tab in every space, in sidebar order (each list keeps this order).
    public private(set) var tabs: [Tab] = []
    public private(set) var activeSpaceID: UUID
    public private(set) var activeTabID: UUID?

    @ObservationIgnored private let makePage: @MainActor (_ dataStoreID: UUID) -> any PageController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var windowID = UUID()
    /// What each tab looked like when last saved, so a record's last-changed
    /// time only moves when the record really changed.
    @ObservationIgnored private var savedRecords: [UUID: TabRecord] = [:]

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
    /// The current space's pinned tabs, in order.
    public var pinnedTabs: [Tab] { list(.pinned) }
    /// The everyday tabs of the current space, in order.
    public var openTabs: [Tab] { list(.open) }

    /// Everything in the current space's sidebar, top to bottom: Basecamp,
    /// pins, then everyday tabs.
    public var sidebarTabs: [Tab] { basecampTabs + pinnedTabs + openTabs }

    public var canAddToBasecamp: Bool { basecampTabs.count < Self.basecampLimit }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    private func list(_ place: Tab.Place, in spaceID: UUID? = nil) -> [Tab] {
        let spaceID = spaceID ?? activeSpaceID
        return tabs.filter { $0.spaceID == spaceID && $0.place == place }
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

    /// Links from an everyday tab open right below it; links from a pin or
    /// a Basecamp tile open at the top of the everyday tabs. Either way,
    /// several links from one tab stay in the order they were opened.
    private func add(_ tab: Tab, below opener: Tab?, inBackground: Bool) {
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            var position = opener.place == .open
                ? index + 1
                : tabs.firstIndex { $0.spaceID == opener.spaceID && $0.place == .open } ?? tabs.count
            while position < tabs.count, tabs[position].openerTabID == opener.id { position += 1 }
            tabs.insert(tab, at: position)
        } else {
            tabs.append(tab)
        }
        if !inBackground { select(tab) }
    }

    /// Closes a tab. An everyday tab goes away; a pin or a Basecamp tile lets
    /// its page go and rests in its place until clicked. If it was on screen,
    /// `next` is shown if it's still there; otherwise, for an everyday tab,
    /// the one below (or above, if it was last); failing that, the tab in
    /// this space that was on screen most recently.
    public func close(_ tab: Tab, showing next: Tab? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let position = openTabs.firstIndex { $0.id == tab.id }
        tab.sleep()
        if tab.place == .open || tab.place == .archived { tabs.remove(at: index) }

        guard activeTabID == tab.id else { return }
        activeTabID = nil
        let remaining = openTabs
        if let next, next.id != tab.id, tabs.contains(where: { $0.id == next.id }) {
            select(next)
        } else if let position, !remaining.isEmpty {
            select(remaining[min(position, remaining.count - 1)])
        } else if let recent = tabs
            .filter({ $0.spaceID == activeSpaceID && !$0.isResting })
            .max(by: { $0.lastActiveAt < $1.lastActiveAt }) {
            select(recent)
        }
    }

    // MARK: - Pins and Basecamp

    /// Pins a tab to the end of its space's pins. Its address becomes its
    /// home (a Basecamp tile keeps the home it had).
    public func pin(_ tab: Tab) {
        makeHome(tab, in: .pinned)
    }

    /// Adds a tab to the end of its space's Basecamp, if there's room. Its
    /// address becomes its home (a pin keeps the home it had).
    @discardableResult
    public func addToBasecamp(_ tab: Tab) -> Bool {
        guard list(.basecamp, in: tab.spaceID).count < Self.basecampLimit else { return false }
        return makeHome(tab, in: .basecamp)
    }

    public func unpin(_ tab: Tab) {
        release(tab, from: .pinned)
    }

    public func removeFromBasecamp(_ tab: Tab) {
        release(tab, from: .basecamp)
    }

    /// Takes a pin or Basecamp tile back to its home address, and shows it.
    public func goHome(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }), tab.homeURL != nil else { return }
        tab.goHome()
        select(tab)
    }

    @discardableResult
    private func makeHome(_ tab: Tab, in place: Tab.Place) -> Bool {
        guard tab.place != place, let index = tabs.firstIndex(where: { $0.id == tab.id }),
              let home = tab.homeURL ?? tab.url else { return false }
        tabs.remove(at: index)
        tab.place = place
        tab.homeURL = home
        tabs.append(tab)
        return true
    }

    /// An awake tab becomes an everyday tab at the top of the list, so its
    /// page isn't lost. A resting one has nothing open to keep, so it goes.
    private func release(_ tab: Tab, from place: Tab.Place) {
        guard tab.place == place, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        guard !tab.isResting else { return }
        tab.place = .open
        tab.homeURL = nil
        let top = tabs.firstIndex { $0.spaceID == tab.spaceID && $0.place == .open } ?? tabs.count
        tabs.insert(tab, at: top)
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

    /// Moves a tab to `position` in its own list (Basecamp, pins, or
    /// everyday tabs; 0-based, the count means the end). Other lists and
    /// other spaces keep their places.
    public func move(_ tab: Tab, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: from)
        let visible = list(tab.place, in: tab.spaceID)
        let target: Int
        if position < visible.count, let before = tabs.firstIndex(where: { $0.id == visible[max(position, 0)].id }) {
            target = before
        } else if let last = visible.last, let after = tabs.firstIndex(where: { $0.id == last.id }) {
            target = after + 1
        } else {
            target = tabs.count
        }
        tabs.insert(tab, at: target)
    }

    // MARK: - Saving and restoring

    /// The session as it is now, for `SessionSaver`. The window's sidebar
    /// lives in the app, so it's passed in.
    public func session(sidebarWidth: Double, sidebarCollapsed: Bool) -> Session {
        let stamp = now()
        let records = tabs.enumerated().map { order, tab in
            var record = TabRecord(
                id: tab.id, spaceID: tab.spaceID, place: tab.place, url: tab.url,
                title: tab.savedTitle, homeURL: tab.homeURL, order: order,
                lastActiveAt: tab.lastActiveAt, openerTabID: tab.openerTabID, lastChangedAt: stamp
            )
            if let saved = savedRecords[tab.id], saved.sameContent(as: record) {
                record.lastChangedAt = saved.lastChangedAt
            }
            return record
        }
        savedRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let window = WindowRecord(
            id: windowID, activeSpaceID: activeSpaceID, activeTabID: activeTabID,
            sidebarWidth: sidebarWidth, sidebarCollapsed: sidebarCollapsed
        )
        return Session(spaces: spaces, tabs: records, window: window)
    }

    /// The saved file is Firn's own, but it's checked as if it weren't: only
    /// web addresses come back, tabs must belong to a space, ids are unique,
    /// and Basecamp holds no more than its limit.
    private func restore(_ session: Session) {
        let spaceIDs = Set(spaces.map(\.id))
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
            return Tab(
                id: record.id, spaceID: record.spaceID, place: place, url: url ?? home,
                title: record.title, homeURL: place == .open ? nil : home,
                openerTabID: record.openerTabID, lastActiveAt: record.lastActiveAt
            )
        }
        savedRecords = Dictionary(session.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
