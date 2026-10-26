import AppKit
import FirnCore
import SwiftUI

@main
struct FirnApp: App {
    @State private var window: WindowModel
    private let saver: SessionSaver
    private let sleeper: TabSleeper

    /// Picks up where the last session left off, then saves as things change
    /// and once more at quit.
    init() {
        BrowserEngine.startBlocking(enabled: Preference.blocksContentAtLaunch)
        let file = SessionFile.standard
        let session = file.load()
        let store = BrowserStore(
            restoring: session, defaultSpaces: [FirstSpace.space],
            makePage: BrowserEngine.makePage,
            removeData: { id in
                BrowserEngine.removeData(for: id)
                Task.detached(priority: .utility) { try? PasswordStore.keychain.removeAll(in: id) }
                Task.detached(priority: .utility) { await HistoryStore.standard.removeAll(in: id) }
            },
            passwords: .keychain,
            history: .standard
        )
        // Erase what's left of deleted spaces: data their open pages still
        // held, passwords the Keychain couldn't be reached for, and history.
        // Only after a session really loaded: a fresh start after a damaged
        // file doesn't know which spaces exist, so it erases nothing.
        if let session, !session.spaces.isEmpty {
            let inUse = Set(store.spaces.map(\.dataStoreID))
            BrowserEngine.removeUnusedData(keeping: inUse)
            Task.detached(priority: .utility) { try? PasswordStore.keychain.removeUnused(keeping: inUse) }
            Task.detached(priority: .utility) { await HistoryStore.standard.removeUnused(keeping: inUse) }
        }
        // History is kept a year.
        Task.detached(priority: .utility) { await HistoryStore.standard.removeExpired() }
        let window = WindowModel(store: store, restoring: session?.window)
        // The welcome, the very first time (no session yet).
        if session == nil, !UserDefaults.standard.bool(forKey: Preference.welcomed) { window.showWelcome() }
        _window = State(initialValue: window)
        saver = SessionSaver(file: file) {
            store.session(sidebarWidth: window.sidebarWidth, sidebarCollapsed: window.sidebarCollapsed)
        }
        saver.start()
        sleeper = TabSleeper(store: store)
        sleeper.start()
        // Starts Sparkle, so its scheduled checks (once allowed) run.
        _ = Updater.shared
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [saver] _ in
            MainActor.assumeIsolated { saver.saveNow() }
        }
    }

    var body: some Scene {
        // One window for now; several windows sharing tabs is its own step.
        Window("Firn", id: "browser") {
            BrowserWindow(window: window)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands { BrowserCommands(window: window) }
        // Links from other apps come to this one window (see `openFromOtherApp`).
        .handlesExternalEvents(matching: ["*"])

        // History › Show History (⌘Y).
        Window("History", id: "history") {
            HistoryWindow(window: window)
        }
        .defaultSize(width: 680, height: 620)

        Settings {
            SettingsView(window: window)
        }
    }
}

/// The space Firn starts with. It keeps Phase 1's named data store, never
/// .default(), so sign-ins carry over.
enum FirstSpace {
    static let space = Space(
        id: UUID(uuidString: "0B8E5D2C-7A41-4F6E-9D3B-5C2A1E8F7B64")!,
        name: "Personal",
        icon: SpaceIcon.default.rawValue,
        color: "glacier",
        order: 0,
        dataStoreID: UUID(uuidString: "6F1C2A4E-3B7D-4E8A-9C5F-2D1E0B7A9F31")!
    )
}
