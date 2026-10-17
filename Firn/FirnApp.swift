import FirnCore
import SwiftUI

@main
struct FirnApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserWindow()
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { BrowserCommands() }
    }
}

/// Phase 1 has no spaces yet, so every page shares this one store. It's still
/// a named store, never .default(), so Phase 4 starts from the right habit.
enum PhaseOne {
    static let dataStoreID = UUID(uuidString: "6F1C2A4E-3B7D-4E8A-9C5F-2D1E0B7A9F31")!
}
