import Foundation
import Observation

extension BrowserStore {
    // MARK: - Split view

    /// The split view a tab is half of, if any.
    public func split(of tab: Tab) -> SplitGroup? {
        guard let splitID = tab.splitID else { return nil }
        return splits.first { $0.id == splitID }
    }

    /// A split's two tabs, left then right.
    public func tabs(in split: SplitGroup) -> [Tab] {
        tabs.filter { $0.splitID == split.id }
    }

    /// The other half of a tab's split, if it's in one.
    public func splitPartner(of tab: Tab) -> Tab? {
        guard let splitID = tab.splitID else { return nil }
        return tabs.first { $0.splitID == splitID && $0.id != tab.id }
    }

    /// Shows `incoming` beside `anchor`, on `side`, in split view, with
    /// `incoming` the one in use. `anchor` stays where it is, and `incoming`
    /// joins it there, in its group. A Basecamp tile is never moved: a copy
    /// of its page goes in the tab list instead (for `anchor`, where new
    /// tabs go). A tidied-away tab comes back. If `anchor` was already in a
    /// split, its other half leaves, right below the new pair (so dropping
    /// a tab on one half replaces that half); a split `incoming` was in ends.
    @discardableResult
    public func openSplit(_ incoming: Tab, beside anchor: Tab, on side: SplitSide = .right) -> SplitGroup? {
        guard incoming.id != anchor.id, incoming.spaceID == anchor.spaceID,
              tabs.contains(where: { $0.id == incoming.id }), tabs.contains(where: { $0.id == anchor.id })
        else { return nil }
        // Already a pair: only the sides can change.
        if let split = split(of: anchor), incoming.splitID == split.id {
            let pair = tabs(in: split)
            if (side == .left) != (pair.first?.id == incoming.id), let from = tabs.firstIndex(where: { $0.id == incoming.id }) {
                tabs.remove(at: from)
                let at = tabs.firstIndex { $0.id == anchor.id }!
                tabs.insert(incoming, at: side == .left ? at : at + 1)
            }
            select(incoming)
            return split
        }
        let anchor = everyday(anchor, at: arrivalIndex(in: anchor.spaceID))
        let displaced = endSplit(of: anchor)
        _ = endSplit(of: incoming)
        let incoming = everyday(incoming, at: nil)
        if let from = tabs.firstIndex(where: { $0.id == incoming.id }) { tabs.remove(at: from) }
        let oldGroupID = incoming.groupID
        incoming.groupID = anchor.groupID
        let at = tabs.firstIndex { $0.id == anchor.id }!
        tabs.insert(incoming, at: side == .left ? at : at + 1)
        if oldGroupID != anchor.groupID { endIfEmpty(oldGroupID) }
        let split = SplitGroup(spaceID: anchor.spaceID)
        splits.append(split)
        anchor.splitID = split.id
        incoming.splitID = split.id
        // The displaced half goes right below the new pair.
        if let displaced, let from = tabs.firstIndex(where: { $0.id == displaced.id }) {
            tabs.remove(at: from)
            tabs.insert(displaced, at: lastIndex(withSplitOf: anchor)! + 1)
        }
        select(incoming)
        return split
    }

    /// Whether `tab` can be dragged onto the page to open it in split view:
    /// not what's already on screen, not a split (it's two pages already),
    /// and not while a Lookout is open over the page.
    public func canDropOnPage(_ tab: Tab) -> Bool {
        guard lookout == nil, let active = activeTab, active.spaceID == tab.spaceID else { return false }
        return tab.splitID == nil && !onScreenTabIDs.contains(tab.id)
    }

    /// Opens `tab` on `side` of the page: beside the tab on screen, or, in
    /// a split, in place of that half (the other half stays).
    @discardableResult
    public func dropOnPage(_ tab: Tab, on side: SplitSide) -> SplitGroup? {
        guard canDropOnPage(tab), let active = activeTab else { return nil }
        var anchor = active
        if let split = split(of: active) {
            let pair = tabs(in: split)
            guard pair.count == 2 else { return nil }
            anchor = side == .left ? pair[1] : pair[0]
        }
        return openSplit(tab, beside: anchor, on: side)
    }

    /// An everyday tab for a split: the tab itself (a drifted one comes back
    /// first), or for a Basecamp tile, a copy of its page, placed at
    /// `index` (or nowhere yet, if nil).
    func everyday(_ tab: Tab, at index: Int?) -> Tab {
        switch tab.place {
        case .open:
            return tab
        case .drifted:
            bringBack(tab)
            return tab
        case .basecamp:
            let copy = Tab(spaceID: tab.spaceID, url: tab.url, title: tab.title, icon: tab.icon, lastActiveAt: now())
            if let index { tabs.insert(copy, at: min(index, tabs.count)) }
            return copy
        }
    }

    /// Ends a split view. Its two tabs stay right where they are, as
    /// ordinary tabs.
    public func closeSplit(_ split: SplitGroup) {
        guard let first = tabs.first(where: { $0.splitID == split.id }) else { return }
        // Both were on screen, so neither should drift straight away.
        if onScreenTabIDs.contains(first.id) {
            markOnScreenSeen()
        }
        _ = endSplit(of: first)
    }

    /// Sets how much of the width the left page takes (kept within
    /// `SplitGroup.fractionRange`).
    public func setLeftFraction(of split: SplitGroup, to fraction: Double) {
        guard let index = splits.firstIndex(where: { $0.id == split.id }) else { return }
        splits[index].leftFraction = SplitGroup.clamped(fraction)
    }

    /// Ends the split a tab is in, if any, and returns its other half.
    func endSplit(of tab: Tab) -> Tab? {
        guard let splitID = tab.splitID else { return nil }
        let partner = splitPartner(of: tab)
        tab.splitID = nil
        partner?.splitID = nil
        splits.removeAll { $0.id == splitID }
        return partner
    }

    /// Where a tab is in `tabs`, or the second half of its split if that's
    /// further down.
    func lastIndex(withSplitOf tab: Tab) -> Int? {
        tabs.lastIndex { $0.id == tab.id || (tab.splitID != nil && $0.splitID == tab.splitID) }
    }

    /// Moves a tab with `change`, then brings the other half of its split
    /// back beside it, on the same side and in the same group.
    func movingSplit(of tab: Tab, _ change: () -> Void) {
        let partner = splitPartner(of: tab)
        let partnerOnLeft = partner.map { partner in
            (tabs.firstIndex { $0.id == partner.id } ?? 0) < (tabs.firstIndex { $0.id == tab.id } ?? 0)
        } ?? false
        change()
        if let partner, let from = tabs.firstIndex(where: { $0.id == partner.id }) {
            let oldGroupID = partner.groupID
            tabs.remove(at: from)
            partner.groupID = tab.groupID
            if let at = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs.insert(partner, at: partnerOnLeft ? at : at + 1)
            } else {
                tabs.insert(partner, at: min(from, tabs.count))
            }
            if oldGroupID != tab.groupID { endIfEmpty(oldGroupID) }
        }
        keepSplitsTogether()
    }

    /// Puts each split's halves back side by side, in the first one's group,
    /// if something landed between them.
    func keepSplitsTogether() {
        for split in splits {
            let pair = tabs(in: split)
            guard pair.count == 2, let first = tabs.firstIndex(where: { $0.id == pair[0].id }),
                  let second = tabs.firstIndex(where: { $0.id == pair[1].id }),
                  second != first + 1 || pair[1].groupID != pair[0].groupID else { continue }
            let oldGroupID = pair[1].groupID
            tabs.remove(at: second)
            pair[1].groupID = pair[0].groupID
            tabs.insert(pair[1], at: first + 1)
            if oldGroupID != pair[0].groupID { endIfEmpty(oldGroupID) }
        }
    }
}
