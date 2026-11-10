import FirnCore
import SwiftUI

/// What the window is doing, apart from its tabs: whether the address bar is
/// being edited, or the command bar is open.
@MainActor
@Observable
final class WindowModel {
    let store: BrowserStore
    /// History › Clear History… was chosen: the History window opens and
    /// asks (see `HistoryWindow`).
    var asksToClearHistory = false
    /// Whether the command bar (⌘T) is open over the page.
    private(set) var showsCommandBar = false
    /// ⌃Tab is held: the recent tabs, one picked (see `pressTabSwitch`).
    private(set) var tabSwitcher: TabSwitcher?
    /// ⌃ has been held a moment, so the panel of recent tabs shows.
    private(set) var showsTabSwitcher = false
    @ObservationIgnored private var tabSwitcherDelay: Task<Void, Never>?
    /// Pictures of pages, taken as their tabs are left, for the ⌃Tab
    /// panel. In memory only, never on disk; the newest few, by tab.
    private(set) var tabPictures: [UUID: CGImage] = [:]
    @ObservationIgnored private var pictureOrder: [UUID] = []
    /// The tab a split view is being made beside (Open as Split on the
    /// tab on screen, or a tile): it moves to the left half, and the command
    /// bar sits over an empty right half until something is picked.
    private(set) var splitPickAnchor: FirnCore.Tab?
    /// The half that tab takes; the empty half is the other. Open as Split
    /// puts it on the left; dragged onto the page, it goes where it's let go.
    private(set) var splitPickSide = SplitSide.left
    /// A split just made: its row opens from its left tab's row (see `SplitRow`).
    var formingSplitID: UUID?
    /// Whether that's happening now, with its tab on screen.
    var isPickingSplit: Bool {
        splitPickAnchor != nil && splitPickAnchor?.id == store.activeTabID
    }
    /// The command bar was opened to pick a split's page, so it sits over
    /// the empty half. Kept until it's next opened, so it fades out where it was.
    private(set) var commandBarHalf: SplitSide?
    /// Goes up each time the address bar is asked to take focus.
    private(set) var addressRequest = 0

    /// A tab dragged out of the sidebar over the page: which half it's
    /// over, where frost shows it would open (see `PageArea`).
    var pageDrop: PageDrop?
    /// A tab lifted off the sidebar, following the pointer (see `TabLiftGhost`).
    var tabLift: TabLift?
    /// A Basecamp tile dragged out over the tab list: the list makes room
    /// for it as a row, and settles it there once it's let go (see `TabList`).
    var tileInList: TileInList?
    /// A tab dragged up out of the tab list over Basecamp: Basecamp makes
    /// room for it as a tile, and settles it there once it's let go (see `BasecampGrid`).
    var tabInBasecamp: TileInList?
    /// A tab just added to Basecamp from its menu, on its way up to its
    /// tile (see `TabList.addToBasecamp` and `TileArrivalChip`).
    var tileArrival: TileArrival?
    /// A tab held up over a full Basecamp: a quiet line says so.
    var basecampFullHint = false
    /// The pointer while a tab is lifted, in the window's space. Apart from
    /// `tabLift` and `pageDrop`, so only the lifted tab redraws as it moves.
    var dragPointer: CGPoint = .zero
    /// Where the pages sit in the window, so a drag knows when it's over one.
    @ObservationIgnored var pagesFrame: CGRect = .zero
    /// A tab is being dragged in the sidebar: a peeking sidebar stays out
    /// until it's let go, wherever the pointer goes.
    var isDraggingTab = false {
        didSet {
            if !isDraggingTab, sidebarCollapsed, !pointerNearSidebar, !peekHeld { isPeeking = false }
        }
    }

    /// The sidebar's width while it's showing (CLAUDE.md: 200–360pt).
    var sidebarWidth = CGFloat(SidebarSizing.standard)
    private(set) var sidebarCollapsed = false
    /// Hidden, but slid out over the page because the pointer is at the left
    /// edge (or the address bar was asked for).
    private(set) var isPeeking = false
    private var pointerNearSidebar = false
    /// The address bar was asked for while the sidebar was hidden: it stays
    /// out, wherever the pointer goes, until typing is done.
    private var peekHeldForTyping = false
    /// The address bar's prompt (saving a password) is up while the sidebar
    /// is hidden: it stays out until the prompt is answered.
    private var peekHeldForPrompt = false
    private var peekHeld: Bool { peekHeldForTyping || peekHeldForPrompt }
    private var peekHideTask: Task<Void, Never>?
    /// The group whose name is being edited, if any. Here rather than in the
    /// sidebar so the menu bar's New Group can ask for a name too.
    var renamingGroupID: UUID?
    /// A group just made: its card starts thawed (looking like a loose tab)
    /// and frost forms around its tab (see `TabList`).
    var formingGroupID: UUID?
    /// The New space card, while it's open. Here so the menu bar's New
    /// Space… can open it too.
    private(set) var showsSpaceSheet = false
    /// The space Settings › Spaces should pick, set by Space Settings….
    var settingsSpaceID: UUID?
    /// Idle tabs waiting to be tidied away, one by one, so each is seen
    /// going (see `TabList`).
    var tidyQueue: [FirnCore.Tab] = []
    /// Site icons on their way down to the overflow button, or up out of it.
    var flyingIcons: [FlyingIcon] = []
    /// Tabs just brought back, whose icons rise out of the overflow button
    /// one by one (see `TabList`).
    var riseQueue: [FirnCore.Tab] = []
    /// Brought-back tabs whose icons haven't landed yet; their rows wait unseen.
    var arrivingTabIDs: Set<UUID> = []
    /// The overflow button's archive box, open while brought-back icons rise out.
    var boxOpen = false
    /// Where the overflow button sits in the sidebar, where they land.
    @ObservationIgnored var overflowButtonFrame: CGRect = .zero
    /// "Tidied away 4 tabs", while the overflow button says so.
    var tidyAnnouncement: TidyAnnouncement?
    /// Whether the overflow (the tidied-away tabs) is open.
    var showsOverflow = false
    /// Whether the downloads popover is open.
    var showsDownloads = false
    /// In full screen.
    private(set) var isFullScreen = false
    /// How far the menu bar has come down in full screen (0 at rest): the
    /// sidebar above its bottom row and the page's top edge sit this much
    /// lower, as in Dia. The web page itself doesn't move.
    private(set) var menuBarDrop: CGFloat = 0

    func setFullScreen(_ on: Bool) {
        isFullScreen = on
        if !on { menuBarDrop = 0 }
    }

    /// The menu bar came down (by `height`) or went back up. One glide, not
    /// following AppKit's uneven steps; `animated` false puts it in place.
    func menuBarMoved(to drop: CGFloat, animated: Bool) {
        guard drop != menuBarDrop else { return }
        let glide = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(glide ? .easeOut(duration: 0.2) : nil) { menuBarDrop = drop }
    }

    init(store: BrowserStore, restoring saved: WindowRecord? = nil) {
        self.store = store
        if let saved {
            if case let .width(width) = SidebarSizing.outcome(forProposedWidth: saved.sidebarWidth) {
                sidebarWidth = width
            }
            sidebarCollapsed = saved.sidebarCollapsed
        }
    }

    func toggleSidebar() { setSidebarCollapsed(!sidebarCollapsed) }

    /// The overflow button frosts over and says how many tabs were tidied
    /// away (see `SpaceRow`); VoiceOver hears it too.
    func announceTidied(_ count: Int) {
        let announcement = TidyAnnouncement(count: count)
        tidyAnnouncement = announcement
        AccessibilityNotification.Announcement(announcement.text).post()
    }

    // MARK: Spaces

    /// Changes which space is on screen: the sidebar's tabs fade across and
    /// the tint cross-fades (`SpaceTint`); Reduce Motion: in place.
    func showSpace(_ change: () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2), change)
        focusPage()
    }

    /// Opens the New space card, in place of the command bar if it's open.
    func newSpace() {
        guard !showsWelcome else { return }
        closeCommandBar(focusingPage: false)
        showsSpaceSheet = true
    }

    /// The welcome, over the whole window (see `WelcomeLayer`).
    private(set) var showsWelcome = false

    /// The welcome's finish, while it plays (see `finishWelcome`).
    private(set) var welcomeFinish: WelcomeFinish?
    private var welcomeFinishTask: Task<Void, Never>?

    enum WelcomeFinish {
        /// The step fades, the sun rises, "Welcome in.", and the real window
        /// waits low behind the snow, a little smaller.
        case begun
        /// The window rises over the words into its place.
        case rising
        /// The snow fades away, leaving the browser.
        case fading
    }

    /// Opens the welcome: the first time Firn opens, or Help › Show Welcome Again.
    func showWelcome() {
        closeCommandBar(focusingPage: false)
        showsSpaceSheet = false
        welcomeFinishTask?.cancel()
        welcomeFinish = nil
        showsWelcome = true
    }

    /// "Start Browsing", Skip, or Esc: "Welcome in.", and the real window
    /// (your sidebar, color, and tiles) rises out of the scene, about 2.4s
    /// as in the approved source (docs/electron-welcome, styles.css). With
    /// Reduce Motion, the welcome simply fades (300ms).
    func finishWelcome(reduceMotion: Bool) {
        guard showsWelcome, welcomeFinish == nil else { return }
        guard !reduceMotion else { return closeWelcome() }
        welcomeFinish = .begun
        AccessibilityNotification.Announcement("Welcome in.").post()
        welcomeFinishTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.25, 0.7, 0.3, 1, duration: 1.1)) { welcomeFinish = .rising }
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.5)) { welcomeFinish = .fading }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // `welcomeFinish` stays `.fading` until the welcome opens again:
            // cleared now, the faded card would flash back as the welcome goes.
            closeWelcome()
        }
    }

    /// The welcome is done (finished or skipped): it doesn't come back on
    /// its own, and an empty window opens the command bar, as at any launch.
    func closeWelcome() {
        UserDefaults.standard.set(true, forKey: Preference.welcomed)
        showsWelcome = false
        if store.activeTab == nil { openCommandBar() }
    }

    /// A link from another app (Firn as the default browser), or a web page
    /// file opened from Finder, opens as a new tab in the space on screen,
    /// the space used last. Anything else macOS hands over is refused
    /// (CLAUDE.md, Security).
    func openFromOtherApp(_ url: URL) {
        guard WebAddress.isWebURL(url) || OpenedFiles.accept(url) else { return }
        closeCommandBar(focusingPage: false)
        store.closeLookout()
        store.openTab(url)
    }

    /// Help › Report a Problem…: GitHub's new-issue form as a new tab, with
    /// only Firn's and macOS's versions filled in (nothing from the person's
    /// tabs or spaces). Nothing is sent until they submit it themselves.
    func reportProblem() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var form = URLComponents(string: "https://github.com/dwurgy/firn/issues/new")!
        form.queryItems = [URLQueryItem(name: "body", value: """
            **What happened?**


            **What did you expect?**


            ---
            Firn \(version) (\(build)), macOS \(os)
            """)]
        guard let url = form.url else { return }
        closeCommandBar(focusingPage: false)
        store.closeLookout()
        store.openTab(url)
    }

    /// Space Settings…: Settings › Spaces, with `space` picked. The caller
    /// opens the Settings window.
    func showSpaceSettings(for space: Space) {
        settingsSpaceID = space.id
        UserDefaults.standard.set(SettingsPane.spaces.rawValue, forKey: "settingsPane")
    }

    /// Closes the space card; the page in front gets the keys back.
    func closeSpaceSheet() {
        guard showsSpaceSheet else { return }
        showsSpaceSheet = false
        focusPage()
    }

    /// The first space color no space has yet (or, with all taken, the next in turn).
    var freeSpaceColor: String { Self.freeColor(among: store.spaces) }

    /// A new space's color, given `spaces`; an import asks once per space,
    /// so each one it adds takes the next.
    static func freeColor(among spaces: [Space]) -> String {
        let taken = Set(spaces.map(\.color))
        let names = Theme.spaceColorNames
        return names.first { !taken.contains($0) } ?? names[spaces.count % names.count]
    }

    /// File › Import from Arc…: reads Arc's file and shows the sheet (`ArcImportFlow`).
    var startingArcImport = false

    func importFromArc() {
        guard !showsWelcome else { return }
        closeCommandBar(focusingPage: false)
        startingArcImport = true
    }

    // MARK: Tab actions (the tab's right-click menu and the menu bar)

    /// Starts a group with an everyday tab. The tab doesn't move: its card
    /// appears thawed, in the tab's exact shape, so the change is invisible,
    /// and then the frost forms (`finishForming`). Reduce Motion: a fade.
    /// It names itself (`BrowserStore.groupNamer`): no prompt (David, 2026-11-06).
    func newGroup(with tab: FirnCore.Tab) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { _ = store.newGroup(with: tab) }
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            formingGroupID = store.newGroup(with: tab)?.id
        }
    }

    /// The frost has formed around a new group.
    func finishForming(_ id: UUID) {
        formingGroupID = nil
    }

    /// Closes a tab; if it was on screen, the tab shown next takes keyboard
    /// focus, so space and the arrow keys scroll it straight away.
    func close(_ tab: FirnCore.Tab) {
        let wasShowing = tab.id == store.activeTabID
        store.close(tab)
        if wasShowing { focusPage() }
    }

    /// Close Other Tabs, on a loose tab's menu: the rest of the loose tabs go.
    func closeOtherTabs(than tab: FirnCore.Tab) {
        let wasShowing = store.activeTabID != tab.id
            && store.otherLooseTabs(than: tab).contains { $0.id == store.activeTabID }
        store.closeOtherLooseTabs(than: tab)
        if wasShowing { focusPage() }
    }

    /// Close All Tabs, on the sidebar's blank space: every loose tab goes;
    /// tiles and groups stay.
    func closeAllTabs() {
        let wasShowing = store.looseTabs.contains { $0.id == store.activeTabID }
        store.closeAllLooseTabs()
        if wasShowing { focusPage() }
    }

    /// Close on a tile's menu: it leaves Basecamp (⇧⌘T brings it back).
    func closeTile(_ tab: FirnCore.Tab) {
        let wasShowing = tab.id == store.activeTabID
        withAnimation(Theme.glide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            store.closeTile(tab)
        }
        if wasShowing { focusPage() }
    }

    /// ⌘W: closes the Lookout if one is open (as in Arc), or else the tab on screen.
    func closeFront() {
        if store.lookout != nil {
            store.closeLookout()
            focusPage()
        } else if let tab = store.activeTab {
            close(tab)
        }
    }

    /// ⇧⌘T: brings back the last closed tab or group.
    func reopenClosed() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(Theme.glide(reduceMotion: reduceMotion)) { store.reopenClosed() }
        focusPage()
    }

    /// The page in front: a Lookout's while one is open, so Back and Reload act on it.
    var frontPage: (any PageController)? { store.lookout?.page ?? store.activeTab?.page }

    /// The tab on screen, if it's an everyday tab (not a Basecamp tile).
    var everydayTab: FirnCore.Tab? { store.activeTab.flatMap { $0.place == .open ? $0 : nil } }

    func duplicate(_ tab: FirnCore.Tab) {
        store.duplicate(tab)
        focusPage()
    }

    /// The address of the page in front, as the address bar shows it: a
    /// Lookout's while one is open; after a failed load, the address that failed.
    var frontURL: URL? {
        if let page = store.lookout?.page { return page.loadError?.url ?? page.url }
        return store.activeTab?.url
    }

    /// Puts the tab's address on the clipboard (only http and https reach a tab).
    func copyLink(of tab: FirnCore.Tab) {
        copy(tab.url)
    }

    /// ⇧⌘C: the page in front's address, so with a Lookout open it's the
    /// Lookout's, as the address bar shows.
    func copyFrontLink() {
        copy(frontURL)
    }

    private func copy(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Whether the page in front can be loaded again: it has an address,
    /// or its first one failed (the error page's Try Again).
    var canReloadFront: Bool {
        frontPage.map { $0.url != nil || $0.loadError != nil } ?? false
    }

    enum ZoomChange { case larger, smaller, actualSize }

    /// The zoom a change would give the page in front, or nil if it would do nothing.
    private func zoom(after change: ZoomChange) -> Double? {
        guard let page = frontPage, page.url != nil, page.loadError == nil else { return nil }
        switch change {
        case .larger: return PageZoom.larger(than: page.zoom)
        case .smaller: return PageZoom.smaller(than: page.zoom)
        case .actualSize: return PageZoom.isActualSize(page.zoom) ? nil : 1
        }
    }

    func canZoomFront(_ change: ZoomChange) -> Bool { zoom(after: change) != nil }

    func zoomFront(_ change: ZoomChange) {
        guard let zoom = zoom(after: change) else { return }
        frontPage?.setZoom(zoom)
    }

    // MARK: Blocking

    /// What turning blocking on or off for the page in front is called
    /// ("Stop Blocking on example.com"), or nil if there's no site to do it
    /// for: no page, an error page, or blocking off everywhere (`enabled`).
    func frontBlockingName(enabled: Bool) -> String? {
        guard enabled, let page = frontPage, page.loadError == nil, let url = page.url,
              let site = BlockingSite.of(url) else { return nil }
        return store.blocksContent(on: url) ? "Stop Blocking on \(site)" : "Block Ads and Trackers on \(site)"
    }

    /// Turns blocking on or off for the front page's site, in this space
    /// only, and loads the page again so the change shows.
    func toggleFrontBlocking() {
        guard let page = frontPage, page.loadError == nil, let url = page.url else { return }
        store.setBlocksContent(!store.blocksContent(on: url), on: url)
        page.reload()
    }

    // MARK: Find on page

    /// Whether the find bar (⌘F) is open over the page in front.
    private(set) var showsFindBar = false
    /// What's being looked for. Kept after the bar closes, so ⌘G can go on;
    /// never saved.
    var findText = ""
    /// How many matches the last search found; nil before one has run.
    private(set) var findCount: Int?
    /// Goes up each time the find field is asked to take focus.
    private(set) var findRequest = 0

    var canFindInFront: Bool { frontPage.map { $0.url != nil && $0.loadError == nil } ?? false }

    /// ⌘F: opens the bar, or gives it focus again, with its words selected.
    func openFindBar() {
        guard canFindInFront else { return }
        showsFindBar = true
        findRequest += 1
    }

    /// Esc, the close button, or the page in front changing: the bar goes,
    /// and the page keeps the match selected, as in Safari.
    func closeFindBar(focusingPage: Bool = true) {
        guard showsFindBar else { return }
        showsFindBar = false
        findCount = nil
        if focusingPage { focusPage() }
    }

    /// Looks for `findText` on the page in front. ⌘G and ⇧⌘G open the bar
    /// first, so the count can be seen.
    func find(_ direction: FindOnPage.Direction) {
        guard let page = frontPage, canFindInFront else { return }
        if direction != .fromHere, !showsFindBar { showsFindBar = true }
        let text = findText
        guard !FindOnPage.query(text).isEmpty else {
            findCount = nil
            return
        }
        Task { @MainActor in
            let count = await page.find(text, direction)
            // A newer search, or a closed bar, has the last word.
            guard text == findText, showsFindBar, page === frontPage else { return }
            findCount = count
        }
    }

    /// ⌘E: looks for what's selected on the page.
    func useSelectionForFind() {
        guard let page = frontPage, canFindInFront else { return }
        Task { @MainActor in
            let selected = await page.selectedText()
            guard !selected.isEmpty, page === frontPage else { return }
            findText = selected
            showsFindBar = true
            find(.fromHere)
        }
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        guard collapsed != sidebarCollapsed else { return }
        sidebarCollapsed = collapsed
        isPeeking = false
        pointerNearSidebar = false
        peekHeldForTyping = false
        peekHideTask?.cancel()
    }

    /// Where the pointer is across the window, so a hidden sidebar can peek.
    /// Decided by position alone, so there are no gaps between areas: the left
    /// edge brings the card out, and it stays while the pointer is over it or
    /// just beside it.
    func pointerMoved(toX x: CGFloat) {
        guard sidebarCollapsed else { return }
        let reach = isPeeking
            ? Theme.peekInset + sidebarWidth + Theme.pageInset + Theme.peekLeaveMargin
            : Theme.peekEdgeZone
        setPointerNear(x <= reach, hideAfter: .milliseconds(150))
    }

    /// The pointer left the window. A longer pause, so overshooting past the
    /// left edge doesn't snatch the card away, but it still tucks away if the
    /// pointer stays outside (another app beside Firn, say).
    func pointerLeftWindow() {
        guard sidebarCollapsed else { return }
        setPointerNear(false, hideAfter: .seconds(1))
    }

    private func setPointerNear(_ near: Bool, hideAfter delay: Duration) {
        guard near != pointerNearSidebar else { return }
        pointerNearSidebar = near
        peekHideTask?.cancel()
        if near {
            isPeeking = true
        } else if !peekHeld {
            peekHideTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, !pointerNearSidebar, !peekHeld, !isDraggingTab else { return }
                isPeeking = false
            }
        }
    }

    /// Focuses the address bar, to change the page in front (or, with no
    /// tab on screen, to open one).
    func editAddress() {
        addressRequest += 1
        // The address bar lives in the sidebar, so a hidden one slides out to be typed in.
        if sidebarCollapsed {
            peekHideTask?.cancel()
            peekHeldForTyping = true
            isPeeking = true
        }
    }

    func finishEditingAddress() {
        peekHeldForTyping = false
        if sidebarCollapsed, !pointerNearSidebar, !peekHeld { isPeeking = false }
    }

    /// Holds a hidden sidebar out while the address bar's prompt is up, or
    /// lets it go.
    func holdPeekForPrompt(_ held: Bool) {
        guard held != peekHeldForPrompt else { return }
        peekHeldForPrompt = held
        guard sidebarCollapsed else { return }
        if held {
            peekHideTask?.cancel()
            isPeeking = true
        } else if !pointerNearSidebar, !peekHeld, !isDraggingTab {
            isPeeking = false
        }
    }

    // MARK: Command bar

    /// Opens the command bar (⌘T, the New tab button, an empty window). No
    /// tab exists until something in it is picked.
    func openCommandBar() {
        // Nothing opens behind the welcome to take its keys.
        guard !showsWelcome else { return }
        // A pick whose page has gone (closed, say) is over: the bar opens whole.
        if !isPickingSplit { splitPickAnchor = nil }
        showsSpaceSheet = false
        commandBarHalf = isPickingSplit ? splitPickSide.other : nil
        showsCommandBar = true
    }

    /// The tab on screen changed some other way while a page was being
    /// picked for a split (⌘1–9, ⌃Tab, a click in the sidebar, its page
    /// closed): the pick ends, so the bar never sits over half of a page
    /// that's back to full width.
    func tabOnScreenChanged() {
        guard let anchor = splitPickAnchor, anchor.id != store.activeTabID else { return }
        if showsCommandBar { closeCommandBar() } else { splitPickAnchor = nil }
    }

    /// Closes the command bar, leaving nothing behind. The page in front
    /// gets the keys back, unless focus already went somewhere else (a
    /// click in the sidebar's address bar, say).
    func closeCommandBar(focusingPage: Bool = true) {
        guard showsCommandBar else { return }
        showsCommandBar = false
        // Nothing picked: the page glides back to full width.
        if splitPickAnchor != nil {
            withAnimation(Theme.slide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
                splitPickAnchor = nil
            }
        }
        if focusingPage { focusPage() }
    }

    /// Open as Split on the tab on screen or a Basecamp tile (or the tab on
    /// screen dragged onto the page): the page glides over to `side`, and
    /// the command bar opens over the empty other half to pick what goes
    /// there. Esc leaves things as they were.
    func pickSplit(beside tab: FirnCore.Tab, on side: SplitSide = .left) {
        store.select(tab)
        withAnimation(Theme.slide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            splitPickAnchor = tab
            splitPickSide = side
        }
        openCommandBar()
    }

    /// Shows `incoming` beside `anchor` in split view, on `side`; a new
    /// split's row forms in the sidebar.
    func openSplit(_ incoming: FirnCore.Tab, beside anchor: FirnCore.Tab, on side: SplitSide = .right) {
        let existing = Set(store.splits.map(\.id))
        if let split = store.openSplit(incoming, beside: anchor, on: side), !existing.contains(split.id) {
            formingSplitID = split.id
        }
    }

    /// The half of the page `pointer` (in the window's space) is over, if
    /// `tab` could open there; nil over the sidebar (left of `sidebarEdge`,
    /// so a peeking sidebar counts), or when it can't.
    func pageSide(at pointer: CGPoint, for tab: FirnCore.Tab, past sidebarEdge: CGFloat) -> SplitSide? {
        let pages = pagesFrame
        guard canDragOntoPage(tab), !isPickingSplit, !showsCommandBar,
              pages.contains(pointer), pointer.x > sidebarEdge else { return nil }
        // A split's halves meet at its divider; one page is split down the middle.
        let fraction = store.activeTab.flatMap { store.split(of: $0) }?.leftFraction ?? 0.5
        let middle = pages.minX + (pages.width - Theme.pageInset) * fraction + Theme.pageInset / 2
        return pointer.x < middle ? .left : .right
    }

    /// Whether `tab` can be dragged onto the page: one that would open in
    /// split view, or the tab on screen itself (not a split), which makes
    /// room for a new page beside it, as Open as Split does.
    func canDragOntoPage(_ tab: FirnCore.Tab) -> Bool {
        store.canDropOnPage(tab) || isAloneOnScreen(tab)
    }

    private func isAloneOnScreen(_ tab: FirnCore.Tab) -> Bool {
        tab.id == store.activeTabID && tab.splitID == nil && store.lookout == nil
    }

    /// A dragged tab let go over the page: it opens on the half the frost
    /// showed, the frost giving way to the page. The tab on screen goes to
    /// the half it was let go over, and the command bar opens over the
    /// other to pick a page for it.
    func dropOnPage() {
        guard let drop = pageDrop else { return }
        if isAloneOnScreen(drop.tab) {
            withAnimation(Theme.slide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
                pageDrop = nil
            }
            return pickSplit(beside: drop.tab, on: drop.side)
        }
        let existing = Set(store.splits.map(\.id))
        let split = withAnimation(Theme.slide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            pageDrop = nil
            return store.dropOnPage(drop.tab, on: drop.side)
        }
        if let split, !existing.contains(split.id) { formingSplitID = split.id }
    }

    /// Something was picked for the empty half: the split is made, in the
    /// very places the two pages already show.
    func finishSplitPick(_ make: () -> Void) {
        make()
        splitPickAnchor = nil
    }

    /// Tabs just brought back: their site icons rise out of the overflow
    /// button to their rows, which wait unseen until they land (see
    /// `TabList`). With Reduce Motion, or the sidebar hidden, the rows
    /// simply appear.
    func rise(_ tabs: [FirnCore.Tab]) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !sidebarCollapsed || isPeeking else { return }
        arrivingTabIDs.formUnion(tabs.map(\.id))
        riseQueue = tabs
    }

    /// Gives the page in front (a Lookout's, or the tab on screen's) keyboard
    /// focus, once it's in the window.
    func focusPage() {
        Task { @MainActor in
            await Task.yield()
            (store.lookout?.page ?? store.activeTab?.page)?.focus()
        }
    }

    // MARK: ⌃Tab

    /// ⌃Tab (or ⇧⌃Tab) pressed: starts a switch, or moves its pick while ⌃
    /// is still held. See `TabSwitcher` and `TabSwitchKeys`.
    func pressTabSwitch(backward: Bool) {
        guard !showsWelcome else { return }
        if tabSwitcher != nil { return moveTabSwitch(by: backward ? -1 : 1) }
        tabSwitcher = TabSwitcher(tabIDs: switchableTabs.map(\.id), backward: backward)
        guard tabSwitcher != nil else { return }
        takePicture(of: store.activeTabID)
        // A quick tap never flashes the panel; held a moment, it shows.
        tabSwitcherDelay = Task {
            try? await Task.sleep(for: .seconds(0.12))
            guard !Task.isCancelled, tabSwitcher != nil else { return }
            showsTabSwitcher = true
            announceTabSwitchPick()
        }
    }

    /// The recent tabs ⌃Tab offers: only those opened since launch (a page
    /// loaded, or a picture kept from one that's since slept), so the panel
    /// holds as many cards as there are, two to five.
    var switchableTabs: [FirnCore.Tab] {
        store.recentRows.filter { $0.page != nil || tabPictures[$0.id] != nil || $0.id == store.activeTabID }
    }

    func moveTabSwitch(by offset: Int) {
        tabSwitcher?.move(by: offset)
        announceTabSwitchPick()
    }

    /// VoiceOver hears the pick, "Title, 2 of 4", since keys stay with the
    /// page while ⌃ is held and the panel never takes focus.
    private func announceTabSwitchPick() {
        guard showsTabSwitcher, let switcher = tabSwitcher,
              let tab = store.tabs.first(where: { $0.id == switcher.pickedID }) else { return }
        let title = tab.title.isEmpty ? "New Tab" : tab.title
        AccessibilityNotification.Announcement(
            "\(title), \(switcher.picked + 1) of \(switcher.tabIDs.count)"
        ).post()
    }

    /// The pointer over a card in the panel.
    func pickTabSwitch(_ id: UUID) { tabSwitcher?.pick(id) }

    /// ⌃ let go: the picked tab shows, if it's still in this space.
    func finishTabSwitch() {
        guard let switcher = tabSwitcher else { return }
        endTabSwitch()
        guard let tab = store.tabs.first(where: { $0.id == switcher.pickedID }),
              tab.spaceID == store.activeSpaceID else { return }
        // The command bar belonged to the tab left behind.
        closeCommandBar(focusingPage: false)
        store.select(tab)
        focusPage()
    }

    /// Esc, or Firn left mid-switch: the tab on screen stays.
    func cancelTabSwitch() { endTabSwitch() }

    private func endTabSwitch() {
        tabSwitcherDelay?.cancel()
        tabSwitcherDelay = nil
        tabSwitcher = nil
        showsTabSwitcher = false
    }

    /// Takes a picture of a tab's page for the ⌃Tab panel, as it's left
    /// (and of the tab on screen as ⌃Tab is pressed). A sleeping page is
    /// never woken for it; its card shows the site's icon instead.
    func takePicture(of tabID: UUID?) {
        guard let tabID, let page = store.tabs.first(where: { $0.id == tabID })?.page else { return }
        Task {
            // Twice the card's width, so it's sharp on a Retina screen.
            guard let picture = await page.snapshot(width: Theme.liftedCard.width * 2) else { return }
            keepPicture(picture, for: tabID)
        }
    }

    private func keepPicture(_ picture: CGImage, for tabID: UUID) {
        let open = Set(store.tabs.map(\.id))
        pictureOrder.removeAll { $0 == tabID || !open.contains($0) }
        guard open.contains(tabID) else { return }
        pictureOrder.append(tabID)
        // Only the newest few: the panel never shows more than five a space.
        while pictureOrder.count > Self.pictureLimit { tabPictures[pictureOrder.removeFirst()] = nil }
        tabPictures = tabPictures.filter { open.contains($0.key) }
        tabPictures[tabID] = picture
    }

    private static let pictureLimit = 24
}
