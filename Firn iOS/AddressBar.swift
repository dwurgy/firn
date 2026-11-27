import FirnCore
import SwiftUI

/// The bar at the bottom of the screen, laid out as Safari's: Back (widening
/// to hold Forward) in a small glass pill, and the address field beside it,
/// with the page menu on its left and reload (or stop) on its right.
/// Tapping the field hides the pill so the field has the whole width, picks
/// out the whole address, and the bar rides up with the keyboard. Go opens
/// it; tapping the page cancels. At rest it shows only the committed
/// address's site, never a pending one.
struct AddressBar: View {
    let store: BrowserStore
    var editing: FocusState<Bool>.Binding
    /// Typing from the overview's +: the field starts empty and Go opens a
    /// new tab.
    let typingNewTab: Bool
    let showTabs: () -> Void
    /// After Go has opened what was typed (the overview closes then).
    var opened: () -> Void = {}
    /// The page menu. Open, the field's glass grows into it and the rest of
    /// the bar slips into the field, as in Safari; closing is the same move
    /// back. The screen closes it on a tap anywhere else.
    @Binding var menuOpen: Bool
    /// Scrolling down to read has shrunk the bar (phase 5); a tap on the
    /// small pill grows it back.
    @Binding var shrunk: Bool
    /// The move between the full bar and the small pill: it follows the
    /// finger first, then finishes on its own (`BarGlide`).
    var shrinkGlide: Animation = AddressBar.plainShrinkGlide
    /// The other devices' tabs in the space on screen ("On your Mac";
    /// `ICloudSync.otherDeviceTabs`). None until sync's first sync.
    var otherDeviceTabs: () -> [DeviceTab] = { [] }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.barSlide) private var barSlide
    @Environment(\.barGive) private var barGive
    /// What's being typed, for the results above the field (empty at rest).
    @State private var typed = ""
    /// This space's history pages for what's typed, looked up as you type.
    @State private var history: [HistoryPage] = []
    /// The engine's latest suggestions, kept until new ones come so the rows
    /// don't flicker on every key. Only with the setting on.
    @State private var suggestions: [String] = []
    @AppStorage(SearchSuggestions.preferenceKey) private var asksForSuggestions = false
    /// Just after typing, while the keyboard slides away: the field's glass
    /// rides down with it, so the bar's resting parts (the site, its
    /// buttons, Back, and Tabs) wait until it has landed, then fade in.
    /// Shown at once, they sat at the bottom before the field got there
    /// (David's recording, 2026-11-05).
    @State private var settling = false
    /// Whether iOS's keyboard is on screen (a hardware keyboard shows none,
    /// so there's nothing to wait for).
    @State private var keyboardShown = false
    /// Add to Basecamp was picked with 12 tiles already there.
    @State private var basecampFull = false
    @Environment(\.newSpace) private var newSpace
    /// Send to My Mac (sync step 6): the devices to send to.
    @Environment(Sending.self) private var sending: Sending?
    /// The menu was opened by holding the field: its own short rows, about
    /// this tab (Copy Link, Paste and Go, Close Tab), not •••'s.
    @State private var heldMenu = false
    /// The row whose list the menu has turned to (Move to Group, or Send
    /// to… with several devices), by its key; nil for the menu itself.
    @State private var menuTurned: String?
    /// Something is copied, as the held menu opens: Paste and Go shows.
    @State private var canPaste = false
    @Environment(\.showDownloads) private var showDownloads
    @Environment(\.showHistory) private var showHistory
    @Environment(\.barQuiet) private var barQuiet
    /// A finger is holding the field (from the touch, before it's a hold).
    /// A plain box nothing watches (`FieldHold` keeps the gesture's own).
    @State private var held = BarQuiet()
    private var holding: Bool { held.on }
    /// The held field sinks a little until the page menu opens, as a held
    /// tab does before its menu (`pressedScale`).
    @State private var fieldPressed = false
    /// Bumped as a hold opens the menu: the lifted tab's tap.
    @State private var holdOpenings = 0
    /// The hold that opened the menu is still down: the same finger can
    /// slide onto a row and let go to pick it, as on a held tab's menu.
    @State private var holdTracking = false
    /// Where that finger is (global), once it has slid: the menu opens
    /// under it, so a hold let go without sliding picks nothing.
    @State private var menuPoint: CGPoint?
    /// Bumped as the sliding finger lifts, at `menuLiftPoint`.
    @State private var menuLift = 0
    @State private var menuLiftPoint: CGPoint?
    /// How far the finger slides before it points at rows.
    private static let pointSlop: CGFloat = 10

    private var page: (any PageController)? { store.activeTab?.page }
    /// The page on screen's translating, absent while Reader is on (as
    /// on the Mac) and before iOS 26.4; nil when the page isn't offered.
    private var translator: PageTranslator? {
        guard let page, !page.isReading, let translator = page.translator, translator.actionName != nil else { return nil }
        return translator
    }
    private var space: String { store.activeSpace.color }
    private var engine: SearchEngine { SearchEngine.chosen }
    @AppStorage(BrowserEngine.blockingKey) private var blocksContent = true
    /// "Stop Blocking on example.com" (or turning it back on) for the page
    /// on screen; nil when there's no site, or blocking is off everywhere.
    private var blockingName: String? {
        guard let page else { return nil }
        return store.blockingToggleName(for: page, enabled: blocksContent)
    }

    /// The menu's rows, in quiet sections (David, 2026-11-17, after
    /// Safari's). From •••, about the page: Show Reader, Summarize · Share…,
    /// Send to My Mac · Add to Basecamp, Move to Group · Find on Page, Stop
    /// Blocking · History, Downloads. From holding the field, about this
    /// tab, quick: Copy Link, Paste and Go, Move to Group, Send to My Mac ·
    /// Close Tab.
    private var menuSections: [[PageMenuPanel.Entry]] {
        typealias Entry = PageMenuPanel.Entry
        guard let page, let url = page.url, let tab = store.activeTab else { return [] }
        let space = space
        // Move to Group reads the same in every menu: New Group first, then
        // this space's other groups, and Remove from Group last for a tab
        // that's in one. Not for a Basecamp tile.
        var keep: [Entry] = []
        if tab.place == .open {
            var groups = [Entry(key: "group-new", title: "New Group", icon: .symbol("folder.badge.plus")) {
                _ = store.newGroup(with: tab)
            }]
            groups += store.tabGroups.filter { $0.id != tab.groupID }.map { group in
                Entry(key: "group-\(group.id)", title: group.name, icon: .dot) { store.move(tab, toEndOf: group) }
            }
            if tab.groupID != nil {
                groups.append(Entry(key: "group-leave", title: "Remove from Group", icon: .symbol("folder.badge.minus")) {
                    store.takeOutOfGroup(tab)
                })
            }
            keep.append(Entry(key: "group", title: "Move to Group", icon: .symbol("folder"), children: groups))
        }
        // Send to My Mac, with another device known: sent at once, or, with
        // several, "Send to…" and their names.
        var send: [Entry] = []
        if let sending {
            let targets = sending.targets(for: tab)
            if let title = SendTarget.menuTitle(for: targets), let first = targets.first {
                if targets.count == 1 {
                    send.append(Entry(key: "send", title: title, icon: .symbol(first.kind.symbol)) {
                        sending.send(tab, to: first)
                    })
                } else {
                    send.append(Entry(key: "send", title: title, icon: .symbol("laptopcomputer.and.iphone"),
                                      children: targets.map { target in
                        Entry(key: "send-\(target.id)", title: target.name, icon: .symbol(target.kind.symbol)) {
                            sending.send(tab, to: target)
                        }
                    }))
                }
            }
        }

        if heldMenu {
            var first = [Entry(key: "copy", title: "Copy Link", icon: .symbol("link")) { UIPasteboard.general.url = url }]
            if canPaste {
                // Reading what's copied is when iOS may ask "Allow Paste?".
                first.append(Entry(key: "paste", title: "Paste and Go", icon: .symbol("doc.on.clipboard")) {
                    // A copied link may come as an address alone, with no text.
                    let copied = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
                    guard let text = copied,
                          let url = AddressInput.url(for: text, searchEngine: SearchEngine.chosen) else { return }
                    InsecureFallback.remember(typed: text)
                    page.load(url)
                })
            }
            return [first + keep + send, [
                Entry(key: "close", title: "Close Tab", icon: .symbol("xmark"), closes: true) { store.close(tab) },
            ]]
        }

        // Show Reader first, on a page that reads as an article (as
        // Safari); Summarize just under it, only with Apple Intelligence.
        var reading: [Entry] = []
        if page.isArticle || page.isReading {
            reading.append(Entry(key: "reader", title: page.isReading ? "Hide Reader" : "Show Reader", icon: .book) {
                ReaderStyle.shared.toggle(page, space: space)
            })
            if ArticleSummarizer.isOffered {
                reading.append(Entry(key: "summarize", title: "Summarize", icon: .symbol("text.line.3.summary")) {
                    ReaderStyle.shared.summarize(page, space: space)
                })
            }
        }
        // Translate, just under them, on any page in a language the person
        // doesn't read (design, 2026-11-27). The iPhone has no mark, so the
        // second line says what the Mac's mark does.
        if let translator, let title = translator.actionName {
            let detail: String? = switch translator.state {
            case .translating: "Translating…"
            case .translated: translator.sourceName.map { "Translated from \($0)" }
            case .failed: "Couldn't translate this page"
            case .none, .offered: nil
            }
            reading.append(Entry(key: "translate", title: title, detail: detail,
                                 spoken: detail.map { "\(title), \($0)" }, icon: .symbol("translate")) {
                translator.toggle()
            })
        }
        let share = [Entry(key: "share", title: "Share…", icon: .symbol("square.and.arrow.up")) { ShareSheet.present(url) }]
        if tab.place == .open {
            keep.insert(Entry(key: "basecamp", title: "Add to Basecamp", icon: .symbol("mountain.2")) {
                if store.canAddToBasecamp { _ = store.addToBasecamp(tab) } else { basecampFull = true }
            }, at: 0)
        }
        // Find on Page (iOS's own find bar, on a page that loaded), and the
        // site's blocking: the words, and the site on a second line, since
        // a whole "Stop Blocking on …" won't fit the menu's width.
        var onPage: [Entry] = []
        if page.loadError == nil {
            onPage.append(Entry(key: "find", title: "Find on Page", icon: .symbol("doc.text.magnifyingglass")) {
                page.showFind()
            })
        }
        if blockingName != nil, let site = BlockingSite.of(url) {
            let title = store.blocksContent(on: url) ? "Stop Blocking" : "Block Ads and Trackers"
            onPage.append(Entry(key: "blocking", title: title, detail: site, spoken: "\(title) on \(site)",
                                icon: .symbol("hand.raised")) {
                store.toggleBlocking(on: page)
            })
        }
        // History, and Downloads while the space has any: how many are
        // saving, or how many there are.
        var places: [Entry] = []
        if let showHistory {
            places.append(Entry(key: "history", title: "History", icon: .symbol("clock")) { showHistory() })
        }
        if let showDownloads, let detail = Downloads.shared.summary(for: store.activeSpace.dataStoreID) {
            places.append(Entry(key: "downloads", title: "Downloads", detail: detail,
                                icon: .symbol("arrow.down.circle")) { showDownloads() })
        }
        return [reading, share + send, keep, onPage, places].filter { !$0.isEmpty }
    }

    /// The small pill shows only at rest: typing and the page menu always
    /// have the whole bar.
    private var compact: Bool { shrunk && !editing.wrappedValue && !menuOpen && store.activeTab?.page != nil }

    /// The pill, the field, and the tabs button each carry their own frost
    /// (`BarFrost`, Firn's own, not Liquid Glass; David, 2026-11-09), drawn
    /// with them, so it glides frame by frame with their words.
    var body: some View {
        let rows = editing.wrappedValue
            ? store.commandRows(for: typed, searchEngine: engine, suggestions: suggestions, history: history,
                                otherDevices: otherDeviceTabs(),
                                actions: actions.map(\.action)) : []
        VStack(spacing: Self.spacing) {
            if !rows.isEmpty {
                CommandResults(rows: rows, engine: engine, space: space, pick: pick, swipedDown: cancelTyping)
                    .transition(.opacity)
            }
            buttons
                .gesture(SwipeDown(enabled: editing.wrappedValue, action: cancelTyping))
        }
        // The card comes and goes with a short fade; its rows change in
        // place as you type, never gliding on each key.
        .animation(.easeOut(duration: 0.15), value: rows.isEmpty)
        .frame(maxWidth: 640)
        // Larger text grows the bar's words only as far as its 48pt height
        // holds them, as in Safari's bar.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, editing.wrappedValue ? 16 : Self.sideInset)
        .padding(.top, 8)
        .padding(.bottom, editing.wrappedValue ? 8 : 0)
        .onChange(of: page?.url) { menuOpen = false }
        .basecampFullAlert(isPresented: $basecampFull)
        // Closed, the menu forgets how it was opened and what it had turned to.
        .onChange(of: menuOpen) {
            guard !menuOpen else { return }
            heldMenu = false
            menuTurned = nil
        }
        // History is on this device, so it's read at once; each key cancels
        // the last lookup.
        .task(id: typed) {
            let found = typed.isEmpty ? [] : await store.historyPages(for: typed)
            guard !Task.isCancelled else { return }
            history = found
        }
        // A short pause after typing, then the engine's suggestions, as the
        // Mac's bar: each key cancels the last request, and nothing is sent
        // for an address or with the setting off.
        .task(id: typed) {
            guard asksForSuggestions, SearchSuggestions.mayAsk(about: typed) else {
                suggestions = []
                return
            }
            let text = typed
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = await SearchSuggestions.fetch(text, from: engine)
            guard !Task.isCancelled else { return }
            suggestions = found
        }
        .onChange(of: editing.wrappedValue) {
            if editing.wrappedValue {
                menuOpen = false
                settling = false
            } else {
                typed = ""
                settle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        // The resting parts come back once the field is most of the way
        // down, 30% into the keyboard's slide, timed from iOS's own start, so
        // their fade ends about as it lands. Waiting for the keyboard to be
        // gone, they came a beat after the field had settled (David,
        // 2026-11-13); earlier still, they sat at the bottom before the field
        // got there (2026-11-05).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            let slide = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(min(max(slide, 0.1), 0.6) * 0.3))
                land()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardShown = false
            land()
        }
        .environment(\.barSettling, settling)
    }

    /// A swipe down on the field or the results: typing ends and the
    /// keyboard goes away, as a tap on the dimmed page does.
    private func cancelTyping() {
        guard editing.wrappedValue else { return }
        editing.wrappedValue = false
    }

    /// Typing ended: the resting parts wait for the field to come down
    /// (see the keyboard's will-hide above), with a limit, in case iOS
    /// never says so.
    private func settle() {
        guard keyboardShown, !reduceMotion else { return }
        settling = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            land()
        }
    }

    /// The field has landed: its resting parts fade in.
    private func land() {
        guard settling else { return }
        withAnimation(.easeOut(duration: 0.18)) { settling = false }
    }

    /// A row picked. Go and Search do what Go on the keyboard does (load in
    /// the tab on screen, or a new tab from +); an open tab is switched to,
    /// never opened again.
    private func pick(_ row: CommandRow) {
        // A swipe down already ended typing: nothing is picked.
        guard editing.wrappedValue else { return }
        defer { editing.wrappedValue = false }
        switch row {
        case let .go(url), let .search(_, url, _):
            if case .go = row { InsecureFallback.remember(typed: typed) }
            if let page, !typingNewTab { page.load(url) } else { store.openTab(url) }
        case let .history(visit):
            if let page, !typingNewTab { page.load(visit.url) } else { store.openTab(visit.url) }
        // This device's own copy, where new tabs go (step 5).
        case let .otherDevice(remote):
            store.openTab(remote.url)
        case let .tab(tab), let .tidied(tab):
            store.select(tab)
        case let .closed(entry):
            store.reopen(entry)
        case let .action(action):
            guard let run = actions.first(where: { $0.action.id == action.id })?.run else { return }
            run()
            // Only from +: the overview closes once a tab is brought back.
            guard typingNewTab, action.id == "reopen" else { return }
        }
        opened()
    }

    /// What can be done by name right now, in the Mac's words
    /// (`Firn/CommandBar.swift`), with no shortcuts shown. Only what would
    /// do something is offered. From the overview's + there's no page on
    /// screen, so only Reopen Closed Tab.
    private var actions: [BarAction] {
        var list: [BarAction] = []
        func add(_ id: String, _ name: String, _ keywords: [String] = [], when available: Bool = true,
                 run: @escaping @MainActor () -> Void) {
            guard available else { return }
            list.append(BarAction(action: CommandAction(id: id, name: name, keywords: keywords), run: run))
        }
        if !typingNewTab, let tab = store.activeTab, let page {
            add("reload", "Reload Page", ["refresh"], when: page.url != nil || page.loadError != nil) { page.reload() }
            add("back", "Back", ["previous", "page"], when: page.canGoBack) { page.goBack() }
            add("forward", "Forward", ["next", "page"], when: page.canGoForward) { page.goForward() }
            if let url = page.url {
                add("copy-link", "Copy Link", ["address", "url"]) { UIPasteboard.general.url = url }
                add("share", "Share…", ["send", "link"]) { ShareSheet.present(url) }
            }
            add("find", "Find on Page…", ["search page", "look for", "find"],
                when: page.url != nil && page.loadError == nil) {
                page.showFind()
            }
            if let name = blockingName {
                add("blocking", name, ["ads", "trackers", "blocker", "allow", "site"]) {
                    store.toggleBlocking(on: page)
                }
            }
            add("reader", page.isReading ? "Hide Reader" : "Show Reader",
                ["reader", "reading", "article", "text only", "book"], when: page.isArticle || page.isReading) {
                ReaderStyle.shared.toggle(page, space: space)
            }
            // Opens Reader first if it's off, then the summary at the top.
            add("summarize", "Summarize", ["summary", "article", "reader", "tl;dr", "apple intelligence"],
                when: (page.isArticle || page.isReading) && ArticleSummarizer.isOffered) {
                ReaderStyle.shared.summarize(page, space: space)
            }
            if let translator, let name = translator.actionName {
                add("translate", name, translator.searchWords) { translator.toggle() }
            }
            add("new-group", "New Group with This Tab", [], when: tab.groupID == nil && tab.place == .open) {
                _ = store.newGroup(with: tab)
            }
            if tab.place != .basecamp, tab.url != nil {
                add("add-basecamp", "Add to Basecamp", ["tile", "favorite", "keep"]) {
                    if store.canAddToBasecamp { _ = store.addToBasecamp(tab) } else { basecampFull = true }
                }
            }
            // Send to My Mac: one row per device, in the Mac's way.
            let targets = sending?.targets(for: tab) ?? []
            for target in targets {
                let name = targets.count == 1 ? SendTarget.menuTitle(for: targets) ?? "" : "Send to \(target.name)"
                add("send \(target.id)", name, ["send", "device", "iphone", "ipad", "mac", "share", "handoff"]) {
                    sending?.send(tab, to: target)
                }
            }
            add("close", "Close Tab", []) { store.close(tab) }
        }
        // The Mac's words; the space on screen isn't offered.
        for space in store.spaces where space.id != store.activeSpaceID {
            add("space-\(space.id.uuidString)", "Switch to \(space.name)", ["space", "go to"]) {
                store.selectSpace(space)
            }
        }
        if let newSpace { add("new-space", "New Space…", ["space", "create"]) { newSpace() } }
        if let showHistory {
            add("history", "History", ["visited", "past", "recent", "pages"]) { showHistory() }
        }
        if let showDownloads {
            add("downloads", "Downloads", ["files", "saved", "download"],
                when: Downloads.shared.summary(for: store.activeSpace.dataStoreID) != nil) { showDownloads() }
        }
        add("reopen", store.nextToReopen == .group ? "Reopen Closed Group" : "Reopen Closed Tab",
            ["undo", "restore", "bring back"], when: store.nextToReopen != nil) { store.reopenClosed() }
        return list
    }

    private var buttons: some View {
        HStack(spacing: Self.spacing) {
            // Reduce Motion: Back and Tabs leave while the small pill shows,
            // so each fades where it stands; kept in place, they jumped
            // beside the narrowed field as they faded (Simulator recording,
            // 2026-11-10).
            if let tab = store.activeTab, let page, !editing.wrappedValue, !(reduceMotion && compact) {
                hidesForMenu(toward: .trailing) {
                    NavigationPill(store: store, tab: tab, page: page, space: space, compact: compact)
                }
                    .transition(reduceMotion ? Self.shrinkFade : .opacity)
            }
            AddressField(store: store, editing: editing, typingNewTab: typingNewTab,
                         menuOpen: $menuOpen, typed: $typed, compact: compact,
                         grow: { shrunk = false }, opened: opened)
                // Sideways, the words fade with their pill: gone by the time
                // it's about half the gap, so the next page's come in as its
                // pill grows, with nothing popping as the tab changes.
                .opacity(activeSlide?.wordsOpacity ?? 1)
                // Sideways, the field's words stay inside its own pill as
                // it shares the gap with the next one (`BarSlide`), and
                // dissolve toward the seam rather than being cut by it (a
                // long site's name was cut mid-letter). Only the words: the
                // glass, below, keeps its crisp edge. Only while sliding:
                // otherwise nothing is clipped, as before.
                .mask {
                    if let activeSlide {
                        GeometryReader { geo in
                            let pill = activeSlide.pills(in: geo.size).held
                            activeSlide.wordsMask(width: pill.width)
                                .clipShape(Capsule())
                                .frame(width: pill.width, height: pill.height)
                                .position(x: pill.midX, y: pill.midY)
                        }
                    } else {
                        Rectangle().padding(-400)
                    }
                }
                // The glass and the menu are laid out with the field itself,
                // in the same pass, so they glide with it as Back widens or
                // narrows; measured afterwards, they trailed it (step 2c).
                .background { GeometryReader { loadingTint(fieldSize: $0.size) } }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { fieldSize = $0 }
                // The field's one glass, iOS's own (David, 2026-11-18: one
                // native glass per button, never a second taking over). On
                // the field itself, so a finger anywhere on it (the site,
                // •••, Reload) reaches it and it takes iOS's press. Growing
                // into the page menu, shrinking to the small pill, and
                // sliding sideways are this same glass changing shape
                // (`GlassFrame`).
                .firnGlassSurface(glassShape, interactive: fieldAtRest && !editing.wrappedValue)
                .overlay { GeometryReader { menuPanel(fieldSize: $0.size) } }
                // Holding anywhere on the field opens the page menu, as in
                // Safari, with a held tab's feel: it sinks from 0.15s, then
                // at 0.5s a medium tap and the menu grows out of it, rising
                // back from the sunk size as it grows (one motion). Reduce
                // Motion: no sinking; the menu fades as it does on a tap.
                .scaleEffect(fieldPressed && !reduceMotion ? pressedScale : 1)
                .animation(fieldPressed ? .easeIn(duration: HoldThenMove.menuHold - HoldThenMove.hold)
                                        : .smooth(duration: 0.2), value: fieldPressed)
                // Kept on while the hold that opened the menu is down, so
                // the finger can go on to a row.
                .modifier(FieldHold(including: canHoldForMenu || holdTracking ? .all : .subviews,
                                    changed: holdChanged, ended: holdEnded) { now in
                    held.on = now
                    pressHeld()
                })
                .sensoryFeedback(.impact(weight: .medium), trigger: holdOpenings)
                // The page coming in brings its own pill, an empty one of
                // the same frost, growing out from the other button. Outside
                // the mask, which only holds the field's own pill (inside
                // it, the coming pill never showed).
                .background {
                    if let activeSlide {
                        GeometryReader { geo in
                            let pills = activeSlide.pills(in: geo.size)
                            if let coming = pills.coming {
                                BarFrost(shape: Capsule())
                                    .frame(width: coming.width, height: coming.height)
                                    .opacity(pills.comingOpacity)
                                    .position(x: coming.midX, y: coming.midY)
                            }
                        }
                    }
                }
                // Swiped past the last tab, the field's right edge gives
                // toward the thumb. Its own slot stays the same (the tabs
                // button doesn't move); the field, its glass, and its words
                // lay out narrower inside it, so the site stays centered
                // and Reload stays inside the frost.
                .padding(.trailing, compact || menuOpen ? 0 : barGive)
                .zIndex(1)
            if !editing.wrappedValue, !(reduceMotion && compact) {
                hidesForMenu(toward: .leading) { TabsButton(space: space, action: showTabs) }
                    .transition(reduceMotion ? Self.shrinkFade : .opacity)
            }
        }
        // One glide, no bounce: Safari's move, made calm. Reduce Motion: the
        // menu fades in place instead (below).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0), value: menuOpen)
        // The same glide as the menu turns to a row's list and back.
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0), value: menuTurned)
        // Forward coming or going moves the pill and the field together, in
        // one glide. Reduce Motion: a short plain ease rather than a jump
        // (it's a small change of width, not movement across the screen).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: page?.canGoForward)
        // Shrinking and growing: the bar follows the finger a little of
        // the way, then finishes on its own, bounce-free, as Safari's on
        // iOS 27 (David, 2026-11-23; `BarGlide`). Reduce Motion: nothing
        // moves; the full bar and the small pill cross-fade in place
        // (`shrinkFade`, on each piece).
        .animation(reduceMotion ? nil : shrinkGlide, value: compact)
    }

    /// The field at its own size, nothing growing, shrinking, or sliding:
    /// only then is its glass pressed by a finger.
    private var fieldAtRest: Bool { !menuOpen && !compact && activeSlide == nil }

    /// The field's size at rest, for the page menu and a sideways slide,
    /// which start from a field that isn't changing size. The small pill
    /// never reads it: the field's width glides as it shrinks, and a
    /// measured width arrives whole, in one frame.
    @State private var fieldSize: CGSize = .zero

    /// The field's one glass, measured from the field's own edges: the
    /// field, the page menu above it, the small pill below it, or its share
    /// of the gap mid-slide.
    private func glassShape(fieldSize: CGSize) -> GlassFrame {
        if compact {
            return GlassFrame(top: Self.compactTopDrop, bottom: -Self.compactDrop, radius: Self.compactHeight / 2)
        }
        let rest = GlassFrame(radius: BarButton.glassSize / 2)
        guard fieldSize != .zero else { return rest }
        if menuOpen {
            return GlassFrame(frame: menuFrame(fieldSize: fieldSize), in: fieldSize, radius: PageMenuPanel.cornerRadius)
        }
        if let held = activeSlide?.pills(in: fieldSize).held {
            return GlassFrame(frame: held, in: fieldSize, radius: held.height / 2)
        }
        return rest
    }

    private var glassShape: GlassFrame { glassShape(fieldSize: fieldSize) }

    /// The field can be held for the page menu: at rest on a page, the full
    /// bar (a tap on the small pill grows it), and not mid-swipe.
    private var canHoldForMenu: Bool {
        !editing.wrappedValue && !menuOpen && !compact && !settling && barSlide == nil && page?.url != nil
    }

    /// Hold, and the menu opens; the same finger then slides onto a row
    /// (a highlight follows it, with a tick per row) and lets go to pick
    /// it, as on a held tab's menu (David, 2026-11-13). Let go without
    /// sliding, the menu stays open for a tap.
    private func holdChanged(_ value: FieldHold.Value) {
        guard case let .second(true, drag) = value else { return }
        if !holdTracking {
            guard canHoldForMenu, barQuiet?.on != true else { return }
            holdTracking = true
            fieldPressed = false
            holdOpenings += 1
            // Whether something is copied never asks; reading it does.
            canPaste = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
            heldMenu = true
            menuOpen = true
        }
        guard menuOpen, let drag else { return }
        let moved = hypot(drag.translation.width, drag.translation.height)
        if menuPoint != nil || moved > Self.pointSlop { menuPoint = drag.location }
    }

    private func holdEnded() {
        if holdTracking, menuOpen, let point = menuPoint {
            menuLiftPoint = point
            menuLift += 1
        }
        holdTracking = false
        menuPoint = nil
    }

    /// The sinking starts a beat into the touch, as a held tab's does, so a
    /// tap never dips the field.
    private func pressHeld() {
        guard holding else {
            fieldPressed = false
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(HoldThenMove.hold))
            if holding, canHoldForMenu { fieldPressed = true }
        }
    }

    /// A sideways swipe, while the full bar shows (the small pill and the
    /// open menu keep their own look).
    private var activeSlide: BarSlide? {
        compact || menuOpen ? nil : barSlide
    }

    static let plainShrinkGlide = Animation.spring(duration: 0.32, bounce: 0)
    /// Reduce Motion's shrink and grow: a plain fade, carried by the
    /// pieces themselves, since the bar's own change isn't animated then.
    static let shrinkFade = AnyTransition.opacity.animation(.easeOut(duration: 0.2))
    /// The small pill: shorter than the bar, and lower, nearer the home
    /// indicator, as Safari's. The bar keeps its own 48pt spot, so the page
    /// doesn't lay out again as it shrinks. Matched to Safari's from David's
    /// screenshots side by side (2026-11-11): about 33pt tall, its bottom
    /// about 14pt above the screen's edge, just over the home indicator.
    static let compactHeight: CGFloat = 33
    static let compactDrop: CGFloat = 20
    /// The site's name in the small pill, against its 16pt at rest.
    static let compactTextScale: CGFloat = 0.78
    static let compactPadding: CGFloat = 16
    /// A long site's name is cut short with "…" in a pill no wider than
    /// this, so it stays small.
    static let compactMaxWidth: CGFloat = 240
    /// How far the small pill's top sits below the full bar's, so the
    /// page's end can rest just above the pill (phase 5, step 3).
    static let compactTopDrop: CGFloat = BarButton.glassSize - compactHeight + compactDrop

    /// The menu's spot, in the field's own coordinates: from the field's
    /// left edge up, its bottom on the field's, kept inside the bar's right
    /// edge (the tabs button's).
    private func menuFrame(fieldSize: CGSize) -> CGRect {
        let width = max(fieldSize.width, PageMenuPanel.width)
        let rightEdge = fieldSize.width + Self.spacing + BarButton.glassSize
        let x = min(0, rightEdge - width)
        let height = PageMenuPanel.height(sections: menuSections, turned: menuTurned)
        return CGRect(x: x, y: fieldSize.height - height, width: width, height: height)
    }

    /// The loading frost, over the field's glass in the glass's own shape;
    /// gone while the menu is open.
    private func loadingTint(fieldSize: CGSize) -> some View {
        let glass = glassShape(fieldSize: fieldSize)
        let frame = glass.box(in: CGRect(origin: .zero, size: fieldSize))
        let shape = RoundedRectangle(cornerRadius: min(glass.radius, frame.height / 2), style: .continuous)
        return LoadingFrost(isLoading: page?.isLoading ?? false, progress: page?.progress ?? 0, space: space)
            .opacity(menuOpen ? 0 : 1)
            .clipShape(shape)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder private func menuPanel(fieldSize: CGSize) -> some View {
        if menuOpen, page?.url != nil, fieldSize != .zero {
            let frame = menuFrame(fieldSize: fieldSize)
            PageMenuPanel(sections: menuSections, turned: $menuTurned, space: space, pointer: menuPoint,
                          lift: menuLift, liftPoint: menuLiftPoint) { menuOpen = false }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                // The words come in once the glass has mostly grown, and go
                // first when it closes.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.16).delay(reduceMotion ? 0 : 0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.08))))
        }
    }

    /// Slips into the field while the page menu is open and comes back
    /// out after, keeping its place so nothing else moves: shrinking toward
    /// the field as it fades (Liquid Glass once left dark discs behind a
    /// plain fade, David's recordings, 2026-11-04; kept as the move).
    private func hidesForMenu(toward anchor: UnitPoint, @ViewBuilder _ content: () -> some View) -> some View {
        let hidden = menuOpen || settling || compact
        // Shrinking to the small pill is another move, Safari's (David's
        // recordings side by side, 2026-11-23): Back and Tabs stay beside
        // the pill and go down with it, at its smaller size, gone by about
        // halfway and back only once the bar has mostly grown. Shrunk to a
        // dot, they faded up where the bar had been while the pill dropped
        // away below them. Sideways they already keep to the field's edges
        // (the row lays out again around the narrower field).
        let riding = compact && !settling && !reduceMotion
        let scale: CGFloat = riding ? Self.compactHeight / BarButton.glassSize : hidden && !reduceMotion ? 0.01 : 1
        return content()
            // The fade goes with the bar's own move, gone by three
            // quarters of the way, so it keeps with a bar that is
            // following a slow finger.
            .opacity(menuOpen || settling ? 0 : 1)
            .modifier(FadesWithTheBar(amount: compact ? 1 : 0, gone: 0.75))
            .scaleEffect(scale, anchor: anchor)
            .offset(y: riding ? Self.compactTopDrop + (Self.compactHeight - BarButton.glassSize) / 2 : 0)
            .allowsHitTesting(!hidden)
            .hiddenFromVoiceOver(hidden)
    }

    /// How far the bar's round buttons sit from the screen's edges, at rest.
    /// Safari's spot (about 35pt on David's iPhone, from his screenshots,
    /// 2026-11-04), shared with the overview's bar so + and the check sit
    /// exactly where Back and the tabs button were. Typing gives the field
    /// the usual 16pt instead.
    static let sideInset: CGFloat = 34
    /// The gap between Back, the field, and the tabs button: Safari's 8pt
    /// (measured from David's screenshots, 2026-11-04).
    static let spacing: CGFloat = 8
}

/// Back, as one round button that widens to hold Forward once there's
/// somewhere to go forward (as Safari does). Back with nowhere to go fades
/// rather than leaving, so the field never jumps.
private struct NavigationPill: View {
    let store: BrowserStore
    let tab: FirnCore.Tab
    let page: any PageController
    let space: String
    /// Hidden in the small pill: round, so Back and Tabs balance and the
    /// pill sits centered on the screen.
    let compact: Bool
    private var wide: Bool { page.canGoForward && !compact }

    /// On a tab a link opened, with no page to go back to, Back closes it
    /// and shows the tab it came from, as in Safari.
    private var opener: FirnCore.Tab? { page.canGoBack ? nil : store.opener(of: tab) }

    private func goBack() {
        if let opener {
            store.close(tab, showing: opener)
        } else {
            page.goBack()
        }
    }

    /// Round (Back alone) or wide (Back and Forward). Forward is always
    /// there, faded out and clipped away when it can't be used: a width
    /// that glides is smooth both ways, where adding and removing the
    /// button snapped the pill narrow before the field had moved over.
    private static let padding: CGFloat = 2
    private static let roundWidth = BarButton.glassSize
    private static let wideWidth = BarButton.size * 2 + padding * 2

    var body: some View {
        HStack(spacing: 0) {
            BarButton(symbol: "chevron.backward", label: "Back", action: goBack)
                .disabled(!page.canGoBack && opener == nil)
                .accessibilityHint(opener != nil ? "Closes this tab and goes back to the one it came from" : "")
            BarButton(symbol: "chevron.forward", label: "Forward", action: page.goForward)
                .opacity(wide ? 1 : 0)
                .disabled(!wide)
                .hiddenFromVoiceOver(!wide)
        }
        .padding(.horizontal, Self.padding)
        .frame(width: wide ? Self.wideWidth : Self.roundWidth,
               height: AddressField.height, alignment: .leading)
        .clipShape(.capsule)
        // iOS's glass on the pill itself, so pressing Back or Forward
        // swells it (step 3 of "iOS's own glass buttons").
        .firnGlassSurface(Capsule(), interactive: true)
    }
}

private struct AddressField: View {
    @Environment(\.barQuiet) private var barQuiet
    /// The keyboard is still leaving (see `AddressBar.settling`).
    @Environment(\.barSettling) private var settling
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let height: CGFloat = 48
    let store: BrowserStore
    var editing: FocusState<Bool>.Binding
    let typingNewTab: Bool
    @Binding var menuOpen: Bool
    /// What's typed, passed up for the results (only while typing).
    @Binding var typed: String
    /// The small pill (phase 5): only the site, smaller, and a tap grows
    /// the bar back rather than starting to type.
    let compact: Bool
    let grow: () -> Void
    let opened: () -> Void
    @State private var text = ""
    /// The site's name at its resting size, so the small pill fits it.
    @State private var labelWidth: CGFloat = 0
    /// The room the name has in the full bar, between the page menu and
    /// Reload. Kept from the full bar only; the small pill's is its own.
    @State private var restWidth: CGFloat = 0
    /// The address editing started from, so it alone shows no results.
    @State private var startedWith = ""
    @State private var selection: TextSelection?
    /// "Reader available" is showing (see `sawArticle`).
    @State private var readerNote = false
    @State private var noteTask: Task<Void, Never>?

    private var page: (any PageController)? { store.activeTab?.page }
    /// The address the page shows: one that failed to load comes first, as
    /// on the Mac, so the bar never names the old site over Firn's error
    /// (and editing starts from the address to fix).
    /// The page's own address; while a tab woken from rest is still coming
    /// back, the address it was at (`Tab.addressWhileWaking`, never one
    /// nothing has loaded yet), so the bar names the site in the picture
    /// instead of asking for an address.
    private var frontURL: URL? { page?.loadError?.url ?? page?.url ?? store.activeTab?.addressWhileWaking }
    private var isEditing: Bool { editing.wrappedValue }

    var body: some View {
        HStack(spacing: 0) {
            // The page menu also balances the button on the right, so the
            // site sits centered.
            if !isEditing, let page, frontURL != nil, !(reduceMotion && compact) {
                pageMenuButton(page)
                    // Safari's icon sits this much further in from the
                    // field's rounded end.
                    .padding(.leading, compact ? 0 : 3.5)
                    .opacity(menuOpen || settling ? 0 : 1)
                    .animation(.easeOut(duration: 0.1), value: menuOpen)
                    .modifier(RidesThePill(compact: compact, drop: compactDrop))
                    .transition(reduceMotion ? AddressBar.shrinkFade : .opacity)
            }
            // Typing for a new tab (the overview's +, or swiping past the
            // last tab) starts with a + in the space's color, so it never
            // looks like editing the page's own address.
            if isEditing, typingNewTab {
                Image(systemName: "plus")
                    .font(BarButton.symbolFont)
                    .foregroundStyle(Theme.spaceInk(store.activeSpace.color))
                    .padding(.leading, 18)
                    // In once the field has widened into Back's place (a
                    // 0.25s glide); shown at once, it sat outside the glass
                    // until the glass got there (David, 2026-11-06).
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.15).delay(reduceMotion ? 0 : 0.2)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))))
                    .accessibilityHidden(true)
            }
            TextField("Address", text: $text, selection: $selection,
                      // A new tab says so, so it never reads as editing
                      // the page on screen (David, 2026-11-06).
                      prompt: Text(typingNewTab ? "Open a new tab" : "Search or enter address")
                          .foregroundStyle(Theme.muted))
                .font(.body)
                // At rest the site shows as a label instead (below); the
                // field itself is only seen while typing, and while it rides
                // the keyboard down, carrying the site with it.
                .opacity(isEditing || settling ? 1 : 0)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(isEditing ? .leading : .center)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused(editing)
                .padding(.leading, isEditing ? (typingNewTab ? 10 : 18) : 0)
                .opacity(menuOpen ? 0 : 1)
                .animation(.easeOut(duration: 0.1), value: menuOpen)
                .accessibilityLabel(typingNewTab ? "New Tab Address" : "Address")
                // The results card sits above the field, out of the way of
                // a VoiceOver swipe forward, so the field says it's there.
                .accessibilityHint("Results appear above as you type")
                .onSubmit(open)
                // Only typing counts: the page's own address, put in as
                // editing starts, shows no results until it's changed.
                .onChange(of: text) { if isEditing { typed = text == startedWith ? "" : text } }
                // VoiceOver's scrub cancels, as tapping the page does (the
                // dimmed page is hidden from VoiceOver).
                .accessibilityAction(.escape) { editing.wrappedValue = false }
                // At rest the field only shows the site; a tap on it starts
                // editing (below), so the finger never drops a cursor into
                // the middle of the address.
                .allowsHitTesting(isEditing)
                .hiddenFromVoiceOver(!isEditing)
                .overlay {
                    if !isEditing, !compact {
                        // Not after a hold opened the menu: the finger lifting isn't a tap.
                        Button { if barQuiet?.on != true, !menuOpen { beginEditing() } } label: { Color.clear.contentShape(.rect) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Address")
                            .accessibilityValue(spokenAddress)
                            .accessibilityHint("Edit the address or search")
                    }
                }
                // Over the edit button, taking no taps.
                .overlay {
                    if !isEditing {
                        // Reduce Motion: the full-size name and the small
                        // pill's cross-fade rather than gliding.
                        restingLabel
                            .id(reduceMotion && compact)
                            .transition(reduceMotion ? AddressBar.shrinkFade : .opacity)
                    }
                }
            if !(reduceMotion && compact) {
                trailingButton
                // Reload and Stop cross-fade rather than snap (a fade, so
                // it stays with Reduce Motion).
                .animation(.easeOut(duration: 0.15), value: page?.isLoading)
                .opacity(menuOpen || (settling && !isEditing) ? 0 : 1)
                .animation(.easeOut(duration: 0.1), value: menuOpen)
                .modifier(RidesThePill(compact: compact, drop: compactDrop))
                .transition(reduceMotion ? AddressBar.shrinkFade : .opacity)
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: compact ? compactWidth : .infinity)
        // The page menu and reload fade inside the field as it narrows or
        // widens; unclipped, they lingered outside the glass (Simulator
        // recording, 2026-11-09). Reduce Motion: no narrowing to see, and
        // clipped, they vanished rather than fading (2026-11-10).
        // It reaches down past the field's spot, where the small pill's name
        // now sits (2026-11-11: clipped at the field's bottom, only the
        // letters' tops showed).
        .clipShape(reduceMotion ? AnyShape(Rectangle().inset(by: -200))
                                : AnyShape(ReachingDown(by: AddressBar.compactDrop)))
        // The small pill: a tap anywhere on the field's 48pt spot (the
        // pill is drawn in its lower part) grows the bar back. Over the
        // whole field, not the text field: an overlay there only took taps
        // inside the text's own height (Simulator, 2026-11-09).
        .overlay {
            if compact {
                // Reaching down past the field's spot: the pill hangs below
                // it, as Safari's does (2026-11-11).
                Button { if barQuiet?.on != true { grow() } } label: {
                    Color.clear.contentShape(.rect).padding(.bottom, -AddressBar.compactDrop)
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Address")
                    .accessibilityValue(spokenAddress)
                    .accessibilityHint("Shows the address bar")
            }
        }
        // The field's glass is the bar's (`AddressBar.glassShape`), so it
        // can grow into the page menu.
        .allowsHitTesting(!menuOpen)
        .hiddenFromVoiceOver(menuOpen)
        .onChange(of: isEditing) { startOrEndEditing() }
        .onChange(of: frontURL) { showRestingAddress() }
        .onChange(of: articleSighting, sawArticle)
        .onAppear(perform: showRestingAddress)
    }

    /// The page menu's button: •••, or Reader's book while "Reader
    /// available" shows, fading back to ••• with the words (David,
    /// 2026-11-13), as Safari's; the book in the space's color, its pages
    /// washed with it, while Reader is on. It opens the page menu, where
    /// Show Reader is the first row; but while "Reader available" shows, a
    /// tap goes straight into Reader (David, 2026-11-13).
    private func pageMenuButton(_ page: any PageController) -> some View {
        let reader = showsReaderNote || page.isReading
        let color = Theme.spaceColor(store.activeSpace.color)
        // Only opens: a hold already opened it, and the finger lifting
        // over the button mustn't close it again.
        return Button {
            guard barQuiet?.on != true else { return }
            if showsReaderNote, page.isArticle {
                noteTask?.cancel()
                readerNote = false
                ReaderStyle.shared.toggle(page, space: store.activeSpace.color)
            } else {
                menuOpen = true
            }
        } label: {
            ZStack {
                if reader {
                    ReaderBookIcon(isOn: page.isReading, color: color, off: Theme.ink,
                                   size: 19, lineWidth: 1.9)
                        .transition(.opacity)
                } else {
                    Image(systemName: "ellipsis")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(Theme.ink)
                        .transition(.opacity)
                }
            }
            .frame(width: BarButton.size, height: BarButton.size)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: reader)
        .animation(.easeOut(duration: 0.2), value: page.isReading)
        .accessibilityLabel("Page Menu")
        .accessibilityValue(page.isReading ? "Reader on" : reader ? "Reader available" : "")
        .accessibilityHint(showsReaderNote ? "Opens Reader"
                           : reader ? "Reader, share, or copy this page's link" : "Share or copy this page's link")
    }

    /// The site at rest, as Safari shows it: 16pt rather than the field's
    /// 17, and a long name first draws its letters a little closer, then a
    /// touch smaller, before it's cut short. A text field can do neither,
    /// so this is a plain label over it.
    private var restingLabel: some View {
        HStack(spacing: 2) {
            Group {
                if showsReaderNote {
                    Text("Reader available").foregroundStyle(Theme.ink)
                } else if text.isEmpty {
                    Text("Search or enter address").foregroundStyle(Theme.muted)
                } else if notSecure {
                    // Plain http: an open lock before the site, in the hold
                    // menu's terracotta, which reads on the glass. The words
                    // "Not Secure" took most of the field and cut the site
                    // to "...m" (David, 2026-11-16), so they're said to
                    // VoiceOver instead (`spokenAddress`). The lock comes
                    // first, so a long name is cut short before it ever is;
                    // only whose site it is ("neverssl.com"), cut from its
                    // start if even that is too long.
                    HStack(spacing: 5) {
                        Image(systemName: "lock.open.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.menuDanger)
                            .fixedSize()
                            // Reaches into the gap beside the page menu, so it
                            // sits nearer the ••• and leaves the name more room
                            // (David, 2026-11-16).
                            .padding(.leading, -7)
                        Text(verbatim: WebAddress.shortSite(of: frontURL)).foregroundStyle(Theme.ink)
                            .truncationMode(.head)
                    }
                } else {
                    Text(verbatim: text).foregroundStyle(Theme.ink)
                }
            }
            // Medium, as Safari's: regular read thin over the glass (David,
            // 2026-11-05).
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .allowsTightening(true)
            // Only until the room is known: after that the squeeze is
            // Firn's own (`restTextScale`).
            .minimumScaleFactor(restWidth > 0 ? 1 : 0.9)
            .truncationMode(.tail)
            // Laid out at its resting size and then scaled down, so the words
            // glide smaller rather than jumping to a new font size. A name a
            // little too long for the full bar is laid out whole there too,
            // and scaled to fit: left to the text to shrink itself, it came
            // back from the small pill unshrunk, against Reload, until the
            // next move (David's recording, 2026-11-23).
            .frame(width: compact ? compactTextWidth : restTextWidth)
            // The name and "Reader available" cross-fade, never slide.
            .id(showsReaderNote)
            .transition(.opacity.animation(.easeOut(duration: 0.3)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // The room it's given whatever the name's own width (with no least
        // width, a wider name made this frame wider too).
        .frame(minWidth: 0, maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if !compact { restWidth = $0 } }
        .scaleEffect(compact ? AddressBar.compactTextScale : restTextScale)
        .offset(y: compact ? compactDrop : 0)
        .background {
            Text(verbatim: text.isEmpty ? "Search or enter address"
                           : notSecure ? "\u{2003}\u{2002}" + WebAddress.shortSite(of: frontURL) : text)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
        }
        .opacity(menuOpen || settling ? 0 : 1)
        .animation(.easeOut(duration: 0.1), value: menuOpen)
        .allowsHitTesting(false)
    }

    /// The page is on plain http, so the bar says "Not Secure" before the
    /// site, never suggesting a privacy that isn't there.
    private var notSecure: Bool {
        !text.isEmpty && WebAddress.isNotSecure(frontURL)
    }

    /// What VoiceOver hears for the address at rest.
    private var spokenAddress: String {
        notSecure ? "Not Secure, \(text)" : text
    }

    /// "Reader available" in the site's place, for a moment after a page
    /// turns out to be an article, as Safari says it; never in the small
    /// pill, and gone once Reader is on.
    private var showsReaderNote: Bool {
        readerNote && !compact && !typingNewTab && page?.isReading == false
    }

    /// The tab on screen, and whether its page reads as an article: the
    /// note shows when the same tab's page becomes one, not on a switch to
    /// a tab that already was.
    private struct ArticleSighting: Equatable {
        let tab: UUID?
        let isArticle: Bool
    }

    private var articleSighting: ArticleSighting {
        ArticleSighting(tab: store.activeTab?.id, isArticle: page?.isArticle == true)
    }

    private func sawArticle(_ old: ArticleSighting, _ new: ArticleSighting) {
        noteTask?.cancel()
        guard new.tab == old.tab, !old.isArticle, new.isArticle else {
            readerNote = false
            return
        }
        readerNote = true
        noteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            readerNote = false
        }
    }

    /// How far the small pill's middle sits below the field's.
    private var compactDrop: CGFloat {
        (Self.height - AddressBar.compactHeight) / 2 + AddressBar.compactDrop
    }

    /// The small pill's width: the site's name, scaled, with room either
    /// side.
    private var compactWidth: CGFloat {
        min(labelWidth * AddressBar.compactTextScale + AddressBar.compactPadding * 2,
            AddressBar.compactMaxWidth)
    }

    /// How much the name is scaled to fit the full bar: a touch smaller
    /// for one a little too long, as Safari's (never under 0.9; past that
    /// it's cut short). "Reader available" and a name that fits aren't.
    private var restTextScale: CGFloat {
        guard !showsReaderNote, restWidth > 0, labelWidth > restWidth else { return 1 }
        return max(restWidth / labelWidth, 0.9)
    }

    /// The name's width in the full bar before `restTextScale`; nil for
    /// one that fits, which takes the room it's given.
    private var restTextWidth: CGFloat? {
        restTextScale < 1 ? restWidth / restTextScale : nil
    }

    /// The name's width before it's scaled into the small pill.
    private var compactTextWidth: CGFloat {
        max(compactWidth - AddressBar.compactPadding * 2, 0) / AddressBar.compactTextScale
    }

    /// Stop or Reload shows in the trailing spot (not while typing).
    private var hasPageButton: Bool {
        guard !isEditing, let page else { return false }
        return page.isLoading || page.url != nil || page.loadError != nil
    }

    private var clearShown: Bool { isEditing && !text.isEmpty }

    private var trailingButton: some View {
        ZStack {
            // Clear is always part of the field, unseen until typing, so it
            // rides up with the field as the keyboard comes, fading in on the
            // way, as every other button does. Made only as typing started,
            // it was put straight at its spot ahead of the field and came in
            // from above (David's recordings, 2026-11-13).
            BarButton(symbol: "xmark.circle.fill", label: "Clear", tint: Theme.muted) { text = "" }
                // Only the fade on its own clock: an animation on the button
                // moved it on that quicker clock too, ahead of the field. A
                // hair above 0 when hidden: the rise is the keyboard's own
                // animation, which moves only what's already drawn, and at 0
                // it wasn't, so it showed straight at its spot (Simulator).
                .animation(.easeOut(duration: 0.2)) { $0.opacity(clearShown ? 1 : 0.002) }
                .allowsHitTesting(clearShown)
                .hiddenFromVoiceOver(!clearShown)
            if !isEditing, let page {
                if page.isLoading {
                    // Neither runs as the finger lifts from a hold that opened the menu.
                    BarButton(symbol: "xmark", label: "Stop") { if !menuOpen { page.stopLoading() } }
                } else if page.url != nil || page.loadError != nil {
                    // After a failed load too (a new tab's first page, say), so it
                    // can be tried again: Reload loads the address that failed.
                    BarButton(symbol: "arrow.clockwise", label: "Reload") { if !menuOpen { page.reload() } }
                }
            }
        }
        // No room taken when the spot is empty at rest (a blank new tab), as
        // before.
        .frame(width: isEditing || hasPageButton ? nil : 0)
        .clipped()
    }

    /// Typing starts from the whole address, all picked out, so it can be
    /// edited or simply typed over.
    private func beginEditing() {
        text = frontURL?.absoluteString ?? ""
        startedWith = text
        editing.wrappedValue = true
    }

    private func startOrEndEditing() {
        guard isEditing else { return showRestingAddress() }
        if typingNewTab { text = ""; startedWith = ""; return }
        // The field takes focus first, then the selection; set together,
        // UIKit puts the cursor at the end instead.
        Task { @MainActor in
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func open() {
        defer { editing.wrappedValue = false }
        guard let url = AddressInput.url(for: text, searchEngine: SearchEngine.chosen) else { return }
        InsecureFallback.remember(typed: text)
        if let page, !typingNewTab {
            page.load(url)
        } else {
            store.openTab(url)
        }
        opened()
    }

    private func showRestingAddress() {
        guard !isEditing else { return }
        selection = nil
        text = WebAddress.site(of: frontURL)
    }
}

/// The bar's own short menu, grown out of the field's glass (Firn's own,
/// not iOS's, so it's the field's one glass changing shape). Its rows come
/// in quiet sections, a thin line between them; a row with a list of its
/// own (Move to Group) turns the menu to that list, with a way back on
/// top, as Basecamp's hold menu does.
private struct PageMenuPanel: View {
    struct Entry {
        enum Icon {
            case symbol(String)
            /// Reader's book.
            case book
            /// A dot in the space's color: a group, by its name.
            case dot
        }
        let key: String
        let title: String
        /// A second, quieter line (the site, or how many downloads).
        var detail: String?
        /// What VoiceOver says, when the two lines read badly together.
        var spoken: String?
        let icon: Icon
        /// Close Tab: iOS's destructive red, as its own menus' (David, 2026-11-23).
        var closes = false
        /// A list of its own, which the menu turns to.
        var children: [Entry] = []
        var action: @MainActor () -> Void = {}
    }

    let sections: [[Entry]]
    /// The row whose list is showing, by its key (the bar keeps it, since
    /// the glass changes size with it).
    @Binding var turned: String?
    let space: String
    /// The finger that held the bar open, once it has slid (global).
    let pointer: CGPoint?
    /// Bumped as that finger lifts, at `liftPoint`: the row there runs.
    let lift: Int
    let liftPoint: CGPoint?
    let close: () -> Void
    /// VoiceOver starts on the first row.
    @AccessibilityFocusState private var focused: String?
    /// Each row's frame (global), for the sliding finger.
    @State private var frames: [String: CGRect] = [:]
    /// A finger resting on Move to Group: its list opens after a moment.
    @State private var opening: Task<Void, Never>?
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func parent(in sections: [[Entry]], turned: String?) -> Entry? {
        guard let turned else { return nil }
        return sections.joined().first { $0.key == turned && !$0.children.isEmpty }
    }

    private var parent: Entry? { Self.parent(in: sections, turned: turned) }

    private static let backKey = "back"

    /// The rows on screen: the menu's, or a list's with its way back.
    private var visible: [Entry] {
        guard let parent else { return Array(sections.joined()) }
        return [Entry(key: Self.backKey, title: parent.title, icon: .symbol("chevron.left"))] + parent.children
    }

    /// The row under a point (global), if any.
    private func key(at point: CGPoint?) -> String? {
        guard let point else { return nil }
        return visible.first { frames[$0.key]?.contains(point) == true }?.key
    }

    /// A row tapped, or let go on: a list turns the menu, the way back
    /// turns it back, and anything else closes the menu and runs.
    private func run(_ entry: Entry) {
        opening?.cancel()
        if entry.key == Self.backKey {
            turned = nil
        } else if !entry.children.isEmpty {
            turned = entry.key
        } else {
            close()
            entry.action()
        }
    }

    static let width = GrownMenu.width
    static let cornerRadius = GrownMenu.cornerRadius
    /// A list longer than this scrolls (a space with many groups).
    private static let longList = 8

    static func height(sections: [[Entry]], turned: String?) -> CGFloat {
        let insets = GrownMenu.topInset * 2
        if let parent = parent(in: sections, turned: turned) {
            return GrownMenu.rowHeight * CGFloat(min(parent.children.count, longList) + 1) + GrownMenu.lineHeight + insets
        }
        let rows = sections.joined().reduce(0) { $0 + GrownMenu.rowHeight(tall: $1.detail != nil) }
        return rows + GrownMenu.lineHeight * CGFloat(max(sections.count - 1, 0)) + insets
    }

    var body: some View {
        let lit = key(at: pointer)
        VStack(spacing: 0) {
            if let parent {
                Group {
                    row(Entry(key: Self.backKey, title: parent.title, icon: .symbol("chevron.left")), lit: lit)
                        .accessibilityLabel("Back")
                    line
                    if parent.children.count > Self.longList {
                        ScrollView { VStack(spacing: 0) { rows(parent.children, lit: lit) } }
                            .scrollIndicators(.hidden)
                    } else {
                        rows(parent.children, lit: lit)
                    }
                }
                .transition(.opacity)
            } else {
                Group {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, entries in
                        if index > 0 { line }
                        rows(entries, lit: lit)
                    }
                }
                .transition(.opacity)
            }
        }
        // The words change with a short fade as the menu turns.
        .animation(.easeOut(duration: 0.15), value: turned)
        // The highlight glides from row to row: quick, no bounce; none
        // with Reduce Motion.
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: lit)
        // A tick each time the sliding finger reaches another row.
        .sensoryFeedback(trigger: lit) { _, now in now == nil ? nil : .selection }
        // The sliding finger resting on a row with a list: it opens.
        .onChange(of: lit) { _, now in
            opening?.cancel()
            guard let now, let entry = visible.first(where: { $0.key == now }), !entry.children.isEmpty else { return }
            opening = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled, key(at: pointer) == now else { return }
                turned = now
            }
        }
        // Let go on a row: it runs, as a tap. Elsewhere, the menu stays.
        .onChange(of: lift) {
            guard let key = key(at: liftPoint), let entry = visible.first(where: { $0.key == key }) else { return }
            run(entry)
        }
        .padding(.horizontal, GrownMenu.sideInset)
        .padding(.vertical, GrownMenu.topInset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if turned != nil { turned = nil } else { close() } }
        .onAppear { focused = visible.first?.key }
        .onChange(of: turned) { focused = visible.first?.key }
        .onDisappear { opening?.cancel() }
    }

    private func rows(_ entries: [Entry], lit: String?) -> some View {
        ForEach(entries, id: \.key) { entry in
            row(entry, lit: lit)
                .accessibilityLabel(entry.spoken ?? entry.detail.map { "\(entry.title), \($0)" } ?? entry.title)
        }
    }

    private var line: some View { GrownMenuLine() }

    /// A row: its symbol, Reader's book, or a group's dot; lit while the
    /// sliding finger is on it. The way back is smaller and muted.
    private func row(_ entry: Entry, lit: String?) -> some View {
        let back = entry.key == Self.backKey
        let ink = entry.closes ? Theme.systemDestructive : back ? Theme.muted : Theme.ink
        return GrownMenuRow(title: entry.title, detail: entry.detail, ink: ink, small: back,
                            more: !entry.children.isEmpty, lit: lit == entry.key, highlight: highlight) {
            run(entry)
        } mark: {
            switch entry.icon {
            case let .symbol(name):
                Image(systemName: name).font(back ? .footnote.weight(.semibold) : BarButton.symbolFont)
            case .book:
                ReaderBookShape()
                    .stroke(style: StrokeStyle(lineWidth: 1.9, lineJoin: .round))
                    .frame(width: 19, height: 19)
            case .dot:
                Circle().fill(Theme.spaceColor(space)).frame(width: 8, height: 8)
            }
        }
        .accessibilityFocused($focused, equals: entry.key)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[entry.key] = $0 }
    }
}

/// An action the bar can run: what FirnCore matches, and what picking it does.
private struct BarAction {
    let action: CommandAction
    let run: @MainActor () -> Void
}

/// iOS's own share sheet, over whatever's on screen.
@MainActor enum ShareSheet {
    static func present(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.keyWindow, var presenter = window.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad: from the bottom of the screen, where the menu was.
        sheet.popoverPresentationController?.sourceView = window
        sheet.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 60, width: 1, height: 1)
        presenter.present(sheet, animated: true)
    }
}

/// The overview's button, at the bar's right: an iOS glass button, the
/// same size as Back's and the overview's + (step 3 of "iOS's own glass
/// buttons"), so it takes iOS's press.
private struct TabsButton: View {
    let space: String
    let action: () -> Void
    @Environment(\.barQuiet) private var barQuiet

    var body: some View {
        Button { if barQuiet?.on != true { action() } } label: {
            Image(systemName: "square.on.square")
                .font(BarButton.symbolFont)
                .foregroundStyle(Theme.ink)
                .frame(width: GlassButton.label(BarButton.glassSize), height: GlassButton.label(BarButton.glassSize))
                .contentShape(.circle)
        }
        .firnGlassButton()
        .accessibilityLabel("Tabs")
        .accessibilityHint("Shows all your tabs")
    }
}

/// A round 44pt tap target with an SF Symbol, in Firn's ink. Every symbol
/// on Firn's bars, the overview's included, takes `symbolFont`, so they all
/// read as one set (step 2c).
struct BarButton: View {
    static let size: CGFloat = 44
    /// A round glass button's whole size: the tap target and 2pt of glass
    /// around it (Back, Tabs, and the overview's + and check).
    static let glassSize: CGFloat = size + 4
    static let symbolFont = Font.system(size: 17, weight: .medium)
    let symbol: String
    let label: String
    var tint: Color = Theme.ink
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.barQuiet) private var barQuiet

    var body: some View {
        Button { if barQuiet?.on != true { action() } } label: {
            Image(systemName: symbol)
                .font(Self.symbolFont)
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.3))
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension EnvironmentValues {
    /// While the page is pulled up from the bar (and a moment after), the
    /// bar's buttons don't act (`BarQuiet`).
    @Entry var barQuiet: BarQuiet? = nil
    /// Typing just ended and the keyboard is still leaving: the field rides
    /// down with it, and its resting parts wait (see `AddressBar.settling`).
    @Entry var barSettling = false
    /// Pages sliding sideways: how far the page on screen has slid
    /// (`BarSlide`), so the two pills share the gap.
    @Entry var barSlide: BarSlide? = nil
    /// Swiping past the last tab: how far (pt) the field's right edge has
    /// pulled in toward the thumb. 0 at rest.
    @Entry var barGive: CGFloat = 0
}

/// The bar's pills during a sideways swipe, as Safari's but calm (David,
/// 2026-11-11): both stay in the gap between Back and the tabs button,
/// never under them. The page on screen's pill keeps its far edge at its
/// button while its near edge pulls in; the coming page's pill grows out
/// from the other button; a thin seam between them follows the swipe.
/// Flat frost, no swelling or melting where they meet.
struct BarSlide: Equatable {
    /// How far the page on screen has slid, in pages: positive to the
    /// right (the page before it coming in from Back's side), negative to
    /// the left. 0 at rest; only where a page is there to come in.
    var progress: CGFloat

    /// The gap between the two pills.
    static let seam: CGFloat = 6

    /// How much of the held pill's words show: none until it's past half
    /// the gap, all of them once it's nearly whole. The same curve going
    /// and coming, so a swipe let go early fades them back.
    var wordsOpacity: Double {
        let held = 1 - min(abs(progress), 1)
        let x = min(max((held - 0.55) / 0.35, 0), 1)
        return Double(x * x * (3 - 2 * x))
    }

    /// How far in from the seam the held pill's words dissolve.
    static let feather: CGFloat = 28

    /// The held pill's words: whole at its far edge, fading out over the
    /// last few points toward the seam. The fade grows in with the swipe,
    /// so nothing near the field's edge dims as it starts.
    func wordsMask(width: CGFloat) -> LinearGradient {
        let pulled = min(abs(progress) * width / Self.feather, 1)
        let f = Double(min(Self.feather * pulled / max(width, 1), 1))
        // Sliding right, the held pill is on the right, its seam on the left.
        let stops: [Gradient.Stop] = progress >= 0
            ? [.init(color: .clear, location: 0), .init(color: .black, location: f)]
            : [.init(color: .black, location: 1 - f), .init(color: .clear, location: 1)]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// Where each pill sits in the field's own space. A pill narrower than
    /// it is tall becomes a shrinking circle against its button, fading.
    func pills(in size: CGSize) -> (held: CGRect, heldOpacity: Double, coming: CGRect?, comingOpacity: Double) {
        let t = min(max(progress, -1), 1)
        let w = size.width, h = size.height
        let split = t >= 0 ? w * t : w * (1 + t)
        // The seam opens over the swipe's first few points, so the pill
        // doesn't jump narrower as it starts.
        let seam = Self.seam * min(abs(t) * w / Self.seam, 1)
        // The coming pill is on the left when the page slides right.
        let left = split - seam / 2, right = w - split - seam / 2
        let heldWidth = t >= 0 ? right : left
        let comingWidth = t >= 0 ? left : right
        func rect(_ width: CGFloat, atLeft: Bool) -> CGRect {
            // Narrower than tall, it's a circle that shrinks against its
            // button, never reaching into the other pill.
            let tall = min(h, max(width, 0))
            return CGRect(x: atLeft ? 0 : w - max(width, 0), y: (h - tall) / 2, width: max(width, 0), height: tall)
        }
        func fade(_ width: CGFloat) -> Double { Double(min(max(width / h, 0), 1)) }
        let held = rect(heldWidth, atLeft: t < 0)
        let coming = comingWidth > 0 ? rect(comingWidth, atLeft: t >= 0) : nil
        return (held, fade(heldWidth), coming, fade(comingWidth))
    }
}

/// A rectangle that reaches further down than its frame: the field's clip,
/// so the small pill's name, hanging below the field, isn't cut off.
/// The page menu and Reload as the bar shrinks into the small pill and back:
/// they stay in the field's row, so they ride its edges inward, smaller and
/// lower with the site's name, as Back and Tabs ride their own pills. Removed
/// instead, they faded where they stood while the glass slid out from under
/// them (David's recording, 2026-11-13). Shrinking, they're gone at once, in
/// about three frames, as Safari's: fading with the bar's move, they hung
/// half faded while the bar followed a slow finger (David's recordings,
/// 2026-11-23). Growing, they come back with the bar's own move, once the
/// edges have cleared the name (`FadesWithTheBar`).
private struct RidesThePill: ViewModifier {
    let compact: Bool
    let drop: CGFloat

    func body(content: Content) -> some View {
        content
            .animation(compact ? .easeOut(duration: 0.05) : nil) { $0.opacity(compact ? 0 : 1) }
            .modifier(FadesWithTheBar(amount: compact ? 1 : 0, gone: 0.4))
            .scaleEffect(compact ? AddressBar.compactTextScale : 1)
            .offset(y: compact ? drop : 0)
            .allowsHitTesting(!compact)
            .hiddenFromVoiceOver(compact)
    }
}

private struct ReachingDown: Shape {
    let by: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + by))
    }
}
