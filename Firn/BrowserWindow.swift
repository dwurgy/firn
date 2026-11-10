import FirnCore
import SwiftUI

/// One browser window: the sidebar and the page, on the space-tinted frame.
struct BrowserWindow: View {
    /// The whole window's space, for a tab dragged from the sidebar onto the page.
    nonisolated static let space = "browserWindow"
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preference.newTabPlacement) private var newTabPlacement = NewTabPlacement.bottom
    @AppStorage(Preference.driftAfter) private var driftAfter = DriftAfter.sevenDays
    @AppStorage(Preference.blocksContent) private var blocksContent = true
    /// Waiting out the beat before idle tabs drift.
    @State private var driftTask: Task<Void, Never>?
    @Environment(\.openWindow) private var openWindow

    private var store: BrowserStore { window.store }
    private var showsSidebar: Bool { !window.sidebarCollapsed || window.isPeeking }

    var body: some View {
        ZStack(alignment: .leading) {
            // The page and the sidebar move together, frame by frame, on one curve.
            PageArea(store: store, window: window)
                .overlay { LookoutLayer(store: store, window: window) }
                .overlay { FindBarLayer(store: store, window: window) }
                .overlay { CommandBarLayer(store: store, window: window) }
                .overlay { TabSwitcherLayer(store: store, window: window) }
                .overlay { SpaceSheetLayer(window: window) }
                .overlay { GlassSheetLayer(cornerRadius: Theme.pageCornerRadius) }
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
        .coordinateSpace(.named(Self.space))
        // The welcome's finish lifts the sidebar and the page out of the
        // scene; the frame stays put, and its glass gives way to the rising
        // card's (`WelcomeBackdrop`) until it's in place.
        .modifier(WelcomeLift(finish: window.welcomeFinish))
        .background {
            ZStack {
                Group {
                    FrameGlass()
                    SpaceTint(color: store.activeSpace.color)
                }
                .opacity(window.welcomeFinish == .begun || window.welcomeFinish == .rising ? 0 : 1)
                // Empty frame (around the page, the sidebar's top row) moves the window.
                WindowDragArea()
                WindowSetup(window: window)
                PointerTracker(
                    onMove: { window.pointerMoved(toX: $0) },
                    onLeave: { window.pointerLeftWindow() }
                )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        // At the welcome's finish, the sky is behind the window and the snow
        // in front (see `WelcomeLayer`).
        .background { WelcomeBackdrop(window: window) }
        .overlay { WelcomeLayer(window: window) }
        .environment(\.spaceColorName, store.activeSpace.color)
        .navigationTitle(store.activeTab?.title ?? "Firn")
        .background(TabShortcuts(store: store, window: window))
        .background(TabSwitchKeys(window: window))
        .onAppear {
            if store.activeTab == nil { window.openCommandBar() }
            // Launching may bring Firn to the front before this window listens.
            driftIdleTabs(afterABeat: true)
        }
        // A demo's screenshot (`--shot`); nothing otherwise.
        .task { await DemoShot.stage(window, openWindow: openWindow) }
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
        .onChange(of: store.activeTabID) { old, _ in
            window.takePicture(of: old)
            window.tabOnScreenChanged()
        }
        .onOpenURL { window.openFromOtherApp($0) }
        .modifier(ArcImportFlow(starting: Bindable(window).startingArcImport, window: window))
        .glassSheetHost(color: Theme.spaceColor(store.activeSpace.color))
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
    /// edge, so it (and the traffic lights in it) sits this much further in.
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
            Sidebar(store: store, window: window)
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

/// ⌘1–9, which don't need their own menu items. ⌃Tab and ⇧⌘[ / ⇧⌘] are
/// in the Window menu, where they can be found.
private struct TabShortcuts: View {
    let store: BrowserStore
    let window: WindowModel

    var body: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") { select { store.selectTab(at: number - 1) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")))
            }
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
