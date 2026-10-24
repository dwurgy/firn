import FirnCore
import SwiftUI

/// What the window is doing, apart from its tabs: whether the address bar is
/// being edited, or the command bar is open.
@MainActor
@Observable
final class WindowModel {
    let store: BrowserStore
    /// Whether the command bar (⌘T) is open over the page.
    private(set) var showsCommandBar = false
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
            if !isDraggingTab, sidebarCollapsed, !pointerNearSidebar, !peekHeldForTyping { isPeeking = false }
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
    private var peekHideTask: Task<Void, Never>?
    /// The group whose name is being edited, if any. Here rather than in the
    /// sidebar so the menu bar's New Group can ask for a name too.
    var renamingGroupID: UUID?
    /// A group just made: its card starts thawed (looking like a loose tab)
    /// and frost forms around its tab (see `TabList`).
    var formingGroupID: UUID?
    /// The New space or Edit space card, while it's open. Here so the menu
    /// bar's New Space… can open it too.
    private(set) var spaceSheet: SpaceSheetMode?
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
    func newSpace() { openSpaceSheet(.new) }

    /// The welcome, over the whole window (see `WelcomeLayer`).
    private(set) var showsWelcome = false

    /// Opens the welcome: the first time Firn opens, or Help › Show Welcome Again.
    func showWelcome() {
        closeCommandBar(focusingPage: false)
        spaceSheet = nil
        showsWelcome = true
    }

    /// The welcome is done (finished or skipped): it doesn't come back on
    /// its own, and an empty window opens the command bar, as at any launch.
    func closeWelcome() {
        UserDefaults.standard.set(true, forKey: Preference.welcomed)
        showsWelcome = false
        if store.activeTab == nil { openCommandBar() }
    }

    /// A link from another app (Firn as the default browser) opens as a new
    /// tab in the space on screen, the space used last. Only web addresses:
    /// anything else macOS hands over is refused (CLAUDE.md, Security).
    func openFromOtherApp(_ url: URL) {
        guard WebAddress.isWebURL(url) else { return }
        closeCommandBar(focusingPage: false)
        store.closeLookout()
        store.openTab(url)
    }

    /// Opens the Edit space card for `space`.
    func editSpace(_ space: Space) { openSpaceSheet(.edit(space.id)) }

    private func openSpaceSheet(_ mode: SpaceSheetMode) {
        guard !showsWelcome else { return }
        closeCommandBar(focusingPage: false)
        spaceSheet = mode
    }

    /// Closes the space card; the page in front gets the keys back.
    func closeSpaceSheet() {
        guard spaceSheet != nil else { return }
        spaceSheet = nil
        focusPage()
    }

    /// The icon a new space starts on, picked the same way as its color.
    var freeSpaceIcon: SpaceIcon {
        SpaceIcon.next(after: store.spaces.map(\.icon))
    }

    /// The first space color no space has yet (or, with all taken, the next in turn).
    var freeSpaceColor: String {
        let taken = Set(store.spaces.map(\.color))
        let names = Theme.spaceColorNames
        return names.first { !taken.contains($0) } ?? names[store.spaces.count % names.count]
    }

    // MARK: Tab actions (the tab's right-click menu and the menu bar)

    /// Starts a group with an everyday tab. The tab doesn't move: its card
    /// appears thawed, in the tab's exact shape, so the change is invisible,
    /// and then the frost forms (`finishForming`). Reduce Motion: a fade.
    func newGroup(with tab: FirnCore.Tab) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let group = withAnimation(.easeOut(duration: 0.2)) { store.newGroup(with: tab) }
            if let group { askForName(group.id) }
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            formingGroupID = store.newGroup(with: tab)?.id
        }
    }

    /// The frost has formed around a new group: it asks for its name, when
    /// the sidebar is showing.
    func finishForming(_ id: UUID) {
        formingGroupID = nil
        askForName(id)
    }

    private func askForName(_ id: UUID) {
        if !sidebarCollapsed || isPeeking { renamingGroupID = id }
    }

    /// Closes a tab; if it was on screen, the tab shown next takes keyboard
    /// focus, so space and the arrow keys scroll it straight away.
    func close(_ tab: FirnCore.Tab) {
        let wasShowing = tab.id == store.activeTabID
        store.close(tab)
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
        } else if !peekHeldForTyping {
            peekHideTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, !pointerNearSidebar, !peekHeldForTyping, !isDraggingTab else { return }
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
        if sidebarCollapsed, !pointerNearSidebar { isPeeking = false }
    }

    // MARK: Command bar

    /// Opens the command bar (⌘T, the New tab button, an empty window). No
    /// tab exists until something in it is picked.
    func openCommandBar() {
        // Nothing opens behind the welcome to take its keys.
        guard !showsWelcome else { return }
        // A pick whose page has gone (closed, say) is over: the bar opens whole.
        if !isPickingSplit { splitPickAnchor = nil }
        spaceSheet = nil
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
}

/// One browser window: the sidebar and the page, on the space-tinted frame.
struct BrowserWindow: View {
    /// The whole window's space, for a tab dragged from the sidebar onto the page.
    nonisolated static let space = "browserWindow"
    let window: WindowModel
    @State private var lights = TrafficLights()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preference.newTabPlacement) private var newTabPlacement = NewTabPlacement.bottom
    @AppStorage(Preference.driftAfter) private var driftAfter = DriftAfter.sevenDays
    @AppStorage(Preference.blocksContent) private var blocksContent = true
    /// Waiting out the beat before idle tabs drift.
    @State private var driftTask: Task<Void, Never>?

    private var store: BrowserStore { window.store }
    private var showsSidebar: Bool { !window.sidebarCollapsed || window.isPeeking }

    var body: some View {
        ZStack(alignment: .leading) {
            // The page and the sidebar move together, frame by frame, on one curve.
            PageArea(store: store, window: window)
                .overlay { LookoutLayer(store: store, window: window) }
                .overlay { FindBarLayer(store: store, window: window) }
                .overlay { CommandBarLayer(store: store, window: window) }
                .overlay { SpaceSheetLayer(window: window) }
                .modifier(PageBesideSidebar(
                    reveal: window.sidebarCollapsed ? 0 : 1,
                    sidebarWidth: window.sidebarWidth
                ))
                .padding([.top, .trailing, .bottom], Theme.pageInset)
                .animation(slide, value: window.sidebarCollapsed)
            sidebarLayer
            if !window.sidebarCollapsed {
                // Its own layer, over everything, so the whole gap can be grabbed.
                SidebarResizeHandle(window: window, slide: slide)
                    .frame(width: Theme.pageInset + 3)
                    .padding(.leading, window.sidebarWidth - 3)
            }
        }
        // A dragged tab follows the pointer over everything, off the sidebar and onto the page.
        .overlay(alignment: .topLeading) { TabLiftGhost(window: window) }
        .overlay(alignment: .topLeading) { TileArrivalChip(window: window) }
        .accessibilityHidden(window.showsWelcome)
        .overlay { WelcomeLayer(window: window) }
        .coordinateSpace(.named(Self.space))
        .background {
            ZStack {
                FrameGlass()
                SpaceTint(color: store.activeSpace.color)
                // Empty frame (around the page, the sidebar's top row) moves the window.
                WindowDragArea()
                WindowSetup(lights: $lights)
                PointerTracker(
                    onMove: { window.pointerMoved(toX: $0) },
                    onLeave: { window.pointerLeftWindow() }
                )
                // The traffic lights ride along with the sidebar, frame by frame.
                Color.clear
                    .modifier(TrafficLightsSlide(
                        reveal: showsSidebar ? 1 : 0,
                        shift: peekShift,
                        distance: window.sidebarWidth,
                        fades: reduceMotion
                    ))
                    .animation(slide, value: showsSidebar)
                    .animation(slide, value: window.isPeeking)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .environment(\.spaceColorName, store.activeSpace.color)
        .navigationTitle(store.activeTab?.title ?? "Firn")
        .background(TabShortcuts(store: store, window: window))
        .onAppear {
            if store.activeTab == nil { window.openCommandBar() }
            // Launching may bring Firn to the front before this window listens.
            driftIdleTabs(afterABeat: true)
        }
        .onChange(of: newTabPlacement, initial: true) { store.newTabPlacement = newTabPlacement }
        .onChange(of: blocksContent) { BrowserEngine.setBlocking(enabled: blocksContent) }
        .onChange(of: driftAfter, initial: true) { old, new in
            store.driftAfter = driftAfter
            if old != new { driftIdleTabs(afterABeat: false) }
        }
        // Coming back to Firn (on a new day, perhaps, or at launch) is when
        // tabs drift. Nothing runs on a timer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            driftIdleTabs(afterABeat: true)
        }
        .onChange(of: store.activeTab == nil) {
            if store.activeTab == nil { window.openCommandBar() }
        }
        .onChange(of: store.activeTabID) { window.tabOnScreenChanged() }
        .onOpenURL { window.openFromOtherApp($0) }
    }

    private var slide: Animation { Theme.slide(reduceMotion: reduceMotion) }

    /// Idle tabs are tidied away. Coming back to Firn, it waits a beat
    /// first, so it's seen. With the sidebar showing, the space on screen's
    /// tabs go one by one (`TabList` shows each icon drifting down to the
    /// overflow button), then the button says so. With Reduce Motion they
    /// fade and the button says so; with the sidebar hidden, they simply
    /// go and the button's dot is left to tell. Other spaces' tabs go
    /// quietly.
    private func driftIdleTabs(afterABeat: Bool) {
        driftTask?.cancel()
        driftTask = Task { @MainActor in
            if afterABeat {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, NSApp.isActive else { return }
            }
            let idle = store.idleTabs()
            let here = idle.filter { $0.spaceID == store.activeSpaceID }
            let watched = showsSidebar && !reduceMotion ? here : []
            let watchedIDs = Set(watched.map(\.id))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : nil) {
                for tab in idle where !watchedIDs.contains(tab.id) { store.drift(tab) }
            }
            if !watched.isEmpty {
                window.tidyQueue += watched.filter { tab in !window.tidyQueue.contains { $0.id == tab.id } }
            } else if showsSidebar {
                let count = here.count { $0.place == .drifted }
                if count > 0 { window.announceTidied(count) }
            }
        }
    }

    /// While peeking, the sidebar is a card floating just inside the window
    /// edge, so it and its traffic lights sit this much further in.
    private var peekShift: CGFloat { window.isPeeking ? Theme.peekInset : 0 }
    /// Hidden, the sidebar keeps its card look (wider by the page inset, with a
    /// shadow up to 24pt blur and 4pt across), so it slides that much further out.
    private var hiddenOffset: CGFloat {
        -(window.sidebarWidth + (window.sidebarCollapsed ? Theme.pageInset + 32 : 0))
    }

    /// The sidebar always stays in the view tree and slides by an offset, so a
    /// slide can reverse midway (a quick peek in and out) without a jump.
    private var sidebarLayer: some View {
        ZStack(alignment: .leading) {
            Sidebar(store: store, window: window, lights: lights)
                .frame(width: window.sidebarWidth)
                // Blank sidebar moves the window (as in Dia), and never lets a
                // click fall through to the page under a peeking card.
                .background { WindowDragArea() }
                .background(alignment: .leading) { sidebarBackground }
                .offset(x: reduceMotion || showsSidebar ? peekShift : hiddenOffset)
                .opacity(reduceMotion && !showsSidebar ? 0 : 1)
                .allowsHitTesting(showsSidebar)
                .accessibilityHidden(!showsSidebar)
                .animation(slide, value: showsSidebar)
                .animation(slide, value: window.isPeeking)
        }
    }

    /// Nothing while docked, so the sidebar sits on the window's glass seamlessly.
    /// While it peeks over the page it's a card floating just outside the
    /// page's edge, its corners nesting with the page's: a little wider than the
    /// sidebar, so its buttons have room at the right, with a soft shadow.
    private var sidebarBackground: some View {
        // Held for the whole slide, not just while the pointer is near, so the
        // edge and shadow travel with the card as it leaves instead of fading early.
        let floating = window.sidebarCollapsed
        let radius = floating ? Theme.peekCornerRadius : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Docked, it's clear: the window's own glass is the sidebar.
        return ZStack {
            FrameGlass(overPage: true)
            SpaceTint(color: store.activeSpace.color)
        }
        .opacity(floating ? 1 : 0)
        .clipShape(shape)
        .overlay {
            // Always drawn, so it never has to fade in or out apart from the card.
            Group {
                // A glass edge: a hairline to define the card, a lit rim just inside it.
                shape.strokeBorder(Theme.peekEdgeLine, lineWidth: 0.5)
                shape.inset(by: 0.5).strokeBorder(
                    LinearGradient(colors: [Theme.peekEdgeRim, Theme.peekEdgeRim.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .opacity(floating ? 1 : 0)
        }
        .shadow(color: floating ? Theme.shadowPeek : .clear, radius: 24, x: 4, y: 8)
        .shadow(color: floating ? Theme.shadowPeek.opacity(0.5) : .clear, radius: 3, y: 1)
        .frame(width: window.sidebarWidth + (floating ? Theme.pageInset : 0))
        .padding(.vertical, floating ? Theme.peekInset : 0)
        .ignoresSafeArea()
        // The window's drag area underneath still moves the window from the top row.
        .allowsHitTesting(false)
    }
}

/// Keeps the page beside the sidebar. SwiftUI calls `body` on every frame of
/// an animation with the in-between values, so the page's real size (not just
/// its picture) follows the sidebar smoothly, the way a live window resize does.
private struct PageBesideSidebar: ViewModifier, Animatable {
    /// 1 when the sidebar is in its place, 0 when it's hidden.
    var reveal: CGFloat
    var sidebarWidth: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(reveal, sidebarWidth) }
        set { reveal = newValue.first; sidebarWidth = newValue.second }
    }

    func body(content: Content) -> some View {
        content.padding(.leading, Theme.pageInset + reveal * sidebarWidth)
    }
}

/// Hands the sidebar's slide, one frame at a time, to the traffic lights.
/// SwiftUI calls `body` on every frame of the animation with the in-between
/// value, so the lights move on exactly the sidebar's curve.
private struct TrafficLightsSlide: ViewModifier, Animatable {
    /// 1 when the sidebar is showing, 0 when it's slid away.
    var reveal: CGFloat
    /// How far in the peeking card sits.
    var shift: CGFloat
    let distance: CGFloat
    let fades: Bool

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(reveal, shift) }
        set { reveal = newValue.first; shift = newValue.second }
    }

    func body(content: Content) -> some View {
        content.background(TrafficLightsMover(
            offset: fades ? shift : -(1 - reveal) * distance + shift,
            alpha: fades ? reveal : 1,
            hidden: reveal <= 0.001
        ))
    }
}

/// The gap between the sidebar and the page: drag it to set the sidebar's
/// width. Pulling narrower stops at the minimum, and pulling on past that
/// snaps the sidebar away. Double-click for the standard width.
private struct SidebarResizeHandle: View {
    let window: WindowModel
    let slide: Animation
    @State private var startWidth: CGFloat?

    var body: some View {
        SidebarResizeGrip(
            onDrag: { distance in
                let start = startWidth ?? window.sidebarWidth
                startWidth = start
                guard !window.sidebarCollapsed else { return }
                switch SidebarSizing.outcome(forProposedWidth: start + distance) {
                case .width(let width):
                    window.sidebarWidth = width
                case .collapse:
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    window.setSidebarCollapsed(true)
                }
            },
            onEnd: { startWidth = nil },
            onDoubleClick: { withAnimation(slide) { window.sidebarWidth = CGFloat(SidebarSizing.standard) } }
        )
    }
}

/// The page on screen, floating in the frame. With no tab open, a calm
/// empty page. In split view, two pages side by side, with a gap between
/// them that can be dragged (double-click evens them) and a thin frost ring
/// on the page in use; pressing the other page moves it there, and the
/// address bar and buttons follow. Picking a page for a split, the page
/// takes the left half beside an empty one. One layout for all three, so
/// the left page never changes places between them (swapping whole layouts
/// left the old one stuck over the new split).
private struct PageArea: View {
    let store: BrowserStore
    let window: WindowModel
    @State private var startFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = store.activeTab
        let split = active.flatMap { store.split(of: $0) }
        let pair = split.map { store.tabs(in: $0) } ?? []
        let drop = window.pageDrop
        // Picking a split's page, or a tab dragged over one page, shows
        // halves, as a new split has.
        let fraction = split?.leftFraction ?? (window.isPickingSplit || drop != nil ? 0.5 : nil)
        GeometryReader { proxy in
            let room = max(proxy.size.width - Theme.pageInset, 1)
            let leftWidth = fraction.map { room * $0 } ?? proxy.size.width
            let rightX = leftWidth + Theme.pageInset
            // Each page keeps its place in a ZStack, by its tab, so it glides
            // from one half to the other instead of being made again.
            ZStack(alignment: .topLeading) {
                ForEach(slots(active: active, pair: pair, drop: drop)) { slot in
                    Group {
                        if slot.isFrost, drop != nil {
                            DropFrost(window: window, color: Theme.spaceColor(store.activeSpace.color))
                                .transition(.opacity)
                        } else {
                            page(slot.tab, inUseID: split == nil ? nil : active?.id,
                                 frosted: split != nil && drop?.side == slot.side ? drop?.tab : nil)
                        }
                    }
                    .frame(width: slot.side == nil ? proxy.size.width
                               : slot.side == .left ? leftWidth : max(proxy.size.width - rightX, 0),
                           height: proxy.size.height)
                    // Padding, not an offset, so the web view itself moves, not just its picture.
                    .padding(.leading, slot.side == .right ? rightX : 0)
                }
                if let split {
                    grip(split, room: room)
                        .frame(height: proxy.size.height)
                        .padding(.leading, leftWidth)
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BrowserWindow.space)) } action: {
            window.pagesFrame = $0
        }
    }

    /// What shows where: a split's two pages; one page beside the frost of
    /// a tab dragged over the other half (or beside an empty page while
    /// one is picked); or one page across the whole width.
    private func slots(active: FirnCore.Tab?, pair: [FirnCore.Tab], drop: PageDrop?) -> [PageSlot] {
        if pair.count == 2 {
            return [PageSlot(id: pair[0].id, tab: pair[0], side: .left),
                    PageSlot(id: pair[1].id, tab: pair[1], side: .right)]
        }
        let id = active?.id ?? PageSlot.emptyID
        if let drop {
            // The tab on screen dragged over a half goes there; the frost
            // shows where a new page will be.
            let frostSide = drop.tab.id == active?.id ? drop.side.other : drop.side
            return [PageSlot(id: id, tab: active, side: frostSide.other),
                    PageSlot(id: frostSide == .left ? PageSlot.leftFrostID : PageSlot.rightFrostID,
                             tab: nil, side: frostSide, isFrost: true)]
        }
        if window.isPickingSplit {
            return [PageSlot(id: id, tab: active, side: window.splitPickSide),
                    PageSlot(id: PageSlot.emptyID, tab: nil, side: window.splitPickSide.other)]
        }
        return [PageSlot(id: id, tab: active, side: nil)]
    }

    private func grip(_ split: SplitGroup, room: CGFloat) -> some View {
        SidebarResizeGrip(
            onDrag: { distance in
                let start = startFraction ?? split.leftFraction
                startFraction = start
                store.setLeftFraction(of: split, to: start + distance / room)
            },
            onEnd: { startFraction = nil },
            onDoubleClick: {
                withAnimation(Theme.slide(reduceMotion: reduceMotion)) {
                    store.setLeftFraction(of: split, to: 0.5)
                }
            }
        )
        .frame(width: Theme.pageInset)
        .accessibilityLabel("Resize split view")
        .accessibilityValue("Left page \(Int((split.leftFraction * 100).rounded())) percent")
        // VoiceOver can move the divider too, a twentieth of the way at a time.
        .accessibilityAdjustableAction { direction in
            let step = switch direction {
            case .increment: 0.05
            case .decrement: -0.05
            @unknown default: 0.0
            }
            store.setLeftFraction(of: split, to: split.leftFraction + step)
        }
    }

    /// A page; in split view (`inUseID` set), ringed when it's the one in
    /// use, and made the one in use when pressed.
    /// `frosted`: a tab dragged over this half of a split, which would take its place.
    private func page(_ tab: FirnCore.Tab?, inUseID: UUID?, frosted: FirnCore.Tab?) -> some View {
        let isInUse = tab != nil && tab?.id == inUseID
        let pressable = inUseID != nil && !isInUse
        // With no tab open at all, the empty page is First light, in this space's snow.
        let firstLight = store.activeTab == nil && inUseID == nil ? store.activeSpace.color : nil
        return PagePane(tab: tab, firstLight: firstLight,
                        onPointerDown: pressable ? { if let tab { store.select(tab) } } : nil)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                    .strokeBorder(Theme.frost, lineWidth: 2)
                    .opacity(isInUse ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: isInUse)
            .overlay {
                if frosted != nil {
                    DropFrost(window: window, color: Theme.spaceColor(store.activeSpace.color))
                        .transition(.opacity)
                }
            }
    }
}

/// A tab lifted off the sidebar. It's drawn over the whole window, not in
/// the list, so it can leave the sidebar. In the sidebar it's the row,
/// kept to the sidebar's column (giving a little toward the pointer); once
/// the pointer is out over a page where it could open in split view, it
/// comes loose as a small picture of its page (as in Dia). Let go in the
/// sidebar, it glides into its slot. It keeps hold of the same spot under
/// the pointer as it changes shape.
struct TabLift {
    let tab: FirnCore.Tab
    /// The row as drawn in the sidebar.
    let row: AnyView
    /// Where the pointer holds it, as a fraction of its width and height.
    let grab: CGPoint
    /// The row's width (its slot's, which narrows inside a group card).
    var width: CGFloat
    /// The row's left edge in the window: its slot's.
    var column: CGFloat
    /// Out over the page: the picture, not the row.
    var isCard = false
    /// The page's picture, once taken; nil for a sleeping page.
    var preview: CGImage?
    /// Let go in the sidebar: the slot it glides into, in the window's space.
    var settle: CGRect?
    /// Settling into a folded group: it fades into the name line.
    var fades = false
    /// Held over a tab to make a group with it: solid, so the tab under it
    /// doesn't show through.
    var solid = false
    /// Settling into a group forming under it: just the row, no backing or
    /// shadow, so it lands on the glass as the row itself.
    var bare = false
    /// Picked up from Basecamp: the tile as drawn there, and where it's
    /// held, in the window's space.
    var tileFace: AnyView?
    var tile: CGRect?
    /// Drawn as the tile (in Basecamp), not the row (over the tab list).
    var isTile = false
    /// How high and low the row's top may go, in the window's space: the
    /// tab list's. Past these it only tugs (`Tug`).
    var reach: ClosedRange<CGFloat>?
}

/// A Basecamp tile dragged out over the tab list (see `WindowModel.tileInList`),
/// or a tab dragged up over Basecamp (`WindowModel.tabInBasecamp`).
struct TileInList: Equatable {
    let tab: FirnCore.Tab
    /// The tab's id, kept here so comparing needs no main actor.
    private let tabID: UUID
    /// Let go: the list settles it into its place.
    var released = false

    @MainActor init(tab: FirnCore.Tab) {
        self.tab = tab
        tabID = tab.id
    }

    static func == (a: Self, b: Self) -> Bool { a.tabID == b.tabID && a.released == b.released }
}

private struct TabLiftGhost: View {
    let window: WindowModel

    var body: some View {
        if let lift = window.tabLift {
            ZStack(alignment: .topLeading) {
                lift.row
                    .frame(width: lift.width, height: Theme.rowHeight)
                    .opacity(lift.isCard || lift.isTile ? 0 : 1)
                if let face = lift.tileFace, let tile = lift.tile {
                    face
                        .frame(width: tile.width, height: tile.height)
                        .opacity(lift.isTile && !lift.isCard ? 1 : 0)
                }
                card(lift)
                    // At least the picture's size, so turning from the row
                    // (or tile) uncovers it rather than squeezing it.
                    .frame(minWidth: Theme.liftedCard.width, maxWidth: .infinity,
                           minHeight: Theme.liftedCard.height, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(lift.isCard ? 1 : 0)
            }
            .modifier(LiftPlacement(card: lift.isCard ? 1 : 0, settled: lift.settle == nil ? 0 : 1,
                                    width: lift.width, column: lift.column,
                                    pointer: window.dragPointer, grab: lift.grab, slot: lift.settle,
                                    tile: lift.tile, tileness: lift.isTile ? 1 : 0, reach: lift.reach,
                                    solid: lift.solid ? 1 : 0, bare: lift.bare ? 1 : 0))
            .opacity(lift.fades ? 0 : 1)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The page's picture, from the top; a sleeping page, its icon and title.
    @ViewBuilder private func card(_ lift: TabLift) -> some View {
        if let preview = lift.preview {
            LiftPicture(image: preview)
        } else {
            VStack(spacing: 8) {
                SiteIconView(icon: lift.tab.icon, size: 22) {
                    Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(Theme.muted)
                }
                Text(lift.tab.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            // The card's own size, not the row's it grows from, so it's centered.
            .frame(width: Theme.liftedCard.width, height: Theme.liftedCard.height)
        }
    }
}

/// The page's picture, from the top, filling the card.
private struct LiftPicture: View {
    let image: CGImage

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let scale = max(w / CGFloat(max(image.width, 1)), h / CGFloat(max(image.height, 1)))
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                .frame(width: w, height: h, alignment: .top)
                .clipped()
        }
    }
}

/// Where the lifted tab is and what shape it has: the row in the sidebar's
/// column, the picture at the pointer, or the row settling into its slot,
/// and every step between. Worked out from these numbers as they animate,
/// with the pointer read fresh each time, so the pointer moving never
/// interrupts a change of shape.
private struct LiftPlacement: ViewModifier, Animatable {
    /// 0 the row, 1 the picture.
    var card: CGFloat
    /// 0 following the pointer, 1 in its slot.
    var settled: CGFloat
    var width: CGFloat
    var column: CGFloat
    let pointer: CGPoint
    let grab: CGPoint
    let slot: CGRect?
    /// A tile's held place, standing in for the row.
    let tile: CGRect?
    /// 0 the row, 1 the tile.
    var tileness: CGFloat
    let reach: ClosedRange<CGFloat>?
    /// 0 the usual backing, 1 fully solid.
    let solid: CGFloat
    /// 0 lifted, 1 just the row (backing and shadow gone).
    var bare: CGFloat

    nonisolated var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>,
                                                   AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(AnimatablePair(card, settled), tileness),
                           AnimatablePair(AnimatablePair(width, column), bare))
        }
        set {
            card = newValue.first.first.first
            settled = newValue.first.first.second
            tileness = newValue.first.second
            width = newValue.second.first.first
            column = newValue.second.first.second
            bare = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        // The row keeps to its column, giving at most 8pt toward the pointer,
        // as if about to come loose.
        let pull = pointer.x - (column + grab.x * width)
        var top = pointer.y - grab.y * Theme.rowHeight
        if let reach { top = Tug.held(top, reach.lowerBound, reach.upperBound) }
        var row = CGRect(x: column + 8 * CGFloat(tanh(Double(pull) / 60)),
                         y: top, width: width, height: Theme.rowHeight)
        if let slot { row = Self.mix(row, slot, settled) }
        if let tile { row = Self.mix(row, tile, tileness) }
        let size = Theme.liftedCard
        let picture = CGRect(x: pointer.x - grab.x * size.width, y: pointer.y - grab.y * size.height,
                             width: size.width, height: size.height)
        let frame = Self.mix(row, picture, card)
        let corner = Theme.tabRadius + (Theme.tileRadius - Theme.tabRadius) * (tile == nil ? 0 : tileness)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let lift = card
        return content
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .background {
                ZStack {
                    shape.fill(Theme.frame).opacity(solid)
                    LiftBacking(shape: shape)
                }
                .opacity(1 - bare)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.frost, lineWidth: 1).opacity(lift) }
            .shadow(color: Theme.shadowPageFar.opacity(1 - bare), radius: 8 + 6 * lift, y: 3 + 3 * lift)
            .offset(x: frame.minX, y: frame.minY)
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ amount: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * amount, y: a.minY + (b.minY - a.minY) * amount,
               width: a.width + (b.width - a.width) * amount, height: a.height + (b.height - a.height) * amount)
    }
}

/// Where one page sits in `PageArea`: a half, or the whole width (`side` nil).
private struct PageSlot: Identifiable {
    /// The empty page beside one being picked for, or with no tab at all.
    static let emptyID = UUID()
    /// A frost on each side, so moving halves thaws one and forms the other.
    static let leftFrostID = UUID()
    static let rightFrostID = UUID()
    let id: UUID
    let tab: FirnCore.Tab?
    let side: SplitSide?
    var isFrost = false
}

/// A tab dragged out of the sidebar, over a half of the page.
struct PageDrop: Equatable {
    let tab: FirnCore.Tab
    private let tabID: UUID
    var side: SplitSide

    @MainActor init(tab: FirnCore.Tab, side: SplitSide) {
        self.tab = tab
        tabID = tab.id
        self.side = side
    }

    static func == (a: PageDrop, b: PageDrop) -> Bool { a.tabID == b.tabID && a.side == b.side }
}

/// Where a dragged tab would open: frost over that half, in the space's
/// color (`docs/split-drop-design.html`), forming from under its picture.
private struct DropFrost: View {
    let window: WindowModel
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where it starts forming: under the picture, in the frost's own space.
    @State private var origin: CGPoint?
    /// 0 nothing yet, 1 frosted across the whole half.
    @State private var formed: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        GeometryReader { proxy in
            let size = proxy.size
            let start = origin ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = Self.farthest(from: start, in: size) + Self.softEdge * 2
            ZStack {
                glass(shape)
                shape.strokeBorder(Theme.frost, lineWidth: 1.5)
            }
            // Ice forming on a window: a soft-edged circle widening from the picture.
            .mask {
                Circle()
                    .frame(width: reach * 2, height: reach * 2)
                    .scaleEffect(formed)
                    .position(start)
                    .blur(radius: Self.softEdge)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BrowserWindow.space)) } action: { begin(in: $0) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let softEdge: CGFloat = 24
    /// Once, when it first has a place: forms from under the picture.
    private func begin(in area: CGRect) {
        guard origin == nil, area.width > 0 else { return }
        var start = CGPoint(x: area.width / 2, y: area.height / 2)
        if let lift = window.tabLift {
            let card = Theme.liftedCard
            start = CGPoint(x: window.dragPointer.x + (0.5 - lift.grab.x) * card.width - area.minX,
                            y: window.dragPointer.y + (0.5 - lift.grab.y) * card.height - area.minY)
            start.x = min(max(start.x, 0), area.width)
            start.y = min(max(start.y, 0), area.height)
        }
        origin = start
        guard !reduceMotion else { formed = 1; return }
        withAnimation(.smooth(duration: 0.4)) { formed = 1 }
    }

    private static func farthest(from point: CGPoint, in size: CGSize) -> CGFloat {
        let dx = max(point.x, size.width - point.x), dy = max(point.y, size.height - point.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    @ViewBuilder private func glass(_ shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid).overlay { shape.fill(color.opacity(Theme.dropTint)) }
        } else if #available(macOS 26, *) {
            shape.fill(.clear).glassEffect(.regular.tint(color.opacity(Theme.dropTint)), in: shape)
        } else {
            shape.fill(.ultraThinMaterial).overlay { shape.fill(color.opacity(Theme.dropTint)) }
        }
    }
}

extension SplitSide {
    var other: SplitSide { self == .left ? .right : .left }
}

/// Where the pages sit while a split is being picked: halves, as a new split has.
enum SplitPicking {
    static func leftWidth(in width: CGFloat) -> CGFloat {
        max(width - Theme.pageInset, 1) * 0.5
    }
}

/// One page, floating in the frame, or a calm empty page with no tab.
private struct PagePane: View {
    let tab: FirnCore.Tab?
    /// The space's color, when this is the empty page (no tab open).
    var firstLight: String? = nil
    var onPointerDown: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        ZStack {
            // The sidebar covers whatever shadow falls on it, which would leave a hard
            // line in the gap. So the shadow leans right and down and fades inside the gap.
            shape
                .fill(Theme.page)
                .shadow(color: Theme.shadowPageFar, radius: 12, x: 4, y: 8)
            if tab == nil, let firstLight {
                FirstLightScene(spaceColor: firstLight)
                    .clipShape(shape)
                    .transition(.opacity)
            }
            if let tab, let page = tab.page {
                PageView(page: page, cornerRadius: Theme.pageCornerRadius, onPointerDown: onPointerDown)
                    .overlay {
                        if let error = page.loadError {
                            LoadErrorView(error: error, isRetrying: page.isLoading, retry: page.reload)
                                .clipShape(shape)
                                .transition(.opacity)
                                .simultaneousGesture(TapGesture().onEnded { onPointerDown?() })
                        } else if page.url == nil {
                            // Until something has loaded, show Firn's calm page color, not WebKit's white.
                            shape.fill(Theme.page).allowsHitTesting(false)
                        }
                    }
                    // A plain fade either way; quicker with Reduce Motion.
                    .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: page.loadError)
                    .id(tab.id)
            }
        }
    }
}

/// ⌘1–9 and ⇧⌘[ / ⇧⌘], which don't need their own menu items.
/// ⌃Tab and ⌃⇧Tab are in the Window menu, where they can be found.
private struct TabShortcuts: View {
    let store: BrowserStore
    let window: WindowModel

    var body: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") { select { store.selectTab(at: number - 1) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")))
            }
            Button("Next Tab") { select { store.selectTab(by: 1) } }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { select { store.selectTab(by: -1) } }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            // ⌘+ needs Shift on most keyboards; ⌘= is the same key without it.
            Button("Zoom In") { window.zoomFront(.larger) }
                .keyboardShortcut("=")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func select(_ change: () -> Void) {
        change()
        window.focusPage()
    }
}

// MARK: - Menu commands

/// Menu items, so every action can be found by looking, with the Mac
/// shortcuts as a bonus.
struct BrowserCommands: Commands {
    let window: WindowModel
    @AppStorage(Preference.blocksContent) private var blocksContent = true

    private var store: BrowserStore { window.store }
    private var page: (any PageController)? { window.frontPage }
    private var everydayTab: FirnCore.Tab? { window.everydayTab }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { window.openCommandBar() }
                .keyboardShortcut("t")
            Button("Open Location…") { window.editAddress() }
                .keyboardShortcut("l")
            Divider()
            Button("Duplicate Tab") { if let tab = everydayTab { window.duplicate(tab) } }
                .disabled(everydayTab?.url == nil)
            // As in Dia.
            Button("New Group with This Tab") {
                if let tab = everydayTab {
                    window.newGroup(with: tab)
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .control])
            .disabled(everydayTab == nil || everydayTab?.groupID != nil)
            Divider()
            Button("New Space…") { window.newSpace() }
        }
        CommandGroup(replacing: .printItem) {
            // The page in front: a Lookout's while one is open.
            Button("Print…") { page?.printPage() }
                .keyboardShortcut("p")
                .disabled(page?.url == nil || page?.loadError != nil)
        }
        // As in Arc and Dia.
        CommandGroup(after: .pasteboard) {
            Button("Copy Link") { window.copyFrontLink() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(window.frontURL == nil)
        }
        // Safari's Find menu, for the page in front (a Lookout's while one is
        // open). In place of the Mac's own, which would act on text fields only.
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                Button("Find…") { window.openFindBar() }
                    .keyboardShortcut("f")
                Button("Find Next") { window.find(.next) }
                    .keyboardShortcut("g")
                Button("Find Previous") { window.find(.previous) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Use Selection for Find") { window.useSelectionForFind() }
                    .keyboardShortcut("e")
            }
            .disabled(!window.canFindInFront)
        }
        // As in Arc and Dia: ⌘W closes the tab, ⇧⌘W the window.
        CommandGroup(replacing: .saveItem) {
            // With a Lookout open, ⌘W closes the Lookout, not the tab under it (as in Arc).
            Button(store.lookout == nil ? "Close Tab" : "Close Lookout") { window.closeFront() }
                .keyboardShortcut("w")
                .disabled(store.activeTab == nil && store.lookout == nil)
            Button(store.nextToReopen == .group ? "Reopen Closed Group" : "Reopen Closed Tab") { window.reopenClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(store.nextToReopen == nil)
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Back") { page?.goBack() }
                .keyboardShortcut("[")
                .disabled(page?.canGoBack != true)
            Button("Forward") { page?.goForward() }
                .keyboardShortcut("]")
                .disabled(page?.canGoForward != true)
            Divider()
            Button("Reload Page") { page?.reload() }
                .keyboardShortcut("r")
                .disabled(!window.canReloadFront)
            #if DEBUG
            Divider()
            // For trying drifting without waiting days; never in a release build.
            Button("Tidy Away Loose Tabs Now (Debug)") {
                window.tidyQueue += store.looseTabs.filter { tab in
                    tab.id != store.activeTabID && !window.tidyQueue.contains { $0.id == tab.id }
                }
            }
            #endif
        }
        CommandGroup(replacing: .sidebar) {
            Button(window.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") { window.toggleSidebar() }
                .keyboardShortcut("s")
            Divider()
            // The page in front, as with Print. ⌘= also zooms in (TabShortcuts).
            Button("Zoom In") { window.zoomFront(.larger) }
                .keyboardShortcut("+")
                .disabled(!window.canZoomFront(.larger))
            Button("Zoom Out") { window.zoomFront(.smaller) }
                .keyboardShortcut("-")
                .disabled(!window.canZoomFront(.smaller))
            Button("Actual Size") { window.zoomFront(.actualSize) }
                .keyboardShortcut("0")
                .disabled(!window.canZoomFront(.actualSize))
            if let name = window.frontBlockingName(enabled: blocksContent) {
                Divider()
                Button(name) { window.toggleFrontBlocking() }
            }
        }
        CommandGroup(replacing: .help) {
            Button("Show Welcome Again") { window.showWelcome() }
                .disabled(window.showsWelcome)
        }
        CommandGroup(before: .windowArrangement) {
            Button("Show Next Tab") { store.selectTab(by: 1); window.focusPage() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(store.sidebarRows.count < 2)
            Button("Show Previous Tab") { store.selectTab(by: -1); window.focusPage() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(store.sidebarRows.count < 2)
            Divider()
            // As in Arc: ⌃1–9 for a space, ⌥⌘ and the arrows for the next one.
            ForEach(Array(store.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button(space.name) { window.showSpace { store.selectSpace(space) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
            Button("Show Next Space") { window.showSpace { store.selectSpace(by: 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
                .disabled(store.spaces.count < 2)
            Button("Show Previous Space") { window.showSpace { store.selectSpace(by: -1) } }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
                .disabled(store.spaces.count < 2)
            Divider()
        }
    }
}
