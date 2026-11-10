import FirnCore
import SwiftUI

/// Menu items, so every action can be found by looking, with the Mac
/// shortcuts as a bonus.
struct BrowserCommands: Commands {
    let window: WindowModel
    @AppStorage(Preference.blocksContent) private var blocksContent = true
    @Environment(\.openWindow) private var openWindow

    private var store: BrowserStore { window.store }
    private var page: (any PageController)? { window.frontPage }
    private var everydayTab: FirnCore.Tab? { window.everydayTab }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.checkNow() }
                .disabled(!Updater.shared.canCheck)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",")
        }
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
            Button("Import from Arc…") { window.importFromArc() }
                .disabled(window.showsWelcome)
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
            Button(store.lookout == nil ? "Close Tab" : "Close Lookout") {
                // In the History or Settings window, ⌘W closes that window,
                // never a tab behind it.
                if let key = NSApp.keyWindow, let id = key.identifier?.rawValue,
                   id.hasPrefix("history") || id.hasPrefix("settings") {
                    key.performClose(nil)
                } else {
                    window.closeFront()
                }
            }
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
        // As in Safari.
        CommandMenu("History") {
            Button("Show History") { openWindow(id: "history") }
                .keyboardShortcut("y")
            Button("Clear History…") {
                window.asksToClearHistory = true
                openWindow(id: "history")
            }
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
            Button("Report a Problem…") { window.reportProblem() }
        }
        CommandGroup(before: .windowArrangement) {
            // Held, ⌃Tab shows the recent tabs to pick from (`TabSwitchKeys`);
            // chosen here, it's a tap.
            Button("Show Last Used Tab") { window.pressTabSwitch(backward: false); window.finishTabSwitch() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(window.switchableTabs.count < 2)
            // Down and up the sidebar, as in Arc and Dia.
            Button("Show Next Tab") { store.selectTab(by: 1); window.focusPage() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(store.sidebarRows.count < 2)
            Button("Show Previous Tab") { store.selectTab(by: -1); window.focusPage() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
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
