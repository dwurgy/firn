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

    init(store: BrowserStore) { self.store = store }

    /// Focuses the address bar: to change the tab on screen, or (⌘T) to open a
    /// new tab, which only appears once an address is entered.
    func editAddress(_ target: AddressTarget) {
        addressTarget = store.activeTab == nil ? .newTab : target
        addressRequest += 1
    }

    func finishEditingAddress() { addressTarget = .currentTab }

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

    private var store: BrowserStore { window.store }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store, window: window, lights: lights)
                .frame(width: Theme.sidebarWidth)
            PageArea(tab: store.activeTab)
                .padding(Theme.pageInset)
        }
        .background {
            ZStack {
                Theme.frame
                Theme.frameTint(store.activeSpace.color)
                // Empty frame (around the page, the sidebar's top row) moves the window.
                WindowDragArea()
                WindowSetup(lights: $lights)
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
}

/// The page on screen, floating in the frame. With no tab open, a calm empty page.
private struct PageArea: View {
    let tab: FirnCore.Tab?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        ZStack {
            shape
                .fill(Theme.page)
                .shadow(color: Theme.shadowPageNear, radius: 1.5, y: 1)
                .shadow(color: Theme.shadowPageFar, radius: 10, y: 6)
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
