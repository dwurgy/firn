import FirnCore
import SwiftUI

/// The command bar over the page area (⌘T, the New tab button, an empty
/// window): a frosted card in the space's color over a lightly dimmed
/// page. Just the field until something is typed; then up to seven rows
/// from the space on screen only (`BrowserStore.commandRows`). No tab
/// exists until a row is picked; Esc or a click on the dim leaves nothing
/// behind. It rises a hair as it fades in; Reduce Motion: fades.
struct CommandBarLayer: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        GeometryReader { proxy in
            // Picking a page for a split, the bar sits over the empty half.
            let half = window.commandBarHalf
            let leftWidth = half != nil ? SplitPicking.leftWidth(in: proxy.size.width) : 0
            let rightStart = leftWidth == 0 ? 0 : leftWidth + Theme.pageInset
            ZStack(alignment: .top) {
                if window.showsCommandBar {
                    // Each page dims on its own, so the gap between them doesn't.
                    HStack(spacing: Theme.pageInset) {
                        if leftWidth > 0 { shape.fill(Theme.commandDim).frame(width: leftWidth) }
                        shape.fill(Theme.commandDim)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { window.closeCommandBar() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    CommandBar(store: store, window: window)
                        .frame(width: min(560, max(0, proxy.size.width - rightStart - 64)))
                        .frame(maxWidth: .infinity)
                        .padding(.leading, half == .right ? rightStart : 0)
                        .padding(.trailing, half == .left ? rightStart : 0)
                        // About a fifth of the way down, as a glance, not a page.
                        .padding(.top, max(48, proxy.size.height * 0.22))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeOut(duration: 0.2), value: window.showsCommandBar)
    }
}

private struct CommandBar: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    /// The chosen row, by id, so suggestions arriving don't move it; nil
    /// means the first.
    @State private var selection: String?
    /// The engine's latest suggestions. Kept until new ones come, so the
    /// rows don't flicker on every key.
    @State private var suggestions: [String] = []
    /// This space's history pages for what's typed, kept the same way.
    @State private var history: [HistoryPage] = []
    @FocusState private var focused: Bool
    /// Set once the field has had focus, so losing it can close the bar.
    @State private var hadFocus = false

    @AppStorage(Preference.searchEngine) private var engine = SearchEngine.default
    @AppStorage(Preference.searchSuggestions) private var asksForSuggestions = false
    private static let fieldHeight: CGFloat = 48

    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preference.blocksContent) private var blocksContent = true

    private func rows(actions: [BarAction]) -> [CommandRow] {
        // Picking a page for a split, it's pages only, not actions.
        let actions = window.splitPickAnchor == nil ? actions.map(\.action) : []
        return store.commandRows(
            for: text, searchEngine: engine, suggestions: suggestions, history: history, actions: actions
        )
    }

    var body: some View {
        let actions = actions
        let rows = rows(actions: actions)
        let selected = selectedIndex(in: rows)
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        VStack(spacing: 0) {
            field()
            if !rows.isEmpty {
                Rectangle()
                    .fill(Theme.tileHairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, Theme.rowPadding)
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        CommandRowView(row: row, engine: engine, isSelected: index == selected) { pick(row, actions: actions) }
                    }
                }
                .padding(6)
            }
        }
        .background { CommandBarGlass(shape: shape, color: Theme.spaceColor(store.activeSpace.color)) }
        .clipShape(shape)
        .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
        .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
        .background { ArrowCatcher(onArrow: { move(by: $0, in: rows) }) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command bar")
        .task(id: text) { await fetchSuggestions() }
        .task(id: text) { await fetchHistory() }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focused = true
            }
        }
    }

    private func field() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField(window.splitPickAnchor == nil ? "Search or enter address" : "Search, enter address, or find a tab",
                      text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                // Read fresh at Return, not from this render: a held copy
                // of the rows could miss the row the arrows just chose.
                .onSubmit { submit() }
                .onExitCommand { window.closeCommandBar() }
                .onChange(of: text) { selection = nil }
                .onChange(of: focused) {
                    // Clicking elsewhere (the sidebar, say) closes it, and
                    // leaves focus where the click put it.
                    if focused { hadFocus = true } else if hadFocus { window.closeCommandBar(focusingPage: false) }
                }
        }
        .padding(.horizontal, Theme.rowPadding + 4)
        .frame(height: Self.fieldHeight)
    }

    /// Return: picks the chosen row as things are right now.
    private func submit() {
        let actions = actions
        let rows = rows(actions: actions)
        let selected = selectedIndex(in: rows)
        if rows.indices.contains(selected) { pick(rows[selected], actions: actions) }
    }

    private func selectedIndex(in rows: [CommandRow]) -> Int {
        selection.flatMap { id in rows.firstIndex { $0.id == id } } ?? 0
    }

    private func move(by offset: Int, in rows: [CommandRow]) {
        guard !rows.isEmpty else { return }
        let index = min(max(selectedIndex(in: rows) + offset, 0), rows.count - 1)
        guard rows[index].id != selection ?? rows[0].id else { return }
        selection = rows[index].id
        // The field keeps VoiceOver's focus while typing, so say which row
        // Return would pick.
        AccessibilityNotification.Announcement(CommandRowView.spoken(rows[index], engine: engine)).post()
    }

    /// A short pause after typing, then the engine's suggestions. Each key
    /// cancels the last request; nothing is sent for an address.
    private func fetchSuggestions() async {
        guard asksForSuggestions, SearchSuggestions.mayAsk(about: text) else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let found = await SearchSuggestions.fetch(text, from: engine)
        guard !Task.isCancelled else { return }
        suggestions = found
    }

    /// History is on this Mac, so it's read at once, with no pause. Each key
    /// cancels the last lookup.
    private func fetchHistory() async {
        let found = await store.historyPages(for: text)
        guard !Task.isCancelled else { return }
        history = found
    }

    private func pick(_ row: CommandRow, actions: [BarAction]) {
        if let anchor = window.splitPickAnchor { return pickSplit(row, beside: anchor) }
        // The bar goes first, so an action that opens a sheet or names a
        // group gets the focus, not the page.
        if case let .action(action) = row {
            window.closeCommandBar(focusingPage: false)
            actions.first { $0.action.id == action.id }?.run()
            return
        }
        let change = { @MainActor in
            switch row {
            case let .go(url), let .search(_, url, _):
                store.openTab(url)
            case let .history(page):
                store.openTab(page.url)
            case let .tab(tab):
                store.select(tab)
            case let .tidied(tab):
                window.rise([tab])
                store.select(tab)
            case let .closed(entry):
                store.reopen(entry)
            case .action:
                break
            }
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2), change)
        window.closeCommandBar()
    }

    /// The page picked for the empty half goes there, beside `anchor`.
    private func pickSplit(_ row: CommandRow, beside anchor: FirnCore.Tab) {
        window.finishSplitPick {
            let incoming: FirnCore.Tab?
            switch row {
            case let .go(url), let .search(_, url, _):
                incoming = store.openTab(url, inBackground: true)
            case let .history(page):
                incoming = store.openTab(page.url, inBackground: true)
            case let .tab(tab), let .tidied(tab):
                incoming = tab
            case let .closed(entry):
                store.reopen(entry)
                incoming = store.activeTab
            case .action:
                incoming = nil
            }
            if let incoming, incoming.id != anchor.id {
                window.openSplit(incoming, beside: anchor, on: window.splitPickSide.other)
            } else {
                store.select(anchor)
            }
        }
        window.closeCommandBar()
    }

    /// What can be done by name right now, the same things as the menu bar
    /// with the same shortcuts. Only what would do something is offered.
    private var actions: [BarAction] {
        var list: [BarAction] = []
        func add(_ id: String, _ name: String, _ keywords: [String] = [], _ shortcut: String? = nil,
                 when available: Bool = true, run: @escaping @MainActor () -> Void) {
            guard available else { return }
            list.append(BarAction(action: CommandAction(id: id, name: name, keywords: keywords, shortcut: shortcut), run: run))
        }
        let page = window.frontPage
        let tab = window.everydayTab

        add("reload", "Reload Page", ["refresh"], "⌘R", when: window.canReloadFront) {
            page?.reload()
            window.focusPage()
        }
        add("back", "Back", ["previous", "page"], "⌘[", when: page?.canGoBack == true) {
            page?.goBack()
            window.focusPage()
        }
        add("forward", "Forward", ["next", "page"], "⌘]", when: page?.canGoForward == true) {
            page?.goForward()
            window.focusPage()
        }
        add("copy-link", "Copy Link", ["address", "url", "share"], "⇧⌘C", when: window.frontURL != nil) {
            window.copyFrontLink()
            window.focusPage()
        }
        add("print", "Print…", ["printer", "pdf"], "⌘P", when: page?.url != nil && page?.loadError == nil) {
            page?.printPage()
        }
        add("find", "Find on Page…", ["search page", "look for"], "⌘F", when: window.canFindInFront) {
            window.openFindBar()
        }
        add("zoom-in", "Zoom In", ["bigger", "larger", "magnify"], "⌘+", when: window.canZoomFront(.larger)) {
            window.zoomFront(.larger)
            window.focusPage()
        }
        add("zoom-out", "Zoom Out", ["smaller"], "⌘−", when: window.canZoomFront(.smaller)) {
            window.zoomFront(.smaller)
            window.focusPage()
        }
        add("actual-size", "Actual Size", ["reset zoom", "normal size", "100%"], "⌘0",
            when: window.canZoomFront(.actualSize)) {
            window.zoomFront(.actualSize)
            window.focusPage()
        }
        if let name = window.frontBlockingName(enabled: blocksContent) {
            add("blocking", name, ["ads", "trackers", "blocker", "allow", "site"]) {
                window.toggleFrontBlocking()
                window.focusPage()
            }
        }
        add("duplicate", "Duplicate Tab", ["copy"], when: tab?.url != nil) {
            if let tab { window.duplicate(tab) }
        }
        add("new-group", "New Group with This Tab", [], "⌃⌘N", when: tab != nil && tab?.groupID == nil) {
            if let tab { window.newGroup(with: tab) }
        }
        add("close", store.lookout == nil ? "Close Tab" : "Close Lookout", [], "⌘W",
            when: store.activeTab != nil || store.lookout != nil) {
            window.closeFront()
        }
        add("reopen", store.nextToReopen == .group ? "Reopen Closed Group" : "Reopen Closed Tab",
            ["undo", "restore", "bring back"], "⇧⌘T", when: store.nextToReopen != nil) {
            window.reopenClosed()
        }
        add("sidebar", window.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar", ["toggle"], "⌘S") {
            window.toggleSidebar()
            window.focusPage()
        }
        // Only the names of the other spaces, never what's in them.
        for (index, space) in store.spaces.enumerated() where space.id != store.activeSpace.id {
            add("space \(space.id)", "Switch to \(space.name)", ["space", "go"], index < 9 ? "⌃\(index + 1)" : nil) {
                window.showSpace { store.selectSpace(space) }
            }
        }
        add("new-space", "New Space…", ["add", "create", "space"]) { window.newSpace() }
        add("settings", "Settings", ["preferences", "options"], "⌘,") { openWindow(id: "settings") }
        return list
    }
}

/// An action the bar can run: what FirnCore matches, and what picking it does.
private struct BarAction {
    let action: CommandAction
    let run: @MainActor () -> Void
}

/// One row: an icon, the words, and a faint hint at the right saying what
/// picking it does.
private struct CommandRowView: View {
    let row: CommandRow
    let engine: SearchEngine
    let isSelected: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.muted)
                Text(title)
                    .font(Theme.tabFont)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                if let hint {
                    Text(hint)
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        // A long title gives way, never the hint.
                        .fixedSize()
                }
            }
            .padding(.horizontal, Theme.rowPadding - 2)
            .frame(height: Theme.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(isSelected ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Self.spoken(row, engine: engine))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// What VoiceOver says for a row: the words, then the hint.
    static func spoken(_ row: CommandRow, engine: SearchEngine) -> String {
        let view = CommandRowView(row: row, engine: engine, isSelected: false) {}
        return view.hint.map { "\(view.title), \($0)" } ?? view.title
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .go:
            Image(systemName: "globe")
        case .search:
            Image(systemName: "magnifyingglass")
        case let .tab(tab), let .tidied(tab):
            SiteIconView(icon: tab.icon, size: 16) { Image(systemName: "globe") }
        case let .closed(entry):
            if entry.kind == .group {
                Image(systemName: "square.on.square")
            } else {
                SiteIconView(icon: entry.icon, size: 16) { Image(systemName: "globe") }
            }
        case .history:
            Image(systemName: "clock")
        case .action:
            Image(systemName: "command")
        }
    }

    private var title: String {
        switch row {
        // The whole address, scheme and all, so it never hides an http.
        case let .go(url): url.absoluteString
        case let .search(text, _, _): text
        case let .tab(tab), let .tidied(tab): tab.title
        case let .closed(entry): entry.title
        // A page that never had a title shows where it was.
        case let .history(page): page.title.isEmpty ? page.url.absoluteString : page.title
        case let .action(action): action.name
        }
    }

    private var hint: String? {
        switch row {
        case .go: "Open"
        case .search(_, _, isSuggestion: false): "Search \(engine.name)"
        case .search: nil
        case .tab: "Switch to tab"
        case .tidied: "Tidied away"
        case .closed: "Recently closed"
        case .history: "History"
        case let .action(action): action.shortcut
        }
    }
}

/// The bar's glass: Liquid Glass on macOS 26, a regular material before,
/// tinted by the space's color. It sits over web pages, so it's the
/// regular (denser) glass, not the sidebar groups' thinner frost. The space
/// card (`SpaceSheet`) wears it too.
struct CommandBarGlass: View {
    let shape: RoundedRectangle
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.fill(color.opacity(Theme.groupTint)) }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else if #available(macOS 26, *) {
            shape.fill(Theme.commandVeil)
                .overlay { shape.strokeBorder(Theme.tileFrostEdge, lineWidth: 0.5) }
                .glassEffect(.regular.tint(color.opacity(Theme.groupTint)), in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(Theme.commandVeil) }
                .overlay { shape.fill(color.opacity(Theme.groupTint)) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        }
    }
}

/// ↑ and ↓ move through the rows while typing. AppKit, because the text
/// field's editor takes the arrow keys before SwiftUI sees them.
private struct ArrowCatcher: NSViewRepresentable {
    let onArrow: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onArrow = onArrow }

    final class CatcherView: NSView {
        var onArrow: ((Int) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let caught = MainActor.assumeIsolated { self?.catches(event) ?? false }
                return caught ? nil : event
            }
        }

        /// Only plain arrows, only in this window, and only while a text
        /// field is being typed in (the bar's own, since it closes when
        /// focus leaves it).
        private func catches(_ event: NSEvent) -> Bool {
            let offset = switch event.keyCode {
            case 125: 1
            case 126: -1
            default: 0
            }
            guard offset != 0, let window, event.window === window,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  (window.firstResponder as? NSTextView)?.isFieldEditor == true,
                  let onArrow else { return false }
            onArrow(offset)
            return true
        }
    }
}
