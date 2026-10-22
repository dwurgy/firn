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
    /// A split just made: its row opens from its left tab's row (see `SplitRow`).
    var formingSplitID: UUID?
    /// Whether that's happening now, with its tab on screen.
    var isPickingSplit: Bool {
        splitPickAnchor != nil && splitPickAnchor?.id == store.activeTabID
    }
    /// The command bar was opened to pick a split's page, so it sits over
    /// the right half. Kept until it's next opened, so it fades out where it was.
    private(set) var commandBarOnRightHalf = false
    /// Goes up each time the address bar is asked to take focus.
    private(set) var addressRequest = 0

    /// A tab dragged out of the sidebar over the page: which half it's
    /// over, where frost shows it would open (see `PageArea`).
    var pageDrop: PageDrop?
    /// The pointer during that drag, in the window's space, for the lifted
    /// row following it over the page. Apart from `pageDrop`, so the pages
    /// don't redraw as the pointer moves.
    var pageDropPointer: CGPoint = .zero
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
    /// The New space or Edit space sheet, while it's open. Here so the menu
    /// bar's New Space… can open it too.
    var spaceSheet: SpaceSheetMode?
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
    /// Whether the overflow (drifted tabs and Recently closed) is open.
    var showsOverflow = false

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

    /// Opens the New space sheet.
    func newSpace() { spaceSheet = .new }

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

    /// Puts the tab's address on the clipboard (only http and https reach a tab).
    func copyLink(of tab: FirnCore.Tab) {
        guard let url = tab.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
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
        commandBarOnRightHalf = splitPickAnchor != nil
        showsCommandBar = true
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

    /// Open as Split on the tab on screen or a Basecamp tile: the page
    /// glides over to the left half, and the command bar opens over the
    /// empty right half to pick what goes there. Esc leaves things as they were.
    func pickSplit(beside tab: FirnCore.Tab) {
        store.select(tab)
        withAnimation(Theme.slide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            splitPickAnchor = tab
        }
        openCommandBar()
    }

    /// Shows `incoming` beside `anchor` in split view; a new split's row
    /// forms in the sidebar.
    func openSplit(_ incoming: FirnCore.Tab, beside anchor: FirnCore.Tab) {
        let existing = Set(store.splits.map(\.id))
        if let split = store.openSplit(incoming, beside: anchor), !existing.contains(split.id) {
            formingSplitID = split.id
        }
    }

    /// A dragged tab let go over the page: it opens on the half the frost
    /// showed, the frost giving way to the page.
    func dropOnPage() {
        guard let drop = pageDrop else { return }
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
    /// Waiting out the beat before idle tabs drift.
    @State private var driftTask: Task<Void, Never>?

    private var store: BrowserStore { window.store }
    private var showsSidebar: Bool { !window.sidebarCollapsed || window.isPeeking }

    var body: some View {
        ZStack(alignment: .leading) {
            // The page and the sidebar move together, frame by frame, on one curve.
            PageArea(store: store, window: window)
                .overlay { LookoutLayer(store: store, window: window) }
                .overlay { CommandBarLayer(store: store, window: window) }
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
        // A tab dragged out over the page: its row follows the pointer, over everything.
        .overlay(alignment: .topLeading) { PageDropGhost(window: window) }
        .coordinateSpace(.named(Self.space))
        .background {
            ZStack {
                Theme.frame
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
        .navigationTitle(store.activeTab?.title ?? "Firn")
        .background(TabShortcuts(store: store, window: window))
        .sheet(item: Binding(get: { window.spaceSheet }, set: { window.spaceSheet = $0 })) { mode in
            SpaceSheet(window: window, mode: mode)
        }
        .onAppear {
            if store.activeTab == nil { window.openCommandBar() }
            // Launching may bring Firn to the front before this window listens.
            driftIdleTabs(afterABeat: true)
        }
        .onChange(of: newTabPlacement, initial: true) { store.newTabPlacement = newTabPlacement }
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

    /// The frame's own color, so the sidebar sits on the window seamlessly.
    /// While it peeks over the page it's a card floating just outside the
    /// page's edge, its corners nesting with the page's: a little wider than the
    /// sidebar, so its buttons have room at the right, with a soft shadow.
    private var sidebarBackground: some View {
        // Held for the whole slide, not just while the pointer is near, so the
        // edge and shadow travel with the card as it leaves instead of fading early.
        let floating = window.sidebarCollapsed
        let radius = floating ? Theme.peekCornerRadius : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            Theme.frame
            SpaceTint(color: store.activeSpace.color)
        }
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
                        if slot.isFrost, let drop {
                            DropFrost(tab: drop.tab, color: Theme.spaceColor(store.activeSpace.color))
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
            return [PageSlot(id: id, tab: active, side: drop.side == .left ? .right : .left),
                    PageSlot(id: PageSlot.frostID, tab: nil, side: drop.side, isFrost: true)]
        }
        if window.isPickingSplit {
            return [PageSlot(id: id, tab: active, side: .left),
                    PageSlot(id: PageSlot.emptyID, tab: nil, side: .right)]
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
    }

    /// A page; in split view (`inUseID` set), ringed when it's the one in
    /// use, and made the one in use when pressed.
    /// `frosted`: a tab dragged over this half of a split, which would take its place.
    private func page(_ tab: FirnCore.Tab?, inUseID: UUID?, frosted: FirnCore.Tab?) -> some View {
        let isInUse = tab != nil && tab?.id == inUseID
        let pressable = inUseID != nil && !isInUse
        return PagePane(tab: tab, onPointerDown: pressable ? { if let tab { store.select(tab) } } : nil)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
                    .strokeBorder(Theme.frost, lineWidth: 2)
                    .opacity(isInUse ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: isInUse)
            .overlay {
                if let frosted {
                    DropFrost(tab: frosted, color: Theme.spaceColor(store.activeSpace.color))
                        .transition(.opacity)
                }
            }
    }
}

/// The row of a tab dragged over the page, shrunk to fit beside the
/// pointer (in the sidebar, the list draws its own lifted row).
private struct PageDropGhost: View {
    let window: WindowModel

    var body: some View {
        if let drop = window.pageDrop {
            HStack(spacing: 8) {
                SiteIconView(icon: drop.tab.icon, size: 16) {
                    Image(systemName: "globe").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Text(drop.tab.title)
                    .font(Theme.tabFont)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.rowPadding)
            .frame(width: 220, height: Theme.rowHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(Theme.activeTab)
                    .shadow(color: Theme.shadowPageFar, radius: 8, y: 3)
            }
            .offset(x: window.pageDropPointer.x - 24, y: window.pageDropPointer.y - Theme.rowHeight / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Where one page sits in `PageArea`: a half, or the whole width (`side` nil).
private struct PageSlot: Identifiable {
    /// The empty page beside one being picked for, or with no tab at all.
    static let emptyID = UUID()
    static let frostID = UUID()
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
/// color, with the tab's site icon and title (`docs/split-drop-design.html`).
private struct DropFrost: View {
    let tab: FirnCore.Tab
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        VStack(spacing: 10) {
            SiteIconView(icon: tab.icon, size: 32) {
                Image(systemName: "globe").font(.system(size: 26)).foregroundStyle(Theme.muted)
            }
            Text(tab.title)
                .font(Theme.tabFont)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(maxWidth: 260)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { glass(shape) }
        .overlay { shape.strokeBorder(Theme.frost, lineWidth: 1.5) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// Where the pages sit while a split is being picked: halves, as a new split has.
enum SplitPicking {
    static func leftWidth(in width: CGFloat) -> CGFloat {
        max(width - Theme.pageInset, 1) * 0.5
    }
}

/// One page, floating in the frame, or a calm empty page with no tab.
private struct PagePane: View {
    let tab: FirnCore.Tab?
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
        }
        // As in Arc and Dia.
        CommandGroup(after: .pasteboard) {
            Button("Copy Link") { if let tab = store.activeTab { window.copyLink(of: tab) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.activeTab?.url == nil)
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
                .disabled(page?.url == nil)
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
            Button("New Space…") { window.newSpace() }
            Divider()
        }
    }
}
