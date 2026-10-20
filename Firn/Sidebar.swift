import FirnCore
import SwiftUI

/// The sidebar: the top row (traffic lights, the sidebar button, back, and
/// forward), the
/// address bar, and the space's tabs.
struct Sidebar: View {
    let store: BrowserStore
    let window: WindowModel
    /// Where macOS put the traffic lights; the top row lines up with them.
    let lights: TrafficLights

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            AddressBar(store: store, window: window)
                .padding(.top, 8)
                .padding(.bottom, Theme.sectionSpacing)
            BasecampGrid(store: store, window: window)
            TabList(store: store, window: window)
        }
        .padding(.leading, Theme.pageInset)
    }

    /// Centered on the traffic lights, which sit at its left.
    private var topRow: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: lights.trailingX + Theme.trafficLightGap - Theme.pageInset - 2, height: 1)
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
        .padding(.top, max(lights.centerY - Theme.rowHeight / 2, 0))
    }
}

// MARK: - Back and forward

private struct NavigationButtons: View {
    let page: any PageController

    var body: some View {
        ChromeButton("Back", systemImage: "chevron.left") { page.goBack() }
            .disabled(!page.canGoBack)
        ChromeButton("Forward", systemImage: "chevron.right") { page.goForward() }
            .disabled(!page.canGoForward)
    }

    /// The same buttons, disabled, when no tab is open.
    @ViewBuilder static var placeholder: some View {
        ChromeButton("Back", systemImage: "chevron.left") {}.disabled(true)
        ChromeButton("Forward", systemImage: "chevron.right") {}.disabled(true)
    }
}

/// A small icon button for the sidebar: quiet until hovered.
struct ChromeButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(ChromeButtonStyle())
            .help(label)
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Theme.muted : Theme.faint.opacity(0.6))
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering && isEnabled ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Address bar

/// Shows where the tab on screen is, and takes an address or a search.
/// At rest it shows just the site; clicking in shows the whole address.
private struct AddressBar: View {
    let store: BrowserStore
    let window: WindowModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var url: URL? { window.addressTarget == .newTab ? nil : store.activeTab?.url }
    /// Reload sits inside the bar, as in Safari, so the top row fits at the narrowest width.
    private var reloadablePage: (any PageController)? {
        guard !focused, let page = store.activeTab?.page, page.url != nil else { return nil }
        return page
    }

    var body: some View {
        TextField("Search or enter address", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(.leading, Theme.rowPadding)
            .padding(.trailing, reloadablePage == nil ? Theme.rowPadding : Theme.rowPadding + 24)
            .frame(height: Theme.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(focused ? Theme.page : hovering ? Theme.press : Theme.hover)
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(Theme.frost, lineWidth: 2)
                }
            }
            .overlay(alignment: .trailing) {
                if let page = reloadablePage {
                    Group {
                        if page.isLoading {
                            ChromeButton("Stop loading", systemImage: "xmark") { page.stopLoading() }
                        } else {
                            ChromeButton("Reload this page", systemImage: "arrow.clockwise") { page.reload() }
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
            .onHover { hovering = $0 }
            .accessibilityLabel(window.addressTarget == .newTab ? "New tab address" : "Address")
            .onSubmit(open)
            .onExitCommand(perform: cancel)
            .onChange(of: window.addressRequest) {
                text = url?.absoluteString ?? ""
                focused = true
            }
            .onChange(of: focused) {
                if !focused { cancel() } else { text = url?.absoluteString ?? "" }
            }
            .onChange(of: store.activeTab?.url) { showRestingAddress() }
            .onChange(of: store.activeTabID) { showRestingAddress() }
            .onAppear(perform: showRestingAddress)
    }

    private func open() {
        guard let url = AddressInput.url(for: text) else { return }
        if window.addressTarget == .newTab || store.activeTab == nil {
            store.openTab(url)
        } else {
            store.activeTab?.page?.load(url)
        }
        window.finishEditingAddress()
        focused = false
        window.focusPage()
    }

    private func cancel() {
        window.finishEditingAddress()
        if focused, store.activeTab != nil {
            focused = false
            window.focusPage()
        }
        showRestingAddress()
    }

    /// While someone isn't typing, the bar shows the committed address (never a
    /// pending one, so it can't claim to be a page that isn't there yet), as just the site.
    private func showRestingAddress() {
        guard !focused else { return }
        text = Self.site(of: store.activeTab?.url)
    }

    private static func site(of url: URL?) -> String {
        guard let url, let host = url.host(percentEncoded: false) else { return "" }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = url.port { return "\(site):\(port)" }
        return site
    }
}

// MARK: - Tabs

private struct TabList: View {
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
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Group {
                                switch item {
                                case let .group(group): card(group)
                                case let .tab(tab): row(tab)
                                }
                            }
                            .padding(.top, extraSpace(above: index, in: items))
                        }
                        if !atTop {
                            newTabRow
                                .padding(.top, isCard(items.last) ? Theme.groupSpacing : 0)
                        }
                    }
                    .overlay(alignment: .topLeading) { lifted }
                    .coordinateSpace(.named(Self.space))
                    // One drag for the whole list, so a tab can cross into and out
                    // of the group cards (a drag on the row itself would stop the
                    // moment the row moved to another card).
                    .simultaneousGesture(dragGesture)
                    .onChange(of: dragging) { if !dragging { drop() } }
                    .padding(.bottom, Theme.pageInset)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    .background { WindowDragArea() }
                }
                .scrollIndicators(.never)
                // A tab coming on screen (a new one at the bottom of a long
                // list, say) scrolls into view, by as little as it takes.
                .onChange(of: store.activeTabID) {
                    guard let id = store.activeTabID, store.activeTab?.place == .open else { return }
                    withAnimation(reduceMotion ? nil : Self.glide) { scroller.scrollTo(id) }
                }
            }
        }
    }

    private var newTabRow: some View {
        NewTabRow { window.editAddress(.newTab) }
    }

    private func isCard(_ item: TabListItem?) -> Bool {
        if case .group = item { true } else { false }
    }

    private func card(_ group: TabGroup) -> some View {
        let members = shownTabs(in: group)
        return GroupCard(
            group: group,
            hasRows: !members.isEmpty,
            color: Theme.spaceColor(store.activeSpace.color),
            renaming: Bindable(window).renamingGroupID,
            foldLocked: foldLocked,
            store: store
        ) {
            ForEach(members) { tab in row(tab) }
        }
        // While dragged, the card holds its slot open; the lifted copy is what shows.
        .opacity(groupDrag?.group.id == group.id ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
            frames[group.id] = $0
        }
    }

    /// Air around the group cards, on top of the usual gap between rows.
    /// The cards' own edges keep them apart from loose tabs; a little extra
    /// below a card lets that read.
    private func extraSpace(above index: Int, in items: [TabListItem]) -> CGFloat {
        let afterCard = index > 0 && isCard(items[index - 1])
        if afterCard && !isCard(items[index]) { return Theme.groupSpacing }
        return afterCard || isCard(items[index]) ? Theme.groupSpacing - Theme.rowSpacing : 0
    }

    private func row(_ tab: FirnCore.Tab) -> some View {
        TabRow(tab: tab, isActive: tab.id == store.activeTabID) {
            store.select(tab)
            window.focusPage()
        } close: {
            store.close(tab)
        } menu: {
            menu(for: tab)
        }
        // While dragged, the row holds its slot open; the lifted copy is what shows.
        .opacity(drag?.tab.id == tab.id ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
            frames[tab.id] = $0
        }
    }

    // MARK: Where things show while dragging

    /// A group's tabs as they'd be if the dragged tab landed where it is now.
    private func shownTabs(in group: TabGroup) -> [FirnCore.Tab] {
        var list = store.tabs(in: group)
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
        guard let drag else { return list }
        list.removeAll { $0.id == drag.tab.id }
        if case let .list(position) = drag.target {
            list.insert(.tab(drag.tab), at: min(position, list.count))
        }
        return list
    }

    /// The tab rows on show (folded groups hide theirs).
    private var shownTabs: [FirnCore.Tab] {
        store.sidebarTabs.filter { $0.place == .open }
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
            let members = store.tabs(in: group)
            return .group(group.id, group.folded ? members.filter { $0.id != tab.id }.count : position(in: members))
        }
        return .list(items.filter { (frames[$0.id]?.midY ?? .infinity) < y }.count)
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
        if let groupID = tab.groupID {
            let members = store.openTabs.filter { $0.groupID == groupID }
            return .group(groupID, members.firstIndex { $0.id == tab.id } ?? 0)
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
    /// Later: Open as Split (split view) and Move to Space (Phase 4).
    @ViewBuilder private func menu(for tab: FirnCore.Tab) -> some View {
        let glide = reduceMotion ? nil : Self.glide
        if tab.place == .open {
            Button("Add to Basecamp", systemImage: "mountain.2") { store.addToBasecamp(tab) }
                .disabled(!store.canAddToBasecamp)
            Divider()
            Button("Duplicate", systemImage: "plus.square.on.square") { window.duplicate(tab) }
                .disabled(tab.url == nil)
            Divider()
            if tab.groupID == nil {
                Button("New Group with This Tab", systemImage: "folder.badge.plus") {
                    withAnimation(glide) { window.newGroup(with: tab) }
                }
                .keyboardShortcut("n", modifiers: [.command, .control])
            } else {
                Button("Remove from Group", systemImage: "folder.badge.minus") {
                    withAnimation(glide) { store.takeOutOfGroup(tab) }
                }
            }
            // Only this space's groups, so nothing crosses between spaces.
            let others = store.tabGroups.filter { $0.id != tab.groupID }
            if !others.isEmpty {
                Menu("Move to Group", systemImage: "folder") {
                    ForEach(others) { group in
                        Button(group.name) { withAnimation(glide) { store.move(tab, toEndOf: group) } }
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
        Button("Close Tab", systemImage: "xmark") { store.close(tab) }
            .keyboardShortcut("w")
    }

    /// The dragged tab, lifted a little above the list; it follows the
    /// pointer up and down, and takes the width of the slot it's over.
    @ViewBuilder private var lifted: some View {
        if let drag, let slot = slot(for: drag) {
            TabRow(tab: drag.tab, isActive: true, select: {}, close: {}) { EmptyView() }
                .shadow(color: drag.settling ? .clear : Theme.shadowPageFar, radius: 8, y: 3)
                .frame(width: slot.width)
                .offset(x: slot.minX)
                .animation(reduceMotion ? nil : Self.glide, value: slot.width)
                .offset(y: drag.location.y - drag.grab.height)
                .opacity(drag.settling && intoFoldedGroup ? 0 : 1)
                // It sticks to the pointer; only settling into place glides.
                .transaction { if !drag.settling { $0.animation = nil } }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let groupDrag, let slot = frames[groupDrag.group.id] {
            GroupCard(group: groupDrag.group, hasRows: !store.tabs(in: groupDrag.group).isEmpty,
                      color: Theme.spaceColor(store.activeSpace.color), renaming: .constant(nil),
                      foldLocked: true, store: store) {
                ForEach(store.tabs(in: groupDrag.group)) { tab in
                    TabRow(tab: tab, isActive: tab.id == store.activeTabID, select: {}, close: {}) { EmptyView() }
                }
            }
            .shadow(color: groupDrag.settling ? .clear : Theme.shadowPageFar, radius: 8, y: 3)
            .frame(width: slot.width)
            .offset(x: slot.minX, y: groupDrag.location.y - groupDrag.grab.height)
            .transaction { if !groupDrag.settling { $0.animation = nil } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                    return
                }
                guard !current.settling else { return }
                current.location = value.location
                let target = target(at: value.location.y - current.grab.height + Theme.rowHeight / 2, for: current.tab)
                if target == current.target {
                    drag = current
                } else {
                    current.target = target
                    withAnimation(reduceMotion ? nil : Self.glide) { drag = current }
                }
            }
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

    /// The lifted copy settles into its slot, then the tab really moves
    /// there (which looks like nothing, since it's already showing there).
    private func drop() {
        if groupDrag != nil { return dropGroup() }
        guard var current = drag, !current.settling else { return }
        @MainActor func commit() {
            if store.openTabs.contains(where: { $0.id == current.tab.id }) {
                switch current.target {
                case let .group(id, position):
                    if let group = store.tabGroups.first(where: { $0.id == id }) {
                        store.move(current.tab, toGroup: group, at: position)
                    }
                case let .list(position):
                    store.move(current.tab, toGroup: nil, at: position)
                }
            }
            drag = nil
        }
        guard !reduceMotion, let slot = slot(for: current) else { return commit() }
        current.settling = true
        current.location.y = slot.minY + current.grab.height
        withAnimation(Self.glide) {
            drag = current
        } completion: {
            // A group the tab left empty fades away.
            withAnimation(Self.glide) { commit() }
        }
    }
}

/// Where a dragged tab would land: a place among a group's tabs, or in the
/// tab list, where each group counts as one (not counting the tab itself).
private enum DropTarget: Equatable {
    case group(UUID, Int)
    case list(Int)
}

private struct TabDrag {
    let tab: FirnCore.Tab
    /// Where the pointer holds the row, from its top-left.
    let grab: CGSize
    /// The pointer, in the list's space.
    var location: CGPoint
    var target: DropTarget
    /// True while the lifted copy glides into its slot after the drop.
    var settling = false
}

private struct GroupDrag {
    let group: TabGroup
    /// Where the pointer holds the card, from its top-left.
    let grab: CGSize
    /// The pointer, in the list's space.
    var location: CGPoint
    /// Its place in the tab list, not counting itself.
    var target: Int
    /// True while the lifted card glides into its slot after the drop.
    var settling = false
}

private struct NewTabRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New tab", systemImage: "plus")
                .labelStyle(RowLabelStyle(color: Theme.muted))
        }
        .buttonStyle(RowButtonStyle(isActive: false))
        .help("New tab (⌘T)")
    }
}

private struct TabRow<MenuItems: View>: View {
    let tab: FirnCore.Tab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void
    @ViewBuilder let menu: MenuItems
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Label {
                    Text(tab.title)
                } icon: {
                    SiteIconView(icon: tab.icon, size: 16) { Image(systemName: "globe") }
                }
                    .labelStyle(RowLabelStyle(color: Theme.ink))
                Spacer(minLength: 0)
            }
            // Room for the close button, so long titles stop short of it.
            .padding(.trailing, hovering ? 20 : 0)
        }
        .buttonStyle(RowButtonStyle(isActive: isActive))
        .overlay(alignment: .trailing) {
            if hovering {
                Button("Close tab", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CloseButtonStyle())
                    .help("Close tab (⌘W)")
                    .padding(.trailing, 8)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: "Close tab", close)
    }
}

// MARK: - Groups

/// A group: a soft frosted card tinted by the space's color, with its name,
/// a dot in the space's color, and a fold arrow. The close button shows
/// only while the pointer is on the name line.
private struct GroupCard<Rows: View>: View {
    let group: TabGroup
    /// False while a dragged tab has left it with none to show.
    let hasRows: Bool
    let color: Color
    @Binding var renaming: UUID?
    /// True while the group is being dragged, so letting go doesn't fold it.
    let foldLocked: Bool
    let store: BrowserStore
    @ViewBuilder let rows: Rows
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous) }
    private var isRenaming: Bool { renaming == group.id }

    var body: some View {
        VStack(spacing: Theme.rowSpacing) {
            header
            if !group.folded {
                rows
            }
        }
        // Rows sit 4pt inside the card, so their 10pt corners nest in its 14pt.
        .padding(.horizontal, Theme.panelRadius - Theme.tabRadius)
        .padding(.bottom, group.folded || !hasRows ? 0 : Theme.panelRadius - Theme.tabRadius)
        .background { card }
        .contextMenu {
            Button("Rename", action: startRenaming)
            Button("Ungroup") { animate { store.ungroup(group) } }
            Divider()
            Button("Close Group") { animate { store.close(group) } }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.trailing, 2)
                .accessibilityHidden(true)
            if isRenaming {
                nameField
            } else {
                Text(group.name)
                    .font(Theme.groupNameFont)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(group.folded ? -90 : 0))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            if hovering, !isRenaming {
                Button("Close group", systemImage: "xmark") { animate { store.close(group) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(CloseButtonStyle())
                    .help("Close group")
            }
        }
        .padding(.leading, Theme.rowPadding)
        .padding(.trailing, 4)
        .frame(height: Theme.groupHeaderHeight)
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming, !foldLocked { toggleFold() } }
        .onHover { hovering = $0 }
        // While renaming, VoiceOver reaches the name field itself.
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(group.name)
        .accessibilityValue(group.folded ? "Folded" : "Open")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(group.folded ? "Shows the group's tabs" : "Hides the group's tabs")
        .accessibilityAction { toggleFold() }
        .accessibilityAction(named: "Rename", startRenaming)
        .accessibilityAction(named: "Close group") { animate { store.close(group) } }
    }

    private var nameField: some View {
        TextField("Group name", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.groupNameFont)
            .foregroundStyle(Theme.ink)
            .focused($nameFocused)
            .onSubmit(finishRenaming)
            .onExitCommand { renaming = nil }
            .onChange(of: nameFocused) { _, focused in if !focused { finishRenaming() } }
            .onAppear {
                draft = group.name
                nameFocused = true
            }
    }

    /// The same frosted glass as the Basecamp tiles, washed with the space's color.
    @ViewBuilder private var card: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.fill(color.opacity(Theme.groupTint)) }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else if #available(macOS 26, *) {
            shape.fill(.clear)
                .overlay { shape.strokeBorder(Theme.tileFrostEdge, lineWidth: 0.5) }
                .glassEffect(.regular.tint(color.opacity(Theme.groupTint)), in: shape)
        } else {
            shape.fill(Theme.groupFill)
                .overlay { shape.fill(color.opacity(Theme.groupTint)) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        }
    }

    private func toggleFold() {
        animate { store.setFolded(group, !group.folded) }
    }

    private func startRenaming() {
        renaming = group.id
    }

    private func finishRenaming() {
        guard isRenaming else { return }
        store.rename(group, to: draft)
        renaming = nil
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2), change)
    }
}

/// Icon and title, as every sidebar row shows them.
private struct RowLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 16)
            configuration.title
                .font(Theme.tabFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// A 36pt sidebar row: a warm wash on hover and press, lifted when it's the tab on screen.
private struct RowButtonStyle: ButtonStyle {
    let isActive: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.rowPadding)
            .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
                    .shadow(color: isActive ? Theme.shadowSoft : .clear, radius: 1, y: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
            .onHover { hovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if isActive { return Theme.activeTab }
        if pressed { return Theme.press }
        return hovering ? Theme.hover : .clear
    }
}

private struct CloseButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 20, height: 20)
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
