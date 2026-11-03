import SwiftUI

/// Firn for iPhone and iPad. For now, an empty page; phase 1 grows it into
/// a window that browses (see docs/IOS-PLAN.md).
@main
struct FirnIOSApp: App {
    var body: some Scene {
        WindowGroup {
            Theme.page.ignoresSafeArea()
        }
    }
}
