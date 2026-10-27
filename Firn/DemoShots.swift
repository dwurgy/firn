import AppKit
import FirnCore
import SwiftUI

/// The website's screenshots (docs/HISTORY.md, "Demo mode", step 3): a demo
/// started with `--shot=<name>` (and `--dark` for the dark one) sets up one
/// shot from the shot list, waits for its pages to load, and says which
/// window to capture by writing its number to a hidden file in Downloads. `scripts/demo-shots.sh` captures it and removes the file, and
/// Firn quits. Nothing here runs outside a demo.
enum DemoShot: String, CaseIterable {
    case hero, work, trip, command, lookout, split, tidied, history, empty, peek

    static let current: DemoShot? = {
        // One word, `--shot=hero`: AppKit opens a bare word at launch as a
        // file, and then no window opens.
        guard DemoMode.isOn,
              let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--shot=") })
        else { return nil }
        return DemoShot(rawValue: String(argument.dropFirst("--shot=".count)))
    }()

    static let isDark = ProcessInfo.processInfo.arguments.contains("--dark")

    /// What the command bar shot has typed: it finds Work's two guidelines
    /// pages, open and in its history.
    static var typed: String? { current == .command ? "guide" : nil }

    /// Every shot's browser window is this size, so the set matches.
    private static let windowSize = CGSize(width: 1440, height: 900)

    /// Sets up the shot, once the browser window is on screen.
    @MainActor static func stage(_ window: WindowModel, openWindow: OpenWindowAction) async {
        guard let shot = current else { return }
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        guard let browser = await browserWindow() else { return }
        browser.setContentSize(windowSize)
        browser.center()
        // Launched from a script, Firn may not be the app in front: an
        // inactive window has grey traffic lights and a smaller shadow, and
        // a popover won't open from it.
        NSApp.activate(ignoringOtherApps: true)
        browser.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))

        let store = window.store
        func show(_ name: String) {
            guard let space = store.spaces.first(where: { $0.name == name }) else { return }
            window.showSpace { store.selectSpace(space) }
        }
        func tabs(in space: String) -> [FirnCore.Tab] {
            guard let id = store.spaces.first(where: { $0.name == space })?.id else { return [] }
            return store.tabs.filter { $0.spaceID == id }
        }
        var captured: NSWindow = browser

        switch shot {
        case .hero:
            show("Personal")
        case .work:
            show("Work")
        case .trip:
            show("Trip")
        case .command:
            show("Work")
            window.openCommandBar()
        case .lookout:
            show("Personal")
            if let url = tabs(in: "Personal").compactMap(\.url).first(where: { $0.host() == "en.wikipedia.org" }) {
                store.openLookout(url)
            }
        case .split:
            show("Personal")
            // The two in "Weekend cooking" (a tidied-away recipe is there too).
            let recipes = tabs(in: "Personal").filter { $0.place == .open && $0.url?.host() == "smittenkitchen.com" }
            if recipes.count == 2 { window.openSplit(recipes[1], beside: recipes[0]) }
        case .tidied:
            show("Personal")
            window.showsOverflow = true
        case .history:
            show("Personal")
            openWindow(id: "history")
            if let history = await appWindow("history") { captured = history }
        case .empty:
            show("Trip")
            let trip = store.activeSpace.id
            for group in store.groups where group.spaceID == trip { store.close(group) }
            window.closeAllTabs()
            // An empty window opens the command bar; the shot is the scene.
            try? await Task.sleep(for: .milliseconds(500))
            window.closeCommandBar(focusingPage: false)
        case .peek:
            show("Personal")
            window.setSidebarCollapsed(true)
            try? await Task.sleep(for: .milliseconds(600))
            window.pointerMoved(toX: 0)
        }

        await waitForPages(of: store)
        // Icons, fonts, and the motion settle.
        try? await Task.sleep(for: .seconds(2.5))
        NSApp.activate(ignoringOtherApps: true)
        captured.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        await handOver(captured)
    }

    /// The pages on screen, Lookout included, have finished loading (or 25
    /// seconds have passed).
    @MainActor private static func waitForPages(of store: BrowserStore) async {
        let deadline = Date.now.addingTimeInterval(25)
        try? await Task.sleep(for: .seconds(1))
        while Date.now < deadline {
            var pages: [any PageController] = []
            if let tab = store.activeTab {
                pages += [tab.page, store.splitPartner(of: tab)?.page].compactMap { $0 }
            }
            if let lookout = store.lookout?.page { pages.append(lookout) }
            if !pages.contains(where: \.isLoading) { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Tells the script which window to capture, then quits once it has
    /// (it removes the file), or after a minute.
    @MainActor private static func handOver(_ captured: NSWindow) async {
        let ready = DemoMode.shotReadyFile
        try? String(captured.windowNumber).write(to: ready, atomically: true, encoding: .utf8)
        let deadline = Date.now.addingTimeInterval(60)
        while Date.now < deadline, FileManager.default.fileExists(atPath: ready.path(percentEncoded: false)) {
            try? await Task.sleep(for: .milliseconds(200))
        }
        NSApp.terminate(nil)
    }

    @MainActor private static func browserWindow() async -> NSWindow? { await appWindow("browser") }

    /// A SwiftUI `Window` scene's window, by its id, once it's on screen.
    @MainActor private static func appWindow(_ id: String) async -> NSWindow? {
        for _ in 0..<40 {
            if let found = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix(id) == true }) {
                return found
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

