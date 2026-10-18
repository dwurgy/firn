import FirnCore
import SwiftUI

/// What the window is doing, apart from its tabs: whether the address bar is
/// being edited, and for which tab.
@MainActor
@Observable
final class WindowModel {
    enum AddressTarget { case currentTab, newTab }

    let store: BrowserStore
    private(set) var addressTarget: AddressTarget = .currentTab
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

    /// Focuses the address bar: to change the tab on screen, or (⌘T) to open a
    /// new tab, which only appears once an address is entered.
    func editAddress(_ target: AddressTarget) {
        addressTarget = store.activeTab == nil ? .newTab : target
        addressRequest += 1
        // The address bar lives in the sidebar, so a hidden one slides out to be typed in.
        if sidebarCollapsed {
            peekHideTask?.cancel()
            peekHeldForTyping = true
            isPeeking = true
        }
    }

    func finishEditingAddress() {
        addressTarget = .currentTab
        peekHeldForTyping = false
        if sidebarCollapsed, !pointerNearSidebar { isPeeking = false }
    }

    /// Gives the tab on screen keyboard focus, once its page is in the window.
    func focusPage() {
        Task { @MainActor in
            await Task.yield()
            store.activeTab?.page?.focus()
        }
    }
}

/// One browser window: the sidebar and the page, on the space-tinted frame.
struct BrowserWindow: View {
    let window: WindowModel
    @State private var lights = TrafficLights()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: BrowserStore { window.store }
    private var showsSidebar: Bool { !window.sidebarCollapsed || window.isPeeking }

    var body: some View {
        ZStack(alignment: .leading) {
            // The page and the sidebar move together, frame by frame, on one curve.
            PageArea(tab: store.activeTab)
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
                Theme.frameTint(store.activeSpace.color)
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
        .onAppear { window.editAddress(.newTab) }
        .onChange(of: store.openTabs.isEmpty) {
            if store.openTabs.isEmpty { window.editAddress(.newTab) }
        }
    }

    private var slide: Animation { Theme.slide(reduceMotion: reduceMotion) }
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
            Theme.frameTint(store.activeSpace.color)
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
                        // Until something has loaded, show Firn's calm page color, not WebKit's white.
                        if page.url == nil {
                            shape.fill(Theme.page).allowsHitTesting(false)
                        }
                    }
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
    @State private var lights = TrafficLights()

    private var store: BrowserStore { window.store }
    private var page: (any PageController)? { store.activeTab?.page }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { window.editAddress(.newTab) }
                .keyboardShortcut("t")
            Button("Open Location…") { window.editAddress(.currentTab) }
                .keyboardShortcut("l")
        }
        // As in Arc and Dia: ⌘W closes the tab, ⇧⌘W the window.
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { if let tab = store.activeTab { store.close(tab) } }
                .keyboardShortcut("w")
                .disabled(store.activeTab == nil)
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
        }
        CommandGroup(replacing: .sidebar) {
            Button(window.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") { window.toggleSidebar() }
                .keyboardShortcut("s")
        }
        CommandGroup(before: .windowArrangement) {
            Button("Show Next Tab") { store.selectTab(by: 1); window.focusPage() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(store.openTabs.count < 2)
            Button("Show Previous Tab") { store.selectTab(by: -1); window.focusPage() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(store.openTabs.count < 2)
            Divider()
        }
    }
}
