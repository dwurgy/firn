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
    /// On screen. The overview stays built behind the page while browsing
    /// (hidden), so a swipe up only reveals it; whatever it remembers
    /// resets as it hides.
    var shown = true

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
                                  incoming: drag?.basecamp == true ? drag?.id : nil,
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
            // While a page is held, only the haze is behind it, as in
            // Safari: the cards come in over the landing's last stretch
            // (and leave first as a tab opens). Shown clearly behind a slow
            // hold, they were distracting (David, 2026-11-10). A hair above
            // 0, so the cards' blur isn't dropped and rebuilt mid-glide.
            .modifier(ArrivalBand(arrival: arrival, range: 0.85...1, fadesIn: true, floor: 0.002))
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
            // Ready before it shows: sizes taken, the tidy read, and scrolled
            // to the tab on screen, so the page's card is in place the
            // moment a swipe up starts. Again as it shows (as when it was
            // built on each opening), and while hidden whenever the tab or
            // space on screen changes.
            .onAppear { getReady(scroller) }
            .onChange(of: shown) { _, now in
                if !now { forgetOpening() }
                getReady(scroller)
            }
            .onChange(of: store.activeTab?.id) { if !shown { getReady(scroller) } }
            .onChange(of: store.activeSpace.id) { if !shown { getReady(scroller) } }
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
            // Hidden, only a picture already in memory: browsing never
            // waits on the disk.
            OverviewHaze(tab: store.activeTab?.id,
                         picture: store.activeTab.flatMap {
                             shown ? pictures.image(for: $0.id) : pictures.cachedImage(for: $0.id)
                         }, space: space)
        }
        // Only while shown: it takes the keyboard's focus to hear a shake.
        .background { if shown { ShakeToUndo(undoManager: undoManager, closes: closes) } }
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

    /// What an opening takes as it starts: each tab's last-viewed time
    /// (so nothing changes size while it's open), this space's tidy, and
    /// the list scrolled to the tab on screen.
    private func getReady(_ scroller: ScrollViewProxy) {
        openedAt = .now
        lastViewed = Dictionary(store.openTabs.map { ($0.id, $0.lastActiveAt) }) { a, _ in a }
        loadTidied()
        if let id = store.activeTab?.id { scroller.scrollTo(id, anchor: .center) }
    }

    /// Hidden: everything a visit leaves behind goes, as when the
    /// overview was built afresh for each one (a hold, a menu, a drag and
    /// its moved order, a forming group, a rename, a pinch under way).
    private func forgetOpening() {
        hoverWait?.cancel()
        edgeScroll?.cancel()
        hoverWait = nil
        edgeScroll = nil
        hoverID = nil
        forming = nil
        heldMenu = nil
        pointing = false
        pointer.point = nil
        pointer.card = nil
        drag = nil
        finger.held = nil
        finger.solid = false
        finger.pressed = nil
        order = nil
        members = nil
        tileOrder = nil
        finishing = false
        pinchDone = false
        listFade = 1
        naming = nil
        basecampFull = false
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
                    // Carried up over Basecamp, it becomes a tile: the row
                    // fades as the tile comes through, and the shape glides.
                    let shaped = drag.basecamp
                    LiftedTile(finger: finger, height: shaped ? drag.tileSize.height : drag.start.height,
                               lifted: drag.lifted,
                               steady: tallness(tab, onScreen: isOnScreen(tab)) < 0.5) {
                        ZStack {
                            tile(tab, spot: { _ in })
                                // Kept to the shrinking shape (a card's
                                // picture doesn't shrink with it); loose
                                // otherwise, so nothing of a row is cut.
                                .mask {
                                    RoundedRectangle(cornerRadius: OverviewRow.cornerRadius, style: .continuous)
                                        .padding(shaped ? 0 : -40)
                                }
                                .opacity(shaped ? 0 : 1)
                            BasecampTiles.lifted(tab, space: space, onScreen: isOnScreen(tab),
                                                 solid: drag.lifted)
                                .opacity(shaped ? 1 : 0)
                        }
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
            picture: onScreen && shown ? pictures.image(for: tab.id) : pictures.cachedImage(for: tab.id),
            loadPicture: { await pictures.loadImage(for: tab.id) },
            ring: Theme.spaceColor(space),
            space: space,
            lineShown: !onScreen || lineShown,
            open: { if !busy { open(tab) } },
            close: { if !busy { close(tab) } },
            spot: spot,
            moveUp: moveUp,
            moveDown: moveDown,
            // From every group directly: `tabGroups` walks the whole tab
            // list, and this runs for every tile on every redraw.
            groupName: tab.groupID.flatMap { id in store.groups.first(where: { $0.id == id })?.name }
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
        finger.x = point.x
        finger.y = point.y
        if !drag.tile && !drag.group { return rearrange() }
        finger.top = point.y - drag.grab
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
        let size = drag.basecamp ? drag.tileSize : drag.start.size
        let middle = CGPoint(x: finger.left + size.width / 2, y: finger.top + size.height / 2)
        var nearest = from
        var best = CGFloat.infinity
        for (index, id) in ids.enumerated() {
            // A carried tab's spot is its own (its row's frame is the list's).
            let spot = drag.basecamp && id == drag.id ? spots.incoming : spots.frames[id]
            guard let frame = spot else { continue }
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
        // Once per move, not once per tile: the finger moves every frame.
        let looseIDs: Set<UUID> = drag.group ? [] : Set(store.looseTabs.map(\.id))
        let loose: Set<UUID> = Set(ids.filter { $0 != drag.id && looseIDs.contains($0) })
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

    // MARK: Into Basecamp

    /// Whether the finger is over Basecamp's grid (or above it), while it
    /// shows. A carried tab stays a tile until the finger is clearly below
    /// the grid, past the 12pt gap, so it doesn't flicker at the edge.
    private var overBasecamp: Bool {
        guard let grid = spots.basecamp, grid.maxY > spots.viewport.minY else { return false }
        return finger.y < grid.maxY + (drag?.basecamp == true ? 12 : 0)
    }

    /// A held tab follows the finger. Carried up over Basecamp, it becomes
    /// a tile there and the tiles make room (a short glide, no bounce);
    /// back below, a row again, and the list makes room. Over a full
    /// Basecamp (or for a tab with no address) nothing changes shape and
    /// the list goes back as it was, since letting go there glides it home.
    private func rearrange() {
        guard let drag, drag.lifted, !drag.tile else { return }
        if drag.group { return makeRoom() }
        let over = overBasecamp
        let tab = store.openTabs.first { $0.id == drag.id }
        let fits = store.canAddToBasecamp && tab?.url != nil
        if over && fits {
            if !drag.basecamp { carryIntoBasecamp(drag) }
            followAsTile()
            return makeRoomForTile()
        }
        let left = drag.basecamp ? lane(in: nil).minX : finger.left
        if drag.basecamp { carryOutOfBasecamp(drag) }
        place(finger.y - drag.grab, left)
        if over {
            // Over a full Basecamp: the list as it was, the tab's place open.
            waitToForm(over: nil)
            let rest = restingOrder()
            guard order != rest.ids || members != rest.groups else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                order = rest.ids
                members = rest.groups
            }
            return
        }
        makeRoom()
    }

    /// The list's order and groups as the store has them (nothing moved).
    private func restingOrder() -> (ids: [UUID], groups: [UUID: [UUID]]) {
        (store.tabListItems.map(\.id),
         Dictionary(store.tabGroups.map { group in
             (group.id, group.folded ? [] : store.tabs(in: group).map(\.id))
         }) { a, _ in a })
    }

    /// Puts the held tile's top-left corner here: gliding while it changes
    /// shape (each move retargets the same smooth glide), at once otherwise.
    private func place(_ top: CGFloat, _ left: CGFloat) {
        let gliding = !reduceMotion && Date.now < (drag?.reshaping ?? .distantPast)
        withAnimation(gliding ? .smooth(duration: 0.25) : nil) {
            finger.top = top
            finger.left = left
        }
    }

    /// A tile-shaped tab, centered under the finger, kept inside the list.
    private func followAsTile() {
        guard let drag else { return }
        let view = spots.viewport
        let size = drag.tileSize
        place(finger.y - size.height / 2,
              min(max(finger.x - size.width / 2, view.minX), view.maxX - size.width))
    }

    /// The tab becomes a tile under the finger: its place in the list (or
    /// its group) closes, and a spot opens among the tiles, the nearest.
    private func carryIntoBasecamp(_ old: Drag) {
        var new = old
        new.basecamp = true
        new.reshaping = .now + 0.3
        let width = spots.basecamp?.width ?? spots.viewport.width - 32
        new.tileSize = BasecampTiles.tileSize(count: store.basecampTabs.count + 1, width: width)
        if forming != nil { thaw() }
        waitToForm(over: nil)
        finger.solid = false
        spots.incoming = nil
        var tiles = store.basecampTabs.map(\.id)
        let nearest = tiles.indices.min { a, b in
            let fa = spots.frames[tiles[a]] ?? .zero, fb = spots.frames[tiles[b]] ?? .zero
            return hypot(fa.midX - finger.x, fa.midY - finger.y) < hypot(fb.midX - finger.x, fb.midY - finger.y)
        }
        // Before the nearest tile if the finger is left of its middle.
        let at = nearest.map { index in
            (spots.frames[tiles[index]]?.midX ?? 0) < finger.x ? index + 1 : index
        } ?? tiles.count
        tiles.insert(new.id, at: at)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            drag = new
            order?.removeAll { $0 == new.id }
            members = members?.mapValues { $0.filter { $0 != new.id } }
            tileOrder = tiles
            finger.width = new.tileSize.width
        }
        forms += 1
    }

    /// Back below Basecamp: a row (or card) again, the full list's width,
    /// held where the finger first held it; its spot among the tiles closes.
    private func carryOutOfBasecamp(_ old: Drag) {
        var new = old
        new.basecamp = false
        new.reshaping = .now + 0.3
        spots.incoming = nil
        let lane = lane(in: nil)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            drag = new
            tileOrder = nil
            finger.width = lane.width
        }
    }

    /// Let go over Basecamp: the tile settles into its spot, then the store
    /// adds it there (leaving its group, as Add to Basecamp does), where
    /// the tile already is, so nothing else moves. If iOS took the touch,
    /// nothing is saved and the list is simply as it was.
    private func settleInBasecamp(_ drag: Drag, cancelled: Bool) {
        finger.solid = false
        func finish(adding: Bool) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                if adding, let tab = store.openTabs.first(where: { $0.id == drag.id }),
                   let at = tileOrder?.firstIndex(of: drag.id) {
                    _ = store.addToBasecamp(tab, at: at)
                }
                order = nil
                members = nil
                tileOrder = nil
                self.drag = nil
                finger.held = nil
                spots.incoming = nil
            }
            lastDrop = .now
        }
        guard !cancelled else { return finish(adding: false) }
        let landing = spots.incoming ?? CGRect(x: finger.left, y: finger.top,
                                               width: drag.tileSize.width, height: drag.tileSize.height)
        guard !reduceMotion else { return finish(adding: true) }
        var settling = drag
        settling.lifted = false
        withAnimation(.smooth(duration: 0.25)) {
            finger.top = landing.minY
            finger.left = landing.minX
            finger.width = landing.width
            self.drag = settling
        } completion: {
            finish(adding: true)
        }
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
        if drag.basecamp { return settleInBasecamp(drag, cancelled: cancelled) }
        let fullBasecamp = !drag.group && overBasecamp && !store.canAddToBasecamp
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
            if fullBasecamp { basecampFull = true }
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
            // Let go over a full Basecamp: home first, then the reason.
            if fullBasecamp { basecampFull = true }
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
                if drag?.tile == true { makeRoomForTile() } else { rearrange() }
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

/// Fades a group's card in over the last stretch of the page's glide into
/// its card (arrival 0.6 to 1), following the glide frame by frame: an
/// opacity animated on its own would spread over the whole glide.
struct ArrivalFade: ViewModifier, Animatable {
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
struct Frost<S: InsettableShape>: View {
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
    var frames: [UUID: CGRect] = [:] {
        didSet { SwipeTiming.sawSpots(frames) }
    }
    /// The list's own frame, to find the tab under a pinch.
    var viewport: CGRect = .zero
    /// The tabs shown as tall cards (the rest are slim rows): a card's
    /// title line rides on its picture as the page grows out of it.
    var cards: Set<UUID> = []
    /// The list's scroll, for scrolling while a tab is held at an edge.
    var scroll: ScrollGeometry?
    /// Basecamp's grid (nil while empty), and the empty spot in it for a
    /// tab carried up from the list.
    var basecamp: CGRect?
    var incoming: CGRect?
}

/// UIKit offers "Undo Close Tab" on a shake only when something holds
/// keyboard focus, and the overview has no text field. This invisible view
/// takes that focus (giving it back to any field that wants it) and hands
/// UIKit SwiftUI's undo list. UIKit, because SwiftUI has no say in shakes.
struct ShakeToUndo: UIViewRepresentable {
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
