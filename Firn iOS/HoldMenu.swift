import FirnCore
import SwiftUI

/// One choice in a hold menu (Firn's own, `FrostMenu`): plain words and an
/// SF Symbol, or a list of choices opened in the same card (Move to Group).
struct HoldMenuItem {
    let title: String
    let systemImage: String?
    let action: @MainActor () -> Void
    let children: [HoldMenuItem]
    /// Closes something (Close Tab, Close Group, a tile's Close):
    /// Firn's menu shows it in muted terracotta.
    var closes = false
    /// A space in the space menu: a dot in its color instead of a symbol.
    var dot: String?
    /// The space on screen, checked.
    var checked = false

    init(title: String, systemImage: String?, closes: Bool = false, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.closes = closes
        self.action = action
        children = []
    }

    /// A space in the space menu (phase 4): its dot, checked if on screen.
    init(space: Space, checked: Bool, action: @escaping @MainActor () -> Void) {
        title = space.name
        systemImage = nil
        dot = space.color
        self.checked = checked
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
