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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What's being typed, for the results above the field (empty at rest).
    @State private var typed = ""
    /// This space's history pages for what's typed, looked up as you type.
    @State private var history: [HistoryPage] = []
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

    private var page: (any PageController)? { store.activeTab?.page }
    private var space: String { store.activeSpace.color }
    private var engine: SearchEngine { SearchEngine.chosen }

    /// The pill, the field, and the tabs button each carry their own frost
    /// (`BarFrost`, Firn's own, not Liquid Glass; David, 2026-11-09), drawn
    /// with them, so it glides frame by frame with their words.
    var body: some View {
        let rows = editing.wrappedValue
            ? store.commandRows(for: typed, searchEngine: engine, history: history,
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
        // History is on this device, so it's read at once; each key cancels
        // the last lookup.
        .task(id: typed) {
            let found = typed.isEmpty ? [] : await store.historyPages(for: typed)
            guard !Task.isCancelled else { return }
            history = found
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

    /// Typing ended: wait for the keyboard to finish leaving (with a
    /// limit, in case iOS never says so).
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
            if let page, !typingNewTab { page.load(url) } else { store.openTab(url) }
        case let .history(visit):
            if let page, !typingNewTab { page.load(visit.url) } else { store.openTab(visit.url) }
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
            add("new-group", "New Group with This Tab", [], when: tab.groupID == nil && tab.place == .open) {
                _ = store.newGroup(with: tab)
            }
            if tab.place != .basecamp, tab.url != nil {
                add("add-basecamp", "Add to Basecamp", ["tile", "favorite", "keep"]) {
                    if store.canAddToBasecamp { _ = store.addToBasecamp(tab) } else { basecampFull = true }
                }
            }
            add("close", "Close Tab", []) { store.close(tab) }
        }
        add("reopen", store.nextToReopen == .group ? "Reopen Closed Group" : "Reopen Closed Tab",
            ["undo", "restore", "bring back"], when: store.nextToReopen != nil) { store.reopenClosed() }
        return list
    }

    private var buttons: some View {
        HStack(spacing: Self.spacing) {
            if let tab = store.activeTab, let page, !editing.wrappedValue {
                hidesForMenu(toward: .trailing) { NavigationPill(store: store, tab: tab, page: page, space: space) }
                    .transition(.opacity)
            }
            AddressField(store: store, editing: editing, typingNewTab: typingNewTab,
                         menuOpen: $menuOpen, typed: $typed, opened: opened)
                // The glass and the menu are laid out with the field itself,
                // in the same pass, so they glide with it as Back widens or
                // narrows; measured afterwards, they trailed it (step 2c).
                .background { GeometryReader { fieldGlass(fieldSize: $0.size) } }
                .overlay { GeometryReader { menuPanel(fieldSize: $0.size) } }
                .zIndex(1)
            if !editing.wrappedValue {
                hidesForMenu(toward: .leading) { TabsButton(space: space, action: showTabs) }
                    .transition(.opacity)
            }
        }
        // One glide, no bounce: Safari's move, made calm. Reduce Motion: the
        // menu fades in place instead (below).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0), value: menuOpen)
        // Forward coming or going moves the pill and the field together, in
        // one glide. Reduce Motion: a short plain ease rather than a jump
        // (it's a small change of width, not movement across the screen).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: page?.canGoForward)
    }

    /// The menu's spot, in the field's own coordinates: from the field's
    /// left edge up, its bottom on the field's, kept inside the bar's right
    /// edge (the tabs button's).
    private func menuFrame(fieldSize: CGSize) -> CGRect {
        let width = max(fieldSize.width, PageMenuPanel.width)
        let rightEdge = fieldSize.width + Self.spacing + BarButton.glassSize
        let x = min(0, rightEdge - width)
        return CGRect(x: x, y: fieldSize.height - PageMenuPanel.height, width: width, height: PageMenuPanel.height)
    }

    /// The field's frost, as one piece that becomes the menu: the same tint
    /// and the same frost as the bar, because it is the bar.
    @ViewBuilder private func fieldGlass(fieldSize: CGSize) -> some View {
        let open = menuOpen && fieldSize != .zero
        let frame = open ? menuFrame(fieldSize: fieldSize) : CGRect(origin: .zero, size: fieldSize)
        let radius = open ? PageMenuPanel.cornerRadius : AddressField.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let glass = LoadingFrost(isLoading: page?.isLoading ?? false, progress: page?.progress ?? 0, space: space)
            .opacity(open ? 0 : 1)
            .clipShape(shape)
            .background { BarFrost(shape: shape, space: space) }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        if reduceMotion {
            // Reduce Motion: no growing; the bar's glass and the menu's
            // swap with a fade.
            glass.id(open).transition(.opacity)
        } else {
            glass
        }
    }

    @ViewBuilder private func menuPanel(fieldSize: CGSize) -> some View {
        if menuOpen, let url = page?.url, fieldSize != .zero {
            let frame = menuFrame(fieldSize: fieldSize)
            PageMenuPanel(url: url) { menuOpen = false }
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
        let hidden = menuOpen || settling
        return content()
            .scaleEffect(hidden && !reduceMotion ? 0.01 : 1, anchor: anchor)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
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
                .opacity(page.canGoForward ? 1 : 0)
                .disabled(!page.canGoForward)
                .accessibilityHidden(!page.canGoForward)
        }
        .padding(.horizontal, Self.padding)
        .frame(width: page.canGoForward ? Self.wideWidth : Self.roundWidth,
               height: AddressField.height, alignment: .leading)
        .clipShape(.capsule)
        .background { BarFrost(shape: Capsule(), space: space) }
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
    let opened: () -> Void
    @State private var text = ""
    /// The address editing started from, so it alone shows no results.
    @State private var startedWith = ""
    @State private var selection: TextSelection?

    private var page: (any PageController)? { store.activeTab?.page }
    private var frontURL: URL? { page?.url }
    private var isEditing: Bool { editing.wrappedValue }

    var body: some View {
        HStack(spacing: 0) {
            // The page menu also balances the button on the right, so the
            // site sits centered.
            if !isEditing, frontURL != nil {
                BarButton(symbol: "ellipsis", label: "Page Menu") { menuOpen.toggle() }
                    .accessibilityHint("Share or copy this page's link")
                    // Safari's icon sits this much further in from the
                    // field's rounded end.
                    .padding(.leading, 3.5)
                    .opacity(menuOpen || settling ? 0 : 1)
                    .animation(.easeOut(duration: 0.1), value: menuOpen)
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
                .accessibilityHidden(!isEditing)
                .overlay {
                    if !isEditing {
                        restingLabel
                    }
                }
                .overlay {
                    if !isEditing {
                        Button { if !barQuiet { beginEditing() } } label: { Color.clear.contentShape(.rect) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Address")
                            .accessibilityValue(text)
                            .accessibilityHint("Edit the address or search")
                    }
                }
            trailingButton
                // Reload and Stop cross-fade rather than snap (a fade, so
                // it stays with Reduce Motion).
                .animation(.easeOut(duration: 0.15), value: page?.isLoading)
                .opacity(menuOpen || (settling && !isEditing) ? 0 : 1)
                .animation(.easeOut(duration: 0.1), value: menuOpen)
        }
        .frame(height: Self.height)
        // The field's glass is the bar's (`AddressBar.fieldGlass`), so it
        // can grow into the page menu.
        .allowsHitTesting(!menuOpen)
        .accessibilityHidden(menuOpen)
        .onChange(of: isEditing) { startOrEndEditing() }
        .onChange(of: frontURL) { showRestingAddress() }
        .onAppear(perform: showRestingAddress)
    }

    /// The site at rest, as Safari shows it: 16pt rather than the field's
    /// 17, and a long name first draws its letters a little closer, then a
    /// touch smaller, before it's cut short. A text field can do neither,
    /// so this is a plain label over it.
    private var restingLabel: some View {
        Group {
            if text.isEmpty {
                Text("Search or enter address").foregroundStyle(Theme.muted)
            } else {
                Text(verbatim: text).foregroundStyle(Theme.ink)
            }
        }
        // Medium, as Safari's: regular read thin over the glass (David,
        // 2026-11-05).
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .allowsTightening(true)
        .minimumScaleFactor(0.9)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .opacity(menuOpen || settling ? 0 : 1)
        .animation(.easeOut(duration: 0.1), value: menuOpen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var trailingButton: some View {
        if isEditing {
            BarButton(symbol: "xmark.circle.fill", label: "Clear", tint: Theme.faint) { text = "" }
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty)
                .accessibilityHidden(text.isEmpty)
        } else if let page, page.isLoading {
            BarButton(symbol: "xmark", label: "Stop", action: page.stopLoading)
        } else if let page, page.url != nil {
            BarButton(symbol: "arrow.clockwise", label: "Reload", action: page.reload)
        }
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

/// The page's own short menu, grown out of the field's glass (Firn's own,
/// not iOS's, so it carries the bar's tint and glass). Only what people
/// reach for; Find, Zoom, Stop Blocking, and Request Desktop Site join it
/// in phase 6.
private struct PageMenuPanel: View {
    let url: URL
    let close: () -> Void
    @AccessibilityFocusState private var firstFocused: Bool

    static let width: CGFloat = 250
    static let cornerRadius: CGFloat = 22
    private static let rowHeight: CGFloat = 48
    private static let rows = 2
    private static let inset: CGFloat = 6
    static var height: CGFloat { rowHeight * CGFloat(rows) + inset * 2 }

    var body: some View {
        VStack(spacing: 0) {
            row("Share…", symbol: "square.and.arrow.up") {
                close()
                ShareSheet.present(url)
            }
            .accessibilityFocused($firstFocused)
            row("Copy Link", symbol: "link") {
                UIPasteboard.general.url = url
                close()
            }
        }
        .padding(Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { firstFocused = true }
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(BarButton.symbolFont)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
    }
}

/// A row pressed: Firn's warm wash, in the row's rounded shape.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.press : .clear,
                        in: .rect(cornerRadius: PageMenuPanel.cornerRadius - 6, style: .continuous))
    }
}

/// An action the bar can run: what FirnCore matches, and what picking it does.
private struct BarAction {
    let action: CommandAction
    let run: @MainActor () -> Void
}

/// iOS's own share sheet, over whatever's on screen.
@MainActor private enum ShareSheet {
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

/// The overview's button, at the bar's right: round frost, the same size
/// as Back's.
private struct TabsButton: View {
    let space: String
    let action: () -> Void

    var body: some View {
        BarButton(symbol: "square.on.square", label: "Tabs", action: action)
            .padding(2)
            .background { BarFrost(shape: Circle(), space: space) }
            .accessibilityHint("Shows all your tabs")
    }
}

/// Firn's frost on the iPhone's bars, washed with the space's color, over
/// iOS's thinnest material blur, so the live page's shapes don't show
/// through. A trial (David, 2026-11-09): iOS's soft edge blur, as under
/// Safari's bar, never appeared under a web page (`docs/IOS-PLAN.md`).
/// Reduce Transparency: solid.
struct BarFrost<S: InsettableShape>: View {
    let shape: S
    let space: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        FirnFrost(shape: shape, fill: Theme.barFrost,
                  tint: Theme.spaceColor(space).opacity(Theme.groupTint),
                  solid: reduceTransparency) {
            shape.fill(.ultraThinMaterial)
        }
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
        Button { if !barQuiet { action() } } label: {
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
    /// bar's buttons don't act: the finger lifting over one isn't a tap.
    @Entry var barQuiet = false
    /// Typing just ended and the keyboard is still leaving: the field rides
    /// down with it, and its resting parts wait (see `AddressBar.settling`).
    @Entry var barSettling = false
}
