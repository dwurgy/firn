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
    /// How far a gliding Basecamp tile shows (`BasecampTiles.reveal`).
    var tileReveal: Double = 1
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
    @Environment(\.scenePhase) private var scenePhase

    /// Counts closes, so the shake listener takes focus again after each.
    @State private var closes = 0
    /// When this space's tabs were last pinched together ("tidied"): tabs
    /// looked at before then are slim rows, and every tab looked at since
    /// becomes a card again, so there's no mode to remember (David,
    /// 2026-11-05). Pinching apart undoes it. Saved per space.
    @State private var tidiedAt: Date?
    /// Counts pinches between cards and rows, for their tap.
    @State private var tidyChanges = 0
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
    /// Firn's hold menu, open for the held (lifted) tab (step 3c).
    @State private var heldMenu: OpenHoldMenu?
    @State private var picks = 0
    /// Pulled away from an open menu into a drag: a light tap.
    @State private var pulls = 0
    /// The held finger slid toward the open menu: it points at its rows
    /// until it lifts, and drags nothing.
    @State private var pointing = false
    @State private var pointer = MenuPointer()
    /// Where the held tile's top is, under the finger: its own observed
    /// object, so following the finger redraws only the lifted tile.
    @State private var finger = DragFinger()
    /// The list's order (groups and loose tabs) while a drag moves tabs
    /// aside; saved on letting go.
    @State private var order: [UUID]?
    /// Each group's tabs, in order, while a drag moves a tab into, out
    /// of, or between groups; saved on letting go.
    @State private var members: [UUID: [UUID]]?
    /// Basecamp's tiles in order while one is dragged; saved on letting go.
    @State private var tileOrder: [UUID]?
    /// A held tab resting over a loose tab, and the wait before their
    /// group starts forming around it (hold to form).
    @State private var hoverID: UUID?
    @State private var hoverWait: Task<Void, Never>?
    /// The group a held tab and the loose tab under it would make, shown
    /// while held; saved only on letting go there.
    @State private var forming: Forming?
    @State private var forms = 0
    /// Add to Basecamp was picked with 12 tiles already there.
    @State private var basecampFull = false
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
        pinchedRecently || drag != nil || finishing || Date.now.timeIntervalSince(lastDrop) < 0.35
    }
    /// Done was tapped and the tab on screen's group is opening first.
    @State private var finishing = false

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

    /// The tabs a group shows: all of them, or none while it's folded. The
    /// tab on screen's group opens with the overview, and again just before
    /// the page grows back (`finish`), so the page always has its card.
    /// During a drag, the drag's (a held tab may be on its way in or out).
    private func shownTabs(in group: TabGroup) -> [FirnCore.Tab] {
        if let ids = members?[group.id] {
            let byID = Dictionary(store.openTabs.map { ($0.id, $0) }) { a, _ in a }
            return ids.compactMap { byID[$0] }
        }
        return group.folded ? [] : store.tabs(in: group)
    }

    /// Every tab with a tile in the list.
    private var visibleTabs: [FirnCore.Tab] {
        let folded = Set(store.tabGroups.filter(\.folded).map(\.id))
        return store.openTabs.filter { tab in tab.groupID.map { !folded.contains($0) } ?? true }
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
                    // Basecamp first, scrolling away with the list (hidden
                    // while empty); 12pt below it, as between any items.
                    BasecampTiles(store: store, spots: spots, gliding: gliding,
                                  onScreen: heldCard ?? store.activeTab?.id,
                                  reveal: tileReveal, order: tileOrder,
                                  held: drag?.tile == true ? drag?.id : nil,
                                  pressed: finger.pressed,
                                  open: { tab in if !busy { open(tab) } },
                                  menu: { tileMenu(for: $0) },
                                  move: { tab, to in
                                      withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                                          store.move(tab, to: to)
                                      }
                                  })
                    let items = shownItems
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case let .tab(tab): listTile(tab, at: index, of: items.count, loose: true)
                        case let .group(group): groupTiles(group, at: index, of: items.count)
                        }
                    }
                }
                .padding(.horizontal, 16)
                // Hold, then move, to lift a tab and drag it to a new place,
                // as in Safari: in the list, into a group, between groups,
                // or out; or hold a group's name line to move the whole
                // group. One gesture on the list, not one per tile: a tab
                // moving into or out of a group is rebuilt in its new place,
                // and a gesture on its tile went with the old one, ending
                // the drag under a finger still down (David's recording,
                // 2026-11-08).
                .gesture(HoldToDrag(enabled: gliding == nil,
                                    canBegin: { liftable(at: $0) != nil },
                                    began: lift(at:), moved: follow(to:),
                                    ended: { letGo(cancelled: $0) },
                                    wantsMenu: { menuTarget(at: $0) != nil },
                                    pressing: { point in
                                        finger.pressed = reduceMotion ? nil : point.flatMap { menuTarget(at: $0)?.id }
                                    },
                                    menu: openMenu(at:),
                                    menuEnded: { cancelled in if cancelled { closeMenu() } },
                                    leaveMenu: leaveMenu(to:from:)))
                .opacity(listFade)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.viewport = $0 }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, now in spots.scroll = now }
            .sensoryFeedback(.impact(weight: .medium), trigger: lifts)
            .sensoryFeedback(.impact(weight: .light), trigger: forms)
            .sensoryFeedback(.impact(weight: .light), trigger: picks)
            .sensoryFeedback(.impact(weight: .light), trigger: pulls)
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
            // Only a pinch (or its VoiceOver action) taps: on tidiedAt, it
            // tapped every time a tidied overview opened, as it read the
            // setting back (David, 2026-11-09: no haptic on the swipe up).
            .sensoryFeedback(.selection, trigger: tidyChanges)
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
                OverviewBar(space: store.activeSpace, newTab: newTab, done: finish)
                    // In over the glide's second half, once the page's bar
                    // is gone (see BrowserScreen's bar), never both at once;
                    // a hair above 0 while gliding keeps its glass ready.
                    .modifier(ArrivalBand(arrival: typing ? 0 : arrival, range: 0.55...1, fadesIn: true,
                                          floor: !typing && gliding != nil ? 0.002 : 0))
            }
            .onAppear {
                openedAt = .now
                lastViewed = Dictionary(store.openTabs.map { ($0.id, $0.lastActiveAt) }) { a, _ in a }
                loadTidied()
                if let id = store.activeTab?.id { scroller.scrollTo(id, anchor: .center) }
            }
        }
        // Over everything, bar included: an open menu's dim (a tap on it
        // closes the menu), the held tab lifted over the list and following
        // the finger, and the menu beside it.
        .overlay {
            ZStack(alignment: .topLeading) {
                if heldMenu != nil {
                    Theme.holdDim
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                liftedTile
                HoldMenuPlacement(menu: heldMenu, space: space, pointer: pointer,
                                  pick: pick(_:), dismiss: { closeMenu() })
            }
        }
        .background {
            OverviewHaze(tab: store.activeTab?.id,
                         picture: store.activeTab.flatMap { pictures.image(for: $0.id) }, space: space)
        }
        .background { ShakeToUndo(undoManager: undoManager, closes: closes) }
        .basecampFullAlert(isPresented: $basecampFull)
        // Firn leaving the screen closes an open hold menu, as iOS's do;
        // its frost is a picture of the screen as it opened.
        .onChange(of: scenePhase) { _, now in if now != .active { closeMenu() } }
        .alert("Rename Group",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Done") {
                if let naming { store.rename(naming, to: name) }
            }
        }
    }

    /// The held tab, lifted over the list and following the finger.
    @ViewBuilder private var liftedTile: some View {
        ZStack {
            if let drag {
                if drag.tile, let tab = store.basecampTabs.first(where: { $0.id == drag.id }) {
                    LiftedTile(finger: finger, height: drag.start.height, lifted: drag.lifted) {
                        BasecampTiles.lifted(tab, space: space,
                                             onScreen: tab.id == (heldCard ?? store.activeTab?.id),
                                             solid: drag.lifted)
                    }
                    .transition(.identity)
                } else if let tab = store.openTabs.first(where: { $0.id == drag.id }) {
                    LiftedTile(finger: finger, height: drag.start.height, lifted: drag.lifted,
                               steady: tallness(tab, onScreen: isOnScreen(tab)) < 0.5) {
                        tile(tab, spot: { _ in })
                    }
                    // There or not, never faded in or out.
                    .transition(.identity)
                } else if let group = store.tabGroups.first(where: { $0.id == drag.id }) {
                    LiftedTile(finger: finger, height: drag.start.height, lifted: drag.lifted,
                               steady: true, cornerRadius: GroupCard.cornerRadius) {
                        groupCard(group, lifted: true)
                    }
                    .transition(.identity)
                }
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
    /// undone and the last day's cards come back. Every row's fill glides into
    /// its card's pill (0.3s, ease-out, no bounce), the held tab staying in
    /// place, or the tab on screen held in the middle (VoiceOver's action).
    /// With Reduce Motion, the list fades out, changes, and fades back in.
    private func setCards(_ target: CGFloat, _ scroller: ScrollViewProxy,
                          hold: (id: UUID, anchor: UnitPoint)? = nil) {
        let tidy: Date? = target < 0.5 ? .now : nil
        let held = hold ?? store.activeTab.map { ($0.id, UnitPoint.center) }
        defer { saveTidied() }
        if (tidy == nil) != (tidiedAt == nil) { tidyChanges += 1 }
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
            moveDown: moveDown,
            groupName: tab.groupID.flatMap { id in store.tabGroups.first(where: { $0.id == id })?.name }
        )
    }

    /// A group: a flat tint in the space's color behind its name line and
    /// its tabs, so what's in a group and what's loose reads at a glance
    /// (David's design, 2026-11-06, after spacing alone didn't). The tabs
    /// keep their own glass and look exactly as loose ones, tall cards
    /// included, 8pt apart and 8pt in from the tint's sides and bottom.
    /// The list's 12pt sets it apart from its neighbors.
    /// Folded, the group is only its name line, a slim row's height, the
    /// name and chevron gliding to its middle as the card closes around
    /// them (David, 2026-11-06).
    private func groupTiles(_ group: TabGroup, at index: Int, of count: Int) -> some View {
        // VoiceOver's Move Up and Move Down, on the name line: the group's
        // place in the list, as a drag of its name line.
        groupCard(group, lifted: false, moves: GroupMoves(
            up: index > 0 ? { move(group, to: index - 1) } : nil,
            down: index < count - 1 ? { move(group, to: index + 1) } : nil))
            // Its place stays open while it's held or its menu is open.
            // Holding the name line opens the group's menu, and the whole
            // group lifts with it, tint and tabs, as one piece (David,
            // 2026-11-07: lifting only the name line slid it off its tint);
            // see `menuTarget`. Holding a tab opens that tab's own menu.
            .modifier(EmptyWhileHeld(finger: finger, id: group.id, gliding: false))
            // Where the group is, so a held tab makes room around it or
            // goes in it.
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.frames[group.id] = $0 }
            .id(group.id)
            .transition(drag == nil ? .opacity : .identity)
    }

    /// A group's tint, name line, and tabs: in the list, or `lifted` under
    /// the finger (a picture only: no spots, menus, or gestures).
    private func groupCard(_ group: TabGroup, lifted: Bool, moves: GroupMoves = GroupMoves()) -> some View {
        let tabs = shownTabs(in: group)
        let closed = group.folded && tabs.isEmpty
        // Grouped tabs move within their group, and only while it shows
        // them all: folded, the one tab showing would skip past hidden ones.
        let movable = !lifted && tabs.count == store.tabs(in: group).count
        return VStack(spacing: 0) {
            GroupLine(group: group, height: closed ? GroupCard.foldedHeight : GroupCard.headerHeight,
                      naming: store.isNaming(group), toggle: { fold(group) })
                // Hold the name line, then move, to drag the whole group
                // to a new place, as a tab drags (the list's HoldToDrag);
                // holding still opens its menu.
                .modifier(groupMenu(group).actions)
                .modifier(GroupMoveActions(moves: moves))
            // The header's own 44pt sets the room above the first tab.
            VStack(spacing: GroupCard.inset) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    if lifted {
                        tile(tab, spot: { _ in })
                    } else {
                        listTile(tab, at: movable ? index : nil, of: tabs.count, loose: false)
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
        .background {
            GroupCard(space: space)
                // The card around the tab on screen gathers as the page
                // shrinks into its card, fully there as it lands. Fading in
                // only after it landed lagged (David, 2026-11-08: "could be
                // a little snappier").
                .modifier(ArrivalFade(arrival: !lifted && !lineShown && tabs.contains(where: isOnScreen)
                                      ? arrival : 1))
                // A new space's color cross-fades in, as the Mac's tint.
                .animation(.easeInOut(duration: 0.4), value: space)
        }
    }

    /// A group's long-press menu (Rename, Ungroup, Close Group), also
    /// VoiceOver's actions.
    private func groupMenu(_ group: TabGroup) -> GroupMenu {
        GroupMenu(rename: { askForName(group) },
                  ungroup: { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.ungroup(group) } },
                  close: { close(group) })
    }

    /// Folds or unfolds a group: the card glides to its new size (0.25s, no
    /// bounce) and its tabs fade over the second half (`FoldFade`); with
    /// Reduce Motion the size changes at once and the tabs cross-fade.
    /// Folded tabs forget their spots, so nothing glides to a place that's
    /// gone; folding the tab on screen's group is fine, since `finish`
    /// opens it again before the page grows back.
    private func fold(_ group: TabGroup) {
        guard !busy else { return }
        let folding = !group.folded
        if folding {
            for tab in store.tabs(in: group) {
                spots.frames[tab.id] = nil
                spots.cards.remove(tab.id)
            }
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.setFolded(group, folding) }
    }

    /// Done: back to the tab on screen. If its group was folded here, it
    /// opens again first (the same glide as tapping it), and the page grows
    /// out of its card once the card is there, so the page always has a
    /// card to come from.
    private func finish() {
        guard !finishing else { return }
        guard let id = store.activeTab?.groupID,
              let group = store.tabGroups.first(where: { $0.id == id }), group.folded
        else { return done() }
        finishing = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.setFolded(group, false) }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 250))
            finishing = false
            done()
        }
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

    /// A tab's tile in the list or in its group (not `loose`), at `index`
    /// of `count` there, for VoiceOver's Move Up and Move Down (nil: none).
    private func listTile(_ tab: FirnCore.Tab, at index: Int?, of count: Int, loose: Bool) -> some View {
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
            // Its place stays open while it's held or its menu is open
            // (see EmptyWhileHeld).
            .modifier(EmptyWhileHeld(finger: finger, id: tab.id, gliding: gliding == tab.id))
            // Hold, then move, lifts it (the list's HoldToDrag). Holding
            // still opens Firn's own menu beside the tab (`openMenu`);
            // moving away from it drags the tab on.
            // A held tab resting on this loose one: the group they'd make
            // forms around it (hold to form). Always here, at rest only
            // zero-height spacers, so the tile never changes identity and
            // glides into its place in the card.
            .modifier(FormingCard(forming: loose && forming?.other == tab.id ? forming : nil,
                                  gap: drag?.start.height ?? 0, space: space))
            .id(tab.id)
            // A closed tab fades away; while a tab is held, nothing fades,
            // so the list moving a card can't leave a fading copy of it
            // behind (David, 2026-11-05: a copy lingered on each tab's
            // first drag).
            .transition(drag != nil ? .identity : loose ? .opacity : foldFade)
    }

    /// A grouped tab coming and going as its group unfolds and folds. In:
    /// once the card has opened half its room (the glide's second half), so
    /// it fades into space rather than over its neighbors. Out: over the
    /// first half, gone before the closing card reaches it. Reduce Motion:
    /// a plain 0.15s cross-fade, the size changing at once.
    private var foldFade: AnyTransition {
        if reduceMotion { return .opacity.animation(.easeOut(duration: 0.15)) }
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.125).delay(0.125)),
                           removal: .opacity.animation(.easeOut(duration: 0.125)))
    }

    /// A tab's menu: short, in the Mac's words.
    private func menu(for tab: FirnCore.Tab) -> [[HoldMenuItem]] {
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        var link: [HoldMenuItem] = []
        var keep: [HoldMenuItem] = []
        if let url = tab.url {
            link.append(HoldMenuItem(title: "Copy Link", systemImage: "link") { UIPasteboard.general.url = url })
            keep.append(HoldMenuItem(title: "Add to Basecamp", systemImage: "mountain.2") { addToBasecamp(tab) })
        }
        if tab.groupID == nil {
            keep.append(HoldMenuItem(title: "New Group with This Tab", systemImage: "folder.badge.plus") {
                newGroup(with: tab)
            })
        } else {
            keep.append(HoldMenuItem(title: "Remove from Group", systemImage: "folder.badge.minus") {
                withAnimation(glide) { store.takeOutOfGroup(tab) }
            })
        }
        // Only this space's groups, so nothing crosses between spaces.
        let others = store.tabGroups.filter { $0.id != tab.groupID }
        if !others.isEmpty {
            keep.append(HoldMenuItem(title: "Move to Group", systemImage: "folder", children: others.map { group in
                HoldMenuItem(title: group.name, systemImage: nil) {
                    withAnimation(glide) { store.move(tab, toEndOf: group) }
                }
            }))
        }
        var close = [HoldMenuItem(title: "Close Tab", systemImage: "xmark", closes: true) { self.close(tab) }]
        if tab.groupID == nil, !store.otherLooseTabs(than: tab).isEmpty {
            close.append(HoldMenuItem(title: "Close Other Tabs", systemImage: "xmark.square", closes: true) {
                closeOthers(than: tab)
            })
        }
        // No line under Copy Link, so a pointing finger's highlight glides
        // through every row down to the Close rows (David, 2026-11-09).
        return [link + keep, close]
    }

    /// A Basecamp tile's menu: the Mac's, less what the iPhone has no
    /// place for (split view, sound). Close becomes Remove from Basecamp,
    /// plainer words for the same thing. Firn's own menu (`openMenu`).
    private func tileMenu(for tab: FirnCore.Tab) -> [[HoldMenuItem]] {
        var first: [HoldMenuItem] = []
        if tab.isAwayFromHome {
            first.append(HoldMenuItem(title: "Go Back to Home", systemImage: "house") {
                store.goHome(tab)
                if !busy { open(tab) }
            })
        }
        if let url = tab.url {
            first.append(HoldMenuItem(title: "Copy Link", systemImage: "link") { UIPasteboard.general.url = url })
        }
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        return [first, [
            // Not removed: it stays, as an everyday tab where new tabs go.
            HoldMenuItem(title: "Move to Tabs", systemImage: "arrow.down.to.line") {
                withAnimation(glide) { store.removeFromBasecamp(tab) }
            },
            HoldMenuItem(title: "Remove from Basecamp", systemImage: "xmark", closes: true) { removeTile(tab) },
        ]]
    }

    /// Remove from Basecamp: the tile goes altogether, and a shake brings it
    /// back to its place among the tiles (as ⇧⌘T does on the Mac).
    private func removeTile(_ tab: FirnCore.Tab) {
        let id = tab.id
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
            store.closeTile(tab)
        }
        // Reopened with a shake: no glide with Reduce Motion, as everywhere else here.
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                guard let entry = store.recentlyClosed.first(where: { $0.id == id }) else { return }
                withAnimation(glide) { store.reopen(entry) }
            }
        }
        undoManager?.setActionName("Remove from Basecamp")
        closes += 1
    }

    /// Add to Basecamp: the tab leaves the list (and its group) and becomes
    /// the last tile, its address its home. A 13th says Basecamp is full.
    private func addToBasecamp(_ tab: FirnCore.Tab) {
        guard store.canAddToBasecamp else {
            basecampFull = true
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { _ = store.addToBasecamp(tab) }
    }

    /// Close Other Tabs: the space's other loose tabs go, and a shake
    /// brings them all back.
    private func closeOthers(than tab: FirnCore.Tab) {
        let ids = store.otherLooseTabs(than: tab).map(\.id)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
            store.closeOtherLooseTabs(than: tab)
        }
        // Reopened with a shake: no glide with Reduce Motion, as everywhere else here.
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                withAnimation(glide) {
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

    /// VoiceOver's Move Up and Move Down for a group: the same move as
    /// dragging its name line.
    private func move(_ group: TabGroup, to position: Int) {
        guard drag == nil else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            store.move(group, to: position)
        }
    }

    /// What a hold at a point (global) would lift: a tab's tile, or a
    /// group's name line. Only tiles on screen count.
    private func liftable(at point: CGPoint) -> Liftable? {
        guard spots.viewport.contains(point) else { return nil }
        if let tile = store.basecampTabs.first(where: { spots.frames[$0.id]?.contains(point) == true }) {
            return .tile(tile)
        }
        if let tab = visibleTabs.first(where: { spots.frames[$0.id]?.contains(point) == true }) {
            return .tab(tab)
        }
        for group in store.tabGroups {
            guard let frame = spots.frames[group.id], frame.contains(point) else { continue }
            let closed = group.folded && shownTabs(in: group).isEmpty
            let line = closed ? GroupCard.foldedHeight : GroupCard.headerHeight
            return point.y < frame.minY + line ? .group(group) : nil
        }
        return nil
    }

    // MARK: - Firn's hold menu

    /// What a still hold at a point (global) opens Firn's menu for: a tab,
    /// a group's name line, or a Basecamp tile.
    private func menuTarget(at point: CGPoint) -> Liftable? {
        guard heldMenu == nil, drag == nil, gliding == nil, !pinchedRecently else { return nil }
        return liftable(at: point)
    }

    /// Held still: the tab, group, or tile lifts where it is, on its solid
    /// base, the rest dims, and its menu forms beside it. The list holds
    /// still while it's open (the dim takes every touch).
    private func openMenu(at point: CGPoint) {
        guard let target = menuTarget(at: point), var frame = spots.frames[target.id] else { return }
        let sunk = finger.pressed == target.id
        // A tab reports its place as it is sunk (its spot is measured inside
        // `EmptyWhileHeld`): back to its real size, or the lifted tile shrank
        // twice for a couple of frames (Simulator recording, 2026-11-09).
        // A group's and a tile's places are measured outside the sink.
        if sunk, case .tab = target {
            let grow = 1 / pressedScale - 1
            frame = frame.insetBy(dx: -frame.width * grow / 2, dy: -frame.height * grow / 2)
        }
        // Before anything changes: the screen as it is, for the frost.
        let backdrop = ScreenPicture.take()
        let sections: [[HoldMenuItem]]
        // What the menu opens beside: the tile, or a group's name line.
        var anchor = frame
        let grab = point.y - frame.minY
        switch target {
        case let .tab(tab):
            sections = menu(for: tab)
            startDrag(Drag(id: tab.id, start: frame, grab: grab, group: false, from: tab.groupID), at: point)
        case let .group(group):
            sections = groupMenu(group).sections
            anchor.size.height = group.folded && shownTabs(in: group).isEmpty
                ? GroupCard.foldedHeight : GroupCard.headerHeight
            startDrag(Drag(id: group.id, start: frame, grab: grab, group: true, from: nil), at: point)
        case let .tile(tile):
            sections = tileMenu(for: tile)
            startDrag(Drag(id: tile.id, start: frame, grab: grab, group: false, from: nil,
                           grabX: point.x - frame.minX, tile: true), at: point)
        }
        guard drag?.id == target.id else { return }
        finger.pressed = nil
        if sunk { finger.liftFrom = pressedScale }
        // A held tab near the list's edge doesn't scroll it.
        edgeScroll?.cancel()
        edgeScroll = nil
        finger.solid = true
        let isGroup = if case .group = target { true } else { false }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.2)) {
            heldMenu = OpenHoldMenu(id: target.id, tile: anchor, fingerX: point.x,
                                    sections: sections, backdrop: backdrop, prefersAbove: isGroup)
        }
    }

    /// The finger, still down from the hold, has moved: toward the menu
    /// (mostly up or down, toward the side it opened on) it points at the
    /// rows, as in iOS's menus; away or sideways, the tab drags. Decided
    /// once per touch.
    private func leaveMenu(to point: CGPoint, from start: CGPoint) {
        guard let menu = heldMenu else { return }
        let dx = point.x - start.x, dy = point.y - start.y
        if let card = pointer.card, abs(dy) > abs(dx),
           card.midY > menu.tile.midY ? dy > 0 : dy < 0 {
            pointing = true
            pointer.point = point
            return
        }
        dragOffMenu(to: point)
    }

    /// The finger lifted (or iOS took it) while pointing: the row under it
    /// runs, or, off the rows, the menu simply stays open.
    private func stopPointing(cancelled: Bool) {
        pointing = false
        if cancelled {
            pointer.point = nil
            return closeMenu()
        }
        pointer.releasePoint = pointer.point
        pointer.point = nil
        pointer.release += 1
    }

    /// The finger, still down from the hold, moved away from the open menu: the
    /// menu thaws and the tab already lifted for it becomes the drag, so
    /// there's only ever one tile. Held where the finger has it now, so it
    /// doesn't jump the few points the finger moved; its solid base fades
    /// and the list scrolls at its edges again, as in any drag.
    private func dragOffMenu(to point: CGPoint) {
        guard heldMenu != nil, var drag, drag.lifted, drag.id == heldMenu?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) { heldMenu = nil }
        pointer.card = nil
        pulls += 1
        drag.grab = point.y - finger.top
        drag.grabX = point.x - finger.left
        self.drag = drag
        finger.solid = false
        keepScrollingAtEdges()
        follow(to: point)
    }

    /// A row was tapped: the menu thaws, the tab settles into its place,
    /// and then the choice runs, so a move or a close starts from the tab
    /// where it is in the list.
    private func pick(_ item: HoldMenuItem) {
        guard heldMenu != nil else { return }
        picks += 1
        closeMenu(then: item.action)
    }

    /// The menu thaws (0.15s) and the lifted tab settles back into its
    /// place (0.25s, no bounce; at once with Reduce Motion).
    private func closeMenu(then action: (@MainActor () -> Void)? = nil) {
        guard heldMenu != nil else { return }
        withAnimation(.easeOut(duration: 0.15)) { heldMenu = nil }
        pointing = false
        pointer.point = nil
        pointer.card = nil
        order = nil
        members = nil
        tileOrder = nil
        lastDrop = .now
        guard var drag else { action?(); return }
        let landing = spots.frames[drag.id] ?? drag.start
        guard !reduceMotion else {
            finger.solid = false
            self.drag = nil
            finger.held = nil
            action?()
            return
        }
        drag.lifted = false
        withAnimation(.smooth(duration: 0.25)) {
            finger.solid = false
            finger.top = landing.minY
            finger.left = landing.minX
            finger.width = landing.width
            self.drag = drag
        } completion: {
            self.drag = nil
            finger.held = nil
            lastDrop = .now
            action?()
        }
    }

    /// The hold has begun: the tab or group under the finger lifts.
    private func lift(at point: CGPoint) {
        switch liftable(at: point) {
        case let .tab(tab): lift(tab, at: point)
        case let .group(group): lift(group, at: point)
        case let .tile(tile): lift(tile: tile, at: point)
        case nil: break
        }
    }

    /// The long press has held: the tab lifts out of its place.
    private func lift(_ tab: FirnCore.Tab, at point: CGPoint) {
        guard let frame = spots.frames[tab.id] else { return }
        startDrag(Drag(id: tab.id, start: frame, grab: point.y - frame.minY, group: false,
                       from: tab.groupID), at: point)
    }

    /// A Basecamp tile was held, then moved: it lifts and follows the
    /// finger both ways, within Basecamp.
    private func lift(tile: FirnCore.Tab, at point: CGPoint) {
        guard let frame = spots.frames[tile.id] else { return }
        startDrag(Drag(id: tile.id, start: frame, grab: point.y - frame.minY, group: false,
                       from: nil, grabX: point.x - frame.minX, tile: true), at: point)
    }

    /// The name line was held, then moved: the whole group lifts.
    private func lift(_ group: TabGroup, at point: CGPoint) {
        guard let frame = spots.frames[group.id] else { return }
        startDrag(Drag(id: group.id, start: frame, grab: point.y - frame.minY, group: true,
                       from: nil), at: point)
    }

    private func startDrag(_ new: Drag, at point: CGPoint) {
        guard drag == nil, !pinchedRecently else { return }
        if new.tile {
            tileOrder = store.basecampTabs.map(\.id)
        } else {
            order = shownItems.map(\.id)
            members = Dictionary(store.tabGroups.map { ($0.id, shownTabs(in: $0).map(\.id)) }) { a, _ in a }
        }
        finger.top = new.start.minY
        finger.left = new.start.minX
        finger.width = new.start.width
        finger.y = point.y
        finger.liftFrom = 1
        drag = new
        finger.held = new.id
        lifts += 1
        keepScrollingAtEdges()
    }

    /// Where a tab let go on a forming group settles: its gap in the card.
    private func formingLanding(_ drag: Drag, _ forming: Forming) -> CGRect {
        guard let frame = spots.frames[forming.other] else { return drag.start }
        let lane = lane(in: nil)
        let y = forming.above ? frame.minY - GroupCard.inset - drag.start.height
                              : frame.maxY + GroupCard.inset
        return CGRect(x: lane.minX + GroupCard.inset, y: y,
                      width: lane.width - 2 * GroupCard.inset, height: drag.start.height)
    }

    /// The store makes the forming group, where its card already is.
    private func makeFormed(_ drag: Drag, _ forming: Forming) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            if let tab = store.openTabs.first(where: { $0.id == drag.id }),
               let other = store.openTabs.first(where: { $0.id == forming.other }),
               let group = store.newGroup(with: other) {
                store.move(tab, into: group, at: forming.above ? 0 : 1)
            }
            self.forming = nil
            order = nil
            members = nil
            self.drag = nil
            finger.held = nil
        }
        lastDrop = .now
    }

    /// The tile stays under the finger, straight up and down, and the
    /// other tabs glide aside to show where it will land.
    private func follow(to point: CGPoint) {
        if pointing { pointer.point = point; return }
        guard let drag, drag.lifted else { return }
        finger.top = point.y - drag.grab
        finger.y = point.y
        if drag.tile {
            // Kept inside the list's sides, so it never slides off screen.
            let view = spots.viewport
            finger.left = min(max(point.x - drag.grabX, view.minX), view.maxX - drag.start.width)
            return makeRoomForTile()
        }
        makeRoom()
    }

    /// The other tiles glide aside (0.25s, no bounce; at once with Reduce
    /// Motion) to show where the held tile will land: the spot whose middle
    /// is nearest the tile's middle. Spots are the grid's own, which never
    /// move while one tile is held (the count stays the same, so the rows
    /// stay balanced), so it never flickers between two. Held below or
    /// beside the grid, it lands in the nearest spot; never in the tabs.
    private func makeRoomForTile() {
        guard let drag, var ids = tileOrder, let from = ids.firstIndex(of: drag.id) else { return }
        let middle = CGPoint(x: finger.left + drag.start.width / 2, y: finger.top + drag.start.height / 2)
        var nearest = from
        var best = CGFloat.infinity
        for (index, id) in ids.enumerated() {
            guard let frame = spots.frames[id] else { continue }
            let distance = hypot(frame.midX - middle.x, frame.midY - middle.y)
            if distance < best { best = distance; nearest = index }
        }
        guard nearest != from else { return }
        ids.remove(at: from)
        ids.insert(drag.id, at: nearest)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { tileOrder = ids }
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
        if forming != nil, holdForming() { return }
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

        // Loose tabs a held tab could rest on to make a group with.
        let loose: Set<UUID> = drag.group ? [] : Set(ids.filter { id in
            id != drag.id && store.openTabs.contains { $0.id == id && $0.groupID == nil }
        })
        // The held tile's edge that leads toward `index` among `others`
        // (`was` is its own place there, nil if arriving: then its middle).
        func edge(toward index: Int, was: Int?) -> CGFloat {
            guard let was else { return middle }
            return index < was ? top : bottom
        }

        // Where among its new neighbors: `was` is its place among them if
        // it's already there, nil if it's just arriving (then its middle
        // decides). Next to a held tab, an open group is above once the
        // finger is past its middle (the finger is in it otherwise). Past
        // a loose tab, its edge has to pass three quarters of it, not half,
        // leaving its middle half to rest on and make a group (David,
        // 2026-11-08).
        func place(among others: [UUID], was: Int?) -> Int? {
            let shown = others.indices.filter { shownFrame(others[$0]) != nil }
            guard let first = shown.first else { return others.isEmpty ? 0 : nil }
            let above = shown.filter { index in
                guard let frame = shownFrame(others[index]) else { return false }
                if !drag.group, open.contains(others[index]) { return frame.midY < finger.y }
                guard let was else { return frame.midY < middle }
                let rest = loose.contains(others[index]) ? frame.height / 4 : 0
                return index < was ? frame.midY - rest < top : frame.midY + rest < bottom
            }.count
            return first + above
        }

        // Resting on a loose tab's middle half: the list holds still, and
        // after a moment their group starts forming (`form`).
        func restingOn(_ others: [UUID], was: Int?) -> UUID? {
            others.indices.first { index in
                guard loose.contains(others[index]), let frame = shownFrame(others[index]) else { return false }
                let at = edge(toward: index, was: was)
                return at > frame.minY + frame.height / 4 && at < frame.maxY - frame.height / 4
            }.map { others[$0] }
        }

        if into == nil {
            let others = ids.filter { $0 != drag.id }
            let resting = restingOn(others, was: now == nil ? ids.firstIndex(of: drag.id) : nil)
            waitToForm(over: resting)
            if resting != nil { return }
        } else {
            waitToForm(over: nil)
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
        }
        // Narrower in a group, the width of the list out of one.
        if let lane { resize(to: lane.minX, lane.width) }
    }

    /// Where a tab's tile sits across the list: inside a group's tint, or
    /// the list's full width.
    private func lane(in group: UUID?) -> (minX: CGFloat, width: CGFloat) {
        if let group, let frame = spots.frames[group] {
            return (frame.minX + GroupCard.inset, frame.width - 2 * GroupCard.inset)
        }
        return (spots.viewport.minX + 16, spots.viewport.width - 32)
    }

    // MARK: Hold to form

    /// The held tab rests on a loose tab (or no longer does): after about
    /// 0.5s still there, their group starts forming, as on the Mac.
    private func waitToForm(over id: UUID?) {
        guard id != hoverID else { return }
        hoverWait?.cancel()
        hoverID = id
        finger.solid = id != nil
        guard let id else { return }
        hoverWait = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled, hoverID == id, drag?.lifted == true else { return }
            form(around: id)
        }
    }

    /// The group the two would make forms around the loose tab: the held
    /// tab's place in the list moves into the card, as a gap beside it on
    /// the side it came from. Nothing is saved until it's let go there.
    private func form(around id: UUID) {
        guard let drag, var ids = order, let held = ids.firstIndex(of: drag.id),
              let other = ids.firstIndex(of: id) else { return }
        ids.remove(at: held)
        hoverID = nil
        // Still solid on the card: moving within it passes over the other
        // tab, which showed through (David's recording, 2026-11-08).
        finger.solid = true
        let lane = lane(in: nil)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            order = ids
            forming = Forming(other: id, group: store.previewGroup(), above: held < other)
        }
        resize(to: lane.minX + GroupCard.inset, lane.width - 2 * GroupCard.inset)
        forms += 1
    }

    /// While a group is forming, it holds as long as the finger is on its
    /// card, so the tabs moving under the finger don't undo it; the gap
    /// follows the finger past the other tab's middle. Off the card, it
    /// thaws back. True while it holds.
    private func holdForming() -> Bool {
        guard let forming, let frame = spots.frames[forming.other], let drag else { return false }
        let gap = drag.start.height + GroupCard.inset
        let cardTop = frame.minY - (forming.above ? gap : 0) - GroupCard.headerHeight
        let cardBottom = frame.maxY + (forming.above ? 0 : gap) + GroupCard.inset
        if finger.y > cardTop, finger.y < cardBottom {
            let above = finger.y < frame.midY
            if above != forming.above {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { self.forming?.above = above }
            }
            return true
        }
        thaw()
        return true
    }

    /// Moved off before letting go: the card thaws away and the held tab's
    /// place comes back beside the other, where the list was.
    private func thaw() {
        guard let forming, var ids = order, let other = ids.firstIndex(of: forming.other),
              let drag else { return }
        ids.insert(drag.id, at: forming.above ? other : other + 1)
        finger.solid = false
        let lane = lane(in: nil)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            order = ids
            self.forming = nil
        }
        resize(to: lane.minX, lane.width)
    }

    /// The held tile narrows into a group's lane or widens out of one, both
    /// edges gliding together (0.25s, no bounce).
    private func resize(to left: CGFloat, _ width: CGFloat) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            finger.left = left
            finger.width = width
        }
    }

    /// Let go on a forming group: the tab settles into its gap, then the
    /// store makes the group in its place, where the card already is, and
    /// it names itself (`BrowserStore.groupNamer`).
    private func settle(_ drag: Drag, into forming: Forming) {
        let landing = formingLanding(drag, forming)
        func make() { makeFormed(drag, forming) }
        guard !reduceMotion else { return make() }
        var settling = drag
        settling.lifted = false
        withAnimation(.smooth(duration: 0.25)) {
            finger.top = landing.minY
            finger.left = landing.minX
            finger.width = landing.width
            self.drag = settling
        } completion: {
            make()
        }
    }

    /// Lets go: the tab (or group) is saved in its new place and the tile
    /// settles into it (0.25s, no bounce; with Reduce Motion it's simply
    /// there). `cancelled`: iOS took the touch (a call, the overview
    /// closing); a forming group thaws instead of being made, since
    /// nobody let go on it.
    private func letGo(cancelled: Bool = false) {
        if pointing { return stopPointing(cancelled: cancelled) }
        edgeScroll?.cancel()
        edgeScroll = nil
        hoverWait?.cancel()
        hoverWait = nil
        hoverID = nil
        guard var drag else { finger.solid = false; return }
        if let forming {
            if !cancelled { finger.solid = false; return settle(drag, into: forming) }
            thaw()
        }
        finger.solid = false
        if let ids = order, let groups = members {
            save(drag, ids, groups)
        }
        if let ids = tileOrder, let to = ids.firstIndex(of: drag.id),
           let tile = store.basecampTabs.first(where: { $0.id == drag.id }),
           store.basecampTabs.firstIndex(where: { $0.id == drag.id }) != to {
            // The grid already shows this order, so nothing moves on screen.
            store.move(tile, to: to)
        }
        order = nil
        members = nil
        tileOrder = nil
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
                if drag?.tile == true { makeRoomForTile() } else { makeRoom() }
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
        // Reopened with a shake: no glide with Reduce Motion, as everywhere else here.
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                // This very tab, even if something else closed since.
                guard let entry = store.recentlyClosed.first(where: { $0.id == id }) else { return }
                withAnimation(glide) { store.reopen(entry) }
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
        // Reopened with a shake: no glide with Reduce Motion, as everywhere else here.
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                guard let entry = store.recentlyClosed.first(where: { $0.id == id }) else { return }
                withAnimation(glide) { store.reopen(entry) }
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

/// A group's hold menu (Firn's own, by its name line; the whole group
/// lifts as one piece); `actions` gives the same three to VoiceOver on its
/// name line.
@MainActor private struct GroupMenu {
    let rename: @MainActor () -> Void
    let ungroup: @MainActor () -> Void
    let close: @MainActor () -> Void

    var sections: [[HoldMenuItem]] {
        [[HoldMenuItem(title: "Rename", systemImage: "pencil", action: rename),
          HoldMenuItem(title: "Ungroup", systemImage: "folder.badge.minus", action: ungroup)],
         [HoldMenuItem(title: "Close Group", systemImage: "xmark", closes: true, action: close)]]
    }

    var actions: GroupActions { GroupActions(rename: rename, ungroup: ungroup, close: close) }
}

/// The group menu's three, as VoiceOver actions on the name line.
@MainActor private struct GroupActions: ViewModifier {
    let rename: @MainActor () -> Void
    let ungroup: @MainActor () -> Void
    let close: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            Button("Rename", action: rename)
            Button("Ungroup", action: ungroup)
            Button("Close Group", action: close)
        }
    }
}

/// A group's Move Up and Move Down (nil at an end), for its name line,
/// which is where VoiceOver finds the group.
private struct GroupMoves {
    var up: (() -> Void)?
    var down: (() -> Void)?
}

/// VoiceOver's Move Up and Move Down on a group's name line.
private struct GroupMoveActions: ViewModifier {
    let moves: GroupMoves

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let up = moves.up { Button("Move Up", action: up) }
            if let down = moves.down { Button("Move Down", action: down) }
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

    /// The shadow's spread: wider than the Mac's 1pt, to lift the card off the haze.
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 2
    /// The header's height at the default text size (it grows with it).
    static let headerHeight: CGFloat = 44
    /// A folded group's height at the default text size (it grows too):
    /// a slim row's, so it reads as one line in the list.
    static let foldedHeight: CGFloat = OverviewRow.rowHeight

    var body: some View {
        Frost(shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
              space: space, fill: Theme.groupCardFill, solid: reduceTransparency,
              shadow: Theme.groupCardShadow, shadowRadius: Self.shadowRadius, shadowY: Self.shadowY)
    }
}

/// Fades a group's card in over the last stretch of the page's glide into
/// its card (arrival 0.6 to 1), following the glide frame by frame: an
/// opacity animated on its own would spread over the whole glide.
private struct ArrivalFade: ViewModifier, Animatable {
    var arrival: CGFloat
    nonisolated var animatableData: CGFloat {
        get { arrival }
        set { arrival = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(min(max((arrival - 0.6) / 0.4, 0), 1))
    }
}

/// Shown only within one stretch of the page's arrival, worked out on every
/// frame: the page's bar is gone by 0.45 and the overview's starts at 0.55,
/// so the two never show at once. `floor` keeps a bar's glass alive mid-glide.
struct ArrivalBand: ViewModifier, Animatable {
    var arrival: CGFloat
    let range: ClosedRange<CGFloat>
    let fadesIn: Bool
    var floor: Double = 0
    nonisolated var animatableData: CGFloat {
        get { arrival }
        set { arrival = newValue }
    }

    func body(content: Content) -> some View {
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let through = Double(min(max((arrival - range.lowerBound) / span, 0), 1))
        content.opacity(max(floor, fadesIn ? through : 1 - through))
    }
}

/// Firn's frost, the Mac's `FrostGlass` recipe, for every frosted thing in
/// the overview (group cards, and a card's title and X pills), so there's
/// one kind of glass (David, 2026-11-08): a fill, the space's color at
/// `groupTint`, a 1pt rim lit at the top, a hairline, and a soft shadow.
/// Flat and fixed, never adapting to what's behind. No blur of its own:
/// the group cards sit on the haze, which is already a blur, and a card's
/// pills put their page's own picture, blurred, under it (`CardLine`).
/// Reduce Transparency: the solid tile color, tinted, with its hairline.
private struct Frost<S: InsettableShape>: View {
    let shape: S
    let space: String
    let fill: Color
    let solid: Bool
    var shadow = Theme.shadowSoft
    var shadowRadius: CGFloat = 1
    var shadowY: CGFloat = 0.5

    var body: some View {
        FirnFrost(shape: shape, fill: fill, tint: Theme.spaceColor(space).opacity(Theme.groupTint),
                  solid: solid, shadow: shadow, shadowRadius: shadowRadius, shadowY: shadowY)
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
    /// Where down the tile the finger holds it.
    var grab: CGFloat
    /// A whole group, held by its name line.
    let group: Bool
    /// The group a held tab was in when it lifted.
    let from: UUID?
    /// False once let go, as the tile settles into its place.
    var lifted = true
    /// Where across the tile the finger holds it (Basecamp tiles move both ways).
    var grabX: CGFloat = 0
    /// A Basecamp tile, moving only within Basecamp.
    var tile = false
}

/// A group forming while a held tab rests on a loose one: the loose tab,
/// the group as the store would make it (not saved), and whether the
/// held tab's gap is above the other.
private struct Forming {
    let other: UUID
    let group: TabGroup
    var above: Bool
}

/// A loose tab's tile, with room for the group forming around it: at rest,
/// zero-height spacers and nothing else, so the tile keeps its identity
/// and glides to its place in the card. Forming, it's laid out exactly as
/// the group will be (`groupCard`): the name line, the held tab's gap and
/// this tab 8pt apart, 8pt in from the card's sides and bottom, so making
/// the group on letting go changes nothing on screen. The card fades in
/// as it grows out from the tile (the frost forming); the name line is
/// faint, as on the Mac, until the group is made and names itself.
private struct FormingCard: ViewModifier {
    let forming: Forming?
    /// The held tab's height, for its gap.
    let gap: CGFloat
    let space: String
    @State private var line = GroupCard.headerHeight
    /// The last group shown, kept so the name line fades out where it is
    /// as the card thaws.
    @State private var shown: TabGroup?

    func body(content: Content) -> some View {
        let on = forming != nil
        let above = forming?.above ?? true
        VStack(spacing: 0) {
            Color.clear
                .frame(height: on ? line : 0)
                .overlay(alignment: .bottom) {
                    // Faded, never removed: a removed view keeps its old
                    // size while it fades, so the thawing card and its name
                    // line covered the card below (David's recording,
                    // 2026-11-08).
                    if let group = forming?.group ?? shown {
                        GroupLine(group: group, height: GroupCard.headerHeight, naming: false, toggle: {})
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { line = $0 }
                            .opacity(on ? 0.5 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            Color.clear.frame(height: on && above ? gap + GroupCard.inset : 0)
            content
            Color.clear.frame(height: on && !above ? gap + GroupCard.inset : 0)
        }
        .padding(.horizontal, on ? GroupCard.inset : 0)
        .padding(.bottom, on ? GroupCard.inset : 0)
        // Shrinks with the tile as it fades (see the name line).
        .background {
            if on || shown != nil { GroupCard(space: space).opacity(on ? 1 : 0) }
        }
        .onChange(of: forming?.group.id) { _, id in
            if id != nil { shown = forming?.group }
        }
    }
}

/// What a hold in the list lifts.
private enum Liftable {
    case tab(FirnCore.Tab)
    case group(TabGroup)
    case tile(FirnCore.Tab)

    @MainActor var id: UUID {
        switch self {
        case let .tab(tab), let .tile(tab): tab.id
        case let .group(group): group.id
        }
    }
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
    /// Resting on another tab, waiting for their group to form: the held
    /// tile turns solid so the one under it doesn't show through.
    var solid = false
    /// A tab held still, sinking a little until its menu opens.
    var pressed: UUID?
    /// The size the lifted tile rises from: a pressed tab's, sunk.
    var liftFrom: CGFloat = 1
}

/// How far a held tab sinks before its menu opens (as iOS's items do).
let pressedScale: CGFloat = 0.97

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
        let pressed = finger.pressed == id
        content
            // Held still, it sinks a little over the rest of the hold, so
            // the finger feels the menu coming; let go early, it springs back.
            .scaleEffect(pressed ? pressedScale : 1)
            .animation(pressed ? .easeIn(duration: HoldThenMove.menuHold - HoldThenMove.hold)
                               : .smooth(duration: 0.2), value: pressed)
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
    /// A slim row or a group: see-through at rest (a slim row is 10% in
    /// dark), so while it's held it sits on one steady base, menu, drag,
    /// and forming group alike, never switching with what's under it
    /// (David, 2026-11-09: a dragged group read too transparent).
    var steady = false
    /// The solid base's corners: a group card's are rounder than a tab's.
    var cornerRadius: CGFloat = OverviewRow.cornerRadius
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        let raised = lifted && up && !reduceMotion
        let based = steady ? lifted || finger.solid : finger.solid
        GeometryReader { box in
            let origin = box.frame(in: .global).origin
            content
                .modifier(LaneWidth(width: finger.width, height: height))
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.heldRowBase)
                        .opacity(based ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: based)
                }
                // From a held tab's sunk size (`liftFrom`), so the press
                // and the lift are one motion.
                .scaleEffect(raised ? 1.03 : (up ? 1 : finger.liftFrom))
                .shadow(color: Theme.shadowPeek.opacity(raised ? 1 : 0), radius: 18, y: 8)
                .modifier(LaneLeft(x: finger.left - origin.x))
                .offset(y: finger.top - origin.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.smooth(duration: 0.2)) { up = true } }
    }
}

/// The held tile's width, worked out afresh on every frame of a glide. A
/// plain `.frame` lays the row out at its new width at once and only
/// eases the picture, and the row's left edge jumped as it moved into or
/// out of a group while its right edge glided (David's recordings,
/// 2026-11-09). With these two, both edges move together, frame by frame.
private struct LaneWidth: ViewModifier, Animatable {
    var width: CGFloat
    let height: CGFloat

    nonisolated var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height)
    }
}

/// The held tile's left edge (from its overlay's origin), frame by frame.
private struct LaneLeft: ViewModifier, Animatable {
    var x: CGFloat

    nonisolated var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: x)
    }
}

/// Hold, then move: lifts a tab to drag it. Holding still instead opens
/// Firn's menu (at about 0.5s), and a quick move with no hold is a scroll
/// or a swipe, so the drag starts only when the finger moves after a short
/// hold, before the menu. As in Safari, where hold-and-move drags and
/// holding still opens the menu. UIKit, because SwiftUI has no gesture
/// that waits for a hold and then needs movement.
private struct HoldToDrag: UIGestureRecognizerRepresentable {
    let enabled: Bool
    /// Whether there's something to lift where the finger came down
    /// (global); if not, the touch is left to scrolling.
    let canBegin: (CGPoint) -> Bool
    let began: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    /// True when iOS cancelled the touch rather than the finger lifting.
    let ended: (Bool) -> Void
    /// Whether holding still at a point (global) opens Firn's menu there,
    /// and opening it; then the finger lifting (false) or iOS cancelling
    /// the touch (true). The menu stays open after the finger lifts.
    let wantsMenu: (CGPoint) -> Bool
    let pressing: (CGPoint?) -> Void
    let menu: (CGPoint) -> Void
    let menuEnded: (Bool) -> Void
    /// The held finger moved from where the menu opened (the second
    /// point): from here its moves and its lift come as a drag's
    /// (`moved`, then `ended`), whether it drags or points at the menu.
    let leaveMenu: (CGPoint, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> HoldThenMove {
        let hold = HoldThenMove()
        hold.isEnabled = enabled
        hold.delegate = context.coordinator
        hold.wantsMenu = wantsMenu
        hold.pressing = pressing
        context.coordinator.canBegin = canBegin
        return hold
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (CGPoint) -> Bool = { _ in false }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let hold = gesture as? HoldThenMove else { return false }
            return canBegin(hold.startPoint)
        }

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
        hold.wantsMenu = wantsMenu
        hold.pressing = pressing
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ hold: HoldThenMove, context: Context) {
        let point = context.converter.location(in: .global)
        switch hold.state {
        case .began where hold.heldStill:
            menu(CGPoint(x: point.x - hold.moved.x, y: point.y - hold.moved.y))
        case .began:
            // Lifted from where the finger first came down, then follows it.
            began(CGPoint(x: point.x - hold.moved.x, y: point.y - hold.moved.y))
            moved(point)
        case .changed where hold.leftMenu:
            // Moved off an open menu: it thaws, and the tile drags.
            hold.leftMenu = false
            let move = hold.sinceMenu
            leaveMenu(point, CGPoint(x: point.x - move.x, y: point.y - move.y))
        case .changed:
            if !hold.heldStill { moved(point) }
        case .ended: hold.heldStill ? menuEnded(false) : ended(false)
        case .cancelled: hold.heldStill ? menuEnded(true) : ended(true)
        default: break
        }
    }
}

/// One finger held for `hold`, then moved `slop` points: begins. Moved
/// sooner: fails at once (a scroll or a swipe). Held still for `menuHold`
/// where `wantsMenu` says there's a menu: begins too, `heldStill`, for
/// Firn's hold menu. Otherwise never moved: fails when lifted.
final class HoldThenMove: UIGestureRecognizer {
    static let hold: TimeInterval = 0.15
    static let menuHold: TimeInterval = 0.5
    static let slop: CGFloat = 8
    private var start: CGPoint = .zero
    /// Where the finger came down, in the window.
    var startPoint: CGPoint { start }
    private var startTime: TimeInterval = 0
    /// How far the finger had moved when it began.
    private(set) var moved: CGPoint = .zero
    /// Whether a still hold at a point (window) opens Firn's menu there.
    var wantsMenu: (CGPoint) -> Bool = { _ in false }
    /// A still finger where a menu will open, from `hold` on (the tile
    /// starts to sink), and nil once it isn't (moved, lifted, or begun).
    var pressing: (CGPoint?) -> Void = { _ in }
    /// Began by holding still: a menu, not a drag.
    private(set) var heldStill = false
    /// The finger, still down, has just moved `slop` points from where the
    /// menu opened: from here it's a drag. Read once, by the action.
    var leftMenu = false
    /// The finger's latest point, and where it was as the menu opened.
    private var last: CGPoint = .zero
    private var menuPoint: CGPoint = .zero
    /// How far the finger has moved since the menu opened.
    var sinceMenu: CGPoint { CGPoint(x: last.x - menuPoint.x, y: last.y - menuPoint.y) }
    private var menuTimer: DispatchWorkItem?
    private var pressTimer: DispatchWorkItem?
    private var pressed = false

    private func endPress() {
        pressTimer?.cancel()
        pressTimer = nil
        guard pressed else { return }
        pressed = false
        pressing(nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, (event.allTouches?.count ?? 1) == 1 else {
            if state == .possible { state = .failed }
            return
        }
        start = touch.location(in: nil)
        last = start
        startTime = touch.timestamp
        let press = DispatchWorkItem { [weak self] in
            guard let self, self.state == .possible, self.wantsMenu(self.start) else { return }
            self.pressed = true
            self.pressing(self.start)
        }
        pressTimer = press
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold, execute: press)
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.state == .possible, self.wantsMenu(self.start) else { return }
            // The press stays set: the menu reads it (the tab is sunk) and
            // clears it; `reset` reports the end once the finger lifts.
            self.heldStill = true
            self.menuPoint = self.last
            self.state = .began
        }
        menuTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuHold, execute: timer)
    }

    override func reset() {
        endPress()
        menuTimer?.cancel()
        menuTimer = nil
        heldStill = false
        leftMenu = false
        moved = .zero
        super.reset()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: nil)
        last = point
        switch state {
        case .possible:
            moved = CGPoint(x: point.x - start.x, y: point.y - start.y)
            guard hypot(moved.x, moved.y) >= Self.slop else { return }
            menuTimer?.cancel()
            endPress()
            guard touch.timestamp - startTime >= Self.hold else { state = .failed; return }
            state = .began
        case .began, .changed:
            // Off the menu: the same touch carries on as a drag, so the
            // tile that lifted for the menu is the one that moves.
            if heldStill, hypot(point.x - menuPoint.x, point.y - menuPoint.y) >= Self.slop {
                heldStill = false
                leftMenu = true
            }
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
    let tab: UUID?
    let picture: UIImage?
    let space: String
    @State private var haze: UIImage?

    /// Each tab's last haze, kept while Firn runs (a few small images), so
    /// the overview opens with it already there. Made afresh every time, it
    /// came in after the page had landed, a second change once everything
    /// should be still (David's recording, 2026-11-09); a fresh one still
    /// cross-fades in over it when the page has changed.
    @MainActor private static var kept: [UUID: UIImage] = [:]

    init(tab: UUID?, picture: UIImage?, space: String) {
        self.tab = tab
        self.picture = picture
        self.space = space
        _haze = State(initialValue: tab.flatMap { Self.kept[$0] })
    }
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
            if let tab {
                if Self.kept.count > 30 { Self.kept.removeAll() }
                Self.kept[tab] = haze
            }
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
        return softener.createCGImage(soft, from: extent)
    }

    /// One Core Image context, made once: setting one up for every haze
    /// was most of the wait for a page's first haze. Core Image's contexts
    /// are safe to share between threads.
    private nonisolated(unsafe) static let softener = CIContext(options: [.cacheIntermediates: false])
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
    /// The group it's in, for VoiceOver ("<title>, in <group>"); nil when loose.
    var groupName: String?

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
    /// the row's fill shrinks into the card's frosted pill as the tile grows
    /// around it, and the picture fades in behind. The tab on screen is ringed
    /// in the space's color on the card's inside edge, as Basecamp's tile on
    /// screen is (`CardRing`), so it reads at a glance.
    private var tile: some View {
        Button(action: open) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight + (Self.cardHeight - Self.rowHeight) * t)
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .background {
            // The page fades in behind the pill as the card grows; the
            // row's fill itself is the line's (it becomes the pill).
            Theme.page
                .overlay(alignment: .top) { pictureView }
                .clipShape(Self.shape)
                .opacity(t)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: spot)
        .accessibilityLabel(groupName.map { "\(tab.title), in \($0)" } ?? tab.title)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
        .accessibilityActions {
            if let moveUp { Button("Move Up", action: moveUp) }
            if let moveDown { Button("Move Down", action: moveDown) }
        }
        .overlay(alignment: .top) {
            CardTop(tab: tab, close: close, progress: t, space: space, picture: picture)
                .opacity(lineShown ? 1 : 0)
        }
        .overlay {
            if isOnScreen {
                CardRing(color: ring, radius: Self.cornerRadius)
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
    static let rowHeight: CGFloat = 44

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
/// and a card's pill are one shape (David, 2026-11-05): as the tile grows,
/// the row's flat fill shrinks into the pill in the card's top-left corner
/// and gives way to Firn's frost (the group cards', over a real blur), the
/// icon and title slide with it as one piece, and the row's X moves to the
/// top-right as its round frost forms around it (2026-11-08: one kind of
/// glass in the overview, Firn's own).
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
    /// The page's picture, drawn as wide as the card from its top: blurred
    /// under the pills, so the page's light comes through them.
    var picture: UIImage?

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
                 titleWidth: titleWidth, solid: reduceTransparency, picture: picture)
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
    let picture: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// One font for both sizes (the row's semibold), so the text can't jump.
    /// 13pt, as Safari's tab titles (David, 2026-11-08): smaller pills, more
    /// of the picture.
    static let titleFont = Font.footnote.weight(.semibold)

    // The row's measures, then the card's.
    private static let rowHeight = OverviewRow.rowHeight          // 44
    private static let glassHeight: CGFloat = 30                  // the pill and round X
    private static let inset: CGFloat = 8                         // the pill's and X's distance in
    private static let rowIcon: CGFloat = 20                      // the site icon, row then pill
    private static let pillIcon: CGFloat = 18
    private static let pillPad: CGFloat = 8                       // pill edge to icon
    private static let iconGap: CGFloat = 6                       // icon to title, in the pill
    private static let cardLineHeight: CGFloat = inset + glassHeight + 6
    private static let tapSize: CGFloat = 44
    /// The X's middle, this far in from the right in a row and on a card
    /// alike, so it only moves up and down as the tile grows (David, 2026-11-08).
    private static let xCenterIn: CGFloat = 24
    /// Room on the card's right for the X and a gap before it.
    private static let xRoom: CGFloat = 52

    private var site: String { WebAddress.site(of: tab.url) }

    var body: some View {
        let t = min(max(progress, 0), 1)
        GeometryReader { box in
            let w = box.size.width
            // The fill: the whole row, then the pill.
            let pillLead = Self.pillPad + Self.pillIcon + Self.iconGap
            let pillWidth = min(max(w - Self.xRoom, 0), pillLead + titleWidth + 12)
            let glassWidth = mix(w, pillWidth, t)
            let glassHeight = mix(Self.rowHeight, Self.glassHeight, t)
            let glassShape = RoundedRectangle(cornerRadius: mix(OverviewRow.cornerRadius, Self.glassHeight / 2, t),
                                              style: .continuous)
            // The line's middle: the row's, then the pill's.
            let middle = mix(Self.rowHeight / 2, Self.inset + Self.glassHeight / 2, t)
            let titleX = mix(46, Self.inset + pillLead, t)
            let titleRoom = max(mix(w - 92, pillWidth - pillLead - 12, t), 0)
            ZStack(alignment: .topLeading) {
                ZStack {
                    // A slim row is flat (David, 2026-11-08): only group cards
                    // and a card's pills are frost. As the tile grows, the
                    // row's flat fill shrinks into the pill and gives way to
                    // its frost, one shape all the way. The frost is always
                    // there, only faded: added mid-pinch, SwiftUI gave it a
                    // glide of its own, and it trailed the title (David's
                    // recording, 2026-11-08).
                    // A slim row: flat paper, the same loose and grouped,
                    // with a hairline and a faint shadow so it reads as
                    // something to tap (`Theme.slimRowFill`).
                    glassShape.fill(solid ? Theme.tileSolid : Theme.slimRowFill)
                        .overlay { glassShape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
                        .shadow(color: solid ? .clear : Theme.shadowSoft, radius: 1, y: 0.5)
                        .opacity(1 - t)
                    pillFrost(glassShape, at: CGPoint(x: mix(0, Self.inset, t), y: mix(0, Self.inset, t)),
                              size: CGSize(width: glassWidth, height: glassHeight), cardWidth: w)
                        .opacity(t)
                }
                .frame(width: glassWidth, height: glassHeight)
                .offset(x: mix(0, Self.inset, t), y: mix(0, Self.inset, t))
                .allowsHitTesting(false)
                SiteIconView(icon: tab.icon, size: Self.rowIcon) { LetterMark(site: site, size: Self.rowIcon) }
                    .scaleEffect(mix(1, Self.pillIcon / Self.rowIcon, t))
                    .frame(width: Self.rowIcon, height: Self.rowIcon)
                    .offset(x: mix(24, Self.inset + Self.pillPad + Self.pillIcon / 2, t) - Self.rowIcon / 2,
                            y: middle - Self.rowIcon / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(Self.titleFont)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: titleRoom, height: 30, alignment: .leading)
                    // A change of the row's width (a group forming or
                    // thawing around it) sets the title's room at once: its
                    // width gliding made the title wrap and ride up to the
                    // row's top edge mid-glide (David's recording,
                    // 2026-11-08). The pinch, which changes `t`, still glides.
                    .animation(nil, value: w)
                    .offset(x: titleX, y: middle - 15)
                    // Taps on the icon and title open the tile; only the X is its own.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                closeButton(t, cardWidth: w, middle: middle)
                    .offset(x: (w - Self.xCenterIn) - Self.tapSize / 2,
                            y: middle - Self.tapSize / 2)
            }
        }
        .frame(height: mix(Self.rowHeight, Self.cardLineHeight, t), alignment: .top)
    }

    /// How soft the page is through a pill: enough that no shape can be
    /// made out, while its light and color still come through.
    private static let blurRadius: CGFloat = 10
    /// Frost scatters light, so it's brighter than what's behind it: in
    /// light mode the blurred page is lifted a fixed amount, so a dark
    /// page's pill turns a lighter grey and its dark title reads (David,
    /// 2026-11-08). Bright pages barely change. Dark mode reads as is.
    private static let frostLift: Double = 0.15
    private static let noPicture = UIImage()

    /// A pill's frost: the group cards' recipe, light, over the page's own
    /// picture blurred (David, 2026-11-08: light pouring through frozen
    /// glass). Firn's own blur, not iOS's material, which laid a grey veil
    /// and dulled the colors and can't be tuned. `origin` and `size` are
    /// the pill's spot in the card, so the blur lines up with the picture
    /// around it. Always drawn, even without a picture (an empty image),
    /// so nothing is added mid-pinch.
    private func pillFrost<S: InsettableShape>(_ shape: S, at origin: CGPoint, size: CGSize,
                                               cardWidth: CGFloat) -> some View {
        let image = solid ? Self.noPicture : (picture ?? Self.noPicture)
        let scale = image.size.width > 0 ? cardWidth / image.size.width : 0
        return Frost(shape: shape, space: space, fill: Theme.cardPillVeil, solid: solid)
            .background {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: cardWidth, height: image.size.height * scale)
                    .offset(x: -origin.x, y: -origin.y)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .blur(radius: Self.blurRadius, opaque: true)
                    .brightness(colorScheme == .light ? Self.frostLift : 0)
                    .clipShape(shape)
                    .accessibilityHidden(true)
            }
    }

    /// The row's small X, moving to the card's corner as its round frost
    /// forms around it.
    @ViewBuilder private func closeButton(_ t: CGFloat, cardWidth w: CGFloat, middle: CGFloat) -> some View {
        let size = mix(28, Self.glassHeight, t)
        let formed = min(max((t - 0.3) / 0.7, 0), 1)
        let center = CGPoint(x: (w - Self.xCenterIn), y: middle)
        let mark = ZStack {
            pillFrost(Circle(), at: CGPoint(x: center.x - size / 2, y: center.y - size / 2),
                      size: CGSize(width: size, height: size), cardWidth: w)
                .frame(width: size, height: size)
                .opacity(formed)
            ZStack {
                Image(systemName: "xmark").foregroundStyle(Theme.muted)
                Image(systemName: "xmark").foregroundStyle(Theme.ink).opacity(t)
            }
            .font(.system(size: 12, weight: .semibold))
            .scaleEffect(mix(11 / 12, 1, t))
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

/// The ring around the tab on screen's card: Basecamp's ring on the tile on
/// screen (`BasecampTiles`), on the card's inside edge with light on its top
/// and a faint glow, but always the space's color, never the page's (David,
/// 2026-11-08). Drawn on the card and on the page's picture gliding into it.
struct CardRing: View {
    let color: Color
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = colorScheme == .dark
        shape.strokeBorder(color, lineWidth: BasecampTiles.ringWidth)
            .opacity(reduceTransparency ? 1 : (dark ? 0.95 : 0.9))
            .overlay {
                // Light catching the ring's outer edge along the top, gone by the middle.
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.tileRingSheen, Theme.tileRingSheen.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .shadow(color: color.opacity(dark ? 0.18 : 0.28), radius: 5)
    }
}

/// A site with no icon yet: its first letter on a calm color of its own.
struct LetterMark: View {
    let site: String
    var size: CGFloat = 24

    var body: some View {
        Text(site.first.map { String($0).uppercased() } ?? "")
            .font(.system(size: size * 13 / 24, weight: .semibold))
            .foregroundStyle(Theme.page)
            .frame(width: size, height: size)
            .background(Theme.siteColor(for: site), in: .rect(cornerRadius: size / 4))
            .accessibilityHidden(true)
    }
}

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a frosted pill in the middle (the switcher and its dots come
/// with phase 4), and a round check on the right in a vivid version of the
/// space's color. All on Firn's frost (`BarFrost`), over the list's soft
/// edge blur; pressed, the warm wash.
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
                .background { BarFrost(shape: Capsule(), space: space.color) }
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
                .buttonStyle(FrostPress(shape: Circle()))
                .background { BarFrost(shape: Circle(), space: space.color) }
                .accessibilityLabel("New Tab")
                Spacer()
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(.white)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(FrostPress(shape: Circle()))
                // The one solid button, as Firn's buttons are ink: the
                // space's vivid color under the frost's rim and hairline.
                .background {
                    FirnFrost(shape: Circle(), fill: Theme.spaceVivid(space.color))
                }
                .accessibilityLabel("Done")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, AddressBar.sideInset)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }
}
