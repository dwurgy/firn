import FirnCore
import SwiftUI

/// Firn for iPhone and iPad. Phase 1: one space, one tab, and a plain field
/// for addresses (see docs/IOS-PLAN.md).
@main
struct FirnIOSApp: App {
    @State private var store: BrowserStore
    private let saver: SessionSaver
    @Environment(\.scenePhase) private var scenePhase

    /// Picks up where the last session left off, then saves as things change
    /// and whenever Firn leaves the screen (iOS may end it after that without
    /// a word).
    init() {
        let file = SessionFile.standard
        let session = file.load()
        let store = BrowserStore(
            restoring: session, defaultSpaces: [FirstSpace.make()],
            makePage: BrowserEngine.makePage,
            removeData: { BrowserEngine.removeData(for: $0) }
        )
        let snapshot: @MainActor () -> Session = { store.session(sidebarWidth: 260, sidebarCollapsed: false) }
        // The first space's data store is new: save it at once, so a quit
        // within the first seconds doesn't leave it nameless and forgotten.
        if session == nil { try? file.save(snapshot()) }
        _store = State(initialValue: store)
        saver = SessionSaver(file: file, snapshot: snapshot)
        saver.start()
    }

    var body: some Scene {
        WindowGroup {
            BrowserScreen(store: store)
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { saver.saveNow() }
        }
    }
}

/// The space Firn starts with on a new iPhone or iPad: its own data store,
/// never .default(). Made once, then kept in the saved session.
enum FirstSpace {
    static func make() -> Space {
        Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())
    }
}
