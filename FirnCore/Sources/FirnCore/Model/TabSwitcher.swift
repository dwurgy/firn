import Foundation

/// ⌃Tab, as ⌘Tab switches apps: the space's most recently used tabs, newest
/// first (the tab on screen leads), with one picked. It starts on the tab
/// used before this one (⇧⌃Tab: the oldest shown); Tab and ⇧Tab move the
/// pick, wrapping, and letting go of ⌃ shows it. It holds ids, not tabs, so
/// a tab closed meanwhile is simply never shown.
public struct TabSwitcher: Equatable, Sendable {
    /// At most this many, as in Dia.
    public static let limit = 5

    /// The tabs, newest first (see `BrowserStore.recentRows`).
    public let tabIDs: [UUID]
    public private(set) var picked: Int

    /// Nil with fewer than two tabs: there's nothing to switch to.
    public init?(tabIDs: [UUID], backward: Bool = false) {
        let ids = Array(tabIDs.prefix(Self.limit))
        guard ids.count > 1 else { return nil }
        self.tabIDs = ids
        picked = backward ? ids.count - 1 : 1
    }

    public var pickedID: UUID { tabIDs[picked] }

    /// Moves the pick along (back with a negative offset), wrapping around.
    public mutating func move(by offset: Int) {
        let count = tabIDs.count
        picked = ((picked + offset) % count + count) % count
    }

    /// Picks one by id (clicked, say); an id it doesn't hold changes nothing.
    public mutating func pick(_ id: UUID) {
        if let index = tabIDs.firstIndex(of: id) { picked = index }
    }
}
