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
    /// Goes up each time the address bar is asked to take focus.
    private(set) var addressRequest = 0

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
                guard !Task.isCancelled, !pointerNearSidebar, !peekHeldForTyping else { return }
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
    func openCommandBar() { showsCommandBar = true }

    /// Closes the command bar, leaving nothing behind. The page in front
    /// gets the keys back, unless focus already went somewhere else (a
    /// click in the sidebar's address bar, say).
    func closeCommandBar(focusingPage: Bool = true) {
        guard showsCommandBar else { return }
        showsCommandBar = false
        if focusingPage { focusPage() }
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
            PageArea(tab: store.activeTab)
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

/// The page on screen, floating in the frame. With no tab open, a calm empty page.
private struct PageArea: View {
    let tab: FirnCore.Tab?
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
                PageView(page: page, cornerRadius: Theme.pageCornerRadius)
                    .overlay {
                        if let error = page.loadError {
                            LoadErrorView(error: error, isRetrying: page.isLoading, retry: page.reload)
                                .clipShape(shape)
                                .transition(.opacity)
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
    /// The page in front: a Lookout's while one is open, so Back and Reload act on it.
    private var page: (any PageController)? { store.lookout?.page ?? store.activeTab?.page }
    /// The tab on screen, if it's an everyday tab (not a Basecamp tile).
    private var everydayTab: FirnCore.Tab? { store.activeTab.flatMap { $0.place == .open ? $0 : nil } }

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
            Button(store.lookout == nil ? "Close Tab" : "Close Lookout") {
                if store.lookout != nil {
                    store.closeLookout()
                    window.focusPage()
                } else if let tab = store.activeTab {
                    window.close(tab)
                }
            }
            .keyboardShortcut("w")
            .disabled(store.activeTab == nil && store.lookout == nil)
            Button(store.nextToReopen == .group ? "Reopen Closed Group" : "Reopen Closed Tab") {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                withAnimation(Theme.glide(reduceMotion: reduceMotion)) { store.reopenClosed() }
                window.focusPage()
            }
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
                .disabled(store.sidebarTabs.count < 2)
            Button("Show Previous Tab") { store.selectTab(by: -1); window.focusPage() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(store.sidebarTabs.count < 2)
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
