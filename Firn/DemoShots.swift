import AppKit
import FirnCore
import SwiftUI

/// The website's screenshots (docs/HISTORY.md, "Demo mode", step 3): a demo
/// started with `--shot=<name>` (and `--dark` for the dark one) sets up one
/// shot from the shot list, waits for its pages to load, and says which
/// window to capture by writing its number to a hidden file in Downloads. `scripts/demo-shots.sh` captures it and removes the file, and
/// Firn quits. Nothing here runs outside a demo.
enum DemoShot: String, CaseIterable {
    case hero, work, command, lookout, split, reader, summary, tidied, history, empty, peek, welcome, settings

    static let current: DemoShot? = {
        // One word, `--shot=hero`: AppKit opens a bare word at launch as a
        // file, and then no window opens.
        guard DemoMode.isOn,
              let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--shot=") })
        else { return nil }
        return DemoShot(rawValue: String(argument.dropFirst("--shot=".count)))
    }()

    static let isDark = ProcessInfo.processInfo.arguments.contains("--dark")

    /// What the command bar shot has typed: it finds Norse Projects, open
    /// in Personal and in its history.
    static var typed: String? { current == .command ? "nor" : nil }

    /// The welcome's step to show (`--step=search`, arc, arrived, space,
    /// basecamp, or default), and made-up Arc spaces for its Arc step.
    static let welcomeStep: String? = {
        guard current == .welcome else { return nil }
        return ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--step=") }.map { String($0.dropFirst("--step=".count)) }
    }()
    static var arcPlan: ArcImportPlan? {
        func space(_ name: String, _ count: Int) -> (items: [Any], spaces: [Any]) {
            let tabs = (0..<count).map { "\(name)\($0)" }
            var items: [Any] = tabs.flatMap { [$0, ["id": $0, "childrenIds": [String](), "data": ["tab": ["savedURL": "https://example.com/\($0)", "savedTitle": $0]]]] as [Any] }
            items += [name, ["id": name, "childrenIds": tabs, "data": ["itemContainer": [String: String]()]]] as [Any]
            return (items, [name, ["id": name, "title": name, "containerIDs": ["pinned", name]]])
        }
        let all = [space("Personal", 6), space("Work", 9), space("Reading", 3), space("Trips", 2), space("Recipes", 4)]
        let root: [String: Any] = ["sidebar": ["containers": [["spaces": all.flatMap(\.spaces), "items": all.flatMap(\.items)]]]]
        return (try? JSONSerialization.data(withJSONObject: root)).flatMap { try? ArcImportPlan($0) }
    }

    /// Every shot's browser window is this size, so the set matches;
    /// `--size=700x500` to check a screen at another.
    private static let windowSize: CGSize = {
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--size=") }
        let sides = argument?.dropFirst("--size=".count).split(separator: "x").compactMap { Double($0) } ?? []
        guard sides.count == 2 else { return CGSize(width: 1440, height: 900) }
        return CGSize(width: sides[0], height: sides[1])
    }()

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

        // Snow Peak has no fixed icon address (`DemoSession`): its tab loads
        // once, so its row shows the icon, not a letter.
        if let bare = tabs(in: "Personal").first(where: { $0.place == .open && $0.url?.host() == "www.snowpeak.com" }),
           let front = store.activeTab {
            store.select(bare)
            for _ in 0..<60 where bare.icon == nil { try? await Task.sleep(for: .milliseconds(250)) }
            store.select(front)
        }

        switch shot {
        case .hero:
            show("Personal")
        case .work:
            show("Work")
        case .command:
            show("Personal")
            window.openCommandBar()
        case .lookout:
            show("Personal")
            if let url = tabs(in: "Personal").compactMap(\.url).first(where: { $0.host() == "en.wikipedia.org" }) {
                store.openLookout(url)
            }
        case .split:
            show("Personal")
            // The story beside Snow Peak (the Nordic shops open with
            // popups of their own: a currency picker, a mailing list).
            let open = tabs(in: "Personal").filter { $0.place == .open }
            if let story = open.first(where: { $0.url?.host() == "www.kinfolk.com" }),
               let snowPeak = open.first(where: { $0.url?.host() == "www.snowpeak.com" }) {
                window.openSplit(snowPeak, beside: story)
            }
        case .reader, .summary:
            show("Personal")
            if let article = tabs(in: "Personal").first(where: { $0.place == .open && $0.url?.host() == "en.wikipedia.org" }) {
                store.select(article)
            }
        case .tidied:
            show("Personal")
            window.showsOverflow = true
        case .history:
            show("Personal")
            openWindow(id: "history")
            if let history = await appWindow("history") { captured = history }
        case .empty:
            show("Home")
            // `--color=sage`: the same screen in another space's color.
            if let color = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--color=") }) {
                store.updateSpace(store.activeSpace, name: store.activeSpace.name, color: String(color.dropFirst("--color=".count)))
            }
            // An empty window opens the command bar; the shot is the scene.
            try? await Task.sleep(for: .milliseconds(500))
            window.closeCommandBar(focusingPage: false)
        case .peek:
            show("Personal")
            window.setSidebarCollapsed(true)
            try? await Task.sleep(for: .milliseconds(600))
            window.pointerMoved(toX: 0)
        case .settings:
            // Which pane: `--pane=keyboard`.
            if let pane = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--pane=") }) {
                UserDefaults.standard.set(String(pane.dropFirst("--pane=".count)), forKey: "settingsPane")
            }
            openWindow(id: "settings")
            if let settings = await appWindow("settings") { captured = settings }
        case .welcome:
            // Hello.
            show("Personal")
            window.showWelcome()
        }

        await waitForPages(of: store)
        if shot == .reader || shot == .summary {
            // The page counts as an article a moment after it loads.
            for _ in 0..<40 where !window.canToggleReader { try? await Task.sleep(for: .milliseconds(250)) }
            window.toggleReader()
            for _ in 0..<40 where !window.isReading { try? await Task.sleep(for: .milliseconds(250)) }
            if shot == .summary {
                window.summarizeArticle()
                // The summary is written on the Mac, a few seconds.
                try? await Task.sleep(for: .seconds(12))
            }
        }
        // A cookie banner (or Wikipedia's donation banner) would cover the
        // page: the tab on screen's, its split partner's, and a Lookout's.
        var shown: [any PageController] = []
        if let tab = store.activeTab { shown += [tab.page, store.splitPartner(of: tab)?.page].compactMap { $0 } }
        if let lookout = store.lookout?.page { shown.append(lookout) }
        for page in shown { await page.declineCookieBanner(waiting: 4) }
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

