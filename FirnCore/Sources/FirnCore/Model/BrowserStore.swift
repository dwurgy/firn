import Foundation
import Observation

/// Firn's tabs and spaces, and the one place they change. Views read from
/// here and call its methods; nothing in here touches WebKit.
@MainActor
@Observable
public final class BrowserStore {
    public private(set) var spaces: [Space]
    /// Every tab in every space, in sidebar order.
    public private(set) var tabs: [Tab] = []
    public private(set) var activeSpaceID: UUID
    public private(set) var activeTabID: UUID?

    @ObservationIgnored private let makePage: @MainActor (_ dataStoreID: UUID) -> any PageController
    @ObservationIgnored private let now: () -> Date

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

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    /// The everyday tabs of the current space, in order.
    public var openTabs: [Tab] {
        tabs.filter { $0.spaceID == activeSpaceID && $0.place == .open }
    }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    // MARK: - Opening and closing

    /// Opens `url` in a new tab and shows it, or with `inBackground` starts
    /// it loading and stays put. With an `opener`, the tab joins the opener's
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

    private func add(_ tab: Tab, below opener: Tab?, inBackground: Bool) {
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            // Several links from one tab stay in the order they were opened.
            var position = index + 1
            while position < tabs.count, tabs[position].openerTabID == opener.id { position += 1 }
            tabs.insert(tab, at: position)
        } else {
            tabs.append(tab)
        }
        if inBackground { wake(tab) } else { select(tab) }
    }

    /// Closes a tab and lets its page go. If it was on screen, `next` is
    /// shown if it's still in the list; otherwise the tab below (or the one
    /// above, if it was last).
    public func close(_ tab: Tab, showing next: Tab? = nil) {
        let visible = openTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.sleep()
        tabs.remove(at: index)

        guard activeTabID == tab.id else { return }
        let position = visible.firstIndex { $0.id == tab.id } ?? 0
        let remaining = openTabs
        if let next, remaining.contains(where: { $0.id == next.id }) {
            select(next)
        } else if remaining.isEmpty {
            activeTabID = nil
        } else {
            select(remaining[min(position, remaining.count - 1)])
        }
    }

    // MARK: - What pages ask for

    private func connect(_ page: any PageController, to tab: Tab) {
        page.onRequest = { [weak self, weak tab] request in
            guard let self, let tab else { return }
            self.handle(request, from: tab)
        }
    }

    func handle(_ request: PageRequest, from tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
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

    /// Shows the tab at `position` (0-based) in the list; past the end means the last one.
    public func selectTab(at position: Int) {
        let visible = openTabs
        guard !visible.isEmpty, position >= 0 else { return }
        select(visible[min(position, visible.count - 1)])
    }

    /// Shows the next tab (or the previous one with `by: -1`), wrapping around.
    public func selectTab(by offset: Int) {
        let visible = openTabs
        guard !visible.isEmpty else { return }
        guard let current = visible.firstIndex(where: { $0.id == activeTabID }) else {
            return select(visible[0])
        }
        let count = visible.count
        select(visible[((current + offset) % count + count) % count])
    }

    // MARK: - Reordering

    /// Moves a tab to `position` in the current space's list (0-based; the
    /// count means the end). Other spaces' tabs keep their places.
    public func move(_ tab: Tab, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: from)
        let visible = openTabs
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
}
