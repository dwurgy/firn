import Foundation
import Observation

extension BrowserStore {
    // MARK: - Drifting

    /// Counts today as a day Firn was used, deletes drifted tabs past the
    /// 30-day cutoff, and returns every loose tab that hasn't been on screen
    /// for the set number of used days, in every space, top to bottom. Days
    /// away from Firn don't count. Never drifted: Basecamp tiles, grouped
    /// tabs, the tab on screen, tabs in split view, and a tab playing sound
    /// (muted or not). The app drifts them with `drift(_:)`, one by one, so
    /// it can show each go.
    public func idleTabs() -> [Tab] {
        let today = Self.day(of: now())
        if !usedDays.contains(today) {
            usedDays = Array((usedDays + [today]).sorted().suffix(Self.usedDaysKept))
        }
        deleteExpiredDriftedTabs()
        guard let limit = driftAfter.days else { return [] }
        return tabs.filter { tab in
            guard tab.place == .open, mayTidy(tab), tab.splitID == nil, tab.id != activeTabID,
                  tab.sound == .silent else { return false }
            let lastSeen = Self.day(of: tab.lastActiveAt)
            return usedDays.count { $0 > lastSeen } >= limit
        }
    }

    /// Drifts one loose tab (or one in a group a link made) away to its
    /// space's overflow ("Tidied away"). Its page lets go, so it costs
    /// nothing; it keeps its address, title, and icon. A group it was the
    /// last of ends.
    public func drift(_ tab: Tab) {
        guard tab.place == .open, mayTidy(tab), tab.splitID == nil, tab.id != activeTabID,
              tab.sound == .silent, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        let groupID = tab.groupID
        tab.groupID = nil
        endIfEmpty(groupID)
        tab.sleep()
        tab.place = .drifted
        tab.driftedAt = now()
        tabs.append(tab)
        unseenTidiedSpaces.insert(tab.spaceID)
        lastTabBySpace = lastTabBySpace.filter { $0.value != tab.id }
    }

    /// Brings back all of the current space's tidied-away tabs where new
    /// tabs go, in the order they were tidied, leaving the tab on screen as
    /// it is. They count as just seen, so they don't drift straight back.
    public func restoreAllDrifted() {
        let back = list(.drifted)
        guard !back.isEmpty else { return }
        let ids = Set(back.map(\.id))
        tabs.removeAll { ids.contains($0.id) }
        let stamp = now()
        for tab in back {
            tab.place = .open
            tab.driftedAt = nil
            tab.lastActiveAt = stamp
        }
        tabs.insert(contentsOf: back, at: arrivalIndex(in: activeSpaceID))
        unseenTidiedSpaces.remove(activeSpaceID)
    }

    /// Drifts every idle tab at once (when there's nothing to watch).
    public func driftIdleTabs() {
        for tab in idleTabs() { drift(tab) }
    }

    /// Drifted tabs go for good 30 calendar days after they drifted (unlike
    /// drifting itself, which counts days Firn was used).
    func deleteExpiredDriftedTabs() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let expired = Set(tabs.filter { tab in
            guard tab.place == .drifted, let driftedAt = tab.driftedAt else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: driftedAt), to: today).day ?? 0
            return days >= Self.driftedKeptDays
        }.map(\.id))
        guard !expired.isEmpty else { return }
        tabs.removeAll { expired.contains($0.id) }
    }

    /// A date's day in the Mac's calendar, as "yyyy-MM-dd" (which sorts by date).
    static func day(of date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Keeps only well-formed days, each once, in order.
    static func cleanDays(_ days: [String]) -> [String] {
        let wellFormed = days.filter { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil }
        return Array(Set(wellFormed).sorted().suffix(usedDaysKept))
    }

    // MARK: - Sleeping

    /// How long a tab can be out of sight before its page sleeps.
    static let sleepAfter: TimeInterval = 60 * 60

    /// Lets the pages of tabs out of sight for an hour sleep, keeping each
    /// one's place (history and scroll position) for when it's shown again;
    /// with `memoryIsShort` (the Mac says so), any tab out of sight. Never
    /// asleep: the tab on screen and its split partner, Basecamp tiles,
    /// pages playing sound or video or using the camera or microphone, and
    /// pages holding text typed and not yet sent. The app calls this after the tab on screen changes and when memory
    /// runs short; nothing runs on a timer.
    public func sleepIdleTabs(memoryIsShort: Bool = false) async {
        await sleepTabs { [unowned self] in mayLetSleep($0, memoryIsShort: memoryIsShort) }
    }

    /// iPhone and iPad, where memory is much tighter than on the Mac: beyond
    /// the tab on screen, only the `count` tabs seen most recently stay
    /// awake, and the rest sleep (keeping their place) however briefly
    /// they've been out of sight. The same tabs never sleep as in
    /// `sleepIdleTabs`. The Mac doesn't use this.
    public func sleepIdleTabs(keepingRecent count: Int) async {
        let recent = Set(
            tabs.filter { mayLetSleep($0, memoryIsShort: true) }
                .sorted { $0.lastActiveAt > $1.lastActiveAt }
                .prefix(count).map(\.id)
        )
        await sleepTabs { [unowned self] in mayLetSleep($0, memoryIsShort: true) && !recent.contains($0.id) }
    }

    func sleepTabs(where mayLetSleep: (Tab) -> Bool) async {
        for tab in tabs where mayLetSleep(tab) {
            guard let page = tab.page, !(await page.isInUse()) else { continue }
            // Things may have changed while the page answered.
            guard tab.page === page, tabs.contains(where: { $0.id == tab.id }),
                  mayLetSleep(tab) else { continue }
            tab.sleep(keepingPlace: true)
        }
    }

    func mayLetSleep(_ tab: Tab, memoryIsShort: Bool) -> Bool {
        guard !tab.isResting, tab.place != .basecamp, !onScreenTabIDs.contains(tab.id) else { return false }
        return memoryIsShort || now().timeIntervalSince(tab.lastActiveAt) >= Self.sleepAfter
    }
}
