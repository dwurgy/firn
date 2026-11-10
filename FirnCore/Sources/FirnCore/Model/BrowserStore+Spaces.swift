import Foundation
import Observation

extension BrowserStore {
    // MARK: - Spaces

    /// Makes a space and shows it. It starts with no tabs and, unless it
    /// shares another space's sign-ins, its own empty data store: signed
    /// out of everything.
    @discardableResult
    public func addSpace(name: String, color: String, sharingWith other: Space? = nil) -> Space {
        let shared = other.flatMap { other in spaces.first { $0.id == other.id } }
        let space = Space(
            name: Space.cleanName(name) ?? Space.defaultName, color: color,
            order: spaces.count, dataStoreID: shared?.dataStoreID ?? UUID(), lastChangedAt: now()
        )
        spaces.append(space)
        selectSpace(space)
        return space
    }

    /// Whether Firn has only one space and nothing in it yet (no tiles,
    /// tabs, or groups), as on first launch. Arc's spaces take its place.
    public var hasOnlyUntouchedSpace: Bool {
        guard spaces.count == 1, let only = spaces.first else { return false }
        return !tabs.contains { $0.spaceID == only.id }
            && !groups.contains { $0.spaceID == only.id }
            && !splits.contains { $0.spaceID == only.id }
    }

    /// Adds the spaces read from Arc after the existing ones, without showing
    /// them. Spaces from the same Arc profile share a new data store; the
    /// rest are each separate. All start signed out, and every tab rests
    /// until clicked. If Firn has only its untouched first space, Arc's
    /// spaces replace it and the first of them is shown.
    /// - Parameter color: A new space's color, given the spaces there
    ///   already are; the app picks the next free one, as for any new space.
    @discardableResult
    public func importFromArc(
        _ plan: ArcImportPlan, color: (_ existing: [Space]) -> String
    ) -> [Space] {
        let replacing = hasOnlyUntouchedSpace && !plan.spaces.isEmpty ? spaces.first : nil
        var dataStores: [String: UUID] = [:]
        var added: [Space] = []
        for imported in plan.spaces {
            let dataStoreID = dataStores[imported.profile] ?? UUID()
            dataStores[imported.profile] = dataStoreID
            // The space being replaced doesn't count, so Arc's first space
            // gets the first color, as a first space would.
            let spaceColor = color(spaces.filter { $0.id != replacing?.id })
            let space = Space(
                name: imported.name, color: spaceColor,
                order: spaces.count, dataStoreID: dataStoreID, lastChangedAt: now()
            )
            spaces.append(space)
            for site in imported.basecamp {
                tabs.append(Tab(
                    spaceID: space.id, place: .basecamp, url: site.url, title: site.title,
                    homeURL: site.url, lastActiveAt: now()
                ))
            }
            for importedGroup in imported.groups {
                let group = TabGroup(spaceID: space.id, name: importedGroup.name)
                groups.append(group)
                for site in importedGroup.sites {
                    tabs.append(Tab(spaceID: space.id, url: site.url, title: site.title, groupID: group.id, lastActiveAt: now()))
                }
            }
            added.append(space)
        }
        // Import first, then delete, so there's always a space.
        if let replacing, let first = added.first {
            selectSpace(first)
            deleteSpace(replacing)
        }
        return added
    }

    /// Shows a space, on the tab it last had on screen (or the awake tab it
    /// showed most recently, or none).
    public func selectSpace(_ space: Space) {
        guard space.id != activeSpaceID, spaces.contains(where: { $0.id == space.id }) else { return }
        closeLookout()
        markOnScreenSeen()
        lastTabBySpace[activeSpaceID] = activeTabID
        activeSpaceID = space.id
        activeTabID = nil
        if let id = lastTabBySpace[space.id], let tab = tabs.first(where: { $0.id == id && $0.spaceID == space.id }) {
            show(tab)
        } else {
            selectMostRecent()
        }
    }

    /// Shows the space at `position` (0-based); past the end means the last one.
    public func selectSpace(at position: Int) {
        guard position >= 0 else { return }
        selectSpace(spaces[min(position, spaces.count - 1)])
    }

    /// Shows the next space (or the previous one with `by: -1`), wrapping around.
    public func selectSpace(by offset: Int) {
        guard let current = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let count = spaces.count
        selectSpace(spaces[((current + offset) % count + count) % count])
    }

    /// Changes a space's name and color. An empty name keeps the old one.
    public func updateSpace(_ space: Space, name: String, color: String) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        var updated = spaces[index]
        updated.name = Space.cleanName(name) ?? updated.name
        updated.color = color
        guard updated != spaces[index] else { return }
        updated.lastChangedAt = now()
        spaces[index] = updated
    }

    /// Moves a space to `position` among the spaces (0-based; the count means the end).
    public func moveSpace(_ space: Space, to position: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let moving = spaces.remove(at: from)
        spaces.insert(moving, at: min(max(position, 0), spaces.count))
        renumberSpaces()
    }

    /// The other spaces that share this space's sign-ins, cookies, and site data.
    public func spacesSharingData(with space: Space) -> [Space] {
        guard let dataStoreID = spaces.first(where: { $0.id == space.id })?.dataStoreID else { return [] }
        return spaces.filter { $0.id != space.id && $0.dataStoreID == dataStoreID }
    }

    /// Gives a shared space a new, empty data store of its own: it starts
    /// fresh and signed out, and the spaces it shared with keep theirs.
    /// Its tabs let their pages go; the one on screen loads again at once.
    public func stopSharing(_ space: Space) {
        guard !spacesSharingData(with: space).isEmpty,
              let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[index].dataStoreID = UUID()
        spaces[index].lastChangedAt = now()
        if lookout?.spaceID == space.id { closeLookout() }
        let onScreen = onScreenTabIDs
        for tab in tabs where tab.spaceID == space.id {
            tab.sleep()
            tab.forgetPlace()
            if onScreen.contains(tab.id) { wake(tab) }
        }
    }

    /// Deletes a space: its tabs, its groups, what ⇧⌘T could bring back in
    /// it, and, if no other space shares it, its sign-ins, cookies, and site
    /// data. The last space can't be deleted. If it's on screen, the space
    /// below it (or above, if it's last) is shown first.
    public func deleteSpace(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let deleted = spaces[index]
        if deleted.id == activeSpaceID {
            selectSpace(spaces[index + 1 < spaces.count ? index + 1 : index - 1])
        }
        for tab in tabs where tab.spaceID == deleted.id { tab.sleep() }
        tabs.removeAll { $0.spaceID == deleted.id }
        groups.removeAll { $0.spaceID == deleted.id }
        splits.removeAll { $0.spaceID == deleted.id }
        closed.removeAll { $0.spaceID == deleted.id }
        lastTabBySpace[deleted.id] = nil
        spaces.remove(at: index)
        renumberSpaces()
        if !spaces.contains(where: { $0.dataStoreID == deleted.dataStoreID }) {
            removeData(deleted.dataStoreID)
            // After any visit still being saved, so none lands once it's erased.
            let dataStoreID = deleted.dataStoreID
            history?.enqueue { await $0.removeAll(in: dataStoreID) }
        }
    }

    /// Keeps each space's `order` matching its place in `spaces`.
    func renumberSpaces() {
        for index in spaces.indices where spaces[index].order != index {
            spaces[index].order = index
            spaces[index].lastChangedAt = now()
        }
    }
}
