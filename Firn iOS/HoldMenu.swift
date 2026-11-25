import FirnCore
import SwiftUI

/// One choice in a hold menu (iOS's own, made from these by the overview's
/// grid): plain words and an SF Symbol, or a list of choices (Move to Group).
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

/// A hold menu's choices as VoiceOver's actions, a list's choices among
/// them (Move to Group: each group by its name).
struct HoldMenuActions: View {
    /// Asked here, so what the choices come from (the groups there are)
    /// runs only this when it changes.
    let menu: () -> [[HoldMenuItem]]

    var body: some View {
        ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
            Button(choice.title, action: choice.action)
        }
    }

    private var choices: [(title: String, action: @MainActor () -> Void)] {
        menu().joined().flatMap { item -> [(title: String, action: @MainActor () -> Void)] in
            guard !item.children.isEmpty else { return [(item.title, item.action)] }
            // New Group and Remove from Group read on their own; a group's
            // or a device's name needs what it's for.
            return item.children.map { child in
                let alone = child.title == "New Group" || child.title == "Remove from Group"
                return (alone ? child.title : "\(item.title), \(child.title)", child.action)
            }
        }
    }
}

extension View {
    /// Hidden from VoiceOver while `hidden`, and otherwise as it is.
    ///
    /// Never `.accessibilityHidden(someCondition)`: while the condition is
    /// false it shows everything inside to VoiceOver, pieces hidden on
    /// their own and even pieces at opacity 0 included (a test app, iOS 26
    /// and 27, 2026-11-24). Firn's whole bar stayed reachable behind the
    /// overview that way.
    func hiddenFromVoiceOver(_ hidden: Bool) -> some View {
        accessibilityHidden(true, isEnabled: hidden)
    }
}
