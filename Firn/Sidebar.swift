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
    /// The tab being dragged and how far it has moved; nil when nothing is.
    @State private var dragging: (id: UUID, offset: CGFloat)?
    /// True while a dropped row slides into its slot.
    @State private var settling = false
    /// The group whose name is being edited, if any.
    @State private var renamingGroupID: UUID?

    /// One speed for rows gliding aside and for the dropped row settling.
    private static let glide = Animation.smooth(duration: 0.2)

    private var step: CGFloat { Theme.rowHeight + Theme.rowSpacing }

    var body: some View {
        let tabs = store.looseTabs
        let groups = store.tabGroups
        // The list fills the sidebar's height, so the blank space below the
        // tabs (and the gaps between them) moves the window too.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Theme.rowSpacing) {
                    NewTabRow { window.editAddress(.newTab) }
                    if !groups.isEmpty {
                        VStack(spacing: Theme.groupSpacing) {
                            ForEach(groups) { group in
                                GroupCard(
                                    group: group,
                                    color: Theme.spaceColor(store.activeSpace.color),
                                    renaming: $renamingGroupID,
                                    store: store
                                ) {
                                    let members = store.tabs(in: group)
                                    ForEach(members) { tab in
                                        row(tab, in: members) { store.move(tab, into: group, at: $0) }
                                    }
                                }
                            }
                        }
                        // The cards' own edges keep them apart from the loose
                        // tabs; a little extra air below lets that read.
                        .padding(.top, Theme.groupSpacing - Theme.rowSpacing)
                        .padding(.bottom, Theme.groupSpacing)
                    }
                    ForEach(tabs) { tab in
                        row(tab, in: tabs) { store.move(tab, to: $0) }
                    }
                }
                .padding(.bottom, Theme.pageInset)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .background { WindowDragArea() }
            }
            .scrollIndicators(.never)
        }
    }

    /// A tab row that can be dragged to a new place among `tabs`.
    private func row(_ tab: FirnCore.Tab, in tabs: [FirnCore.Tab], move: @escaping (Int) -> Void) -> some View {
        TabRow(tab: tab, isActive: tab.id == store.activeTabID, canAddToBasecamp: store.canAddToBasecamp) {
            store.select(tab)
            window.focusPage()
        } close: {
            store.close(tab)
        } addToBasecamp: {
            store.addToBasecamp(tab)
        } newGroup: {
            withAnimation(reduceMotion ? nil : Self.glide) {
                // A new group asks for its name straight away.
                renamingGroupID = store.newGroup(with: tab)?.id
            }
        } takeOutOfGroup: {
            withAnimation(reduceMotion ? nil : Self.glide) { store.takeOutOfGroup(tab) }
        }
        .offset(y: offset(of: tab, in: tabs))
        // The dragged row sticks to the pointer; only the others glide.
        .transaction { if dragging?.id == tab.id, !settling { $0.animation = nil } }
        .zIndex(dragging?.id == tab.id ? 1 : 0)
        .simultaneousGesture(drag(tab, in: tabs, move: move))
    }

    /// Where the dragged row would land, as a position in the list.
    private func target(for id: UUID, offset: CGFloat, in tabs: [FirnCore.Tab]) -> Int {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return 0 }
        return min(max(from + Int((offset / step).rounded()), 0), tabs.count - 1)
    }

    /// The dragged row follows the pointer; rows it passes glide out of the way.
    private func offset(of tab: FirnCore.Tab, in tabs: [FirnCore.Tab]) -> CGFloat {
        guard let dragging, let from = tabs.firstIndex(where: { $0.id == dragging.id }),
              let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return 0 }
        if tab.id == dragging.id { return dragging.offset }
        let to = target(for: dragging.id, offset: dragging.offset, in: tabs)
        if from < to, index > from, index <= to { return -step }
        if from > to, index >= to, index < from { return step }
        return 0
    }

    private func drag(_ tab: FirnCore.Tab, in tabs: [FirnCore.Tab], move: @escaping (Int) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !settling else { return }
                withAnimation(reduceMotion ? nil : Self.glide) {
                    dragging = (tab.id, value.translation.height)
                }
            }
            .onEnded { value in
                guard !settling, let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                let position = target(for: tab.id, offset: value.translation.height, in: tabs)
                // Once the row is exactly over its slot, the move changes nothing you can see.
                @MainActor func commit() {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        move(position)
                        dragging = nil
                        settling = false
                    }
                }
                if reduceMotion { return commit() }
                settling = true
                withAnimation(Self.glide) {
                    dragging = (tab.id, CGFloat(position - from) * step)
                } completion: {
                    commit()
                }
            }
    }
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

private struct TabRow: View {
    let tab: FirnCore.Tab
    let isActive: Bool
    let canAddToBasecamp: Bool
    let select: () -> Void
    let close: () -> Void
    let addToBasecamp: () -> Void
    let newGroup: () -> Void
    let takeOutOfGroup: () -> Void
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
        .contextMenu {
            if let page = tab.page {
                Button("Reload") { page.reload() }
            }
            if let url = tab.url {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            if tab.place == .open {
                Button("Add to Basecamp", action: addToBasecamp)
                    .disabled(!canAddToBasecamp)
                if tab.groupID == nil {
                    Button("New Group with This Tab", action: newGroup)
                } else {
                    Button("Remove from Group", action: takeOutOfGroup)
                }
            }
            Divider()
            Button("Close Tab", action: close)
        }
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
    let color: Color
    @Binding var renaming: UUID?
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
        .padding(.bottom, group.folded ? 0 : Theme.panelRadius - Theme.tabRadius)
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
        .onTapGesture { if !isRenaming { toggleFold() } }
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
