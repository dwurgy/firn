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

    /// Opens `url` in a new tab and shows it. The tab goes right below
    /// `opener` if given, otherwise at the end of the list.
    @discardableResult
    public func openTab(_ url: URL, opener: Tab? = nil) -> Tab {
        let tab = Tab(
            spaceID: activeSpaceID, url: url,
            openerTabID: opener?.id, lastActiveAt: now()
        )
        if let opener, let index = tabs.firstIndex(where: { $0.id == opener.id }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        select(tab)
        return tab
    }

    /// Closes a tab and lets its page go. If it was on screen, the tab below
    /// it is shown next (or the one above, if it was last).
    public func close(_ tab: Tab) {
        let visible = openTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.sleep()
        tabs.remove(at: index)

        guard activeTabID == tab.id else { return }
        let position = visible.firstIndex { $0.id == tab.id } ?? 0
        let remaining = openTabs
        if remaining.isEmpty {
            activeTabID = nil
        } else {
            select(remaining[min(position, remaining.count - 1)])
        }
    }

    // MARK: - Switching

    public func select(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        let dataStoreID = spaces.first { $0.id == tab.spaceID }?.dataStoreID ?? activeSpace.dataStoreID
        activeTab?.lastActiveAt = now()
        tab.wake { makePage(dataStoreID) }
        tab.lastActiveAt = now()
        activeTabID = tab.id
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
