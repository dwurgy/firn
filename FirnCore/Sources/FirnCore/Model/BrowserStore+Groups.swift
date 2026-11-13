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
        let oldGroupID = tab.groupID
        movingSplit(of: tab) {
            tab.groupID = group.id
            if let oldGroupID {
                tabs.remove(at: index)
                let below = tabs.lastIndex { $0.groupID == oldGroupID }.map { $0 + 1 } ?? index
                tabs.insert(tab, at: below)
                endIfEmpty(oldGroupID)
            }
        }
        membersChanged(oldGroupID)
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
        let oldGroupID = tab.groupID
        movingSplit(of: tab) {
            tabs.remove(at: index)
            tab.groupID = group.id
            insert(tab, at: position, in: Self.rows(tabs(in: group), skipping: tab.splitID), fallback: index)
            if oldGroupID != group.id {
                endIfEmpty(oldGroupID)
                keep(group)
            }
        }
        if oldGroupID != group.id {
            membersChanged(group.id)
            membersChanged(oldGroupID)
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
        membersChanged(groupID)
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
        groups[index].namedByHand = true
        // Named by hand: the namer's answer, if one comes, is dropped, and
        // it's never named again.
        unnamedGroups[group.id] = nil
        renameRounds[group.id] = nil
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
        endingGroupIDs.remove(group.id)
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
        endingGroupIDs.remove(group.id)
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
            let name = await namer.name(for: named, current: nil)
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

    // MARK: - Naming groups again

    /// A tab joined or left a group on this device. Unless the person named
    /// it, it's named again from its tabs once things settle: after
    /// `groupRenamePause`, when every tab has its title, or with what it has
    /// after `groupNameWait` more. Never for changes from another device
    /// (sync), so two devices can't keep renaming each other's groups.
    func membersChanged(_ groupID: UUID?) {
        guard let groupID, groupNamer?.isAvailable == true,
              let group = groups.first(where: { $0.id == groupID }), !group.namedByHand else { return }
        // Its first name is still waiting for titles: the newcomer is in it.
        guard unnamedGroups[groupID] != .waiting else { return }
        let round = (renameRounds[groupID] ?? 0) + 1
        renameRounds[groupID] = round
        let pause = groupRenamePause
        let wait = groupNameWait
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: pause)
            self?.renameIfReady(groupID, round: round)
            try? await Task.sleep(for: wait)
            self?.renameIfReady(groupID, round: round, waitedLongEnough: true)
        }
    }

    /// Asks the namer again, with the group's current name to keep if it
    /// still fits, once per round.
    func renameIfReady(_ groupID: UUID, round: Int, waitedLongEnough: Bool = false) {
        guard renameRounds[groupID] == round, renameAsked[groupID] != round,
              let group = groups.first(where: { $0.id == groupID }), !group.namedByHand,
              let namer = groupNamer else { return }
        // Its first name is still on the way: try again once it's there.
        guard unnamedGroups[groupID] == nil else {
            if waitedLongEnough { membersChanged(groupID) }
            return
        }
        let members = tabs.filter { $0.groupID == groupID }
        guard !members.isEmpty else { return }
        guard waitedLongEnough || members.allSatisfy({ !$0.savedTitle.isEmpty || $0.page == nil }) else { return }
        renameAsked[groupID] = round
        let named = members.map { GroupNamingTab(title: $0.savedTitle, site: $0.url?.host() ?? "") }
        // "New Group" (its first naming found nothing) isn't worth keeping.
        let current = group.name.hasPrefix(TabGroup.defaultName) ? nil : group.name
        Task { @MainActor [weak self] in
            let name = await namer.name(for: named, current: current)
            self?.finishRenaming(groupID, round: round, with: name)
        }
    }

    /// Takes the answer if nothing newer happened (another change, a
    /// rename by hand, or the group ending) and it's a different name.
    /// Doesn't count as keeping the group (it still tidies).
    func finishRenaming(_ groupID: UUID, round: Int, with answer: String?) {
        guard renameRounds[groupID] == round else { return }
        renameRounds[groupID] = nil
        renameAsked[groupID] = nil
        guard let answer, let name = GroupNaming.cleaned(answer),
              let index = groups.firstIndex(where: { $0.id == groupID }), !groups[index].namedByHand else { return }
        let free = freeGroupName(in: groups[index].spaceID, base: name, for: groupID)
        guard free != groups[index].name else { return }
        groups[index].name = free
    }

    /// A tab's title arrived: its group may be ready for a name.
    func titleArrived(in tab: Tab) {
        guard let groupID = tab.groupID, unnamedGroups[groupID] == .waiting else { return }
        nameIfReady(groupID)
    }

    /// Ends a group a tab just left if nothing's left in it. If a link made
    /// it and it isn't kept yet, one tab left is enough (as in Dia): it's
    /// marked ending, so the apps can let its card go as Ungroup does, and
    /// then that tab is loose, right where it is (David, 2026-11-13). If no
    /// window ends it, the store does after `groupEndingWait`. A group
    /// someone kept may be a group of one.
    func endIfEmpty(_ groupID: UUID?) {
        guard let groupID, let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let members = tabs.filter { $0.groupID == groupID }
        if members.isEmpty {
            endingGroupIDs.remove(groupID)
            groups.remove(at: index)
        } else if endsAtOne(groups[index], members: members.count), !endingGroupIDs.contains(groupID) {
            endingGroupIDs.insert(groupID)
            let wait = groupEndingWait
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: wait)
                self?.finishEnding(groupID)
            }
        }
    }

    private func endsAtOne(_ group: TabGroup, members: Int) -> Bool {
        group.tidies && members == 1
    }

    /// A link-made group down to one tab, whose card should go now (as
    /// Ungroup's does) before `finishEnding` makes its tab loose.
    public func isEnding(_ group: TabGroup) -> Bool {
        endingGroupIDs.contains(group.id)
    }

    /// Ends a group `isEnding` marked, its tab loose right where it is,
    /// unless it's no longer down to one link-made tab (a link opened
    /// another in it, it was renamed, or a tab was put in). Returns whether
    /// it ended, so a window can bring the card back if it didn't.
    @discardableResult
    public func finishEnding(_ group: TabGroup) -> Bool {
        finishEnding(group.id)
    }

    @discardableResult
    func finishEnding(_ groupID: UUID) -> Bool {
        guard endingGroupIDs.remove(groupID) != nil,
              let group = groups.first(where: { $0.id == groupID }),
              endsAtOne(group, members: tabs(in: group).count) else { return false }
        ungroup(group)
        return true
    }

    /// Link-made groups of one left in a saved session (Firn quit before
    /// one ended) end as it opens, with no motion.
    func endLoneLinkGroups() {
        for group in groups where endsAtOne(group, members: tabs(in: group).count) {
            ungroup(group)
        }
    }
}
