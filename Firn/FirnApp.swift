import AppKit
import FirnCore
import SwiftUI

@main
struct FirnApp: App {
    @State private var window: WindowModel
    private let saver: SessionSaver

    /// Picks up where the last session left off, then saves as things change
    /// and once more at quit.
    init() {
        let file = SessionFile.standard
        let session = file.load()
        let store = BrowserStore(
            restoring: session, defaultSpaces: [PhaseTwo.space], makePage: BrowserEngine.makePage
        )
        let window = WindowModel(store: store, restoring: session?.window)
        _window = State(initialValue: window)
        saver = SessionSaver(file: file) {
            store.session(sidebarWidth: window.sidebarWidth, sidebarCollapsed: window.sidebarCollapsed)
        }
        saver.start()
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
    }
}

/// Until spaces arrive (Phase 4), there's one built-in space. It keeps Phase 1's
/// named data store, never .default(), so sign-ins carry over.
enum PhaseTwo {
    static let space = Space(
        id: UUID(uuidString: "0B8E5D2C-7A41-4F6E-9D3B-5C2A1E8F7B64")!,
        name: "Personal",
        icon: "leaf",
        color: "glacier",
        order: 0,
        dataStoreID: UUID(uuidString: "6F1C2A4E-3B7D-4E8A-9C5F-2D1E0B7A9F31")!
    )
}
