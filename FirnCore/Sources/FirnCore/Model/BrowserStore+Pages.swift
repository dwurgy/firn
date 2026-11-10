import Foundation
import Observation

extension BrowserStore {
    // MARK: - What pages ask for

    func connect(_ page: any PageController, to tab: Tab) {
        page.onRequest = { [weak self, weak tab] request in
            guard let self, let tab else { return }
            self.handle(request, from: tab)
        }
        followBlocking(of: page, in: tab.spaceID)
        recordVisits(of: page, in: tab)
    }

    // MARK: - History

    /// Records the tab's visits in its space's history. Only tabs: a Lookout
    /// is a glance until it's kept, and then this records the page it's on.
    /// Also tells a new group its tab's title has arrived.
    func recordVisits(of page: any PageController, in tab: Tab) {
        let (tabID, spaceID) = (tab.id, tab.spaceID)
        page.onVisit = { [weak self, weak tab] url, title in
            guard let self else { return }
            if !title.isEmpty, let tab { self.titleArrived(in: tab) }
            guard self.history != nil, let space = self.spaces.first(where: { $0.id == spaceID }) else { return }
            self.history?.visited(url, title: title, tab: tabID, in: space.dataStoreID)
        }
        // A kept Lookout, or a popup already on its page.
        if history != nil, let url = page.url { page.onVisit?(url, page.title) }
    }

    // MARK: - Blocking

    /// Whether ads and trackers are blocked on `url` in the space on screen.
    public func blocksContent(on url: URL) -> Bool {
        activeSpace.blocksContent(on: url)
    }

    /// Turns blocking on or off for `url`'s site in the space on screen, and
    /// only there. Pages follow from their next load. Turning it back on also
    /// clears a wider site that covered this one (example.com, for shop.example.com).
    public func setBlocksContent(_ blocks: Bool, on url: URL) {
        guard let site = BlockingSite.of(url), let host = BlockingSite.host(of: url),
              let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        var space = spaces[index]
        if blocks {
            space.blockingOffSites.removeAll { BlockingSite.covers($0, host: host) }
        } else if space.blocksContent(on: url) {
            space.blockingOffSites.append(site)
            space.blockingOffSites = Array(space.blockingOffSites.suffix(BlockingSite.limit))
        }
        guard space != spaces[index] else { return }
        space.lastChangedAt = now()
        spaces[index] = space
    }

    /// The page asks its space, as it is then, each time it loads an address.
    func followBlocking(of page: any PageController, in spaceID: UUID) {
        page.blocksContent = { [weak self] url in
            self?.spaces.first { $0.id == spaceID }?.blocksContent(on: url) ?? true
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
        case let .openInSplit(url):
            // Only from a page on screen, and not under a Lookout.
            guard WebAddress.isWebURL(url), onScreenTabIDs.contains(tab.id), lookout == nil else { return }
            openSplit(openTab(url, opener: tab, inBackground: true), beside: tab)
        case .close:
            // A popup that's done (a sign-in, say) hands back to its opener,
            // and so does its offer to save the password.
            if passwordOffer?.tabID == tab.id, let opener = tab.openerTabID { passwordOffer?.tabID = opener }
            close(tab, showing: tabs.first { $0.id == tab.openerTabID }, remembering: false)
        case let .offerToSave(login):
            offerToSave(login, from: tab)
        case let .offerToFill(site, field):
            offerToFill(site, at: field, from: tab)
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
        followBlocking(of: page, in: activeSpaceID)
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

    func handle(_ request: PageRequest, fromLookout id: UUID) {
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
        case .offerToSave, .offerToFill:
            // A Lookout is a glance; sign in from a tab to save or fill a password.
            break
        case .openInSplit:
            // Not offered in a Lookout (see `offersSplitView`).
            break
        }
    }
}
