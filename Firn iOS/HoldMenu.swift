import SwiftUI

/// One choice in a hold menu (Firn's own, `FrostMenu`): plain words and an
/// SF Symbol, or a list of choices opened in the same card (Move to Group).
struct HoldMenuItem {
    let title: String
    let systemImage: String?
    let action: @MainActor () -> Void
    let children: [HoldMenuItem]
    /// Closes something (Close Tab, Close Group, Remove from Basecamp):
    /// Firn's menu shows it in muted terracotta.
    var closes = false

    init(title: String, systemImage: String?, closes: Bool = false, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.closes = closes
        self.action = action
        children = []
    }

    init(title: String, systemImage: String?, children: [HoldMenuItem]) {
        self.title = title
        self.systemImage = systemImage
        action = {}
        self.children = children
    }
}
