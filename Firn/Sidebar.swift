import FirnCore
import SwiftUI

/// The sidebar: the top row (traffic lights, the sidebar button, back, and
/// forward), the
/// address bar, and the space's tabs.
struct Sidebar: View {
    nonisolated static let space = "sidebar"
    let store: BrowserStore
    let window: WindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                AddressBar(store: store, window: window)
                    .padding(.top, 8)
                    .padding(.bottom, Theme.sectionSpacing)
                BasecampGrid(store: store, window: window)
                TabList(store: store, window: window)
            }
            // In full screen, everything above the bottom row glides down
            // with the menu bar, as in Dia.
            .padding(.top, window.menuBarDrop)
            MiniPlayer(store: store)
            SpaceRow(store: store, window: window)
                .padding(.bottom, Theme.pageInset)
        }
        // Site icons drifting down from their rows to the overflow button.
        .overlay { TidyFlights(window: window) }
        .coordinateSpace(.named(Self.space))
        .padding(.leading, Theme.pageInset)
    }

    /// The traffic lights at its left, then the sidebar button.
    private var topRow: some View {
        HStack(spacing: 2) {
            WindowLights()
                .frame(width: Theme.trafficLightsWidth, height: Theme.rowHeight)
            ChromeButton(
                window.sidebarCollapsed ? "Keep sidebar open (⌘S)" : "Hide sidebar (⌘S)",
                systemImage: "sidebar.left"
            ) { window.toggleSidebar() }
            Spacer(minLength: 0)
            if let page = store.activeTab?.page {
                NavigationButtons(page: page)
            } else {
                NavigationButtons.placeholder
            }
        }
        .frame(height: Theme.rowHeight)
        .padding(.top, Theme.pageInset)
    }
}

// MARK: - Tabs

struct TabList: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tab being dragged; nil when nothing is.
    @State private var drag: TabDrag?
    /// The group being dragged by its name line; nil when none is.
    @State private var groupDrag: GroupDrag?
    /// True from a group drag's start until just after its drop, so letting
    /// go on the name line doesn't also fold the group.
    @State private var foldLocked = false
    /// True while the pointer is down on a drag, so a drag the system
    /// cancels (no mouse-up) still ends.
    @GestureState private var dragging = false
    /// Where each tab row and group card sits, in the list's own space.
    @State private var frames: [UUID: CGRect] = [:]
    /// The group being let go (Ungroup): its card is thawing away around its tabs.
    @State private var releasingGroupID: UUID?
    /// The group being closed: its frost lifts away, tabs and all.
    @State private var closingGroupID: UUID?
    /// A tab held over a loose row: the group the two would make, shown
    /// around that row before anything changes (see `holdOnto`).
    @State private var preview: GroupPreview?
    /// Where the list's content sits in the sidebar (it moves as it
    /// scrolls), so a tidied tab's icon knows where it starts. A plain box,
    /// so scrolling doesn't redraw anything.
    @State private var origin = PointBox()
    /// Where the list shows in the sidebar (see `riseBack`).
    @State private var shown = RectBox()
    /// Where the list's content and the list itself sit in the window, so a
    /// dragged tab knows when it's out over the page.
    @State private var windowOrigin = PointBox()
    @State private var shownInWindow = RectBox()
    /// The group whose name is being edited, if any (kept by the window).
    private var renamingGroupID: UUID? { window.renamingGroupID }

    /// One speed for rows gliding aside and for the dropped row settling.
    private static let glide = Animation.smooth(duration: 0.2)
    private nonisolated static let space = "tabList"

    var body: some View {
        let items = shownItems
        let atTop = store.newTabPlacement == .top
        // The list fills the sidebar's height, so the blank space below the
        // tabs (and the gaps between them) moves the window too.
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: Theme.rowSpacing) {
                        // The New tab button sits where new tabs appear.
                        if atTop { newTabRow }
                        // Cards and rows keep one rhythm, the same gap between them all.
                        ForEach(items) { item in
                            switch item {
                            case let .group(group): card(group)
                            case let .tab(tab): row(tab)
                            }
                        }
                        if !atTop { newTabRow }
                    }
                    .overlay(alignment: .topLeading) { lifted }
                    // A split forming or ending: the rows around it glide.
                    .animation(reduceMotion ? nil : Self.glide, value: store.splits.map(\.id))
                    .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(Sidebar.space)).origin } action: {
                        origin.point = $0
                    }
                    .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(BrowserWindow.space)).origin } action: {
                        windowOrigin.point = $0
                    }
                    .coordinateSpace(.named(Self.space))
                    // One drag for the whole list, so a tab can cross into and out
                    // of the group cards (a drag on the row itself would stop the
                    // moment the row moved to another card).
                    .simultaneousGesture(dragGesture)
                    .onChange(of: dragging) { if !dragging { drop() } }
                    .padding(.bottom, Theme.pageInset)
                    // Room at the sides for the group cards' glass shadow, which
                    // the scroll view would otherwise clip; taken back below.
                    .padding(.horizontal, Theme.pageInset)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    .background { WindowDragArea { blankSpaceMenu } }
                }
                .scrollIndicators(.never)
                .padding(.horizontal, -Theme.pageInset)
                // A tab coming on screen (a new one at the bottom of a long
                // list, say) scrolls into view, by as little as it takes.
                .onChange(of: store.activeTabID) {
                    guard let tab = store.activeTab, tab.place == .open else { return }
                    // A split's row goes by its left half.
                    withAnimation(reduceMotion ? nil : Self.glide) { scroller.scrollTo(rowTab(of: tab).id) }
                }
            }
        }
        // Where the list shows in the sidebar, so brought-back tabs out of
        // view don't get a flight.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Sidebar.space)) } action: {
            shown.rect = $0
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BrowserWindow.space)) } action: {
            shownInWindow.rect = $0
        }
        .overlay(alignment: .topLeading) { liftedGroup }
        .onChange(of: window.tileInList) { tileChanged(window.tileInList) }
        // Settled into Basecamp: its row's open slot here closes.
        .onChange(of: window.tabInBasecamp) {
            if window.tabInBasecamp == nil, drag?.overBasecamp == true {
                withAnimation(reduceMotion ? nil : Self.glide) { drag = nil }
            }
        }
        .background {
            if window.tileInList?.released == false {
                PointerWatch(window: window) { tileMoved(to: $0) }
            }
        }
        .task(id: window.tidyQueue.map(\.id)) { await tidyAway() }
        .task(id: window.riseQueue.map(\.id)) { await riseBack() }
        .task(id: drag?.onto) { await holdOnto() }
        // Hidden partway through, the rest simply go, or simply come back.
        .onDisappear {
            for tab in window.tidyQueue { store.drift(tab) }
            window.tidyQueue = []
            window.riseQueue = []
            window.arrivingTabIDs = []
            window.boxOpen = false
        }
    }

    private var newTabRow: some View {
        NewTabRow { window.openCommandBar() }
    }

    /// Idle tabs are tidied away one after another, a moment apart: each
    /// row fades where it is as the list closes up, and its site icon
    /// drifts down to the overflow button (`TidyFlights`). Once the last has
    /// landed, the button says so. (Reduce Motion never gets here; see
    /// `BrowserWindow`.)
    private func tidyAway() async {
        let queue = window.tidyQueue
        guard !queue.isEmpty else { return }
        for tab in queue {
            guard tab.place == .open, tab.spaceID == store.activeSpaceID else { continue }
            let frame = drag == nil && groupDrag == nil ? frames[tab.id] : nil
            withAnimation(.easeOut(duration: 0.25)) { store.drift(tab) }
            guard tab.place == .drifted else { continue }
            if let frame {
                window.flyingIcons.append(FlyingIcon(id: tab.id, icon: tab.icon, row: iconPoint(in: frame)))
            }
            try? await Task.sleep(for: .milliseconds(90))
            // More tabs joined the queue (Firn came back to the front again):
            // the next run carries on from here, one by one, and says it once.
            guard !Task.isCancelled else { return }
        }
        // Then a moment more, so the box's lid has settled shut before
        // the frost forms over it.
        try? await Task.sleep(for: .seconds(FlyingIcon.duration + 0.3))
        guard !Task.isCancelled else { return }
        // Counting any an interrupted run already tidied.
        let count = queue.count { $0.place == .drifted }
        if count > 0 { window.announceTidied(count) }
        window.tidyQueue = []
    }

    /// Brought-back tabs, the tidy moment in reverse: the snow slides off
    /// the overflow button as the rows glide into place unseen, then each
    /// site icon rises out of the box to its row, a moment apart, and the
    /// row fades in under it as it lands. Fresh snow settles once the last
    /// has left. Rows out of view simply appear.
    private func riseBack() async {
        let queue = window.riseQueue
        guard !queue.isEmpty else { return }
        window.boxOpen = true
        try? await Task.sleep(for: .milliseconds(300))
        for tab in queue {
            // Cut short (another restore, say): the rest simply appear.
            guard !Task.isCancelled else {
                reveal(tab.id)
                continue
            }
            if drag == nil && groupDrag == nil, let frame = frames[tab.id],
               shown.rect.contains(iconPoint(in: frame)) {
                window.flyingIcons.append(
                    FlyingIcon(id: tab.id, icon: tab.icon, row: iconPoint(in: frame), rising: true))
                // The row fades in under the icon as the icon fades out.
                Task {
                    try? await Task.sleep(for: .seconds(FlyingIcon.duration - 0.15))
                    reveal(tab.id)
                }
            } else {
                reveal(tab.id)
            }
            try? await Task.sleep(for: .milliseconds(90))
        }
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(200))
        window.boxOpen = false
        window.riseQueue = []
    }

    private func reveal(_ id: UUID) {
        _ = withAnimation(.easeOut(duration: 0.2)) { window.arrivingTabIDs.remove(id) }
    }

    /// A row's site icon's middle, in the sidebar's space: the row's
    /// padding, then half a 16pt icon.
    private func iconPoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: origin.point.x + frame.minX + Theme.rowPadding + 8, y: origin.point.y + frame.midY)
    }

    /// Runs `body` once a `Theme.thaw` change has played. A fixed wait, not
    /// the animation's completion: with tabs not loaded since launch, the
    /// completion fired after 0.05s and the store's change that followed cut
    /// the motion short (see docs/HISTORY.md).
    private func afterThaw(_ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            body()
        }
    }

    /// A card without its frost: thawing away (Ungroup), or new and about to form.
    private func isThawed(_ group: TabGroup) -> Bool {
        group.id == releasingGroupID || group.id == window.formingGroupID
    }

    /// A new group, as frost forming: its card appeared thawed, in its tab's
    /// exact shape; now the glass and insets gather and the name line
    /// unfolds above. Once it has settled, the name field takes focus.
    private func form(_ group: TabGroup) {
        if group.id == preview?.group.id, preview?.formed == false {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.thaw) { preview?.formed = true }
            return
        }
        guard group.id == window.formingGroupID else { return }
        withAnimation(Theme.thaw) {
            window.formingGroupID = nil
        }
        afterThaw { window.finishForming(group.id) }
    }

    /// Ungroup, as frost thawing: the name line folds away, the card's insets
    /// and glass melt, and the tabs rise into place. The card ends exactly
    /// where the loose tabs will be, so the store's change that follows is
    /// invisible. Reduce Motion: a plain fade.
    private func release(_ group: TabGroup) {
        guard releasingGroupID == nil else { return }
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { store.ungroup(group) }
            return
        }
        withAnimation(Theme.thaw) {
            releasingGroupID = group.id
        }
        afterThaw {
            var settled = Transaction()
            settled.disablesAnimations = true
            withTransaction(settled) {
                store.ungroup(group)
                releasingGroupID = nil
            }
        }
    }

    /// Close Group, as frost lifting: the card folds its tabs up under its
    /// name line and fades as the list closes the gap; then the store closes
    /// it (and the next tab shows). Reduce Motion: a plain fade.
    private func close(_ group: TabGroup) {
        guard closingGroupID == nil else { return }
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { store.close(group) }
            return
        }
        withAnimation(Theme.thaw) {
            closingGroupID = group.id
        }
        afterThaw {
            // The empty slot's last few points close up softly.
            withAnimation(Self.glide) {
                store.close(group)
                closingGroupID = nil
            }
        }
    }

    /// Remove from Group: the tab slips out past the card's bottom edge and
    /// settles just below it, as when dragged out. The last tab thaws the
    /// card away instead, like Ungroup.
    private func takeOut(_ tab: FirnCore.Tab) {
        guard let group = store.tabGroups.first(where: { $0.id == tab.groupID }) else { return }
        if store.rows(in: group).count == 1 { return release(group) }
        guard let index = store.tabListItems.firstIndex(where: { $0.id == group.id }) else { return }
        carry(rowTab(of: tab), to: .list(index + 1)) { store.takeOutOfGroup(tab) }
    }

    /// Move to Group: the tab travels to the end of the other group, which
    /// opens room for it; into a folded group, it fades into the name line
    /// (unless it's the tab on screen, which opens the group, as the store does).
    private func move(_ tab: FirnCore.Tab, toEndOf group: TabGroup) {
        let target = DropTarget.group(group.id, store.rows(in: group).count)
        let opens = group.folded && tab.id == store.activeTabID
        carry(rowTab(of: tab), to: target, opening: opens ? group : nil) { store.move(tab, toEndOf: group) }
    }

    /// A tab moved from its menu travels the way a dropped one settles: a
    /// copy lifts off exactly over the row (invisibly), the list makes room
    /// at `target`, the copy follows its slot there, and then `commit`
    /// changes the store, which looks like nothing. Reduce Motion: a fade.
    private func carry(_ tab: FirnCore.Tab, to target: DropTarget, opening folded: TabGroup? = nil,
                       commit: @escaping () -> Void) {
        guard drag == nil, groupDrag == nil else { return }
        guard !reduceMotion, let frame = frames[tab.id] else {
            withAnimation(.easeOut(duration: 0.2), commit)
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            drag = TabDrag(tab: tab, grab: .zero, location: frame.origin,
                           target: currentTarget(of: tab), settling: true, follows: true)
        }
        withAnimation(Theme.thaw) {
            if let folded { store.setFolded(folded, false) }
            drag?.target = target
        }
        afterThaw {
            // A group the tab left empty fades away.
            withAnimation(Self.glide) {
                commit()
                drag = nil
            }
        }
    }

    /// Add to Basecamp: the tab joins Basecamp at once, so the list closes
    /// up, while a chip where its row was rises into its tile's slot (see
    /// `TileArrivalChip` and `BasecampGrid.arrive`). Reduce Motion: a fade.
    private func addToBasecamp(_ tab: FirnCore.Tab) {
        guard !reduceMotion, drag == nil, groupDrag == nil, window.tabLift == nil, window.tileArrival == nil,
              let frame = frames[rowTab(of: tab).id] else {
            _ = withAnimation(.easeOut(duration: 0.2)) { store.addToBasecamp(tab) }
            return
        }
        // The chip takes the row's place at once, so no fading copy of the row lingers.
        window.tileArrival = TileArrival(
            tab: tab, isActive: tab.id == store.activeTabID,
            row: frame.offsetBy(dx: windowOrigin.point.x, dy: windowOrigin.point.y))
        Task { @MainActor in
            let added = withAnimation(Self.glide) { store.addToBasecamp(tab) }
            if !added { window.tileArrival = nil }
        }
    }

    private func card(_ group: TabGroup) -> some View {
        let isPreview = group.id == preview?.group.id
        let members = isPreview ? previewRows : shownTabs(in: group)
        return GroupCard(
            group: group,
            hasRows: !members.isEmpty,
            color: Theme.spaceColor(store.activeSpace.color),
            renaming: Bindable(window).renamingGroupID,
            foldLocked: foldLocked,
            thawed: isThawed(group) || (isPreview && preview?.formed == false),
            closing: group.id == closingGroupID,
            preview: isPreview,
            store: store,
            ungroup: { release(group) },
            close: { close(group) }
        ) {
            ForEach(members) { tab in row(tab) }
        }
        // Shown once without its frost; the frost forms from there.
        .onAppear { form(group) }
        // While dragged, the card holds its slot open; the lifted copy is what shows.
        .opacity(groupDrag?.group.id == group.id ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
            frames[group.id] = $0
        }
    }

    /// A tab's row, or a split's (`tab` is its left half).
    @ViewBuilder private func row(_ tab: FirnCore.Tab) -> some View {
        if let split = store.split(of: tab), let partner = store.splitPartner(of: tab) {
            placed(SplitRow(
                left: tab, right: partner, fraction: split.leftFraction, inUseID: inUseHalf(of: tab),
                forming: window.formingSplitID == split.id
            ) { half in
                store.select(half)
                window.focusPage()
            } close: { half in
                withAnimation(reduceMotion ? nil : Self.glide) { window.close(half) }
            } separate: {
                withAnimation(reduceMotion ? nil : Self.glide) { store.closeSplit(split) }
            } formed: {
                if window.formingSplitID == split.id { window.formingSplitID = nil }
            } menu: { half in
                menu(for: half)
            }, tab)
        } else {
            placed(TabRow(tab: tab, isActive: tab.id == store.activeTabID) {
                store.select(tab)
                window.focusPage()
            } close: {
                window.close(tab)
            } menu: {
                menu(for: tab)
            }, tab)
        }
    }

    /// While dragged, a row holds its slot open; the lifted copy is what
    /// shows. Brought back, it waits unseen for its icon to land.
    private func placed(_ row: some View, _ tab: FirnCore.Tab) -> some View {
        row
            // A tab held over it: a hint of the card the two would make.
            .background {
                // It thaws as the dropped tab settles; the group's own frost forms next.
                if drag?.onto == tab.id, drag?.settling == false, preview?.formed != true {
                    FrostGlass(shape: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous),
                               color: Theme.spaceColor(store.activeSpace.color))
                        .padding(.horizontal, Theme.tabRadius - Theme.panelRadius)
                        .padding(.vertical, -Theme.rowSpacing / 2)
                        .transition(.opacity)
                }
            }
            // Becoming a split or leaving one, the row swaps for its new self
            // at once: the two look the same at that moment.
            .transaction(value: tab.splitID) { $0.animation = nil }
            .opacity(drag?.tab.id == tab.id || window.arrivingTabIDs.contains(tab.id)
                     || window.tileArrival?.tab.id == tab.id ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                frames[tab.id] = $0
            }
    }

    /// The tab a row goes by: a split's left half, or the tab itself.
    private func rowTab(of tab: FirnCore.Tab) -> FirnCore.Tab {
        store.split(of: tab).flatMap { store.tabs(in: $0).first } ?? tab
    }

    /// The half in use, if the split `tab` is in is on screen.
    private func inUseHalf(of tab: FirnCore.Tab) -> UUID? {
        tab.splitID != nil && store.activeTab?.splitID == tab.splitID ? store.activeTabID : nil
    }

    /// A row as dragged or carried: a copy, not clickable.
    @ViewBuilder private func liftedRow(_ tab: FirnCore.Tab, isActive: Bool) -> some View {
        if let partner = store.splitPartner(of: tab) {
            SplitRow(left: tab, right: partner, fraction: store.split(of: tab)?.leftFraction ?? 0.5,
                     inUseID: inUseHalf(of: tab), select: { _ in }, close: { _ in }, separate: {}) { _ in
                EmptyView()
            }
        } else {
            TabRow(tab: tab, isActive: isActive, select: {}, close: {}) { EmptyView() }
        }
    }

    // MARK: Where things show while dragging

    /// A group's tabs as they'd be if the dragged tab landed where it is now.
    private func shownTabs(in group: TabGroup) -> [FirnCore.Tab] {
        var list = store.rows(in: group)
        guard let drag else { return list }
        list.removeAll { $0.id == drag.tab.id }
        if case let .group(id, position) = drag.target, id == group.id {
            list.insert(drag.tab, at: min(position, list.count))
        }
        return list
    }

    /// The tab list as it'd be if the dragged tab landed where it is now.
    private var shownItems: [TabListItem] {
        var list = store.tabListItems
        if let groupDrag {
            list.removeAll { $0.id == groupDrag.group.id }
            list.insert(.group(groupDrag.group), at: min(groupDrag.target, list.count))
            return list
        }
        if let drag {
            list.removeAll { $0.id == drag.tab.id }
            // Held in a forming group, its slot is in the card instead.
            if case let .list(position) = drag.target, !holdsPreview(drag) {
                list.insert(.tab(drag.tab), at: min(position, list.count))
            }
        }
        // The row it's held over, in the card the two would make.
        if let preview, let index = list.firstIndex(where: { $0.id == preview.other.id }) {
            list[index] = .group(preview.group)
        }
        return list
    }

    /// The forming group's rows: the row held over, and the dragged tab's
    /// slot beside it while it's still held there.
    private var previewRows: [FirnCore.Tab] {
        guard let preview else { return [] }
        guard let drag, holdsPreview(drag) else { return [preview.other] }
        return preview.above ? [drag.tab, preview.other] : [preview.other, drag.tab]
    }

    private func holdsPreview(_ drag: TabDrag) -> Bool {
        preview != nil && drag.onto == preview?.other.id
    }

    /// The tab rows on show (folded groups hide theirs; a split is one row,
    /// by its left half).
    private var shownTabs: [FirnCore.Tab] {
        store.sidebarRows.filter { $0.place == .open }
    }

    /// Where the dragged tab would land with its middle at `y`. Well inside
    /// a group card, it goes into that group; near a card's top or bottom
    /// edge, or between cards and rows, it goes in the tab list there. Only
    /// the other rows count, so the slot opening up never pushes the target
    /// back and forth.
    private func target(at y: CGFloat, for tab: FirnCore.Tab) -> DropTarget {
        func position(in list: [FirnCore.Tab]) -> Int {
            list.filter { $0.id != tab.id && (frames[$0.id]?.midY ?? .infinity) < y }.count
        }
        let items = store.tabListItems.filter { $0.id != tab.id }
        for case let .group(group) in items {
            guard let card = frames[group.id] else { continue }
            // Above the middle of the name line means above the group. The
            // bottom edge is thinner, so dropping at a group's end is easy.
            let top = group.folded ? card.height / 4 : Theme.rowHeight / 2
            let bottom = group.folded ? card.height / 4 : Theme.rowHeight / 4
            guard y > card.minY + top, y < card.maxY - bottom else { continue }
            let members = store.rows(in: group)
            return .group(group.id, group.folded ? members.filter { $0.id != tab.id }.count : position(in: members))
        }
        return .list(items.filter { (frames[$0.id]?.midY ?? .infinity) < y }.count)
    }

    /// The loose row (a tab or a split, outside any group) whose middle half
    /// the dragged tab's middle is over. Its top and bottom quarters still
    /// mean above and below it, so tabs can be reordered past it.
    private func looseRow(at y: CGFloat, for tab: FirnCore.Tab) -> FirnCore.Tab? {
        for case let .tab(other) in store.tabListItems where other.id != tab.id {
            guard let frame = frames[other.id] else { continue }
            if y > frame.minY + frame.height / 4, y < frame.maxY - frame.height / 4 { return other }
        }
        return nil
    }

    /// The slot right beside `other`, on the side the dragged tab's slot is
    /// on now (so normally it doesn't move): where it'll sit in their group.
    /// Taking the slot from elsewhere leaves `other` where it is.
    private func slot(beside other: FirnCore.Tab, for drag: TabDrag) -> DropTarget {
        let index = store.tabListItems.filter { $0.id != drag.tab.id }.firstIndex { $0.id == other.id } ?? 0
        return .list(isAbove(drag.tab, other) ? index : index + 1)
    }

    private func isAbove(_ tab: FirnCore.Tab, _ other: FirnCore.Tab) -> Bool {
        (frames[tab.id]?.midY ?? .infinity) < (frames[other.id]?.midY ?? 0)
    }

    /// Where the dragged group would land in the tab list (not counting
    /// itself). An item above its slot stays above until the lifted card's
    /// top passes its middle; one below moves above once the card's bottom
    /// passes its middle. So a tall card swaps with a row as soon as it
    /// overlaps half of it, the same going up or down.
    private func target(of drag: GroupDrag) -> Int {
        guard let slot = frames[drag.group.id] else { return drag.target }
        let top = drag.location.y - drag.grab.height
        let bottom = top + slot.height
        return store.tabListItems.filter { item in
            guard item.id != drag.group.id, let frame = frames[item.id] else { return false }
            return frame.midY < slot.midY ? top >= frame.midY : bottom > frame.midY
        }.count
    }

    /// The tab's place now, so a drag starts by changing nothing.
    private func currentTarget(of tab: FirnCore.Tab) -> DropTarget {
        if let group = store.tabGroups.first(where: { $0.id == tab.groupID }) {
            return .group(group.id, store.rows(in: group).firstIndex { $0.id == tab.id } ?? 0)
        }
        return .list(store.tabListItems.firstIndex { $0.id == tab.id } ?? 0)
    }

    /// The slot the lifted copy lines up with: the open gap, or the name
    /// line of a folded group it's about to slip into.
    private func slot(for drag: TabDrag) -> CGRect? {
        if case let .group(id, _) = drag.target, store.tabGroups.first(where: { $0.id == id })?.folded == true,
           let card = frames[id] {
            let inset = Theme.panelRadius - Theme.tabRadius
            return CGRect(x: card.minX + inset, y: card.minY, width: card.width - 2 * inset, height: Theme.rowHeight)
        }
        return frames[drag.tab.id]
    }

    private var intoFoldedGroup: Bool {
        guard let drag, case let .group(id, _) = drag.target else { return false }
        return store.tabGroups.first { $0.id == id }?.folded == true
    }

    /// A tab's right-click menu: the few things you'd reach for, as in Dia.
    /// Later: Move to Space (Phase 4).
    @ViewBuilder private func menu(for tab: FirnCore.Tab) -> some View {
        if tab.sound != .silent {
            MuteMenuItem(tab: tab)
            Divider()
        }
        if tab.place == .open {
            Button("Add to Basecamp", systemImage: "mountain.2") { addToBasecamp(tab) }
                .disabled(!store.canAddToBasecamp)
            // Beside the tab on screen, or, for that tab, beside a page picked
            // in the command bar. (A split's halves have Separate Tabs instead.)
            if tab.splitID == nil, let onScreen = store.activeTab {
                Button("Open as Split", systemImage: "rectangle.split.2x1") {
                    if onScreen.id == tab.id {
                        window.pickSplit(beside: tab)
                    } else {
                        window.openSplit(tab, beside: onScreen)
                    }
                }
            }
            Divider()
            Button("Duplicate", systemImage: "plus.square.on.square") { window.duplicate(tab) }
                .disabled(tab.url == nil)
            Divider()
            if tab.groupID == nil {
                Button("New Group with This Tab", systemImage: "folder.badge.plus") {
                    window.newGroup(with: tab)
                }
                .keyboardShortcut("n", modifiers: [.command, .control])
            } else {
                Button("Remove from Group", systemImage: "folder.badge.minus") { takeOut(tab) }
            }
            // Only this space's groups, so nothing crosses between spaces.
            let others = store.tabGroups.filter { $0.id != tab.groupID }
            if !others.isEmpty {
                Menu("Move to Group", systemImage: "folder") {
                    ForEach(others) { group in
                        Button(group.name) { move(tab, toEndOf: group) }
                    }
                }
            }
            Divider()
        }
        if tab.url != nil {
            Button("Copy Link", systemImage: "link") { window.copyLink(of: tab) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
        }
        Button("Close Tab", systemImage: "xmark") { window.close(tab) }
            .keyboardShortcut("w")
        if tab.place == .open, tab.groupID == nil {
            Button("Close Other Tabs") { window.closeOtherTabs(than: tab) }
                .disabled(store.otherLooseTabs(than: tab).isEmpty)
        }
    }

    /// The blank space's right-click menu (AppKit; see `WindowDragArea`).
    private var blankSpaceMenu: [BlankSpaceMenuItem] {
        let reopen = store.nextToReopen
        return [
            BlankSpaceMenuItem(title: "New Tab", symbol: "plus.square", key: "t") { window.openCommandBar() },
            BlankSpaceMenuItem(title: reopen == .group ? "Reopen Closed Group" : "Reopen Closed Tab",
                               key: "t", modifiers: [.command, .shift], enabled: reopen != nil) { window.reopenClosed() },
            .divider,
            BlankSpaceMenuItem(title: "New Space…", symbol: "square.stack") { window.newSpace() },
            .divider,
            BlankSpaceMenuItem(title: window.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar", symbol: "sidebar.left", key: "s") { window.toggleSidebar() },
            .divider,
            BlankSpaceMenuItem(title: "Close All Tabs", symbol: "xmark", enabled: !store.looseTabs.isEmpty) {
                window.closeAllTabs()
            },
        ]
    }

    /// The dragged tab, lifted a little above the list; it follows the
    /// pointer up and down, and takes the width of the slot it's over.
    @ViewBuilder private var lifted: some View {
        if let drag, let slot = slot(for: drag) {
            liftedRow(drag.tab, isActive: true)
                .shadow(color: drag.settling || drag.overPage ? .clear : Theme.shadowPageFar, radius: 8, y: 3)
                .frame(width: slot.width)
                .offset(x: slot.minX)
                .animation(reduceMotion ? nil : Self.glide, value: slot.width)
                .offset(y: drag.follows || drag.overPage ? slot.minY : drag.location.y - drag.grab.height)
                // Carried from the menu, it glides along as its slot moves.
                .animation(drag.follows ? Theme.thaw : nil, value: slot.minY)
                // Out over the page (where its row follows the pointer), it
                // rests in its slot, faded, until it's back.
                // Dragged by the pointer, the window draws it instead
                // (`TabLiftGhost`); this copy only keeps its slot in step.
                .opacity(!drag.follows || (drag.settling && intoFoldedGroup) ? 0 : 1)
                .onChange(of: slot) { keepLift(to: slot) }
                // A tile arriving from Basecamp takes its first slot's width.
                .onAppear { if drag.fromBasecamp { keepLift(to: slot) } }
                // It sticks to the pointer; only settling into place, or
                // resting while over the page, glides.
                .transaction { if !drag.settling && !drag.overPage { $0.animation = nil } }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The dragged group's card. Drawn over the list rather than in its
    /// scrolling content, so tugging at the list's edge never clips it.
    @ViewBuilder private var liftedGroup: some View {
        if let groupDrag, let slot = frames[groupDrag.group.id] {
            // The list's content, from where the list shows.
            let dx = windowOrigin.point.x - shownInWindow.rect.minX
            let dy = windowOrigin.point.y - shownInWindow.rect.minY
            GroupCard(group: groupDrag.group, hasRows: !store.tabs(in: groupDrag.group).isEmpty,
                      color: Theme.spaceColor(store.activeSpace.color), renaming: .constant(nil),
                      foldLocked: true, thawed: false, closing: false, lifted: true, store: store,
                      ungroup: {}, close: {}) {
                ForEach(store.rows(in: groupDrag.group)) { tab in
                    liftedRow(tab, isActive: tab.id == store.activeTabID)
                }
            }
            .shadow(color: groupDrag.settling ? .clear : Theme.shadowPageFar, radius: 8, y: 3)
            .frame(width: slot.width)
            .offset(x: slot.minX + dx, y: cardTop(of: groupDrag, height: slot.height) + dy)
            .transaction { if !groupDrag.settling { $0.animation = nil } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The window's lifted copy keeps to the width and column of the slot it's over.
    private func keepLift(to slot: CGRect) {
        withAnimation(reduceMotion ? nil : Self.glide) {
            window.tabLift?.width = slot.width
            window.tabLift?.column = slot.minX + windowOrigin.point.x
        }
    }

    // MARK: Dragging

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                if groupDrag != nil { return moveGroup(to: value.location) }
                guard var current = drag else {
                    // A drag that starts on a group's name line moves the whole group.
                    if startGroupDrag(at: value.startLocation, pointer: value.location) { return }
                    // Only a drag that starts on a tab row moves a tab.
                    guard let tab = shownTabs.first(where: { frames[$0.id]?.contains(value.startLocation) == true }),
                          let frame = frames[tab.id] else { return }
                    drag = TabDrag(
                        tab: tab, grab: CGSize(width: 0, height: value.startLocation.y - frame.minY),
                        location: value.location, target: currentTarget(of: tab))
                    window.isDraggingTab = true
                    lift(tab, from: frame, at: value)
                    return
                }
                guard !current.settling else { return }
                current.location = value.location
                window.dragPointer = inWindow(value.location)
                if overPage(value.location, current: &current) { return }
                if overBasecamp(value.location, current: &current) { return }
                follow(current)
            }
    }

    /// The lifted tab at its new place: the list makes room where it'd land.
    /// Held well over a loose row, the list holds still and that row frosts
    /// over: let go there, the two become a group.
    private func follow(_ moved: TabDrag) {
        var current = moved
        let y = current.location.y - current.grab.height + Theme.rowHeight / 2
        // Once their group is forming, it holds until the tab clearly leaves
        // the card, so the rows moving under it don't undo it. Inside, its
        // slot follows it past the other tab's middle, as reordering does.
        if let preview, holdsPreview(current), let card = frames[preview.group.id], y > card.minY, y < card.maxY {
            let above = frames[preview.other.id].map { y < $0.midY } ?? preview.above
            if above == preview.above {
                drag = current
            } else {
                withAnimation(reduceMotion ? nil : Self.glide) {
                    self.preview?.above = above
                    drag = current
                }
            }
            return
        }
        let onto = current.fromBasecamp ? nil : looseRow(at: y, for: current.tab)
        let target = onto.map { slot(beside: $0, for: current) } ?? target(at: y, for: current.tab)
        if target == current.target, onto?.id == current.onto {
            drag = current
        } else {
            current.target = target
            current.onto = onto?.id
            if let preview, onto?.id != preview.other.id { thawPreview() }
            withAnimation(reduceMotion ? nil : Self.glide) { window.tabLift?.solid = onto != nil }
            withAnimation(reduceMotion ? nil : Self.glide) { drag = current }
        }
    }

    /// A Basecamp tile out over the list, as a row: the list makes room for
    /// it, as for one of its own. Taken back up (or out over the page), the
    /// room closes; let go, it settles in and leaves Basecamp.
    private func tileChanged(_ tile: TileInList?) {
        guard let tile else {
            if drag?.fromBasecamp == true, drag?.settling == false {
                withAnimation(reduceMotion ? nil : Self.glide) { drag = nil }
            }
            return
        }
        if tile.released {
            guard let current = drag, current.fromBasecamp, !current.settling else {
                window.tileInList = nil
                window.tabLift = nil
                return
            }
            return settle(current)
        }
        guard drag == nil, groupDrag == nil else { return }
        let grab = (window.tabLift?.grab.y ?? 0.5) * Theme.rowHeight
        var arriving = TabDrag(tab: tile.tab, grab: CGSize(width: 0, height: grab),
                               location: listPoint(window.dragPointer), target: .list(0), fromBasecamp: true)
        arriving.target = target(at: arriving.location.y - grab + Theme.rowHeight / 2, for: tile.tab)
        window.tabLift?.reach = rowReach
        withAnimation(reduceMotion ? nil : Self.glide) { drag = arriving }
    }

    private func tileMoved(to pointer: CGPoint) {
        guard var current = drag, current.fromBasecamp, !current.settling else { return }
        current.location = listPoint(pointer)
        follow(current)
    }

    /// A point in the window's space, in the list's.
    private func listPoint(_ pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x - windowOrigin.point.x, y: pointer.y - windowOrigin.point.y)
    }

    /// Lifts `tab` off the list: from here it's drawn over the whole window
    /// (`TabLiftGhost`), so it can leave the sidebar. A tab that can open
    /// in split view gets a picture of its page taken now, in case it goes
    /// out over the page; a sleeping page is never woken for it.
    private func lift(_ tab: FirnCore.Tab, from frame: CGRect, at value: DragGesture.Value) {
        let grab = CGPoint(x: (value.startLocation.x - frame.minX) / max(frame.width, 1),
                           y: (value.startLocation.y - frame.minY) / max(frame.height, 1))
        window.dragPointer = inWindow(value.location)
        window.tabLift = TabLift(tab: tab, row: AnyView(liftedRow(tab, isActive: true)), grab: grab,
                                 width: frame.width, column: frame.minX + windowOrigin.point.x)
        window.tabLift?.reach = rowReach
        guard window.canDragOntoPage(tab), let page = tab.page else { return }
        Task {
            // Twice the card's width, so it's sharp on a Retina screen.
            let picture = await page.snapshot(width: Theme.liftedCard.width * 2)
            if window.tabLift?.tab.id == tab.id { window.tabLift?.preview = picture }
        }
    }

    /// A dragged row keeps to the list as it shows (`Tug`): it can't be
    /// pulled up over Basecamp or down over the spaces.
    private var rowReach: ClosedRange<CGFloat> {
        let list = shownInWindow.rect
        return list.minY...max(list.minY, list.maxY - Self.bottomRoom - Theme.rowHeight)
    }

    /// Room kept below a dragged row or card, so even fully tugged it
    /// stops a row's gap short of the spaces.
    private static let bottomRoom = Tug.give + Theme.rowSpacing

    /// A dragged group's card top, kept to the list in the same way.
    private func cardTop(of drag: GroupDrag, height: CGFloat) -> CGFloat {
        let top = shownInWindow.rect.minY - windowOrigin.point.y
        let bottom = shownInWindow.rect.maxY - windowOrigin.point.y
        return Tug.held(drag.location.y - drag.grab.height, top, bottom - Self.bottomRoom - height)
    }

    /// A point in the list's space, in the window's.
    private func inWindow(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x + windowOrigin.point.x, y: location.y + windowOrigin.point.y)
    }

    /// Out over the page, a tab that can open there in split view shows
    /// where it would (frost over a half, see `PageArea`), its row resting
    /// back in its slot. Back over the sidebar, the page goes back as it was.
    /// True while it's over the page.
    private func overPage(_ location: CGPoint, current: inout TabDrag) -> Bool {
        let pointer = inWindow(location)
        let slide = Theme.slide(reduceMotion: reduceMotion)
        guard let side = window.pageSide(at: pointer, for: current.tab, past: shownInWindow.rect.maxX) else {
            if current.overPage {
                current.overPage = false
                withAnimation(slide) { window.pageDrop = nil }
                withAnimation(reshape) { window.tabLift?.isCard = false }
            }
            return false
        }
        if !current.overPage {
            if current.overBasecamp { leaveBasecamp(&current) }
            window.basecampFullHint = false
            current.overPage = true
            withAnimation(reshape) { window.tabLift?.isCard = true }
            current.target = currentTarget(of: current.tab)
            current.onto = nil
            thawPreview()
            window.tabLift?.solid = false
            withAnimation(reduceMotion ? nil : Self.glide) { drag = current }
        } else {
            drag = current
        }
        let drop = PageDrop(tab: current.tab, side: side)
        if window.pageDrop != drop { withAnimation(slide) { window.pageDrop = drop } }
        return true
    }

    /// Held up past the top of the list, a tab that can join Basecamp
    /// comes loose there as a tile (`BasecampGrid` makes room and draws
    /// it). Its row's slot here stays open until it lands, so nothing in
    /// the list jumps under the pointer. A full Basecamp makes no room: a
    /// quiet line says so, and the row only tugs at the top. Coming back
    /// down takes a little more, so it doesn't flicker at the line. True
    /// while it's up there.
    private func overBasecamp(_ location: CGPoint, current: inout TabDrag) -> Bool {
        let pointer = inWindow(location)
        let list = shownInWindow.rect
        let above = pointer.x <= list.maxX && pointer.y < list.minY + (current.overBasecamp ? 8 : 0)
        let joining = basecampTab(for: current.tab)
        let full = above && !store.canAddToBasecamp
        if window.basecampFullHint != full { window.basecampFullHint = full }
        guard above, store.canAddToBasecamp, joining.url != nil else {
            if current.overBasecamp { leaveBasecamp(&current) }
            return false
        }
        if !current.overBasecamp {
            current.overBasecamp = true
            current.target = currentTarget(of: current.tab)
            current.onto = nil
            thawPreview()
            window.tabLift?.solid = false
            withAnimation(reduceMotion ? nil : Self.glide) { drag = current }
            window.tabInBasecamp = TileInList(tab: joining)
        } else {
            drag = current
        }
        return true
    }

    /// Back down over the list (or out over the page): Basecamp closes up, and it's a row again.
    private func leaveBasecamp(_ current: inout TabDrag) {
        current.overBasecamp = false
        window.tabInBasecamp = nil
        withAnimation(reshape) { window.tabLift?.isTile = false }
    }

    /// The tab a dragged row would put in Basecamp: for a split, the half
    /// it was picked up by (the other stays here as an everyday tab).
    private func basecampTab(for tab: FirnCore.Tab) -> FirnCore.Tab {
        guard let split = store.split(of: tab), let partner = store.splitPartner(of: tab) else { return tab }
        return Double(window.tabLift?.grab.x ?? 0) < split.leftFraction ? tab : partner
    }

    /// The row turning into its page's picture and back: a short glide; a fade with Reduce Motion.
    private var reshape: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2)
    }

    /// Starts dragging a group if `start` is on its name line (and it isn't
    /// being renamed).
    private func startGroupDrag(at start: CGPoint, pointer: CGPoint) -> Bool {
        guard let group = store.tabGroups.first(where: { group in
            guard group.id != renamingGroupID, let card = frames[group.id] else { return false }
            return start.y >= card.minY && start.y < card.minY + Theme.groupHeaderHeight
                && start.x >= card.minX && start.x <= card.maxX
        }), let card = frames[group.id],
              let index = store.tabListItems.firstIndex(where: { $0.id == group.id }) else { return false }
        foldLocked = true
        groupDrag = GroupDrag(group: group, grab: CGSize(width: 0, height: start.y - card.minY),
                              location: pointer, target: index)
        return true
    }

    private func moveGroup(to location: CGPoint) {
        guard var current = groupDrag, !current.settling else { return }
        current.location = location
        let target = target(of: current)
        if target == current.target {
            groupDrag = current
        } else {
            current.target = target
            withAnimation(reduceMotion ? nil : Self.glide) { groupDrag = current }
        }
    }

    /// The lifted card settles into its slot, then the group really moves there.
    private func dropGroup() {
        guard var current = groupDrag, !current.settling else { return }
        @MainActor func commit() {
            if let group = store.tabGroups.first(where: { $0.id == current.group.id }) {
                store.move(group, to: current.target)
            }
            groupDrag = nil
            // After this mouse-up's tap on the name line has come and gone.
            Task { @MainActor in foldLocked = false }
        }
        guard !reduceMotion, let slot = frames[current.group.id] else { return commit() }
        current.settling = true
        current.location.y = slot.minY + current.grab.height
        withAnimation(Self.glide) {
            groupDrag = current
        } completion: {
            commit()
        }
    }

    /// A tab let go: over the page, or back in the list.
    private func drop() {
        if groupDrag != nil { return dropGroup() }
        guard let current = drag, !current.settling, !current.fromBasecamp else { return }
        window.isDraggingTab = false
        window.basecampFullHint = false
        // Let go over Basecamp: it settles in there as a tile (see
        // `BasecampGrid`); its row here goes once it has.
        if current.overBasecamp {
            window.tabInBasecamp?.released = true
            return
        }
        // Let go over the page: it opens there at once (no show on the way,
        // you just want the page), its picture fading as it does, and its row
        // becomes the split's.
        if current.overPage {
            drag = nil
            withAnimation(.easeOut(duration: 0.15)) { window.tabLift = nil }
            return window.dropOnPage()
        }
        settle(current)
    }

    /// The lifted copy settles into its slot, then the tab really moves
    /// there (which looks like nothing, since it's already showing there).
    private func settle(_ dropped: TabDrag) {
        if let preview, preview.formed, holdsPreview(dropped) { return settleIntoPreview(dropped, preview) }
        if dropped.onto != nil, !reduceMotion { return settleIntoGroup(dropped) }
        var current = dropped
        @MainActor func commit() {
            if let id = current.onto {
                if let other = store.openTabs.first(where: { $0.id == id }) { group(current.tab, with: other) }
            } else {
                place()
            }
            drag = nil
            window.tabLift = nil
            window.tileInList = nil
        }
        @MainActor func place() {
            switch current.target {
            case let .group(id, position):
                if let group = store.tabGroups.first(where: { $0.id == id }) {
                    land(current.tab, fromBasecamp: current.fromBasecamp, in: group, at: position)
                }
            case let .list(position):
                land(current.tab, fromBasecamp: current.fromBasecamp, in: nil, at: position)
            }
        }
        guard !reduceMotion, let slot = slot(for: current) else { return commit() }
        current.settling = true
        current.location.y = slot.minY + current.grab.height
        // The lifted tab glides back into its slot, a row again.
        let settle = slot.offsetBy(dx: windowOrigin.point.x, dy: windowOrigin.point.y)
        withAnimation(Self.glide) {
            drag = current
            window.tabLift?.isCard = false
            window.tabLift?.settle = settle
            window.tabLift?.fades = intoFoldedGroup
        } completion: {
            // A group the tab left empty fades away.
            withAnimation(Self.glide) { commit() }
        }
    }

    /// Let go onto a loose row: in one motion, as New Group from the menu.
    /// The two become a group at once, in the order they sit (the card
    /// starts thawed, in their exact shape), and as its frost forms, the
    /// lifted tab glides to its place in the card on the same curve, its
    /// backing fading so it lands as the row itself.
    private func settleIntoGroup(_ dropped: TabDrag) {
        var current = dropped
        guard let id = current.onto, let other = store.openTabs.first(where: { $0.id == id }),
              store.openTabs.contains(where: { $0.id == current.tab.id }),
              let slot = frames[current.tab.id] else {
            current.onto = nil
            return settle(current)
        }
        let first = isAbove(current.tab, other)
        // Where its row will be once the card has formed: inside the
        // card's insets, below the name line.
        let inset = Theme.panelRadius - Theme.tabRadius
        let place = CGRect(x: slot.minX + inset, y: slot.minY + Theme.groupHeaderHeight + Theme.rowSpacing,
                           width: slot.width - 2 * inset, height: slot.height)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            window.newGroup(with: other)
            guard let group = store.tabGroups.first(where: { $0.id == other.groupID }) else { return }
            store.move(current.tab, into: group, at: first ? 0 : 1)
            current.target = .group(group.id, first ? 0 : 1)
            drag = current
        }
        window.isDraggingTab = false
        withAnimation(Theme.thaw) {
            // The hint thaws as the card's own frost forms.
            drag?.settling = true
            drag?.location.y = place.minY + current.grab.height
            window.tabLift?.isCard = false
            window.tabLift?.solid = false
            window.tabLift?.bare = true
            window.tabLift?.settle = place.offsetBy(dx: windowOrigin.point.x, dy: windowOrigin.point.y)
        } completion: {
            drag = nil
            window.tabLift = nil
            window.tileInList = nil
        }
    }

    /// Held over a loose row a moment, like folders on the iPhone's home
    /// screen: the group the two would make starts forming around that
    /// row, as New Group's frost does, with a slot for the tab beside it.
    /// The store doesn't change until it's let go there. The card appears
    /// thawed, in the rows' exact shape, and forms once it shows (`form`).
    private func holdOnto() async {
        guard let id = drag?.onto else { return }
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled, preview == nil, let current = drag, current.onto == id, !current.settling,
              let other = store.openTabs.first(where: { $0.id == id }) else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            preview = GroupPreview(group: store.previewGroup(), other: other, above: isAbove(current.tab, other))
        }
    }

    /// Moved off before letting go: the forming group thaws back, and the
    /// list is as it was.
    private func thawPreview() {
        guard let id = preview?.group.id, preview?.formed == true else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.thaw) {
            preview?.formed = false
        } completion: {
            // Thawed, the card looks just like the row it was around.
            guard preview?.group.id == id, preview?.formed == false else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                preview = nil
                frames[id] = nil
            }
        }
    }

    /// Let go in a forming group: the tab settles into its slot in the
    /// card, then the store makes the group (`makeGroup`).
    private func settleIntoPreview(_ dropped: TabDrag, _ preview: GroupPreview) {
        guard !reduceMotion, let slot = frames[dropped.tab.id] else { return makeGroup(from: preview, adding: dropped.tab) }
        window.isDraggingTab = false
        withAnimation(Self.glide) {
            drag?.settling = true
            drag?.location.y = slot.minY + dropped.grab.height
            window.tabLift?.isCard = false
            window.tabLift?.solid = false
            window.tabLift?.bare = true
            window.tabLift?.settle = slot.offsetBy(dx: windowOrigin.point.x, dy: windowOrigin.point.y)
        } completion: {
            makeGroup(from: preview, adding: dropped.tab)
        }
    }

    /// The store makes the group the preview showed, in its place at once
    /// (the two look the same), and its name field opens.
    private func makeGroup(from preview: GroupPreview, adding tab: FirnCore.Tab) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            self.preview = nil
            frames[preview.group.id] = nil
            drag = nil
            window.tabLift = nil
            window.tileInList = nil
            guard store.openTabs.contains(where: { $0.id == tab.id }),
                  let group = store.newGroup(with: preview.other) else { return }
            store.move(tab, into: group, at: preview.above ? 0 : 1)
            window.finishForming(group.id)
        }
    }

    /// A tab let go onto a loose row, with Reduce Motion: the two become a
    /// group in the order they sit, with a fade.
    private func group(_ tab: FirnCore.Tab, with other: FirnCore.Tab) {
        guard store.openTabs.contains(where: { $0.id == tab.id }) else { return }
        let first = isAbove(tab, other)
        window.newGroup(with: other)
        guard let group = store.tabGroups.first(where: { $0.id == other.groupID }) else { return }
        withAnimation(.easeOut(duration: 0.2)) { store.move(tab, into: group, at: first ? 0 : 1) }
    }

    /// The tab really moves where it was let go. A Basecamp tile leaves
    /// Basecamp there, as an everyday tab.
    private func land(_ tab: FirnCore.Tab, fromBasecamp: Bool, in group: TabGroup?, at position: Int) {
        if fromBasecamp {
            if store.basecampTabs.contains(where: { $0.id == tab.id }) {
                store.removeFromBasecamp(tab, toGroup: group, at: position)
            }
        } else if store.openTabs.contains(where: { $0.id == tab.id }) {
            store.move(tab, toGroup: group, at: position)
        }
    }
}
