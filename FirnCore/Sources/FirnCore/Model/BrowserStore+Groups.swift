import Foundation
import Observation

extension BrowserStore {
    // MARK: - Groups

    /// Starts a group with an everyday tab, where the tab already is. A tab
    /// taken from another group starts its new one just below that group.
    /// The other half of its split comes too.
    @discardableResult
    public func newGroup(with tab: Tab) -> TabGroup? {
        guard tab.place == .open, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let group = TabGroup(spaceID: tab.spaceID, name: freeGroupName(in: tab.spaceID))
        groups.append(group)
        startNaming(group.id)
        movingSplit(of: tab) {
            let oldGroupID = tab.groupID
            tab.groupID = group.id
            if let oldGroupID {
                tabs.remove(at: index)
                let below = tabs.lastIndex { $0.groupID == oldGroupID }.map { $0 + 1 } ?? index
                tabs.insert(tab, at: below)
                endIfEmpty(oldGroupID)
            }
        }
        return group
    }

    /// A tab dropped onto another: it joins the other's group, just after
    /// it, or the two start a new group together (the other first).
    public func group(_ tab: Tab, with other: Tab) {
        guard tab.id != other.id, tab.spaceID == other.spaceID, tab.place == .open, other.place == .open,
              tabs.contains(where: { $0.id == other.id }) else { return }
        let group = other.groupID.flatMap { id in groups.first { $0.id == id } } ?? newGroup(with: other)
        guard let group else { return }
        let others = tabs(in: group).filter { $0.id != tab.id }
        let position = others.firstIndex { $0.id == other.id }.map { $0 + 1 } ?? others.count
        move(tab, into: group, at: position)
    }

    /// Moves an everyday tab into a group of its space, at `position` among
    /// the group's tabs (0-based; the count means the end). A group it
    /// leaves empty ends. The other half of its split comes too.
    public func move(_ tab: Tab, into group: TabGroup, at position: Int) {
        guard tab.place == .open, tab.spaceID == group.spaceID, groups.contains(where: { $0.id == group.id }),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        movingSplit(of: tab) {
            let oldGroupID = tab.groupID
            tabs.remove(at: index)
            tab.groupID = group.id
            insert(tab, at: position, in: Self.rows(tabs(in: group), skipping: tab.splitID), fallback: index)
            if oldGroupID != group.id {
                endIfEmpty(oldGroupID)
                keep(group)
            }
        }
    }

    /// A group someone put a tab in, or renamed, is theirs: it no longer
    /// tidies away.
    func keep(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].tidies = false
    }

    /// Whether a tab's group (if it's in one) lets it tidy away: none, or
    /// one a link made that isn't kept yet.
    func mayTidy(_ tab: Tab) -> Bool {
        guard let groupID = tab.groupID else { return true }
        return groups.first { $0.id == groupID }?.tidies == true
    }

    /// Moves an everyday tab to the end of a group (right-click › Move to
    /// Group). A folded group opens if the tab is the one on screen, so it
    /// doesn't vanish.
    public func move(_ tab: Tab, toEndOf group: TabGroup) {
        guard tab.groupID != group.id else { return }
        move(tab, into: group, at: tabs(in: group).count)
        if tab.groupID == group.id, tab.id == activeTabID,
           groups.first(where: { $0.id == group.id })?.folded == true {
            setFolded(group, false)
        }
    }

    /// Takes a tab out of its group: to `position` in the tab list when
    /// dragged, otherwise right below the group, so it doesn't fly off to
    /// where new tabs go (David, 2026-10-19). A group it leaves empty ends.
    /// The other half of its split comes too.
    public func takeOutOfGroup(_ tab: Tab, to position: Int? = nil) {
        guard let groupID = tab.groupID, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        movingSplit(of: tab) {
            tabs.remove(at: index)
            tab.groupID = nil
            if let position {
                insertInTabList([tab], at: position, fallback: index)
            } else {
                // Right below what's left of the group (or where it was).
                let below = tabs.lastIndex { $0.groupID == groupID }.map { $0 + 1 } ?? index
                tabs.insert(tab, at: below)
            }
            endIfEmpty(groupID)
        }
    }

    /// Where a dragged everyday tab lands: `position` among a group's tabs,
    /// or in the tab list when `group` is nil (0-based, not counting the tab
    /// itself, and counting each group as one; the count means the end). A
    /// group it leaves empty ends.
    public func move(_ tab: Tab, toGroup group: TabGroup?, at position: Int) {
        guard tab.place == .open else { return }
        if let group {
            move(tab, into: group, at: position)
        } else if tab.groupID != nil {
            takeOutOfGroup(tab, to: position)
        } else {
            move(tab, to: position)
        }
    }

    /// Renames a group. A name that's blank once tidied changes nothing.
    public func rename(_ group: TabGroup, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }),
              let name = TabGroup.cleanName(name) else { return }
        groups[index].name = name
        groups[index].tidies = false
        // Named by hand: the namer's answer, if one comes, is dropped.
        unnamedGroups[group.id] = nil
    }

    public func setFolded(_ group: TabGroup, _ folded: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].folded = folded
    }

    /// Moves a group, with all its tabs, to `position` in its space's tab
    /// list (0-based, not counting the group itself, and counting each
    /// group as one; the count means the end).
    public func move(_ group: TabGroup, to position: Int) {
        guard let from = tabs.firstIndex(where: { $0.groupID == group.id }) else { return }
        let members = tabs(in: group)
        tabs.removeAll { $0.groupID == group.id }
        insertInTabList(members, at: position, fallback: from)
        keepSplitsTogether()
    }

    /// Ends a group but keeps its tabs, right where the card was, in the
    /// group's order.
    public func ungroup(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        // Its tabs stay right where the card was.
        for tab in tabs(in: group) { tab.groupID = nil }
        groups.remove(at: index)
    }

    /// Closes a group and all its tabs. If one of them was on screen, the
    /// tab seen most recently takes its place.
    public func close(_ group: TabGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let members = tabs(in: group)
        let wasShowing = members.contains { $0.id == activeTabID }
        // So the tab on screen is the one shown again if the group comes back.
        if wasShowing { activeTab?.lastActiveAt = now() }
        rememberClosing(groups[index], members: members)
        for tab in members {
            _ = endSplit(of: tab)
            tab.sleep()
        }
        tabs.removeAll { $0.groupID == group.id }
        groups.remove(at: index)
        if wasShowing {
            activeTabID = nil
            selectMostRecent()
        }
    }

    /// A group as `newGroup` would make it in the current space, for the
    /// sidebar to show while a tab is held over another; nothing is saved.
    public func previewGroup() -> TabGroup {
        TabGroup(spaceID: activeSpaceID, name: freeGroupName(in: activeSpaceID))
    }

    /// "New Group", or "New Group 2", 3, … if this space already has one,
    /// so Move to Group never lists two the same; the same for a name the
    /// namer gave ("Recipes 2"). The lowest number not in use, as Finder does.
    func freeGroupName(in spaceID: UUID, base: String = TabGroup.defaultName, for groupID: UUID? = nil) -> String {
        let taken = Set(groups.filter { $0.spaceID == spaceID && $0.id != groupID }.map(\.name))
        var name = base
        var number = 2
        while taken.contains(name) {
            name = "\(base) \(number)"
            number += 1
        }
        return name
    }

    // MARK: - Naming new groups

    /// The group is new and its name is on the way: the apps show a quiet
    /// "thinking" mark instead of "New Group" (David, 2026-11-07).
    public func isNaming(_ group: TabGroup) -> Bool {
        unnamedGroups[group.id] != nil
    }

    /// A new group gets its name once, from its tabs, after their titles
    /// have loaded (or `groupNameWait`, whichever is first). Waits a turn
    /// first, so a group made by dropping one tab on another has both.
    func startNaming(_ groupID: UUID) {
        guard groupNamer?.isAvailable == true else { return }
        unnamedGroups[groupID] = .waiting
        let wait = groupNameWait
        Task { @MainActor [weak self] in
            self?.nameIfReady(groupID)
            try? await Task.sleep(for: wait)
            self?.nameIfReady(groupID, waitedLongEnough: true)
        }
    }

    /// Asks the namer once every tab in the group has its title. A tab with
    /// no page (a link opened in the background loads only when shown)
    /// won't have one soon, so it's named from its site.
    func nameIfReady(_ groupID: UUID, waitedLongEnough: Bool = false) {
        guard unnamedGroups[groupID] == .waiting else { return }
        let members = tabs.filter { $0.groupID == groupID }
        guard let namer = groupNamer, !members.isEmpty else {
            unnamedGroups[groupID] = nil
            return
        }
        guard waitedLongEnough || members.allSatisfy({ !$0.savedTitle.isEmpty || $0.page == nil }) else { return }
        unnamedGroups[groupID] = .asking
        let named = members.map { GroupNamingTab(title: $0.savedTitle, site: $0.url?.host() ?? "") }
        Task { @MainActor [weak self] in
            let name = await namer.name(for: named)
            self?.finishNaming(groupID, with: name)
        }
    }

    /// Takes the namer's answer, unless the group was renamed or ended
    /// meanwhile. Doesn't count as keeping the group (it still tidies).
    func finishNaming(_ groupID: UUID, with answer: String?) {
        guard unnamedGroups.removeValue(forKey: groupID) == .asking,
              let answer, let name = GroupNaming.cleaned(answer),
              let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].name = freeGroupName(in: groups[index].spaceID, base: name, for: groupID)
    }

    /// A tab's title arrived: its group may be ready for a name.
    func titleArrived(in tab: Tab) {
        guard let groupID = tab.groupID, unnamedGroups[groupID] == .waiting else { return }
        nameIfReady(groupID)
    }

    /// A group with no tabs left ends.
    func endIfEmpty(_ groupID: UUID?) {
        guard let groupID, !tabs.contains(where: { $0.groupID == groupID }) else { return }
        groups.removeAll { $0.id == groupID }
    }
}
