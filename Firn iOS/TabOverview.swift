import CoreImage
import FirnCore
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// The overview behind the page (phase 2, step 2: plain): one column of
/// slim rows, opening scrolled to the tab on screen, which carries a frost
/// ring. Tap a row to show it; its X or a swipe left closes it, and a shake
/// brings it back (phase 2, step 2b, part 2). The glass bar
/// at the bottom: + for a new tab, the space's name in a pill, and a check
/// to go back. Behind it all, a haze of the page you came from (step 3d). Looks from
/// docs/ios-overview-design.html. The tab on screen is a tall card with its
/// page's picture, the spot the page glides into (step 3b); the other
/// tabs' tall cards come in step 4, groups and Basecamp in phase 3.
struct TabOverview: View {
    let store: BrowserStore
    let pictures: PagePictures
    /// Where each card's picture (or slim row) is on screen, for the glide.
    let spots: OverviewSpots
    /// The tab whose card the page is gliding into or out of: hidden, so
    /// the page is the only one of it on screen.
    var gliding: UUID?
    /// The tab on screen's title line, faded in once the page has landed.
    var lineShown = true
    /// Which tab has the tall card while a picked tab grows to the full
    /// screen: still the one that was on screen, so nothing behind the
    /// glide changes size.
    var heldCard: UUID?
    /// How far the overview has arrived (0 to 1, following the page as
    /// it's pulled): its bar fades in and the dim over the cards lifts.
    var arrival: CGFloat = 1
    /// Shows a tab (the page grows out of its card or row).
    let open: (FirnCore.Tab) -> Void
    /// Back to the page, showing the tab on screen.
    let done: () -> Void
    /// A new tab: back to the page, with the address field ready to type.
    let newTab: () -> Void
    /// Typing from +: the address field takes the bar's place, so the bar
    /// steps out of its way (it would show through the field's glass).
    var typing = false

    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Counts closes, so the shake listener takes focus again after each.
    @State private var closes = 0
    /// When this space's tabs were last pinched together ("tidied"): tabs
    /// looked at before then are slim rows, and every tab looked at since
    /// becomes a card again, so there's no mode to remember (David,
    /// 2026-11-05). Pinching apart undoes it. Saved per space.
    @State private var tidiedAt: Date?
    /// How tall the tidied tabs from the last day are: 0 slim rows (tidied),
    /// 1 cards (not tidied), and anything between while a pinch glides.
    @State private var cards: CGFloat = 1
    /// Set once a pinch has switched the list, so the rest of that pinch
    /// does nothing more.
    @State private var pinchDone = false
    /// The list fades out and back in around a switch with Reduce Motion.
    @State private var listFade: Double = 1
    /// "Now" and each tab's last-viewed time, taken as the overview opens,
    /// so nothing changes size while it's open (picking a tab marks it
    /// viewed, which would grow its row into a card behind the glide).
    @State private var openedAt = Date.now
    @State private var lastViewed: [UUID: Date] = [:]
    /// When a pinch last moved: a finger lifting off a card at the end of a
    /// pinch would otherwise count as a tap and open it.
    @State private var lastPinch = Date.distantPast
    private var pinchedRecently: Bool { Date.now.timeIntervalSince(lastPinch) < 0.35 }

    /// A tab held and being dragged to a new place (phase 2, step 5).
    @State private var drag: Drag?
    /// Where the held tile's top is, under the finger: its own observed
    /// object, so following the finger redraws only the lifted tile.
    @State private var finger = DragFinger()
    /// The list's order (groups and loose tabs) while a drag moves tabs
    /// aside; saved on letting go.
    @State private var order: [UUID]?
    /// Each group's tabs, in order, while a drag moves a tab into, out
    /// of, or between groups; saved on letting go.
    @State private var members: [UUID: [UUID]]?
    /// The group being renamed (Rename from its menu).
    @State private var naming: TabGroup?
    @State private var name = ""
    @State private var lastDrop = Date.distantPast
    @State private var lifts = 0
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    /// Scrolls the list while a held tab rests near its top or bottom.
    @State private var edgeScroll: Task<Void, Never>?
    /// A pinch, a drag, or the moment after either: a finger lifting then
    /// would otherwise count as a tap.
    private var busy: Bool {
        pinchedRecently || drag != nil || Date.now.timeIntervalSince(lastDrop) < 0.35
    }

    /// Groups and loose tabs in the order shown: the store's, or the drag's
    /// while one moves.
    private var shownItems: [TabListItem] {
        let items = store.tabListItems
        guard let order else { return items }
        var byID = Dictionary(items.map { ($0.id, $0) }) { a, _ in a }
        // A grouped tab dragged out into the list.
        for tab in store.openTabs where byID[tab.id] == nil { byID[tab.id] = .tab(tab) }
        return order.compactMap { byID[$0] }
    }

    /// The tabs a group shows: all of them, or only the tab on screen while
    /// it's folded, so the page always has its card to glide into. During a
    /// drag, the drag's (a held tab may be on its way in or out).
    private func shownTabs(in group: TabGroup) -> [FirnCore.Tab] {
        if let ids = members?[group.id] {
            let byID = Dictionary(store.openTabs.map { ($0.id, $0) }) { a, _ in a }
            return ids.compactMap { byID[$0] }
        }
        let members = store.tabs(in: group)
        return group.folded ? members.filter(isOnScreen) : members
    }

    /// Every tab with a tile in the list.
    private var visibleTabs: [FirnCore.Tab] {
        let folded = Set(store.tabGroups.filter(\.folded).map(\.id))
        return store.openTabs.filter { tab in
            tab.groupID.map { !folded.contains($0) } ?? true || isOnScreen(tab)
        }
    }

    private var space: String { store.activeSpace.color }
    /// How long a tab stays a tall card after it was last looked at.
    private static let cardAge: TimeInterval = 24 * 60 * 60

    /// How tall a tab's tile is, 0 (slim row) to 1 (card): the tab on
    /// screen is always a card, tabs looked at in the last day follow the
    /// pinch, and older tabs stay rows.
    private func tallness(_ tab: FirnCore.Tab, onScreen: Bool) -> CGFloat {
        if onScreen { return 1 }
        let viewed = lastViewed[tab.id] ?? tab.lastActiveAt
        guard openedAt.timeIntervalSince(viewed) < Self.cardAge else { return 0 }
        if let tidiedAt, viewed > tidiedAt { return 1 }
        return cards
    }

    var body: some View {
        ScrollViewReader { scroller in
            // A plain stack, not a List: List's own swipe can't follow the
            // finger and slide the row away the way Safari's does.
            ScrollView {
                // 12pt apart (David, 2026-11-05: 8 felt a little tight),
                // which also gives the ring around the tab on screen room.
                LazyVStack(spacing: 12) {
                    let items = shownItems
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case let .tab(tab): listTile(tab, at: index, of: items.count)
                        case let .group(group): groupTiles(group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .opacity(listFade)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.viewport = $0 }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, now in spots.scroll = now }
            // The held tab, lifted over the list and following the finger.
            .overlay {
                if let drag {
                    if let tab = store.openTabs.first(where: { $0.id == drag.id }) {
                        LiftedTile(finger: finger, height: drag.start.height, lifted: drag.lifted) {
                            tile(tab, spot: { _ in })
                        }
                        // There or not, never faded in or out.
                        .transition(.identity)
                    } else if let group = store.tabGroups.first(where: { $0.id == drag.id }) {
                        LiftedTile(finger: finger, height: drag.start.height, lifted: drag.lifted) {
                            groupCard(group, lifted: true)
                        }
                        .transition(.identity)
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: lifts)
            // Pinch together for slim rows, apart for cards, as a photo
            // grid zooms. Once the pinch clearly goes one way, the whole
            // change runs as one glide, the tab under the fingers held in
            // place. (Following the fingers was tried, 2026-11-05: a slow
            // pinch reports in steps and every step re-lays out the list,
            // 15 to 20 frames a second on David's iPhone.)
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.02)
                    .onChanged { m in
                        lastPinch = .now
                        pinchMoved(m, scroller)
                    }
                    .onEnded { _ in
                        lastPinch = .now
                        pinchEnded()
                    }
            )
            .sensoryFeedback(.selection, trigger: tidiedAt)
            // Pinching can't be found by VoiceOver: the same choice as an action.
            .accessibilityAction(named: tidiedAt != nil ? "Show Cards" : "Show Rows") {
                setCards(tidiedAt != nil ? 1 : 0, scroller)
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // The other cards wait behind a dim that lifts as the page
            // shrinks into its card.
            .overlay {
                Theme.lookoutDim
                    .ignoresSafeArea()
                    .opacity(1 - arrival)
                    .allowsHitTesting(false)
            }
            .overlay {
                if store.openTabs.isEmpty {
                    Text("No open tabs")
                        .font(.subheadline)
                        .foregroundStyle(Theme.faint)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OverviewBar(space: store.activeSpace, newTab: newTab, done: done)
                    // In over the glide's second half, once the page's bar
                    // is gone (see BrowserScreen's bar), never both at once;
                    // a hair above 0 while gliding keeps its glass ready.
                    .opacity(typing ? 0 : max(gliding != nil ? 0.002 : 0, arrival * 2 - 1))
            }
            .onAppear {
                openedAt = .now
                lastViewed = Dictionary(store.openTabs.map { ($0.id, $0.lastActiveAt) }) { a, _ in a }
                loadTidied()
                if let id = store.activeTab?.id { scroller.scrollTo(id, anchor: .center) }
            }
        }
        .background {
            OverviewHaze(picture: store.activeTab.flatMap { pictures.image(for: $0.id) }, space: space)
        }
        .background { ShakeToUndo(undoManager: undoManager, closes: closes) }
        .alert("Rename Group",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Done") {
                if let naming { store.rename(naming, to: name) }
            }
        }
    }

    /// How far the fingers move (8% apart or together) before the pinch
    /// counts: enough to ignore a wobble, soon enough to feel immediate.
    private static let pinchStart: CGFloat = 1.08

    private func pinchMoved(_ m: MagnifyGesture.Value, _ scroller: ScrollViewProxy) {
        guard !pinchDone, drag == nil else { return }
        let target: CGFloat
        if tidiedAt != nil, m.magnification > Self.pinchStart { target = 1 }
        else if hasCardsToTidy, m.magnification < 1 / Self.pinchStart { target = 0 }
        else { return }
        pinchDone = true
        setCards(target, scroller, hold: anchor(at: m.startLocation))
    }

    private func pinchEnded() { pinchDone = false }

    /// A tall card besides the tab on screen, which pinching together
    /// would tidy into a row.
    private var hasCardsToTidy: Bool {
        store.openTabs.contains { !isOnScreen($0) && tallness($0, onScreen: false) > 0.5 }
    }

    private static let tidiedKey = "overviewTidiedAt"

    /// This space's tidy, as the overview opens. A tidy older than a day
    /// has nothing left to hold (those tabs are rows anyway), so it's
    /// forgotten.
    private func loadTidied() {
        UserDefaults.standard.removeObject(forKey: "overviewSlimRows")  // the old mode
        let saved = UserDefaults.standard.dictionary(forKey: Self.tidiedKey) as? [String: Double] ?? [:]
        let at = saved[store.activeSpace.id.uuidString].map(Date.init(timeIntervalSince1970:))
        tidiedAt = at.flatMap { openedAt.timeIntervalSince($0) < Self.cardAge ? $0 : nil }
        cards = tidiedAt == nil ? 1 : 0
        if at != nil, tidiedAt == nil { saveTidied() }
    }

    private func saveTidied() {
        var saved = UserDefaults.standard.dictionary(forKey: Self.tidiedKey) as? [String: Double] ?? [:]
        saved[store.activeSpace.id.uuidString] = tidiedAt?.timeIntervalSince1970
        UserDefaults.standard.set(saved, forKey: Self.tidiedKey)
    }

    /// The tab under a point in the list (the nearest if it's between
    /// tabs), and the anchor that keeps it where it is: the point at the
    /// same fraction of its tile and of the list's height, so scrolling to
    /// it leaves it in place now and holds it there as tiles resize.
    private func anchor(at point: CGPoint) -> (id: UUID, anchor: UnitPoint)? {
        let view = spots.viewport
        guard view.height > 0 else { return nil }
        let y = view.minY + point.y
        let shown = visibleTabs.compactMap { tab in spots.frames[tab.id].map { (tab.id, $0) } }
            .filter { $0.1.maxY > view.minY && $0.1.minY < view.maxY }
        guard let (id, frame) = shown.min(by: { distance(y, $0.1) < distance(y, $1.1) }) else { return nil }
        let top = frame.minY - view.minY
        let room = view.height - frame.height
        let fraction = room > 0 ? min(max(top / room, 0), 1) : 0.5
        return (id, UnitPoint(x: 0.5, y: fraction))
    }

    private func distance(_ y: CGFloat, _ frame: CGRect) -> CGFloat {
        y < frame.minY ? frame.minY - y : (y > frame.maxY ? y - frame.maxY : 0)
    }

    /// Pinched together (0): every tab but the one on screen becomes a slim
    /// row, until it's looked at again. Pinched apart (1): the tidy is
    /// undone and the last day's cards come back. Every row's glass glides into
    /// its card's pill (0.3s, ease-out, no bounce), the held tab staying in
    /// place, or the tab on screen held in the middle (VoiceOver's action).
    /// With Reduce Motion, the list fades out, changes, and fades back in.
    private func setCards(_ target: CGFloat, _ scroller: ScrollViewProxy,
                          hold: (id: UUID, anchor: UnitPoint)? = nil) {
        let tidy: Date? = target < 0.5 ? .now : nil
        let held = hold ?? store.activeTab.map { ($0.id, UnitPoint.center) }
        defer { saveTidied() }
        if reduceMotion {
            tidiedAt = tidy
            withAnimation(.easeOut(duration: 0.15)) { listFade = 0 } completion: {
                cards = target
                if let held { scroller.scrollTo(held.id, anchor: held.anchor) }
                withAnimation(.easeOut(duration: 0.15)) { listFade = 1 }
            }
            return
        }
        withAnimation(.easeOut(duration: 0.3)) {
            tidiedAt = tidy
            cards = target
            if let held { scroller.scrollTo(held.id, anchor: held.anchor) }
        }
    }

    private func isOnScreen(_ tab: FirnCore.Tab) -> Bool {
        tab.id == (heldCard ?? store.activeTab?.id)
    }

    /// A tab's tile: in the list, or lifted under the finger.
    private func tile(_ tab: FirnCore.Tab, spot: @escaping (CGRect) -> Void,
                      moveUp: (() -> Void)? = nil, moveDown: (() -> Void)? = nil) -> OverviewRow {
        let onScreen = isOnScreen(tab)
        return OverviewRow(
            tab: tab,
            isOnScreen: onScreen,
            tallness: tallness(tab, onScreen: onScreen),
            picture: onScreen ? pictures.image(for: tab.id) : pictures.cachedImage(for: tab.id),
            loadPicture: { await pictures.loadImage(for: tab.id) },
            ring: Theme.spaceColor(space),
            space: space,
            lineShown: !onScreen || lineShown,
            open: { if !busy { open(tab) } },
            close: { if !busy { close(tab) } },
            spot: spot,
            moveUp: moveUp,
            moveDown: moveDown
        )
    }

    /// A group: a flat tint in the space's color behind its name line and
    /// its tabs, so what's in a group and what's loose reads at a glance
    /// (David's design, 2026-11-06, after spacing alone didn't). The tabs
    /// keep their own glass and look exactly as loose ones, tall cards
    /// included, 8pt apart and 8pt in from the tint's sides and bottom.
    /// The list's 12pt sets it apart from its neighbors.
    /// Folded (and not holding the tab on screen, which keeps its card so
    /// the page has somewhere to shrink into), the group is only its name
    /// line, a slim row's height, the name and chevron gliding to its
    /// middle as the tint closes around them (David, 2026-11-06).
    private func groupTiles(_ group: TabGroup) -> some View {
        groupCard(group, lifted: false)
            // Its place stays open while it's held (inside the menu's
            // modifier, for the same reason as a tab's; see listTile).
            .modifier(EmptyWhileHeld(finger: finger, id: group.id, gliding: false))
            // Holding the name line opens the group's menu, and the whole
            // group lifts with it, tint and tabs, as one piece (David,
            // 2026-11-07: lifting only the name line slid it off its tint).
            // Holding a tab still opens that tab's own menu.
            .modifier(groupMenu(group))
            // Where the group is, so a held tab makes room around it or
            // goes in it.
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.frames[group.id] = $0 }
            .id(group.id)
            .transition(drag == nil ? .opacity : .identity)
    }

    /// A group's tint, name line, and tabs: in the list, or `lifted` under
    /// the finger (a picture only: no spots, menus, or gestures).
    private func groupCard(_ group: TabGroup, lifted: Bool) -> some View {
        let tabs = shownTabs(in: group)
        let closed = group.folded && tabs.isEmpty
        return VStack(spacing: 0) {
            GroupLine(group: group, height: closed ? GroupCard.foldedHeight : GroupCard.headerHeight,
                      naming: store.isNaming(group), toggle: { fold(group) })
                .modifier(groupMenu(group).actions)
                // Hold the name line, then move, to drag the whole group
                // to a new place, as a tab drags; holding still opens its
                // menu.
                .gesture(HoldToDrag(enabled: !lifted && gliding == nil,
                                    began: { lift(group, at: $0) }, moved: follow(to:),
                                    ended: letGo))
            // The header's own 44pt sets the room above the first tab.
            VStack(spacing: GroupCard.inset) {
                ForEach(tabs) { tab in
                    if lifted {
                        tile(tab, spot: { _ in })
                    } else {
                        listTile(tab, at: nil, of: 0)
                    }
                }
            }
        }
        .padding(.horizontal, GroupCard.inset)
        .padding(.bottom, closed ? 0 : GroupCard.inset)
        // Nothing shows below the tint while it changes size: a card
        // folding away is cut off by the tint closing over it, not left
        // fading under the row below (David's recording, 2026-11-06). Open
        // at the sides and top, and a little below, so the ring around the
        // tab on screen keeps its glow.
        .mask {
            Rectangle()
                .padding(.horizontal, -24)
                .padding(.top, -24)
                .padding(.bottom, -2)
        }
        .background(GroupCard(space: space))
    }

    /// A group's long-press menu (Rename, Ungroup, Close Group), also
    /// VoiceOver's actions.
    private func groupMenu(_ group: TabGroup) -> GroupMenu {
        GroupMenu(rename: { askForName(group) },
                  ungroup: { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.ungroup(group) } },
                  close: { close(group) })
    }

    /// Folds or unfolds a group (0.25s, no bounce; with Reduce Motion it's
    /// simply done). Folded tabs forget their spots, so nothing glides to
    /// a place that's gone.
    private func fold(_ group: TabGroup) {
        guard !busy else { return }
        let folding = !group.folded
        if folding {
            for tab in store.tabs(in: group) where !isOnScreen(tab) {
                spots.frames[tab.id] = nil
                spots.cards.remove(tab.id)
            }
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.setFolded(group, folding) }
    }

    private func askForName(_ group: TabGroup) {
        name = group.name
        naming = group
    }

    /// New Group with This Tab: the group starts where the tab is and names
    /// itself (`BrowserStore.groupNamer`), as on the Mac: no prompt.
    private func newGroup(with tab: FirnCore.Tab) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { _ = store.newGroup(with: tab) }
    }

    /// A tab's tile in the list, at `index` of `count` (nil inside a group:
    /// VoiceOver's moves for grouped tabs come with dragging, step 3).
    private func listTile(_ tab: FirnCore.Tab, at index: Int?, of count: Int) -> some View {
        let spot: (CGRect) -> Void = { frame in
            spots.frames[tab.id] = frame
            if tallness(tab, onScreen: isOnScreen(tab)) == 1 {
                spots.cards.insert(tab.id)
            } else {
                spots.cards.remove(tab.id)
            }
        }
        let up: (() -> Void)? = index.flatMap { index in index > 0 ? { move(tab, to: index - 1) } : nil }
        let down: (() -> Void)? = index.flatMap { index in index < count - 1 ? { move(tab, to: index + 1) } : nil }
        return tile(tab, spot: spot, moveUp: up, moveDown: down)
            // Its place stays open while it's held (see EmptyWhileHeld).
            // Inside the menu's modifier, not after it: holding a tab, iOS's
            // menu already shows its own picture of it in its place (the
            // preview it lifts before the menu opens), and that picture is
            // drawn from what's inside the modifier. Hidden only outside,
            // the picture lingered as a copy until the menu let it go
            // (David's recordings, 2026-11-05).
            .modifier(EmptyWhileHeld(finger: finger, id: tab.id, gliding: gliding == tab.id))
            // Hold, then move, to lift a tab and drag it to a new place, as
            // in Safari: in the list, into a group, between groups, or out.
            .gesture(HoldToDrag(enabled: gliding == nil,
                                began: { lift(tab, at: $0) }, moved: follow(to:),
                                ended: letGo))
            // Holding still opens iOS's own menu beside the tab, the tab
            // staying where it is, as in Safari. (Moving away from the open
            // menu no longer picks the tab up: that needed iOS's own drag,
            // which on David's iPhone also started with every drag of
            // Firn's, left a copy of the tab behind, and pulled the held tab
            // between two places. David's recordings and phone log,
            // 2026-11-05.)
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: OverviewRow.cornerRadius, style: .continuous))
            .contextMenu { menu(for: tab) }
            .id(tab.id)
            // A closed tab fades away; while a tab is held, nothing fades,
            // so the list moving a card can't leave a fading copy of it
            // behind (David, 2026-11-05: a copy lingered on each tab's
            // first drag).
            .transition(drag == nil ? .opacity : .identity)
    }

    /// A tab's menu: short, in the Mac's words. Basecamp's step adds Add
    /// to Basecamp.
    @ViewBuilder private func menu(for tab: FirnCore.Tab) -> some View {
        if let url = tab.url {
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.url = url }
            Divider()
        }
        if tab.groupID == nil {
            Button("New Group with This Tab", systemImage: "folder.badge.plus") { newGroup(with: tab) }
        } else {
            Button("Remove from Group", systemImage: "folder.badge.minus") {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.takeOutOfGroup(tab) }
            }
        }
        // Only this space's groups, so nothing crosses between spaces.
        let others = store.tabGroups.filter { $0.id != tab.groupID }
        if !others.isEmpty {
            Menu("Move to Group", systemImage: "folder") {
                ForEach(others) { group in
                    Button(group.name) {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.move(tab, toEndOf: group) }
                    }
                }
            }
        }
        Divider()
        Button("Close Tab", systemImage: "xmark") { close(tab) }
        if tab.groupID == nil, !store.otherLooseTabs(than: tab).isEmpty {
            Button("Close Other Tabs", systemImage: "xmark.square") { closeOthers(than: tab) }
        }
    }

    /// Close Other Tabs: the space's other loose tabs go, and a shake
    /// brings them all back.
    private func closeOthers(than tab: FirnCore.Tab) {
        let ids = store.otherLooseTabs(than: tab).map(\.id)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
            store.closeOtherLooseTabs(than: tab)
        }
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                withAnimation(.smooth(duration: 0.25)) {
                    // Last closed first, as Reopen Closed Tab does.
                    for id in ids.reversed() {
                        if let entry = store.recentlyClosed.first(where: { $0.id == id }) { store.reopen(entry) }
                    }
                }
            }
        }
        undoManager?.setActionName("Close Other Tabs")
        closes += 1
    }

    // MARK: - Dragging a tab to a new place

    /// VoiceOver's Move Up and Move Down: the same move as a drag.
    private func move(_ tab: FirnCore.Tab, to position: Int) {
        guard drag == nil else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            store.move(tab, to: position)
        }
    }

    /// The long press has held: the tab lifts out of its place.
    private func lift(_ tab: FirnCore.Tab, at point: CGPoint) {
        guard let frame = spots.frames[tab.id] else { return }
        startDrag(Drag(id: tab.id, start: frame, grab: point.y - frame.minY, group: false,
                       from: tab.groupID), at: point)
    }

    /// The name line was held, then moved: the whole group lifts.
    private func lift(_ group: TabGroup, at point: CGPoint) {
        guard let frame = spots.frames[group.id] else { return }
        startDrag(Drag(id: group.id, start: frame, grab: point.y - frame.minY, group: true,
                       from: nil), at: point)
    }

    private func startDrag(_ new: Drag, at point: CGPoint) {
        guard drag == nil, !pinchedRecently else { return }
        order = shownItems.map(\.id)
        members = Dictionary(store.tabGroups.map { ($0.id, shownTabs(in: $0).map(\.id)) }) { a, _ in a }
        finger.top = new.start.minY
        finger.left = new.start.minX
        finger.width = new.start.width
        finger.y = point.y
        drag = new
        finger.held = new.id
        lifts += 1
        keepScrollingAtEdges()
    }

    /// The tile stays under the finger, straight up and down, and the
    /// other tabs glide aside to show where it will land.
    private func follow(to point: CGPoint) {
        guard let drag, drag.lifted else { return }
        finger.top = point.y - drag.grab
        finger.y = point.y
        makeRoom()
    }

    /// Opens a place for the held tab as soon as its edge passes a
    /// neighbor's middle, as iOS's own lists do: its top for a tab above
    /// it, its bottom for a tab below. (Its middle had to pass instead, so a
    /// card had to travel a whole card's height, about 170pt, before
    /// anything moved; a shorter drag landed it back where it was, the
    /// held card covering its neighbor. David's recordings, 2026-11-05.)
    /// A held tab goes into an open group while the finger is over it, and
    /// back into the list once the finger leaves it, narrowing and widening
    /// to fit. A held group moves only in the list: groups never nest.
    /// Only tabs on screen count (the list is lazy, so others' spots may
    /// be old); the ones above the screen stay above.
    private func makeRoom() {
        guard let drag, var ids = order, var groups = members else { return }
        let top = finger.top
        let bottom = finger.top + drag.start.height
        let middle = (top + bottom) / 2
        let view = spots.viewport
        func shownFrame(_ id: UUID) -> CGRect? {
            spots.frames[id].flatMap { $0.maxY > view.minY && $0.minY < view.maxY ? $0 : nil }
        }
        // Groups a held tab may go into: open ones, and the folded one it
        // came from (where it can go back).
        let open = Set(store.tabGroups.filter { !$0.folded || $0.id == drag.from }.map(\.id))
        let now = groups.first { $0.value.contains(drag.id) }?.key
        let into: UUID? = drag.group ? nil : ids.first { id in
            open.contains(id) && (shownFrame(id).map { $0.minY <= finger.y && finger.y < $0.maxY } ?? false)
        }

        // Where among its new neighbors: `was` is its place among them if
        // it's already there, nil if it's just arriving (then its middle
        // decides). Next to a held tab, an open group is above once the
        // finger is past its middle (the finger is in it otherwise).
        func place(among others: [UUID], was: Int?) -> Int? {
            let shown = others.indices.filter { shownFrame(others[$0]) != nil }
            guard let first = shown.first else { return others.isEmpty ? 0 : nil }
            let above = shown.filter { index in
                guard let frame = shownFrame(others[index]) else { return false }
                if !drag.group, open.contains(others[index]) { return frame.midY < finger.y }
                guard let was else { return frame.midY < middle }
                return frame.midY < (index < was ? top : bottom)
            }.count
            return first + above
        }

        if let into, var others = groups[into] {
            let was = now == into ? others.firstIndex(of: drag.id) : nil
            others.removeAll { $0 == drag.id }
            guard let at = place(among: others, was: was) else { return }
            others.insert(drag.id, at: at)
            if let now, now != into { groups[now]?.removeAll { $0 == drag.id } }
            ids.removeAll { $0 == drag.id }
            groups[into] = others
        } else {
            let was = now == nil ? ids.firstIndex(of: drag.id) : nil
            var others = ids.filter { $0 != drag.id }
            guard let at = place(among: others, was: was) else { return }
            others.insert(drag.id, at: at)
            if let now { groups[now]?.removeAll { $0 == drag.id } }
            ids = others
        }
        guard ids != order || groups != members else { return }
        let lane = into != now ? lane(in: into) : nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            order = ids
            members = groups
            // Narrower in a group, the width of the list out of one.
            if let lane {
                finger.left = lane.minX
                finger.width = lane.width
            }
        }
    }

    /// Where a tab's tile sits across the list: inside a group's tint, or
    /// the list's full width.
    private func lane(in group: UUID?) -> (minX: CGFloat, width: CGFloat) {
        if let group, let frame = spots.frames[group] {
            return (frame.minX + GroupCard.inset, frame.width - 2 * GroupCard.inset)
        }
        return (spots.viewport.minX + 16, spots.viewport.width - 32)
    }

    /// Lets go: the tab (or group) is saved in its new place and the tile
    /// settles into it (0.25s, no bounce; with Reduce Motion it's simply
    /// there).
    private func letGo() {
        edgeScroll?.cancel()
        edgeScroll = nil
        guard var drag else { return }
        if let ids = order, let groups = members {
            save(drag, ids, groups)
        }
        order = nil
        members = nil
        let landing = spots.frames[drag.id] ?? drag.start
        guard !reduceMotion else {
            self.drag = nil
            finger.held = nil
            lastDrop = .now
            return
        }
        drag.lifted = false
        withAnimation(.smooth(duration: 0.25)) {
            finger.top = landing.minY
            finger.left = landing.minX
            finger.width = landing.width
            self.drag = drag
        } completion: {
            self.drag = nil
            finger.held = nil
            lastDrop = .now
        }
    }

    /// Saves where the drag left a tab or group. Places are counted as the
    /// store counts them: without the held one, and each group as one.
    private func save(_ drag: Drag, _ ids: [UUID], _ groups: [UUID: [UUID]]) {
        if drag.group {
            guard let group = store.tabGroups.first(where: { $0.id == drag.id }),
                  let to = ids.firstIndex(of: drag.id),
                  store.tabListItems.firstIndex(where: { $0.id == drag.id }) != to else { return }
            store.move(group, to: to)
            return
        }
        guard let tab = store.openTabs.first(where: { $0.id == drag.id }) else { return }
        if let into = groups.first(where: { $0.value.contains(drag.id) }),
           let group = store.tabGroups.first(where: { $0.id == into.key }),
           let at = into.value.firstIndex(of: drag.id) {
            if group.id == tab.groupID {
                // Back in a folded group: where it was (only it shows).
                guard !group.folded,
                      store.tabs(in: group).firstIndex(where: { $0.id == tab.id }) != at else { return }
                store.move(tab, to: at)
            } else {
                store.move(tab, toGroup: group, at: at)
            }
            return
        }
        // In the list. A group the tab leaves empty ends, so it doesn't count.
        let counted = ids.filter { id in
            guard let group = store.tabGroups.first(where: { $0.id == id }) else { return true }
            return store.tabs(in: group).contains { $0.id != drag.id }
        }
        guard let to = counted.firstIndex(of: drag.id) else { return }
        if tab.groupID != nil {
            store.move(tab, toGroup: nil, at: to)
        } else if store.tabListItems.firstIndex(where: { $0.id == drag.id }) != to {
            store.move(tab, to: to)
        }
    }

    /// While a tab is held, resting it near the top or bottom of the list
    /// scrolls the list that way, faster the nearer the edge. Runs only
    /// during a drag.
    private func keepScrollingAtEdges() {
        edgeScroll?.cancel()
        edgeScroll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard drag?.lifted == true, let scroll = spots.scroll else { continue }
                let view = spots.viewport
                let top = view.minY + scroll.contentInsets.top
                let bottom = view.maxY - scroll.contentInsets.bottom
                let reach: CGFloat = 72
                let speed: CGFloat  // points a frame
                if finger.y < top + reach {
                    speed = -12 * min(1, (top + reach - finger.y) / reach)
                } else if finger.y > bottom - reach {
                    speed = 12 * min(1, (finger.y - (bottom - reach)) / reach)
                } else { continue }
                let lowest = -scroll.contentInsets.top
                let highest = max(lowest, scroll.contentSize.height + scroll.contentInsets.bottom
                                  - scroll.containerSize.height)
                let y = min(max(scroll.contentOffset.y + speed, lowest), highest)
                guard abs(y - scroll.contentOffset.y) > 0.5 else { continue }
                scrollPosition.scrollTo(y: y)
                makeRoom()
            }
        }
    }

    /// Closes a tab with no question, and lets a shake bring it back:
    /// iOS's own "Undo Close Tab" alert, through the window's undo manager.
    private func close(_ tab: FirnCore.Tab) {
        let id = tab.id
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
            store.close(tab)
        }
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                // This very tab, even if something else closed since.
                guard let entry = store.recentlyClosed.first(where: { $0.id == id }) else { return }
                withAnimation(.smooth(duration: 0.25)) { store.reopen(entry) }
            }
        }
        undoManager?.setActionName("Close Tab")
        closes += 1
    }

    /// Closes a group and all its tabs; a shake brings it back whole, as
    /// ⇧⌘T does on the Mac.
    private func close(_ group: TabGroup) {
        let id = group.id
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
            store.close(group)
        }
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                guard let entry = store.recentlyClosed.first(where: { $0.id == id }) else { return }
                withAnimation(.smooth(duration: 0.25)) { store.reopen(entry) }
            }
        }
        undoManager?.setActionName("Close Group")
        closes += 1
    }
}

/// A group's header: the name lined up over its tabs' icons and the fold
/// chevron at the trailing edge, over the rows' X; no count (as on the
/// Mac). Tapping it folds or unfolds the group; holding it opens its menu.
private struct GroupLine: View {
    let group: TabGroup
    /// The header's 44pt, or a folded group's 48pt: the name and chevron
    /// stay in the middle, so they glide there as it folds.
    let height: CGFloat
    /// New, and its name is on the way from the on-device model.
    let naming: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            // The chevron sits just after the name, as on the Mac (David,
            // 2026-11-07): it belongs to the name, and the right edge is
            // left to the tabs' X. A long name shortens first, so the
            // chevron always shows.
            HStack(spacing: 6) {
                // While the on-device model names a new group, quiet dots
                // stand where the name will be, the chevron just after
                // them; then the name fades in and the chevron glides to
                // its end (a fade and a short glide; Reduce Motion: a swap).
                Group {
                    if naming {
                        NamingDots(color: Theme.ink, size: 5)
                    } else {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            // The new name swaps in while hidden, so "New
                            // Group" never fades out over it.
                            .contentTransition(.identity)
                    }
                }
                .transition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(group.folded ? -90 : 0))
                    .fixedSize()
                Spacer(minLength: 14)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: naming)
            // Over the slim rows' icons (24pt, 14pt in from the row).
            .padding(.leading, 14)
            .frame(minHeight: height)
            .contentShape(Rectangle())
        }
        // Not iOS's plain style: it dims the name and chevron as they're
        // pressed, then fades them back while the group folds, which read
        // as a flash (David's recording, 2026-11-06).
        .buttonStyle(UndimmedPress())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel(naming ? "New group, naming" : group.name)
        // The name arrived: VoiceOver hears it, as the dots fade (step 4's look over).
        .onChange(of: naming) { was, now in
            if was, !now { AccessibilityNotification.Announcement("Group named \(group.name)").post() }
        }
        .accessibilityValue(group.folded ? "Folded" : "Open")
        .accessibilityHint(group.folded ? "Shows the group's tabs" : "Folds the group")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A group's long-press menu, on the whole group so it lifts as one
/// piece; `actions` gives the same three to VoiceOver on its name line.
private struct GroupMenu: ViewModifier {
    let rename: () -> Void
    let ungroup: () -> Void
    let close: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: GroupCard.cornerRadius, style: .continuous))
            .contextMenu {
                Button("Rename", systemImage: "pencil", action: rename)
                Button("Ungroup", systemImage: "folder.badge.minus", action: ungroup)
                Divider()
                Button("Close Group", systemImage: "xmark", action: close)
            }
    }

    var actions: GroupActions { GroupActions(rename: rename, ungroup: ungroup, close: close) }
}

/// The group menu's three, as VoiceOver actions on the name line.
private struct GroupActions: ViewModifier {
    let rename: () -> Void
    let ungroup: () -> Void
    let close: () -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            Button("Rename", action: rename)
            Button("Ungroup", action: ungroup)
            Button("Close Group", action: close)
        }
    }
}

/// A button that doesn't dim while it's pressed: what it does (a group
/// folding) is the answer to the tap.
private struct UndimmedPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The card behind a group: the Mac's group frost (`FrostGlass` in
/// `Firn/Sidebar.swift`), not Liquid Glass (David, 2026-11-08). A frosted
/// fill with the space's color in it, a 1pt rim lighter at the top, a
/// hairline, and a soft shadow: an outline that differs from the haze in
/// lightness, which a space-colored edge couldn't over a haze of the same
/// color. No blur: the haze behind is already a blur of the page. Reduce
/// Transparency, the solid tile color. The tabs on it are flat.
private struct GroupCard: View {
    let space: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The rows' and cards' 14pt corners plus the 8pt inside, so the
    /// corners run evenly around the tabs.
    static let cornerRadius: CGFloat = OverviewRow.cornerRadius + inset
    /// Inside on the left, right, and bottom, and between tabs.
    static let inset: CGFloat = 8
    /// The header's height at the default text size (it grows with it).
    static let headerHeight: CGFloat = 44
    /// A folded group's height at the default text size (it grows too):
    /// a slim row's, so it reads as one line in the list.
    static let foldedHeight: CGFloat = OverviewRow.rowHeight

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let tint = Theme.spaceColor(space).opacity(Theme.groupTint)
        Group {
            if reduceTransparency {
                shape.fill(Theme.tileSolid)
                    .overlay { shape.fill(tint) }
                    .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
            } else {
                shape.fill(Theme.groupFill)
                    .overlay { shape.fill(tint) }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    }
                    .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
                    .shadow(color: Theme.shadowSoft, radius: 1, y: 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where each tab's spot (a card's picture, or a slim row) sits on screen,
/// in global points. Not observed: rows write it as they move, and only the
/// glide reads it, so scrolling redraws nothing else.
@MainActor final class OverviewSpots {
    var frames: [UUID: CGRect] = [:]
    /// The list's own frame, to find the tab under a pinch.
    var viewport: CGRect = .zero
    /// The tabs shown as tall cards (the rest are slim rows): a card's
    /// title line rides on its picture as the page grows out of it.
    var cards: Set<UUID> = []
    /// The list's scroll, for scrolling while a tab is held at an edge.
    var scroll: ScrollGeometry?
}

/// A tab or group being dragged: which, where its tile was when it
/// lifted, and where on the tile the finger holds it.
private struct Drag {
    let id: UUID
    let start: CGRect
    let grab: CGFloat
    /// A whole group, held by its name line.
    let group: Bool
    /// The group a held tab was in when it lifted.
    let from: UUID?
    /// False once let go, as the tile settles into its place.
    var lifted = true
}

/// Where the held tile is (global points): observed only by the tile.
@MainActor @Observable private final class DragFinger {
    /// The held tab, whose place in the list stays empty.
    var held: UUID?
    /// The tile's top.
    var top: CGFloat = 0
    /// The tile's left edge and width: a tab narrows inside a group.
    var left: CGFloat = 0
    var width: CGFloat = 0
    /// The finger itself.
    var y: CGFloat = 0
}

/// A tab's place in the list, empty while the tab is held (or its page
/// glides). It reads which tab is held itself: the list doesn't redraw a
/// tab's tile when only the held tab changes, so on each tab's first drag
/// its tile stayed in place, a copy beside the lifted one, until the list
/// first moved (David's recordings, 2026-11-05). At once, never faded.
private struct EmptyWhileHeld: ViewModifier {
    let finger: DragFinger
    let id: UUID
    let gliding: Bool

    func body(content: Content) -> some View {
        let empty = gliding || finger.held == id
        content
            .opacity(empty ? 0 : 1)
            .animation(nil, value: empty)
    }
}

/// The held tab, over the list: a little larger with a soft warm shadow
/// while held, settling back to its own size as it lands.
private struct LiftedTile<Content: View>: View {
    let finger: DragFinger
    let height: CGFloat
    let lifted: Bool
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        let raised = lifted && up && !reduceMotion
        GeometryReader { box in
            let origin = box.frame(in: .global).origin
            content
                .frame(width: finger.width, height: height)
                .scaleEffect(raised ? 1.03 : 1)
                .shadow(color: Theme.shadowPeek.opacity(raised ? 1 : 0), radius: 18, y: 8)
                .offset(x: finger.left - origin.x, y: finger.top - origin.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.smooth(duration: 0.2)) { up = true } }
    }
}

/// Hold, then move: lifts a tab to drag it. Holding still instead opens
/// iOS's menu (at about 0.5s), and a quick move with no hold is a scroll
/// or a swipe, so the drag starts only when the finger moves after a short
/// hold, before the menu. As in Safari, where hold-and-move drags and
/// holding still opens the menu. UIKit, because SwiftUI has no gesture
/// that waits for a hold and then needs movement.
private struct HoldToDrag: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let began: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    func makeUIGestureRecognizer(context: Context) -> HoldThenMove {
        let hold = HoldThenMove()
        hold.isEnabled = enabled
        hold.delegate = context.coordinator
        return hold
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// The row's own tap would otherwise outrank it, so it runs
        /// alongside taps (a tap ends ignored during a drag); never
        /// alongside pans.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        /// The list's scroll and a row's sideways swipe wait until it's
        /// clear this isn't a drag. That's at once for a quick move, so
        /// scrolling and swiping feel the same as before.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
    }

    func updateUIGestureRecognizer(_ hold: HoldThenMove, context: Context) {
        hold.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ hold: HoldThenMove, context: Context) {
        let point = context.converter.location(in: .global)
        switch hold.state {
        case .began:
            // Lifted from where the finger first came down, then follows it.
            began(CGPoint(x: point.x - hold.moved.x, y: point.y - hold.moved.y))
            moved(point)
        case .changed: moved(point)
        case .ended, .cancelled: ended()
        default: break
        }
    }
}

/// One finger held for `hold`, then moved `slop` points: begins. Moved
/// sooner: fails at once (a scroll or a swipe). Never moved: fails when
/// lifted, or when iOS's menu takes the touch.
final class HoldThenMove: UIGestureRecognizer {
    static let hold: TimeInterval = 0.15
    static let slop: CGFloat = 8
    private var start: CGPoint = .zero
    private var startTime: TimeInterval = 0
    /// How far the finger had moved when it began.
    private(set) var moved: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, (event.allTouches?.count ?? 1) == 1 else {
            if state == .possible { state = .failed }
            return
        }
        start = touch.location(in: nil)
        startTime = touch.timestamp
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: nil)
        switch state {
        case .possible:
            moved = CGPoint(x: point.x - start.x, y: point.y - start.y)
            guard hypot(moved.x, moved.y) >= Self.slop else { return }
            guard touch.timestamp - startTime >= Self.hold else { state = .failed; return }
            state = .began
        case .began, .changed:
            state = .changed
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }
}

/// UIKit offers "Undo Close Tab" on a shake only when something holds
/// keyboard focus, and the overview has no text field. This invisible view
/// takes that focus (giving it back to any field that wants it) and hands
/// UIKit SwiftUI's undo list. UIKit, because SwiftUI has no say in shakes.
private struct ShakeToUndo: UIViewRepresentable {
    let undoManager: UndoManager?
    let closes: Int

    func makeUIView(context: Context) -> Listener { Listener() }

    func updateUIView(_ view: Listener, context: Context) {
        view.undo = undoManager
        // Only right after a close, never on other updates: typing from +
        // keeps its keyboard.
        if closes != view.closes {
            view.closes = closes
            if view.window != nil { view.becomeFirstResponder() }
        }
    }

    final class Listener: UIView {
        weak var undo: UndoManager?
        var closes = 0
        override var canBecomeFirstResponder: Bool { true }
        override var undoManager: UndoManager? { undo }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }
    }
}

/// The overview's backdrop, as Firn's Mac window shows a haze of what's
/// behind it: the page you came from, blurred by shrinking its picture to
/// a few pixels and stretching it back up (one still image, no live blur),
/// under a wash of the frame's color, the space's tint, and the paper
/// grain. With no picture (no tab), or Reduce Transparency: the plain
/// tinted frame. Nothing redraws while idle or scrolling; the haze is
/// remade only when the tab on screen or its picture changes, and a space
/// change cross-fades the tint.
private struct OverviewHaze: View {
    let picture: UIImage?
    let space: String
    @State private var haze: UIImage?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Theme.frame
            if !reduceTransparency, let haze {
                // Filling the screen, never sizing the backdrop itself.
                Color.clear
                    .overlay {
                        Image(uiImage: haze)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
                // One level for every page, as honest as the Mac's
                // window: whatever is behind is what shows.
                Theme.overviewWash
            }
            Rectangle()
                .fill(Theme.frameTint(space))
                .animation(.easeOut(duration: 0.2), value: space)
            if !reduceTransparency {
                Image("FirstLightGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(Theme.FirstLight.grainOpacity(dark: colorScheme == .dark))
                    .blendMode(colorScheme == .dark ? .softLight : .multiply)
            }
        }
        .animation(.easeOut(duration: 0.2), value: haze)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: picture.map(ObjectIdentifier.init)) {
            guard let source = picture?.cgImage else { return haze = nil }
            let made = await Task.detached(priority: .userInitiated) { Self.blurred(source) }.value
            guard !Task.isCancelled else { return }
            haze = made.map { UIImage(cgImage: $0) }
        }
    }

    /// The picture shrunk to 6 pixels wide, halving step by step so every
    /// part of the page counts: only blobs of the page's colors are left,
    /// no lines of text (24 kept them; David, 2026-11-04). Enlarged to 128
    /// and softened once (a Gaussian about half a small pixel wide), so
    /// the seams between the small pixels melt into round blobs; SwiftUI
    /// stretches that smooth image the rest of the way. Made once, off
    /// the main thread; never a live blur.
    private nonisolated static func blurred(_ picture: CGImage) -> CGImage? {
        var image = picture
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        func resized(_ image: CGImage, width: Int) -> CGImage? {
            let height = max(Int((CGFloat(width) * aspect).rounded()), 1)
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        let tiny = 6, wide = 128
        while image.width / 2 >= tiny, let half = resized(image, width: image.width / 2) {
            image = half
        }
        guard let small = resized(image, width: tiny),
              let enlarged = resized(small, width: wide) else { return nil }
        let extent = CGRect(x: 0, y: 0, width: enlarged.width, height: enlarged.height)
        let soft = CIImage(cgImage: enlarged)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(wide / tiny) / 2)
            .cropped(to: extent)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(soft, from: extent)
    }
}

/// A slim row on glass: the site's icon and the page's title, one line, as
/// in Safari and Firn's Mac sidebar. The tab on screen stands out on solid page white with a frost
/// ring. An X closes it in one tap; a swipe left follows the finger and,
/// past a third of the row or with a flick, slides it off and closes it
/// (a short swipe glides back), as in Safari.
struct OverviewRow: View {
    let tab: FirnCore.Tab
    let isOnScreen: Bool
    /// 1 a tall card with the page's picture (the tab on screen, and tabs
    /// looked at in the last day), 0 a slim row, between while a pinch moves.
    let tallness: CGFloat
    /// The page's picture, for a tall card, if it's in memory.
    let picture: UIImage?
    /// Reads the picture from disk when a card comes into view without one.
    let loadPicture: () async -> Void
    /// The ring around the tab on screen: the space's color.
    let ring: Color
    /// The space's color name, for the card's frost.
    let space: String
    var lineShown = true
    let open: () -> Void
    let close: () -> Void
    /// Reports where the card's picture (or the slim row) is on screen.
    let spot: (CGRect) -> Void
    /// VoiceOver's way to reorder (a drag can't be found by it); nil at an end.
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the finger has pulled the row left (0 or less).
    @State private var pull: CGFloat = 0
    @State private var width: CGFloat = 0
    /// Set once the row is on its way out, so it takes no more touches.
    @State private var leaving = false

    private var site: String { WebAddress.site(of: tab.url) }
    private var t: CGFloat { min(max(tallness, 0), 1) }
    static let cornerRadius: CGFloat = 14
    private static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    /// The top of the page, a glance rather than a screenshot: a fixed
    /// 160pt on every iPhone (David, 2026-11-05; the mockup's was 148), so
    /// a 15 Pro shows four whole cards and a sliver of the fifth, and
    /// bigger phones simply show more of the list.
    static let cardHeight: CGFloat = 160

    var body: some View {
        tile
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .offset(x: pull)
            .opacity(reduceMotion && leaving ? 0 : 1)
            .gesture(SidewaysPan(changed: follow, ended: letGo))
            .allowsHitTesting(!leaving)
    }

    /// A slim row is one line on a flat fill; a tall card is the same line on its
    /// page's picture. One view for both, so a pinch glides between them:
    /// the row's fill shrinks into the card's glass pill as the tile grows
    /// around it, and the picture fades in behind. The tab on screen is ringed
    /// in the space's color just outside the card, with a soft glow of it,
    /// as the Mac's ⌃Tab switcher marks its pick, so it reads at a glance.
    private var tile: some View {
        Button(action: open) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight + (Self.cardHeight - Self.rowHeight) * t)
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .background {
            // The page fades in behind the glass as the card grows; the
            // row's glass itself is the line's (it becomes the pill).
            Theme.page
                .overlay(alignment: .top) { pictureView }
                .clipShape(Self.shape)
                .opacity(t)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: spot)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
        .accessibilityActions {
            if let moveUp { Button("Move Up", action: moveUp) }
            if let moveDown { Button("Move Down", action: moveDown) }
        }
        .overlay(alignment: .top) {
            CardTop(tab: tab, close: close, progress: t, space: space)
                .opacity(lineShown ? 1 : 0)
        }
        .overlay {
            if isOnScreen {
                Self.shape.inset(by: -3.5)
                    .strokeBorder(ring, lineWidth: 3)
                    .shadow(color: ring.opacity(0.55), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        // An older card's picture is read from disk once it's in view,
        // then fades in over the site's icon.
        // Read as soon as it starts to grow, so it can fade in mid-pinch.
        .task(id: t > 0 && picture == nil) { if t > 0 && picture == nil { await loadPicture() } }
        .animation(.easeOut(duration: 0.15), value: picture != nil)
    }

    /// A slim row's height.
    static let rowHeight: CGFloat = 48

    @ViewBuilder private var pictureView: some View {
        if let picture, picture.size.width > 0 {
            // As wide as the card, from the page's top: exactly where the
            // glide lands, so swapping one for the other shows nothing.
            GeometryReader { box in
                let scale = box.size.width / picture.size.width
                Image(uiImage: picture)
                    .resizable()
                    .frame(width: box.size.width, height: picture.size.height * scale)
            }
            .accessibilityHidden(true)
        } else {
            SiteIconView(icon: tab.icon, size: 40) { LetterMark(site: site) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 22)  // half the card's title line
                .accessibilityHidden(true)
        }
    }

    /// The row stays under the finger going left; going right it barely
    /// gives, so it's clear that way does nothing.
    private func follow(_ dx: CGFloat) {
        pull = dx < 0 ? dx : dx * 0.15
    }

    private func letGo(_ dx: CGFloat, _ speed: CGFloat) {
        let far = width > 0 && -dx > width / 3
        let flick = speed < -700 && dx < -20
        guard far || flick else {
            withAnimation(.smooth(duration: 0.25)) { pull = 0 }
            return
        }
        if reduceMotion {
            // A fade where it stands, no slide.
            withAnimation(.easeOut(duration: 0.2)) { leaving = true } completion: { close() }
            return
        }
        leaving = true
        // Off the left edge at the flick's pace, then closed.
        let gone = -(width + 40)
        let duration = min(0.25, max(0.12, Double((gone - pull) / min(speed, -900))))
        withAnimation(.easeOut(duration: duration)) { pull = gone } completion: { close() }
    }
}

/// A tile's title line, from a slim row (0) to a tall card (1). A slim row
/// and a card's pill are the same piece of glass (David, 2026-11-05): as the
/// tile grows, the row's glass shrinks into the pill in the card's top-left
/// corner, the icon and title slide with it as one piece, and the row's X
/// moves to the top-right as its round glass forms around it. On a card the
/// glass sits on a fixed veil of the frame's color and the space's tint, so
/// it reads as the rows' frost over any page (one kind of glass, not three).
/// Drawn on the card, and on the page's picture as it glides into the card
/// (there at 1, without a working X), so the two match when they swap.
struct CardTop: View {
    let tab: FirnCore.Tab
    /// Closes the tab; nil draws the X without one (on the gliding picture).
    var close: (() -> Void)?
    /// 0 a slim row, 1 a tall card, anything between while a pinch moves.
    var progress: CGFloat = 1
    /// The space's color, which tints the pill as it tints the slim rows' haze.
    var space = "glacier"

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The title's own width on one line, so the pill is only as wide as
    /// the icon and title.
    @State private var titleWidth: CGFloat = 0

    /// Rounded at the top only, as the card's corners.
    static func shape(_ radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
    }

    var body: some View {
        CardLine(tab: tab, close: close, progress: progress, space: space,
                 titleWidth: titleWidth, solid: reduceTransparency)
            .background(alignment: .topLeading) {
                Text(tab.title)
                    .font(CardLine.titleFont)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { titleWidth = $0 }
                    .accessibilityHidden(true)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// The line itself, laid out from `progress` alone so SwiftUI can glide it
/// frame by frame (it's `Animatable`): every size and spot is a mix of the
/// row's and the card's.
private struct CardLine: View, Animatable {
    let tab: FirnCore.Tab
    let close: (() -> Void)?
    var progress: CGFloat
    let space: String
    let titleWidth: CGFloat
    /// Reduce Transparency: the card's frost becomes the solid frame color.
    let solid: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// One weight for both sizes (the row's semibold), so the text can't jump.
    static let titleFont = Font.subheadline.weight(.semibold)

    // The row's measures, then the card's.
    private static let rowHeight = OverviewRow.rowHeight          // 48
    private static let glassHeight: CGFloat = 38                  // the pill and round X
    private static let inset: CGFloat = 10                        // the pill's and X's distance in
    private static let cardLineHeight: CGFloat = inset + glassHeight + 6
    private static let tapSize: CGFloat = 44
    /// A slim row's flat fill: the frame color, partly see-through, the
    /// same loose and grouped. To tune by eye.
    static let rowFill = 0.55
    /// Room on the card's right for the X and a gap before it.
    private static let xRoom: CGFloat = 66

    private var site: String { WebAddress.site(of: tab.url) }

    var body: some View {
        let t = min(max(progress, 0), 1)
        GeometryReader { box in
            let w = box.size.width
            // The glass: the whole row, then the pill.
            let pillWidth = min(max(w - Self.xRoom, 0), 8 + 22 + 7 + titleWidth + 14)
            let glassWidth = mix(w, pillWidth, t)
            let glassHeight = mix(Self.rowHeight, Self.glassHeight, t)
            let glassShape = RoundedRectangle(cornerRadius: mix(OverviewRow.cornerRadius, Self.glassHeight / 2, t),
                                              style: .continuous)
            // The line's middle: the row's, then the pill's.
            let middle = mix(Self.rowHeight / 2, Self.inset + Self.glassHeight / 2, t)
            let titleX = mix(50, Self.inset + 8 + 22 + 7, t)
            let titleRoom = max(mix(w - 96, pillWidth - 51, t), 0)
            ZStack(alignment: .topLeading) {
                ZStack {
                    // A slim row is flat (David, 2026-11-08): only group cards
                    // and a card's pills are frost. The fill gives way to the
                    // pill's glass as the tile grows. The glass is never quite
                    // 0: iOS rebuilds glass that has faded to nothing, a
                    // frozen frame mid-pinch. (Step 2 redoes this morph.)
                    glassShape.fill(solid ? Theme.frame : Theme.frame.opacity(Self.rowFill))
                        .opacity(1 - t)
                    Color.clear
                        .background { veil(t).clipShape(glassShape) }
                        .glassEffect(.regular, in: glassShape)
                        .opacity(max(t, 0.002))
                }
                .frame(width: glassWidth, height: glassHeight)
                .offset(x: mix(0, Self.inset, t), y: mix(0, Self.inset, t))
                .allowsHitTesting(false)
                SiteIconView(icon: tab.icon, size: 24) { LetterMark(site: site) }
                    .scaleEffect(mix(1, 22 / 24, t))
                    .frame(width: 24, height: 24)
                    .offset(x: mix(26, Self.inset + 8 + 11, t) - 12, y: middle - 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(Self.titleFont)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: titleRoom, height: 30, alignment: .leading)
                    .offset(x: titleX, y: middle - 15)
                    // Taps on the icon and title open the tile; only the X is its own.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                closeButton(t)
                    .offset(x: mix(w - 24, w - Self.inset - Self.glassHeight / 2, t) - Self.tapSize / 2,
                            y: middle - Self.tapSize / 2)
            }
        }
        .frame(height: mix(Self.rowHeight, Self.cardLineHeight, t), alignment: .top)
    }

    /// Under the glass on a card, so it reads as the rows' frost over the
    /// page; nothing on a row (the rows' own glass is over the haze).
    @ViewBuilder private func veil(_ t: CGFloat) -> some View {
        if solid {
            Theme.frame.opacity(t)
        } else {
            ZStack {
                Theme.cardPillVeil
                Theme.frameTint(space)
            }
            .opacity(t)
        }
    }

    /// The row's small X, moving to the card's corner as its round glass
    /// forms around it. The glass is never quite 0: iOS rebuilds glass that
    /// has faded to nothing, a frozen frame mid-pinch.
    @ViewBuilder private func closeButton(_ t: CGFloat) -> some View {
        let size = mix(28, Self.glassHeight, t)
        let circle = Circle()
        let formed = min(max((t - 0.3) / 0.7, 0), 1)
        let mark = ZStack {
            Color.clear
                .frame(width: size, height: size)
                .background { veil(1).clipShape(circle) }
                .glassEffect(.regular, in: circle)
                .opacity(max(formed, 0.002))
            ZStack {
                Image(systemName: "xmark").foregroundStyle(Theme.muted)
                Image(systemName: "xmark").foregroundStyle(Theme.ink).opacity(t)
            }
            .font(.system(size: 14, weight: .semibold))
            .scaleEffect(mix(12 / 14, 1, t))
        }
        .frame(width: Self.tapSize, height: Self.tapSize)
        .contentShape(.circle)
        if let close {
            Button(action: close) { mark }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(tab.title)")
        } else {
            mark.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// A sideways pan for a row in a scrolling list: it starts only when the
/// finger moves more across than up or down, so vertical scrolling is left
/// alone. UIKit's pan, because SwiftUI's DragGesture inside a ScrollView
/// either steals the scroll or never starts.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    /// The distance moved and the speed across, in points per second.
    let ended: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: changed(dx)
        case .ended: ended(dx, pan.velocity(in: pan.view).x)
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let speed = pan.velocity(in: pan.view)
            return abs(speed.x) > abs(speed.y)
        }
    }
}

/// A site with no icon yet: its first letter on a calm color of its own.
struct LetterMark: View {
    let site: String

    var body: some View {
        Text(site.first.map { String($0).uppercased() } ?? "")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.page)
            .frame(width: 24, height: 24)
            .background(Theme.siteColor(for: site), in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a tinted glass pill in the middle (the switcher and its dots come
/// with phase 4), and a round check on the right in a vivid version of the
/// space's color.
private struct OverviewBar: View {
    let space: Space
    let newTab: () -> Void
    let done: () -> Void

    /// Back's and the tabs button's size, so + and the check sit exactly
    /// where they were.
    private static let height = BarButton.glassSize

    var body: some View {
        ZStack {
            Text(space.name)
                .font(.headline)
                // The same ink as + : the glass is already tinted, so the
                // words carry no color of their own (David, 2026-11-04).
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(height: Self.height)
                .glassEffect(.regular.tint(Theme.frameTint(space.color)), in: .capsule)
                .padding(.horizontal, Self.height + 16)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: newTab) {
                    Image(systemName: "plus")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(Theme.ink)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.frameTint(space.color)).interactive(), in: .circle)
                .accessibilityLabel("New Tab")
                Spacer()
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(.white)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.spaceVivid(space.color)).interactive(), in: .circle)
                .accessibilityLabel("Done")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, AddressBar.sideInset)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }
}
