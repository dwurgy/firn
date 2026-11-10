import Foundation
import Observation

extension BrowserStore {
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
    /// has one (as in Dia); from a loose tab, the two become a new group
    /// that tidies away like loose tabs until it's kept by hand (David,
    /// 2026-11-06). Below its split if it's in one (no new group then);
    /// links from a Basecamp tile open at the top or
    /// bottom of the tab list, as set. Either way, several links from one
    /// tab stay in the order they were opened.
    func add(_ tab: Tab, below opener: Tab?, inBackground: Bool) {
        if let opener, let index = lastIndex(withSplitOf: opener) {
            var position: Int
            if opener.place == .open {
                if opener.groupID == nil, opener.splitID == nil {
                    let group = TabGroup(spaceID: opener.spaceID, name: freeGroupName(in: opener.spaceID),
                                         tidies: true)
                    groups.append(group)
                    opener.groupID = group.id
                    startNaming(group.id)
                }
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

    /// The everyday tab a link opened `tab` from, if it's still open in the
    /// same space. On iPhone and iPad, Back on a tab with no page to go back
    /// to closes it and shows this one, as in Safari.
    public func opener(of tab: Tab) -> Tab? {
        guard let id = tab.openerTabID, tab.place == .open else { return nil }
        return tabs.first { $0.id == id && $0.spaceID == tab.spaceID && $0.place == .open }
    }

    /// Close on a tile's menu: it leaves Basecamp altogether, rather than
    /// resting there. ⇧⌘T brings it back to its place among the tiles.
    public func closeTile(_ tab: Tab) {
        guard tab.place == .basecamp else { return }
        close(tab, showing: nil, remembering: true, leavingBasecamp: true)
    }

    /// The loose tabs Close Other Tabs would close: the rest of `tab`'s
    /// space's loose tabs. Tiles, groups, and tidied tabs are kept.
    public func otherLooseTabs(than tab: Tab) -> [Tab] {
        list(.open, in: tab.spaceID).filter { $0.groupID == nil && $0.id != tab.id }
    }

    /// Close Other Tabs, on a loose tab's menu: closes the rest of its
    /// space's loose tabs, one by one, so ⇧⌘T brings them back one by one.
    /// If one of them was on screen, `tab` is shown.
    public func closeOtherLooseTabs(than tab: Tab) {
        guard tab.place == .open, tab.groupID == nil else { return }
        for other in otherLooseTabs(than: tab) {
            close(other, showing: tab, remembering: true)
        }
    }

    /// Close All Tabs, on the sidebar's blank space: closes the current
    /// space's loose tabs, one by one (⇧⌘T brings them back one by one).
    /// Tiles, groups, and tidied tabs are kept. The tab on screen goes
    /// last, so no other loose tab is shown on the way.
    public func closeAllLooseTabs() {
        let loose = looseTabs
        let onScreen = loose.filter { $0.id == activeTabID }
        for tab in loose.filter({ $0.id != activeTabID }) + onScreen {
            close(tab, showing: nil, remembering: true)
        }
    }

    /// `remembering`: whether ⇧⌘T can bring it back (not a popup that
    /// closed itself). `leavingBasecamp`: a tile goes, rather than resting.
    func close(_ tab: Tab, showing next: Tab?, remembering: Bool, leavingBasecamp: Bool = false) {
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
    /// opens its group (`select`), so the tab on screen never vanishes.
    func selectMostRecent() {
        let awake = tabs.filter { $0.spaceID == activeSpaceID && !$0.isResting }
        let shown = Set(sidebarTabs.map(\.id))
        let byRecent = { (a: Tab, b: Tab) in a.lastActiveAt < b.lastActiveAt }
        guard let recent = awake.filter({ shown.contains($0.id) }).max(by: byRecent) ?? awake.max(by: byRecent)
        else { return }
        select(recent)
    }

    // MARK: - Switching

    /// Shows a tab. A drifted one comes back first, where new tabs go. A
    /// tab in split view shows with its other half, and is the one in use.
    /// One in a folded group opens its group (picked in the command bar,
    /// say), so the tab on screen never vanishes.
    public func select(_ tab: Tab) {
        if let group = groups.first(where: { $0.id == tab.groupID }), group.folded,
           tabs.contains(where: { $0.id == tab.id }) {
            setFolded(group, false)
        }
        show(tab)
    }

    /// Shows a tab, leaving its group folded if it is: coming back to a
    /// space, or to a session, finds the sidebar as it was left.
    func show(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        closeLookout()
        bringBack(tab)
        markOnScreenSeen()
        wake(tab)
        if let partner = splitPartner(of: tab) { wake(partner) }
        tab.lastActiveAt = now()
        activeTabID = tab.id
        // On screen, its page's own controls take over from the mini player.
        for id in onScreenTabIDs { tabs.first { $0.id == id }?.forgetPause() }
    }

    /// The tab the mini player shows: in this space, out of sight, and
    /// playing (muted counts) or paused from the mini player. Of several,
    /// the one looked at last. Never a tab from another space.
    public var miniPlayerTab: Tab? {
        let onScreen = onScreenTabIDs
        return tabs
            .filter { $0.spaceID == activeSpaceID && !onScreen.contains($0.id)
                && ($0.sound != .silent || $0.isPausedByFirn) }
            .max { $0.lastActiveAt < $1.lastActiveAt }
    }

    /// A drifted tab comes back where new tabs go.
    func bringBack(_ tab: Tab) {
        guard tab.place == .drifted, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.place = .open
        tab.driftedAt = nil
        tabs.insert(tab, at: arrivalIndex(in: tab.spaceID))
    }

    /// The tab on screen and, in split view, its other half.
    var onScreenTabIDs: Set<UUID> {
        guard let activeTab else { return [] }
        return Set([activeTab.id] + (splitPartner(of: activeTab).map { [$0.id] } ?? []))
    }

    /// Marks the tab on screen, and its other half, as seen now: the half in
    /// use last, so ⌃Tab (`recentRows`) comes back to it.
    func markOnScreenSeen() {
        guard let activeTab else { return }
        splitPartner(of: activeTab)?.lastActiveAt = now()
        activeTab.lastActiveAt = now()
    }

    /// Makes the tab's page, in its own space's data store, if it has none.
    func wake(_ tab: Tab) {
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
}
