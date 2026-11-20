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
    /// What a swipe up or a tab opening moves (`Landing`): read only by
    /// the small views that use each value, so its changes don't run this
    /// body and its whole list again (2i step 3). Only `gliding` and
    /// `heldCard` are read here: they change which card shows what.
    let landing: Landing
    /// The tab whose card the page is gliding into or out of: hidden, so
    /// the page is the only one of it on screen.
    private var gliding: UUID? { landing.gliding }
    /// The overview's own view, drawn alone for the landing's picture.
    let canvas: OverviewCanvas
    /// Which tab has the tall card while a picked tab grows to the full
    /// screen: still the one that was on screen, so nothing behind the
    /// glide changes size.
    private var heldCard: UUID? { landing.heldCard }
    /// The screen's middle (global points), which the list and bar grow
    /// around as they come forward (`ComesForward`).
    var screenMiddle: CGPoint?
    /// The screen's middle in the list's scroll view's own points, which
    /// don't move as it scrolls (`ComesForward.inScroll`).
    private var listMiddle: CGPoint? {
        screenMiddle.map { CGPoint(x: $0.x - spots.viewport.minX, y: $0.y - spots.viewport.minY) }
    }
    /// Show a tab (the page grows out of its card or row), back to the
    /// page, and a new tab (back to the page, ready to type).
    let actions: OverviewActions
    private var open: (FirnCore.Tab) -> Void { actions.open }
    private var done: () -> Void { actions.done }
    private var newTab: () -> Void { actions.newTab }
    /// Typing from +: the address field takes the bar's place, so the bar
    /// steps out of its way (it would show through the field's glass).
    var typing = false
    /// On screen. The overview stays built behind the page while browsing
    /// (hidden), so a swipe up only reveals it; whatever it remembers
    /// resets as it hides.
    var shown = true

    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Send to My Mac, in a tab's menu (sync step 6).
    @Environment(Sending.self) private var sending: Sending?
    @Environment(\.scenePhase) private var scenePhase

    /// Counts closes, so the shake listener takes focus again after each.
    @State private var closes = 0

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
    @Environment(\.newSpace) private var newSpace
    @Environment(\.spaceSettings) private var spaceSettings
    /// The group being renamed (Rename from its menu).
    @State private var naming: TabGroup?
    @State private var name = ""
    @State private var lastDrop = Date.distantPast
    @State private var lifts = 0
    /// The grid on iOS 27: what iOS's drag is carrying, so its X hides
    /// (the lift is only the picture, as the menu's).
    @State private var systemDragged: Set<UUID> = []
    /// A group folding into its cell or opening out of it (the grid on
    /// iOS 27), drawn over the list until it's done (`GroupGlideView`),
    /// and how far open it's drawn (0 folded, 1 open).
    @State private var glide: GroupGlide?
    @State private var glideShare: CGFloat = 0
    /// The grid's UIKit cards being swiped to close (`GridCards`).
    @State private var gridSwipes: [UUID: GridSwipe] = [:]
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    /// Where the tab last opened from here sat in the list's view, so the
    /// page closes back into the same spot (David, 2026-11-13: "tabs should
    /// always close back to where they were opened from"). A card cut off
    /// at the top or behind the bar slides just into view instead.
    /// Scrolls the list while a held tab rests near its top or bottom.
    @State private var edgeScroll: Task<Void, Never>?
    /// A drag, or the moment after one: a finger lifting then would
    /// otherwise count as a tap.
    private var busy: Bool {
        drag != nil || finishing || Date.now.timeIntervalSince(lastDrop) < 0.35
    }
    /// Done was tapped and the tab on screen's group is opening first.
    @State private var finishing = false
    /// The overview softened once, for the landing (`FrozenOverview`), and
    /// the wait before the next picture is taken.
    @State private var frozen: FrozenOverview?
    /// Whether that picture was taken behind the page (`freezeSoon`).
    @State private var frozenBehind = false
    @State private var freezing: Task<Void, Never>?
    @State private var scrolling = false
    @Environment(\.colorScheme) private var colorScheme
    /// On iOS 27, iOS's own hold menu and drag to reorder
    /// (`OverviewGridReorder.swift`) instead of Firn's.
    private var systemDrag: Bool {
        if #available(iOS 27, *) { return true }
        return false
    }
    /// Where across the held card the finger took it (0 left, 1 right), so
    /// in the grid it follows the finger sideways as well as up and down.
    @State private var grabAcross: CGFloat = 0.5
    /// The overview's size, for the grid's columns and card height.
    @State private var size: CGSize = .zero
    private var gridMetrics: OverviewGridMetrics {
        OverviewGridMetrics(width: size.width, height: size.height)
    }
    /// A card's height in the grid.
    private var cardHeight: CGFloat { gridMetrics.cardHeight }

    /// Groups and loose tabs in the order shown: the store's, or the drag's
    /// while one moves.
    private var shownItems: [TabListItem] {
        let items = store.tabListItems
        guard let order else { return items }
        var byID = Dictionary(items.map { ($0.id, $0) }) { a, _ in a }
        // A grouped tab dragged out into the list.
        for tab in store.openTabs where byID[tab.id] == nil { byID[tab.id] = .tab(tab) }
        if let carried = carriedTile { byID[carried.id] = .tab(carried) }
        return order.compactMap { byID[$0] }
    }

    /// The tabs a group shows: all of them, or none while it's folded. The
    /// tab on screen's group opens with the overview, and again just before
    /// the page grows back (`finish`), so the page always has its card.
    /// During a drag, the drag's (a held tab may be on its way in or out).
    private func shownTabs(in group: TabGroup) -> [FirnCore.Tab] {
        if let ids = members?[group.id] {
            var byID = Dictionary(store.openTabs.map { ($0.id, $0) }) { a, _ in a }
            if let carried = carriedTile { byID[carried.id] = carried }
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
    /// Between the list's items: Basecamp, runs of loose tabs, and groups.
    private static let listSpacing: CGFloat = 12
    /// The room above the list's first item.
    private static let topMargin: CGFloat = 8
    var body: some View {
        ScrollViewReader { scroller in
            // A plain stack, not a List: List's own swipe can't follow the
            // finger and slide the row away the way Safari's does.
            ScrollView {
                // 12pt apart (David, 2026-11-05: 8 felt a little tight),
                // which also gives the ring around the tab on screen room.
                LazyVStack(spacing: Self.listSpacing) {
                    // Basecamp first, scrolling away with the list (hidden
                    // while empty); 24pt below it (its own 12pt plus this
                    // stack's 12pt).
                    BasecampTiles(store: store, spots: spots, landing: landing,
                                  onScreen: heldCard ?? store.activeTab?.id,
                                  order: tileOrder,
                                  held: drag?.tile == true ? drag?.id : nil,
                                  pressed: finger.pressed,
                                  incoming: drag?.basecamp == true ? drag?.id : nil,
                                  blank: blankSpot,
                                  away: drag?.tile == true && drag?.tabs == true ? drag?.id : nil,
                                  open: openCard,
                                  menu: { tileMenu(for: $0) },
                                  move: { tab, to in
                                      withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                                          store.move(tab, to: to)
                                      }
                                  })
                    gridTiles(shownItems)
                }
                // Where the list's contents start on screen, to place a
                // group's fold over them (`glidePlan`).
                .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).origin }) { spots.listOrigin = $0 }
                .overlay(alignment: .topLeading) { glideDrawing }
                .padding(.horizontal, 16)
                // Where the top of the list's view is on screen, below the
                // status bar and the top margin (the scroll view's own
                // space starts there), to turn a card's spot into the list's
                // offset (`scroll(to:)`). Not `spots.viewport`: the scroll
                // view runs up under the status bar, above its laid-out frame.
                .onGeometryChange(for: CGFloat.self, of: {
                    $0.frame(in: .global).minY - $0.frame(in: .scrollView).minY
                }) { spots.scrollTop = $0 }
                // The blank tile comes and goes with a glide, the list
                // moving down to make room and back up once it's let go.
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: blankSpot != nil)
                // Hold, then move, to lift a tab and drag it to a new place,
                // as in Safari: in the list, into a group, between groups,
                // or out; or hold a group's name line to move the whole
                // group. One gesture on the list, not one per tile: a tab
                // moving into or out of a group is rebuilt in its new place,
                // and a gesture on its tile went with the old one, ending
                // the drag under a finger still down (David's recording,
                // 2026-11-08).
                // The grid on iOS 27 leaves holds and drags to iOS.
                .modifier(GridReorderContainer(on: systemDrag, enabled: gliding == nil && !busy,
                                               dragging: { systemDragged = $0 }) { move in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { move.apply(to: store) }
                })
                .gesture(HoldToDrag(enabled: gliding == nil,
                                    canBegin: { firnHolds(liftable(at: $0)) != nil },
                                    began: lift(at:), moved: follow(to:),
                                    ended: { letGo(cancelled: $0) },
                                    wantsMenu: { menuTarget(at: $0) != nil },
                                    pressing: { point in
                                        finger.pressed = reduceMotion ? nil : point.flatMap { menuTarget(at: $0)?.id }
                                    },
                                    menu: openMenu(at:),
                                    menuEnded: { cancelled in if cancelled { closeMenu() } },
                                    leaveMenu: leaveMenu(to:from:)))
                // The list's fade, growth, and blur all on its contents, never
                // on the scroll view: the scroll view's frame ends at the bar's
                // top, and anything wrapped around it was cut there on David's
                // iPhone, so the cards under the bar showed only down to the
                // bar for the whole landing and popped in as it ended (his
                // recordings, 2026-11-13; first the blur, then the fade and
                // the growth; the Simulator draws them whole either way). The
                // contents run under the bar, so nothing is cut.
                // While a page is held, only the haze is behind it, as in
                // Safari: shown clearly behind a slow hold, the cards were
                // distracting (David, 2026-11-10). They come in as it's let go,
                // around the page while it flies (`listIn`), and leave first as
                // a tab opens. Tied to the glide's last stretch, they faded up
                // only after the page had landed (David's recording,
                // 2026-11-13). A hair above 0, so the cards' blur isn't dropped
                // and rebuilt mid-glide.
                .modifier(LandingBand(landing: landing, value: \.listIn, range: 0...1, floor: 0.002))
                .modifier(LandingUnderPicture(landing: landing, pictured: pictured))
                // Smaller only once a page is let go (the list is unseen
                // before): shrunk while hidden, the scroll view's turn to
                // the tab on screen (`getReady`) also slid it sideways, about
                // 12pt (Simulator, 2026-11-13).
                .modifier(LandingForward(landing: landing, middle: listMiddle, off: reduceMotion,
                                         scalesWithList: true, inScroll: true))
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.viewport = $0 }
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, now in
                spots.scroll = now
                // Behind the page, the list's turn to the tab on screen can
                // come after its picture was taken (just after launch, on
                // David's iPhone: the first close had no blur).
                if !shown, frozen.map({ abs($0.look.scroll - now.contentOffset.y) > FrozenOverview.Look.scrollGive }) ?? false {
                    freezeSoon()
                }
                // The list only ever scrolls up and down, but SwiftUI runs a
                // request by id again as the layout changes, and each run
                // slid it sideways toward centering a grouped tab's card
                // (`scroll(to:)`). Put straight back, where it stands.
                if abs(now.contentOffset.x) > 0.5 {
                    scrollPosition.scrollTo(point: Self.pin(now.contentOffset.y, in: now))
                }
            }
            // A new picture for the landing once a scroll comes to rest.
            .onScrollPhaseChange { _, phase in
                scrolling = phase != .idle
                if !scrolling { freezeSoon() }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: lifts)
            .sensoryFeedback(.impact(weight: .light), trigger: forms)
            .sensoryFeedback(.impact(weight: .light), trigger: picks)
            .sensoryFeedback(.impact(weight: .light), trigger: pulls)
            .contentMargins(.top, Self.topMargin, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // The other cards wait behind a dim that lifts as the page
            // shrinks into its card.
            .overlay { LandingDim(landing: landing) }
            .overlay {
                if store.openTabs.isEmpty {
                    // Muted, centered across and a little above the middle
                    // (optical center): the wash deepens toward the bottom,
                    // and at the true middle Clay in light dipped to 4.4:1
                    // through the grain. Here every space color passes 4.5:1.
                    GeometryReader { proxy in
                        Text("No open tabs")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.38)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OverviewBar(space: store.activeSpace, spaces: store.spaces, newTab: newTab, done: finish,
                            select: showSpace(_:), newSpace: newSpace, spaceSettings: spaceSettings)
                    // In over the glide's second half, once the page's bar
                    // is gone (see BrowserScreen's bar), never both at once;
                    // a hair above 0 while gliding keeps its glass ready.
                    .modifier(LandingBand(landing: landing, value: \.arrival, range: 0.55...1,
                                          glidingFloor: 0.002, off: typing))
                    .modifier(LandingUnderPicture(landing: landing, pictured: pictured))
                    .modifier(LandingForward(landing: landing, middle: screenMiddle, off: reduceMotion))
            }
            // Ready before it shows: sizes taken, the tidy read, and scrolled
            // to the tab on screen, so the page's card is in place the
            // moment a swipe up starts. Again as it shows (as when it was
            // built on each opening), and while hidden whenever the tab or
            // space on screen changes.
            .onAppear {
                getReady(scroller)
                freezeSoon()
            }
            .onChange(of: shown) { _, now in
                if !now { forgetOpening() }
                getReady(scroller)
            }
            .onChange(of: store.activeTab?.id) { if !shown { getReady(scroller) } }
            .onChange(of: store.activeSpace.id) { if !shown { getReady(scroller) } }
        }
        // As a tab lands, the overview's picture covers the list and bar,
        // its blur shrinking to nothing, growing and brightening with them,
        // then they take over (`FrozenOverview`); without an up-to-date
        // picture, no blur at all.
        .overlay {
            if let frozen, pictured {
                LandingFrozen(landing: landing, image: frozen.image, pad: frozen.pad, middle: screenMiddle)
            }
        }
        .background {
            LandingRest(landing: landing, still: shown && drag == nil && heldMenu == nil && !typing && !scrolling,
                        rested: freezeSoon)
        }
        .onChange(of: look(scroll: 0)) { freezeSoon() }
        // Hidden again: a picture from behind the page, once it's still.
        .onChange(of: shown) { freezeSoon() }
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
            // The space wash: the space's color, as the Mac's tinted frame.
            SpaceWash(space: space)
        }
        // Only while shown: it takes the keyboard's focus to hear a shake.
        .background { if shown { ShakeToUndo(undoManager: undoManager, closes: closes) } }
        .basecampFullAlert(isPresented: $basecampFull)
        // Firn leaving the screen closes an open hold menu, as iOS's do;
        // its frost is a picture of the screen as it opened.
        .onChange(of: scenePhase) { _, now in if now != .active { closeMenu() } }
        // A link-made group down to one tab goes as Ungroup's does: the
        // same glide (David, 2026-11-13). Out of view, the store ends it.
        .onChange(of: store.endingGroupIDs) { _, ending in
            for group in store.tabGroups where ending.contains(group.id) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { _ = store.finishEnding(group) }
            }
        }
        .alert("Rename Group",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Done") {
                if let naming { store.rename(naming, to: name) }
            }
        }
    }

    /// There's a picture of the overview as it is now, for the landing.
    private var pictured: Bool {
        guard let frozen, !reduceMotion else { return false }
        return frozen.look.matches(look())
    }

    /// Settled on screen: nothing moving, held, or open over it.
    private var atRest: Bool {
        shown && gliding == nil && landing.arrival >= 1 && landing.focus >= 1 && heldCard == nil && drag == nil
            && heldMenu == nil && !typing && !scrolling
    }

    /// What the overview shows now, for `FrozenOverview` (its scroll from
    /// `spots`, which isn't observed; `scroll` stands in where only the
    /// rest matters).
    private func look(scroll: CGFloat? = nil) -> FrozenOverview.Look {
        let tabs = store.openTabs
        return FrozenOverview.Look(
            space: store.activeSpace.id,
            onScreen: store.activeTab?.id,
            tabs: tabs.map(\.id),
            groups: Dictionary(store.tabGroups.map { ($0.id, $0.folded) }) { a, _ in a },
            grouped: Dictionary(tabs.compactMap { tab in tab.groupID.map { (tab.id, $0) } }) { a, _ in a },
            tiles: store.basecampTabs.map(\.id),
            scroll: scroll ?? (spots.scroll?.contentOffset.y ?? 0).rounded(),
            dark: colorScheme == .dark)
    }

    /// Takes the landing's picture once the overview has been still a
    /// moment, unless the last one still matches. On screen, as it is.
    /// Behind the page (step 1b: it changed there, or Firn just launched),
    /// it's first laid out in its settled look (`Landing.posed`), unseen,
    /// for the few frames the picture needs; a swipe up or the tabs button
    /// in that moment ends the pose and the picture is dropped.
    private func freezeSoon() {
        freezing?.cancel()
        guard !reduceMotion else { return }
        let shown = shown
        freezing = Task {
            // Behind the page there's less to wait out, and a tab is often
            // closed within a second of opening (David's recording,
            // 2026-11-19: no picture yet, so no blur).
            try? await Task.sleep(for: .milliseconds(shown ? 350 : 120))
            guard !Task.isCancelled else { return }
            let now = look()
            // One taken behind the page has an empty place for the tab on
            // screen, one taken on screen has every card: each only serves
            // where it was taken.
            if frozen?.look == now, frozenBehind == !shown { return }
            if shown {
                guard atRest else { return }
            } else {
                guard hiddenAtRest else { return }
                landing.posed = true
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, landing.posed, hiddenAtRest, look() == now else {
                    landing.unpose()
                    return
                }
            }
            let picture = canvas.take()
            if !shown { landing.unpose() }
            guard let picture else { return }
            if let made = await FrozenOverview.make(from: picture, look: now), !Task.isCancelled {
                frozen = made
                frozenBehind = !shown
            }
        }
    }

    /// Behind the page with nothing moving: no landing, no pull, Firn in
    /// front.
    private var hiddenAtRest: Bool {
        landing.gliding == nil && landing.heldCard == nil && landing.arrival <= 0 && landing.listIn <= 0
            && !typing && UIApplication.shared.applicationState == .active
    }

    /// What an opening takes as it starts: the list scrolled to the tab on
    /// screen.
    private func getReady(_ scroller: ScrollViewProxy) {
        guard let id = store.activeTab?.id else { return }
        scroll(to: id, scroller)
    }

    /// Scrolls the list so the tab's card has its middle a third of the way
    /// down the list's view, as Safari lands a tab (David's recording,
    /// 2026-11-14: wherever it was opened from), but never past either end
    /// of the list, so a tab near the end lands whole above the bar.
    /// The spot is worked out here, kept between the list's ends: asked by
    /// id for a spot past the end, SwiftUI stopped at the end at first but
    /// carried the request out later, past it (the card's old spot aimed
    /// at, a snap as it landed; his recording, 2026-11-14).
    /// A spot out of view (not laid out, or its spot from an older scroll)
    /// is first scrolled to by id. Then, a frame at a time, the spot is
    /// worked out again from what the list shows and set as the list's own
    /// position, until the card is there (`tries`).
    private func scroll(to id: UUID, _ scroller: ScrollViewProxy, asked: Bool = false, tries: Int = 4) {
        func again(asked: Bool) {
            guard tries > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                scroll(to: id, scroller, asked: asked, tries: tries - 1)
            }
        }
        // The card's spot where it's laid out in view; or, for a loose card
        // out of view, worked out from its run's (`looseSpot`).
        let seen: (frame: CGRect, scroll: ScrollGeometry, scrollTop: CGFloat)? = {
            guard let scroll = spots.scroll, let scrollTop = spots.scrollTop else { return nil }
            let inView: (CGRect) -> Bool = { $0.maxY > scrollTop && $0.minY < scrollTop + scroll.containerSize.height }
            let loose = looseSpot(of: id)
            if let frame = spots.frames[id], inView(frame) { return (frame, scroll, scrollTop) }
            if let loose, let run = spots.runs[loose.run], inView(run) {
                return (CGRect(x: run.minX, y: run.minY + loose.top, width: run.width, height: loose.height),
                        scroll, scrollTop)
            }
            return nil
        }()
        guard let (frame, scroll, scrollTop) = seen else {
            // Nothing in view to measure from: to the card's run (the list
            // can't look a loose card up by id), or to the card itself.
            if let loose = looseSpot(of: id) {
                scroller.scrollTo(loose.run, anchor: .top)
            } else {
                scroller.scrollTo(id, anchor: .center)
            }
            again(asked: false)
            return
        }
        // The list's view runs from below the status bar and top margin
        // down to the bar (`containerSize` is already that tall): where the
        // card's top is in it now, and where a third puts it.
        let view = scroll.containerSize.height
        let now = frame.minY - scrollTop
        let wanted = max(view / 3 - frame.height / 2, 0)
        let lowest = -scroll.contentInsets.top
        let highest = max(lowest, scroll.contentSize.height - view - scroll.contentInsets.top)
        let y = min(max(scroll.contentOffset.y + now - wanted, lowest), highest)
        // The list's position as a point counts from the top inset's start,
        // the offset from its end (`Self.pin`).
        let point = Self.pin(y, in: scroll)
        guard abs(y - scroll.contentOffset.y) > 0.5 else {
            // There. Set as the list's position too, which takes the place
            // of a request by id: SwiftUI keeps one and does it again
            // whenever the layout changes, up and down and sideways (toward
            // centering the card across, so a tab in an open group's column
            // left the whole overview 16 to 23pt off to the side; Simulator,
            // logged, 2026-11-18). Left live, it ran again as a grouped tab
            // landed and the list jumped (David's recording, 2026-11-19).
            if asked || abs(scroll.contentOffset.x) > 0.5 { scrollPosition.scrollTo(point: point) }
            return
        }
        if asked {
            // The request by id stopped short (it's worked out from the
            // lazy list's guess at its own height): the rest of the way as
            // a point, which a hidden list carries out after such a request.
            scrollPosition.scrollTo(point: point)
        } else {
            // Asked by id first, with the anchor that puts the card there.
            // `scrollPosition.scrollTo(y:)` alone was taken but never
            // carried out while the overview was hidden, and asked again
            // with the same offset as it showed, it was dropped as nothing
            // new: the last tab came back half under the bar (David's
            // recording, 2026-11-14). `scrollTo(id:)` lines the card's
            // anchor up with the same point of the scroll view's whole
            // height, the status bar and top margin included.
            let region = view + scroll.contentInsets.top
            let top = now - (y - scroll.contentOffset.y) + scroll.contentInsets.top
            let unit = min(max(top / max(region - frame.height, 1), 0), 1)
            scroller.scrollTo(id, anchor: UnitPoint(x: 0.5, y: unit))
        }
        again(asked: true)
    }

    /// A loose card's run in UIKit's grid and the card's place in it: how
    /// far below the run's top, and how tall. Loose cards are cells of a
    /// collection view, which the SwiftUI list can't look up by id, and a
    /// cell out of view has no spot of its own: the last of many tabs was
    /// never scrolled to, so the overview opened at the top with no card
    /// for its page to land in (Simulator, 2026-11-19). Nil for a grouped
    /// tab, a tile, and the SwiftUI grid, whose cards the list knows.
    private func looseSpot(of id: UUID) -> (run: String, top: CGFloat, height: CGFloat)? {
        guard systemDrag else { return nil }
        let metrics = gridMetrics
        for run in OverviewGridRun.runs(shownItems, inRun: { folderCell($0) }) {
            guard case let .tabs(_, entries) = run, let place = entries.firstIndex(where: { $0.id == id }) else { continue }
            let row = CGFloat(place / max(metrics.columns, 1))
            return (run.id, row * (metrics.cardHeight + OverviewGridMetrics.rowSpacing), metrics.cardHeight)
        }
        return nil
    }

    /// The list's position, as `scrollPosition` takes a point, for an
    /// offset: a point counts from where the top inset starts, the offset
    /// from where it ends. Set without the inset, the list landed that far
    /// up: about 70pt on David's iPhone, each time a sideways slip was put
    /// right (his recording, 2026-11-19).
    private static func pin(_ y: CGFloat, in scroll: ScrollGeometry) -> CGPoint {
        CGPoint(x: 0, y: y + scroll.contentInsets.top)
    }

    /// Opens a tab.
    private func openCard(_ tab: FirnCore.Tab) {
        guard !busy else { return }
        open(tab)
    }

    /// Hidden: everything a visit leaves behind goes, as when the
    /// overview was built afresh for each one (a hold, a menu, a drag and
    /// its moved order, a forming group, a rename).
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
        naming = nil
        basecampFull = false
    }

    /// The held tab, lifted over the list and following the finger.
    @ViewBuilder private var liftedTile: some View {
        ZStack {
            if let drag {
                if drag.tile, let tab = store.basecampTabs.first(where: { $0.id == drag.id })
                    ?? store.openTabs.first(where: { $0.id == drag.id }) {
                    // Carried down into the tabs, it becomes a card: the
                    // tile fades as the card comes through (step 1 the
                    // other way). Once let go there it's an open tab.
                    let shaped = !drag.tabs
                    LiftedTile(finger: finger, height: drag.height, lifted: drag.lifted) {
                        BasecampTiles.lifted(tab, space: space,
                                             onScreen: tab.id == (heldCard ?? store.activeTab?.id),
                                             solid: drag.lifted)
                            .opacity(shaped ? 1 : 0)
                            .modifier(ReduceMotionFade(value: shaped))
                            .overlay {
                                ScaledRow(size: drag.rowSize) { tile(tab, spot: { _ in }) }
                                    .mask {
                                        RoundedRectangle(cornerRadius: OverviewRow.cornerRadius, style: .continuous)
                                            .padding(shaped ? 0 : -40)
                                    }
                                    .opacity(shaped ? 0 : 1)
                                    .modifier(ReduceMotionFade(value: shaped))
                            }
                    }
                    .transition(.identity)
                } else if let tab = store.openTabs.first(where: { $0.id == drag.id }) {
                    // Carried up over Basecamp, it becomes a tile: the row
                    // fades as the tile comes through, and the shape glides.
                    let shaped = drag.basecamp
                    LiftedTile(finger: finger, height: shaped ? drag.tileSize.height : drag.start.height,
                               lifted: drag.lifted) {
                        // The tile sets the size and the row lies over it:
                        // a card keeps its own height, and side by side in
                        // a stack it held the tile at a card's height, a
                        // tall narrow block (David's recording, 2026-11-12).
                        BasecampTiles.lifted(tab, space: space, onScreen: isOnScreen(tab),
                                             solid: drag.lifted)
                            .opacity(shaped ? 1 : 0)
                            .modifier(ReduceMotionFade(value: shaped))
                            .overlay {
                                ScaledRow(size: drag.rowSize) { tile(tab, spot: { _ in }) }
                                    // Kept to the shrinking shape; loose
                                    // otherwise, so nothing of a row is cut.
                                    .mask {
                                        RoundedRectangle(cornerRadius: OverviewRow.cornerRadius, style: .continuous)
                                            .padding(shaped ? 0 : -40)
                                    }
                                    .opacity(shaped ? 0 : 1)
                                    .modifier(ReduceMotionFade(value: shaped))
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

    private func isOnScreen(_ tab: FirnCore.Tab) -> Bool {
        tab.id == (heldCard ?? store.activeTab?.id)
    }

    /// A tab's tile: in the list, or lifted under the finger.
    private func tile(_ tab: FirnCore.Tab, spot: @escaping (CGRect) -> Void, at index: Int? = nil,
                      moveUp: (() -> Void)? = nil, moveDown: (() -> Void)? = nil,
                      holdMenu: (() -> [[HoldMenuItem]])? = nil, inCollection: Bool = false,
                      height: CGFloat? = nil, bare: Bool = false, titled: Bool = true) -> some View {
        let onScreen = isOnScreen(tab)
        return OverviewRow(
            tab: tab,
            isOnScreen: onScreen,
            pictures: pictures,
            readsDisk: onScreen && shown,
            loadPicture: { await pictures.loadImage(for: tab.id) },
            space: space,
            // Posed behind the page for its picture, the tab on screen's
            // card is empty: that tab is the page, in the hand or about to
            // fly, so it isn't also in the grid (Safari's; David, 2026-11-20).
            windowShown: gliding != tab.id && (!onScreen || (landing.lineShown && !(landing.posed && !shown))),
            open: { openCard(tab) },
            close: { if !busy { close(tab) } },
            spot: spot,
            moveUp: moveUp,
            moveDown: moveDown,
            // From every group directly: `tabGroups` walks the whole tab
            // list, and this runs for every tile on every redraw.
            groupName: tab.groupID.flatMap { id in store.groups.first(where: { $0.id == id })?.name },
            actionsKey: [index ?? -1, reduceMotion ? 1 : 0],
            cardHeight: height ?? cardHeight,
            holdMenu: holdMenu,
            carried: systemDragged.contains(tab.id),
            bare: bare,
            titled: titled,
            swipesItself: !inCollection,
            gridSwipe: gridSwipes[tab.id] ?? .none
        )
        // Runs again only when what it shows changes (`OverviewRow.==`).
        .equatable()
    }

    /// The grid: loose tabs as cards in columns, each run between open
    /// groups one grid; a folded group one card's size among them (UIKit's
    /// grid only), an open group a full-width folder card, its tabs a grid
    /// inside it.
    @ViewBuilder private func gridTiles(_ items: [TabListItem]) -> some View {
        let metrics = gridMetrics
        let inRun: @MainActor (TabGroup) -> Bool = { group in folderCell(group) }
        ForEach(OverviewGridRun.runs(items, inRun: { systemDrag && folderCell($0) })) { run in
            switch run {
            case let .tabs(after, entries) where systemDrag:
                // UIKit's collection view: iOS's menu and iOS's drag, the
                // card full size as it's carried (`OverviewGridCards.swift`).
                let byID = Dictionary(entries.map { ($0.id, $0) }) { a, _ in a }
                GridCards(ids: entries.map(\.id), columns: metrics.columns, cardHeight: metrics.cardHeight,
                          card: { id in
                              guard let entry = byID[id] else { return AnyView(EmptyView()) }
                              if let group = entry.group {
                                  return AnyView(folder(group, at: entry.index, of: items.count))
                              }
                              guard let tab = entry.tab else { return AnyView(EmptyView()) }
                              return AnyView(gridCell(tab, at: entry.index, of: items.count))
                          },
                          menu: { id in
                              guard let entry = byID[id] else { return [] }
                              if let group = entry.group { return groupMenu(group).sections }
                              return entry.tab.map { menu(for: $0) } ?? []
                          },
                          held: { id, held in
                              withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                  if held { systemDragged.insert(id) } else { systemDragged.remove(id) }
                              }
                          },
                          move: { id, before in
                              GridMove(sources: [id], collection: .loose(after: after), before: before,
                                       inRun: inRun).apply(to: store)
                          },
                          swipe: { id, phase in
                              // The title and X go quickly as the swipe starts
                              // and come back on the card's ease home.
                              let ease: Animation? = switch phase {
                              case .swiping: .smooth(duration: 0.2)
                              case .easingHome: .smooth(duration: 0.45)
                              case .none: nil
                              }
                              withAnimation(reduceMotion ? nil : ease) {
                                  gridSwipes[id] = phase == .none ? nil : phase
                              }
                          },
                          close: { id in
                              if !busy, let tab = byID[id]?.tab { close(tab) }
                          },
                          swipes: { id in byID[id]?.tab != nil },
                          isFolder: { id in byID[id]?.group != nil },
                          join: { id, groupID in
                              guard let tab = byID[id]?.tab, let group = byID[groupID]?.group else { return }
                              store.move(tab, toGroup: group, at: store.tabs(in: group).count)
                          },
                          fold: glide?.token,
                          reduceMotion: reduceMotion)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.runs[run.id] = $0 }
                // A run that comes or goes with a fold: its cards glide on
                // their own (`GridCards`), so the run itself doesn't fade.
                .transition(.identity)
            case let .tabs(after, entries):
                let tabs = entries.compactMap { entry in entry.tab.map { (index: entry.index, tab: $0) } }
                LazyVGrid(columns: metrics.gridItems, spacing: OverviewGridMetrics.rowSpacing) {
                    let cards = ForEach(tabs.map { GridEntry(id: $0.tab.id, index: $0.index, tab: $0.tab) }) { entry in
                        if let tab = entry.tab { listTile(tab, at: entry.index, of: items.count, loose: true) }
                    }
                    if systemDrag, #available(iOS 27, *) {
                        cards.reorderable(collectionID: GridCollection.loose(after: after))
                    } else {
                        cards
                    }
                }
            case let .group(index, group):
                // Safari's room around an open group (`GroupCard.gapAbove`),
                // on top of the list's 12pt: more under a row of titles
                // than under another group or at the top.
                groupTiles(group, at: index, of: items.count)
                    .padding(.top, systemDrag && underTabs(items, at: index) ? GroupCard.gapAbove - Self.listSpacing : 0)
                    .padding(.bottom, systemDrag ? GroupCard.gapBelow - Self.listSpacing : 0)
            }
        }
    }

    /// Whether the item before this one is a row of cards (loose tabs or a
    /// folded group's cell), not an open group or the list's top.
    private func underTabs(_ items: [TabListItem], at index: Int) -> Bool {
        guard index > 0 else { return false }
        switch items[index - 1] {
        case .tab: return true
        case let .group(other): return folderCell(other)
        }
    }

    /// A folded group sits in the grid as one card's size (`GroupFolder`),
    /// unless it shows a tab (the tab on screen's, or a drag's).
    private func folderCell(_ group: TabGroup) -> Bool {
        group.folded && shownTabs(in: group).isEmpty
    }

    /// A folded group's cell: a tap opens it; VoiceOver's moves and the
    /// group's menu as actions.
    private func folder(_ group: TabGroup, at index: Int, of count: Int) -> some View {
        GroupFolder(group: group, tabs: store.tabs(in: group), pictures: pictures,
                    cardHeight: cardHeight, naming: store.isNaming(group), open: { fold(group) })
            .modifier(groupMenu(group).actions)
            // Drawn over the list while it folds or opens (`glideDrawing`).
            .opacity(glide?.hidden.contains(group.id) == true ? 0 : 1)
            .accessibilityActions {
                if index > 0 { Button("Move Left") { move(group, to: index - 1) } }
                if index < count - 1 { Button("Move Right") { move(group, to: index + 1) } }
            }
    }

    /// A loose card in UIKit's grid (`GridCards`): its menu and drag are
    /// the collection view's, so none of the list's holds or SwiftUI's.
    private func gridCell(_ tab: FirnCore.Tab, at index: Int, of count: Int) -> some View {
        let spot: (CGRect) -> Void = { frame in
            spots.frames[tab.id] = frame
            spots.cards.insert(tab.id)
        }
        return tile(tab, spot: spot, at: index,
                    moveUp: index > 0 ? { move(tab, to: index - 1) } : nil,
                    moveDown: index < count - 1 ? { move(tab, to: index + 1) } : nil,
                    inCollection: true)
            // Changing grids as a group folds or opens: drawn over the list
            // on its way (`glideDrawing`).
            .opacity(glide?.hidden.contains(tab.id) == true ? 0 : 1)
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
            // Where it's laid out, to bring it to the middle as it opens
            // (`center`).
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.openGroups[group.id] = $0 }
            // Folding or opening, it's drawn over the list (`glideDrawing`).
            .opacity(glide?.id == group.id ? 0 : 1)
            .id(group.id)
            .transition(groupTransition(group))
    }

    /// How an open group comes and goes: with a fade, but at once while
    /// its fold or unfold is drawn over the list (`glideDrawing`), or while
    /// it's dragged.
    private func groupTransition(_ group: TabGroup) -> AnyTransition {
        drag != nil || glide?.id == group.id ? .identity : .opacity
    }

    /// A group's tint, name line, and tabs: in the list, or `lifted` under
    /// the finger (a picture only: no spots, menus, or gestures).
    private func groupCard(_ group: TabGroup, lifted: Bool, moves: GroupMoves = GroupMoves()) -> some View {
        let tabs = shownTabs(in: group)
        let closed = group.folded && tabs.isEmpty
        // Grouped tabs move within their group, and only while it shows
        // them all: folded, the one tab showing would skip past hidden ones.
        let movable = !lifted && tabs.count == store.tabs(in: group).count
        // The grid on iOS 27: the name line and the tabs are iOS's to hold
        // and drag (`OverviewGridReorder.swift`).
        let system = systemDrag && !lifted
        return VStack(spacing: 0) {
            let line = GroupLine(group: group, height: closed ? GroupCard.foldedHeight : GroupCard.headerHeight,
                                 naming: store.isNaming(group), toggle: { fold(group) },
                                 icons: closed ? store.tabs(in: group) : [])
                // Hold the name line, then move, to drag the whole group
                // to a new place, as a tab drags (the list's HoldToDrag);
                // holding still opens its menu.
                .modifier(groupMenu(group).actions)
                .modifier(GroupMoveActions(moves: moves))
            if system, #available(iOS 27, *) {
                // A collection of one, so the folder can be moved by its
                // name line, and its menu there.
                ForEach([GridEntry(id: group.id, index: 0, tab: nil)]) { _ in
                    line.systemHoldMenu(true, shape: RoundedRectangle(cornerRadius: GroupCard.cornerRadius,
                                                                      style: .continuous)) {
                        groupMenu(group).sections
                    }
                }
                .reorderable(collectionID: GridCollection.line(group.id))
            } else {
                line
            }
            // The header's own 44pt sets the room above the first tab.
            let groupTabs = ForEach(tabs.enumerated().map { GridEntry(id: $0.element.id, index: $0.offset,
                                                                      tab: $0.element) }) { entry in
                if let tab = entry.tab {
                    if lifted {
                        tile(tab, spot: { _ in }, height: gridMetrics.groupCardHeight)
                    } else {
                        listTile(tab, at: movable ? entry.index : nil, of: tabs.count, loose: false)
                    }
                }
            }
            // Opened, a folder shows its tabs as a grid inside it, the same
            // columns as outside, at Safari's spacing (`GroupCard`).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GroupCard.columnGap,
                                                         alignment: .top),
                                     count: gridMetrics.columns),
                      spacing: GroupCard.rowGap) {
                if system, #available(iOS 27, *) {
                    groupTabs.reorderable(collectionID: GridCollection.tabs(group.id))
                } else {
                    groupTabs
                }
            }
        }
        .padding(.horizontal, GroupCard.side)
        .padding(.bottom, closed ? 0 : GroupCard.bottom)
        // Folding cards are cut off by the tint closing over them.
        .modifier(FoldMask(on: !system))
        .background {
            GroupCard(space: space)
                // The card around the tab on screen gathers as the page
                // shrinks into its card, fully there as it lands. Fading in
                // only after it landed lagged (David, 2026-11-08: "could be
                // a little snappier").
                .modifier(LandingGroupFade(landing: landing,
                                           holdsOnScreen: !lifted && tabs.contains(where: isOnScreen)))
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
        // One fold at a time: a tap during a glide waits for the next.
        if systemDrag, glide != nil { return }
        let folding = !group.folded
        // The list stays where it is. SwiftUI keeps the last scroll to the
        // tab on screen by id and does it again on any layout change, so a
        // fold or unfold jumped the list toward that tab (David's
        // recording, 2026-11-18; Simulator, frame by frame). Pinned to its
        // offset now, that request is gone.
        // The point is from the content's top, past the top inset; the
        // offset alone moved the list 70pt (Simulator, logged).
        if let scroll = spots.scroll {
            scrollPosition.scrollTo(point: CGPoint(x: 0, y: scroll.contentOffset.y + scroll.contentInsets.top))
        }
        if folding {
            for tab in store.tabs(in: group) {
                spots.frames[tab.id] = nil
                spots.cards.remove(tab.id)
            }
        }
        // The grid on iOS 27: the group shrinks into its cell, or grows
        // out of it, as Safari's (David, 2026-11-18), drawn over the list
        // (`glideDrawing`). The drawing shows first, as things are; then
        // the list changes under it on the same curve (`startGlide`).
        if systemDrag {
            if !reduceMotion, let plan = glidePlan(group, folding: folding) {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    glideShare = folding ? 1 : 0
                    glide = plan
                }
                // If the drawing never shows (it always has), nothing is
                // left hidden.
                Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    if glide == plan, let now = store.tabGroups.first(where: { $0.id == plan.id }),
                       now.folded != folding {
                        store.setFolded(now, folding)
                    }
                    endGlide(plan)
                }
                return
            }
            // Reduce Motion, or nowhere to draw it from: a cross-fade.
            withAnimation(.easeOut(duration: 0.2)) { store.setFolded(group, folding) }
            if !folding { center(group) }
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.setFolded(group, folding) }
    }

    /// The drawing of a fold is up: the list changes under it and the
    /// drawing glides, in one animation, so nothing is a frame apart.
    private func startGlide(_ plan: GroupGlide) {
        guard glide == plan, let group = store.tabGroups.first(where: { $0.id == plan.id }),
              group.folded == plan.opening else { return endGlide(plan) }
        withAnimation(.spring(duration: GridCards.morphDuration, bounce: 0), completionCriteria: .removed) {
            store.setFolded(group, !plan.opening)
            glideShare = plan.opening ? 1 : 0
        } completion: {
            endGlide(plan)
        }
        if plan.opening { center(plan) } else { reveal(plan) }
    }

    /// A folded group's cell stays in view: folding one near the top or
    /// bottom of the screen could leave its folder under the clock or the
    /// bar, so the list scrolls just enough to show it, on the fold's own
    /// curve, as Safari's.
    private func reveal(_ plan: GroupGlide) {
        guard let origin = spots.listOrigin, let scroll = spots.scroll, let scrollTop = spots.scrollTop else { return }
        let view = scroll.containerSize.height - scroll.contentInsets.top - scroll.contentInsets.bottom
        let top = plan.cell.minY + origin.y - scrollTop
        let bottom = top + plan.cardHeight
        var move: CGFloat = 0
        if top < Self.centerMargin {
            move = top - Self.centerMargin
        } else if bottom > view - Self.centerMargin {
            move = min(bottom - (view - Self.centerMargin), top - Self.centerMargin)
        }
        let y = max(scroll.contentOffset.y + move, -scroll.contentInsets.top)
        guard abs(y - scroll.contentOffset.y) > 0.5 else { return }
        Task { @MainActor in
            // A frame later, once the list has its new height, as `center`.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(duration: GridCards.morphDuration, bounce: 0)) {
                scrollPosition.scrollTo(point: CGPoint(x: 0, y: y + scroll.contentInsets.top))
            }
        }
    }

    /// The glide is over: the real folder or group, already in place under
    /// the drawing, shows again.
    private func endGlide(_ plan: GroupGlide) {
        guard glide == plan else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { glide = nil }
    }

    /// A fold or unfold drawn over the list (`GroupGlideView`).
    @ViewBuilder private var glideDrawing: some View {
        if let glide, let group = store.tabGroups.first(where: { $0.id == glide.id }) {
            let tabs = Dictionary(store.openTabs.map { ($0.id, $0) }) { a, _ in a }
            let groups = Dictionary(store.tabGroups.map { ($0.id, $0) }) { a, _ in a }
            GroupGlideView(glide: glide, share: glideShare, name: group.name,
                           tile: { id, height, bare in
                               tabs[id].map { tile($0, spot: { _ in }, height: height, bare: bare, titled: false) }
                           },
                           title: { id in tabs[id].map { GridTitle(tab: $0) } },
                           cell: { id in
                               if let tab = tabs[id] {
                                   tile(tab, spot: { _ in }, inCollection: true)
                               } else if let other = groups[id] {
                                   GroupFolder(group: other, tabs: store.tabs(in: other), pictures: pictures,
                                               cardHeight: cardHeight, naming: store.isNaming(other), open: {})
                               }
                           })
                .onAppear { startGlide(glide) }
                .id(glide.token)
                .transition(.identity)
        }
    }

    /// Where a fold or unfold starts and ends, worked out from the grid's
    /// own measures before anything moves: the folder's cell, the open
    /// card, and the cards after the group, which change grids. In the
    /// list's own space. Nil when the group isn't on screen to start from.
    private func glidePlan(_ group: TabGroup, folding: Bool) -> GroupGlide? {
        guard let origin = spots.listOrigin else { return nil }
        let tabs = store.tabs(in: group)
        let metrics = gridMetrics
        let columns = max(metrics.columns, 1), height = metrics.cardHeight
        let tileHeight = metrics.groupCardHeight
        let width = size.width - 2 * OverviewGridMetrics.margin
        guard !tabs.isEmpty, width > 0 else { return nil }
        let column = (width - OverviewGridMetrics.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        // A cell in a run of the grid whose first row starts at `top`.
        func cell(_ index: Int, top: CGFloat) -> CGRect {
            CGRect(x: CGFloat(index % columns) * (column + OverviewGridMetrics.spacing),
                   y: top + CGFloat(index / columns) * (height + OverviewGridMetrics.rowSpacing),
                   width: column, height: height)
        }
        func runHeight(_ count: Int) -> CGFloat {
            let rows = CGFloat((count + columns - 1) / columns)
            return rows * height + max(rows - 1, 0) * OverviewGridMetrics.rowSpacing
        }
        let runs = OverviewGridRun.runs(shownItems, inRun: { folderCell($0) })
        var folder: CGRect, card: CGRect, after: [GridRunItem], first: Int, top: CGFloat
        var row: [GridRunItem]
        if folding {
            guard let at = runs.firstIndex(where: { $0.id == group.id.uuidString }),
                  let open = spots.frames[group.id] else { return nil }
            card = open.offsetBy(dx: -origin.x, dy: -origin.y)
            var before: [GridRunItem] = []
            if at > 0, case let .tabs(_, items) = runs[at - 1] { before = items }
            after = []
            if at + 1 < runs.count, case let .tabs(_, items) = runs[at + 1] { after = items }
            first = before.count
            top = before.isEmpty ? card.minY : card.minY - GroupCard.gapAbove - runHeight(before.count)
            folder = cell(first, top: top)
            row = Array(before[(first / columns * columns)...])
        } else {
            var found: (items: [GridRunItem], at: Int)?
            for run in runs {
                if case let .tabs(_, items) = run, let at = items.firstIndex(where: { $0.id == group.id }) {
                    found = (items, at)
                }
            }
            guard let found, let seen = GridCards.framesOnScreen()[group.id] else { return nil }
            first = found.at
            after = Array(found.items[(first + 1)...])
            let seenTop = seen.minY - origin.y
            top = seenTop - CGFloat(first / columns) * (height + OverviewGridMetrics.rowSpacing)
            folder = cell(first, top: top)
            row = Array(found.items[(first / columns * columns)..<first])
            let rows = CGFloat((tabs.count + columns - 1) / columns)
            card = CGRect(x: 0, y: first == 0 ? top : top + runHeight(first) + GroupCard.gapAbove, width: width,
                          height: GroupCard.headerHeight + rows * tileHeight + max(rows - 1, 0) * GroupCard.rowGap
                              + GroupCard.bottom)
        }
        folder.size.height = max(height - OverviewRow.gridTitleHeight, 1)
        // What's in view, with room for the list scrolling as it opens.
        let view = spots.viewport.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 0, dy: -500)
        var plan = GroupGlide(id: group.id, opening: !folding, cell: folder, card: card, tabs: [],
                              columns: columns, cardHeight: height, tileHeight: tileHeight,
                              arrivals: [], stays: [], hidden: [])
        let drawn = tabs.enumerated().filter { index, _ in
            index < 4 || plan.tile(index).offsetBy(dx: card.minX, dy: card.minY).intersects(view)
        }.prefix(16).map(\.element.id)
        let arrivals = after.enumerated().map { index, item in
            GroupGlide.Arrival(id: item.id, folded: cell(first + 1 + index, top: top),
                               open: cell(index, top: card.maxY + GroupCard.gapBelow))
        }
        let rowStart = first / columns * columns
        let stays = row.enumerated().map { index, item in
            let spot = cell(rowStart + index, top: top)
            return GroupGlide.Arrival(id: item.id, folded: spot, open: spot)
        }
        plan = GroupGlide(id: group.id, opening: !folding, cell: folder, card: card, tabs: drawn,
                          columns: columns, cardHeight: height, tileHeight: tileHeight,
                          arrivals: arrivals.filter { $0.folded.intersects(view) || $0.open.intersects(view) }
                              .prefix(12).map { $0 },
                          stays: stays,
                          hidden: Set(after.map(\.id)).union(stays.map(\.id)).union([group.id]))
        return plan
    }

    /// A group opening comes to the middle of the screen as it grows, as
    /// Safari's (David's recording, 2026-11-18); one taller than the
    /// screen comes to its top instead. Once it's laid out (a frame
    /// later), from where it then is, on the opening's own curve.
    private func center(_ group: TabGroup) {
        spots.openGroups[group.id] = nil
        Task { @MainActor in
            // Once it's laid out: a few frames at most.
            var tries = 0
            repeat {
                try? await Task.sleep(for: .milliseconds(16))
                tries += 1
            } while tries < 8 && spots.openGroups[group.id] == nil
            guard let frame = spots.openGroups[group.id],
                  let scroll = spots.scroll, let scrollTop = spots.scrollTop else { return }
            let view = scroll.containerSize.height
            let now = frame.minY - scrollTop
            let wanted = max((view - frame.height) / 2, Self.centerMargin)
            let lowest = -scroll.contentInsets.top
            let highest = max(lowest, scroll.contentSize.height - view - scroll.contentInsets.top)
            let y = min(max(scroll.contentOffset.y + now - wanted, lowest), highest)
            guard abs(y - scroll.contentOffset.y) > 0.5 else { return }
            // From the content's top, past the top inset (as `fold`'s pin).
            withAnimation(reduceMotion ? nil : .spring(duration: GridCards.morphDuration, bounce: 0)) {
                scrollPosition.scrollTo(point: CGPoint(x: 0, y: y + scroll.contentInsets.top))
            }
        }
    }

    /// The same, for an opening drawn over the list: from the plan's own
    /// measure of the open card, not the list's report of it. The list is
    /// lazy, and a card that starts below the screen's end (a folder low on
    /// screen, second in its row) was never laid out, so its report never
    /// came and the group didn't come to the middle (David, 2026-11-19).
    private func center(_ plan: GroupGlide) {
        guard let origin = spots.listOrigin, let scrollTop = spots.scrollTop, spots.scroll != nil else { return }
        let now = plan.card.minY + origin.y - scrollTop
        Task { @MainActor in
            // A frame later, once the list has its new height.
            try? await Task.sleep(for: .milliseconds(16))
            guard let scroll = spots.scroll else { return }
            let view = scroll.containerSize.height
            let wanted = max((view - plan.card.height) / 2, Self.centerMargin)
            let lowest = -scroll.contentInsets.top
            let highest = max(lowest, scroll.contentSize.height - view - scroll.contentInsets.top)
            let y = min(max(scroll.contentOffset.y + now - wanted, lowest), highest)
            guard abs(y - scroll.contentOffset.y) > 0.5 else { return }
            withAnimation(.spring(duration: GridCards.morphDuration, bounce: 0)) {
                scrollPosition.scrollTo(point: CGPoint(x: 0, y: y + scroll.contentInsets.top))
            }
        }
    }

    /// Room kept above a group too tall to center.
    private static let centerMargin: CGFloat = 12

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
            spots.cards.insert(tab.id)
        }
        let up: (() -> Void)? = index.flatMap { index in index > 0 ? { move(tab, to: index - 1) } : nil }
        let down: (() -> Void)? = index.flatMap { index in index < count - 1 ? { move(tab, to: index + 1) } : nil }
        return tile(tab, spot: spot, at: index, moveUp: up, moveDown: down,
                    holdMenu: systemDrag ? { menu(for: tab) } : nil,
                    height: loose ? nil : gridMetrics.groupCardHeight)
            // The grid on iOS 27: iOS's own menu sits on the card's picture
            // (`OverviewRow.holdMenu`); the drag lifts that same picture.
            .modifier(GridDragShape(on: systemDrag))
            // Its place stays open while it's held or its menu is open
            // (see EmptyWhileHeld).
            // A card stays while its page glides (only its window empties,
            // `windowShown`).
            .modifier(EmptyWhileHeld(finger: finger, id: tab.id, gliding: false))
            // Hold, then move, lifts it (the list's HoldToDrag). Holding
            // still opens Firn's own menu beside the tab (`openMenu`);
            // moving away from it drags the tab on.
            // A held tab resting on this loose one: the group they'd make
            // forms around it (hold to form). Always here, at rest only
            // zero-height spacers, so the tile never changes identity and
            // glides into its place in the card.
            .modifier(FormingCard(forming: loose && forming?.other == tab.id ? forming : nil,
                                  gap: drag?.height ?? 0, space: space))
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
        // Any tab, not only the one on screen (David, 2026-11-17).
        let send = sending?.menuItems(for: tab) ?? []
        // No line under Copy Link, so a pointing finger's highlight glides
        // through every row down to the Close rows (David, 2026-11-09).
        return [link + keep + send, close]
    }

    /// A Basecamp tile's menu: the Mac's, less what the iPhone has no
    /// place for (split view, sound). Close becomes Remove from Basecamp,
    /// plainer words for the same thing. Firn's own menu (`openMenu`).
    private func tileMenu(for tab: FirnCore.Tab) -> [[HoldMenuItem]] {
        var first: [HoldMenuItem] = []
        if tab.isAwayFromHome {
            first.append(HoldMenuItem(title: "Go Back to Home", systemImage: "house") {
                store.goHome(tab)
                openCard(tab)
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
        guard heldMenu == nil, drag == nil, gliding == nil else { return nil }
        return firnHolds(liftable(at: point))
    }

    /// What Firn's own hold and drag may take: anything, except in the
    /// grid on iOS 27, where cards and folders are iOS's (`systemDrag`)
    /// and only Basecamp tiles are still Firn's (until step 2 of
    /// "Plan: iOS's own menus and drag").
    private func firnHolds(_ target: Liftable?) -> Liftable? {
        guard systemDrag, let target else { return target }
        if case .tile = target { return target }
        return nil
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

    /// Another space: its tabs take the list's place and the glow and tint
    /// cross-fade (a plain fade with Reduce Motion).
    private func showSpace(_ space: Space) {
        withAnimation(.easeOut(duration: 0.25)) { store.selectSpace(space) }
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
        guard drag == nil else { return }
        if new.tile {
            tileOrder = store.basecampTabs.map(\.id)
        } else {
            order = shownItems.map(\.id)
            members = Dictionary(store.tabGroups.map { ($0.id, shownTabs(in: $0).map(\.id)) }) { a, _ in a }
        }
        finger.top = new.start.minY
        finger.left = new.start.minX
        grabAcross = new.start.width > 0 ? min(max((point.x - new.start.minX) / new.start.width, 0), 1) : 0.5
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
        let y = forming.above ? frame.minY - GroupCard.rowGap - drag.start.height
                              : frame.maxY + GroupCard.rowGap
        return CGRect(x: lane.minX + GroupCard.side, y: y,
                      width: lane.width - 2 * GroupCard.side, height: drag.start.height)
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
        if drag.tile { return moveTile() }
        finger.top = point.y - drag.grab
        makeRoom()
    }

    /// The other tiles glide aside (0.25s, no bounce; at once with Reduce
    /// Motion) to show where the held tile will land: the spot whose middle
    /// is nearest the tile's middle. Spots are the grid's own, which never
    /// move while one tile is held (the count stays the same, so the rows
    /// stay balanced), so it never flickers between two. Held beside the
    /// grid, it lands in the nearest spot; carried below it, into the tabs
    /// (`moveTile`).
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

        // In the grid: before every card in a row above the finger, and
        // every card to its left in its own row; a group's card (full
        // width) is before it once the finger is past its middle.
        let groupIDs = Set(store.tabGroups.map(\.id))
        func gridPlace(among others: [UUID]) -> Int? {
            let shown = others.indices.filter { shownFrame(others[$0]) != nil }
            guard let first = shown.first else { return others.isEmpty ? 0 : nil }
            let before = shown.filter { index in
                guard let frame = shownFrame(others[index]) else { return false }
                if groupIDs.contains(others[index]) { return frame.midY < finger.y }
                if frame.maxY <= finger.y { return true }
                if frame.minY > finger.y { return false }
                return frame.midX < finger.x
            }.count
            return first + before
        }

        if let into, var others = groups[into] {
            others.removeAll { $0 == drag.id }
            guard let at = gridPlace(among: others) else { return }
            others.insert(drag.id, at: at)
            if let now, now != into { groups[now]?.removeAll { $0 == drag.id } }
            ids.removeAll { $0 == drag.id }
            groups[into] = others
        } else {
            var others = ids.filter { $0 != drag.id }
            guard let at = gridPlace(among: others) else { return }
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
        let whole: (minX: CGFloat, width: CGFloat)
        if let group, let frame = spots.frames[group] {
            whole = (frame.minX + GroupCard.side, frame.width - 2 * GroupCard.side)
        } else {
            whole = (spots.viewport.minX + 16, spots.viewport.width - 32)
        }
        // One column's width, under the finger.
        let columns = CGFloat(gridMetrics.columns)
        let gap = group == nil ? OverviewGridMetrics.spacing : GroupCard.columnGap
        let width = (whole.width - gap * (columns - 1)) / columns
        let left = min(max(finger.x - grabAcross * width, whole.minX), whole.minX + whole.width - width)
        return (left, width)
    }

    // MARK: Into Basecamp

    /// While a tab moves and Basecamp is empty: the blank tile to carry
    /// it onto, the tab's own spot.
    private var blankTile: UUID? {
        guard let drag, drag.moved, store.basecampTabs.isEmpty,
              store.openTabs.first(where: { $0.id == drag.id })?.url != nil else { return nil }
        return drag.id
    }

    /// Whether the finger is over Basecamp's grid (or above it), while it
    /// shows. A carried tab stays a tile until the finger is clearly below
    /// the grid, past the 12pt gap, so it doesn't flicker at the edge.
    private var overBasecamp: Bool {
        guard let grid = spots.basecamp, grid.maxY > spots.viewport.minY else { return false }
        let inGrid = drag.map { $0.basecamp || ($0.tile && !$0.tabs) } ?? false
        return finger.y < grid.maxY + (inGrid ? 12 : 0)
    }

    /// A held tab follows the finger. Carried up over Basecamp, it becomes
    /// a tile there and the tiles make room (a short glide, no bounce);
    /// back below, a row again, and the list makes room. Over a full
    /// Basecamp (or for a tab with no address) nothing changes shape and
    /// the list goes back as it was, since letting go there glides it home.
    private func rearrange() {
        guard var drag, drag.lifted, !drag.tile else { return }
        if drag.group { return makeRoom() }
        if !drag.moved {
            drag.moved = true
            self.drag = drag
        }
        // Back to its own size: laid out normally again (it looks the same).
        if !drag.basecamp, drag.rowSize != nil, Date.now >= drag.reshaping {
            drag.rowSize = nil
            self.drag = drag
        }
        let over = overBasecamp
        let tab = store.openTabs.first { $0.id == drag.id }
        let fits = store.canAddToBasecamp && tab?.url != nil
        if over && fits {
            if !drag.basecamp { carryIntoBasecamp(drag) }
            followAsTile()
            return makeRoomForTile()
        }
        let left = drag.basecamp ? lane(in: nil).minX
            : finger.x - grabAcross * finger.width
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
        new.rowSize = old.rowSize ?? CGSize(width: finger.width, height: old.start.height)
        let width = spots.basecamp?.width ?? spots.viewport.width - 32
        new.tileSize = BasecampTiles.tileSize(count: store.basecampTabs.count + 1, width: width)
        if forming != nil { thaw() }
        waitToForm(over: nil)
        finger.solid = false
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

    // MARK: Out of Basecamp

    /// A Basecamp tile carried down into the tabs (still in Basecamp until
    /// it's let go there).
    private var carriedTile: FirnCore.Tab? {
        guard let drag, drag.tile, drag.tabs else { return nil }
        return store.basecampTabs.first { $0.id == drag.id }
    }

    /// Basecamp's blank tile: while a tab moves over an empty Basecamp, or
    /// while its only tile is carried down into the tabs (and as it lands
    /// there), so Basecamp doesn't vanish under the finger.
    private var blankSpot: UUID? {
        if let blankTile { return blankTile }
        guard let drag, drag.tile, drag.tabs,
              store.basecampTabs.allSatisfy({ $0.id == drag.id }) else { return nil }
        return drag.id
    }

    /// A held tile follows the finger. Within Basecamp, the tiles make
    /// room; carried below the grid (12pt past it, so the edge doesn't
    /// flicker), it becomes a card and the list makes room, in an open
    /// group too; back over the grid, a tile again.
    private func moveTile() {
        guard var drag, drag.lifted, drag.tile else { return }
        // Back to its own size: laid out normally again (it looks the same).
        if drag.tabs, drag.rowSize != nil, Date.now >= drag.reshaping {
            drag.rowSize = nil
            self.drag = drag
        }
        let view = spots.viewport
        if overBasecamp {
            if drag.tabs { carryTileBack(drag) }
            guard let tile = self.drag else { return }
            // Kept inside the list's sides, so it never slides off screen.
            place(finger.y - tile.grab,
                  min(max(finger.x - tile.grabX, view.minX), view.maxX - tile.start.width))
            return makeRoomForTile()
        }
        let left = drag.tabs ? finger.left : lane(in: nil).minX
        if !drag.tabs { carryTileOut(drag) }
        guard let card = self.drag else { return }
        // Held as far down the card as it was down the tile.
        let share = card.start.height > 0 ? card.grab / card.start.height : 0.5
        place(finger.y - share * card.rowHeight, left)
        makeRoom()
    }

    /// The tile becomes a card under the finger: its spot among the tiles
    /// closes, and a place opens in the list where the finger is.
    private func carryTileOut(_ old: Drag) {
        var new = old
        new.tabs = true
        new.reshaping = .now + 0.3
        new.rowHeight = cardHeight
        let lane = lane(in: nil)
        // Drawn at the card's own size and grown as one picture.
        new.rowSize = CGSize(width: lane.width, height: new.rowHeight)
        let rest = restingOrder()
        var ids = rest.ids
        let view = spots.viewport
        let shown = ids.indices.filter { index in
            spots.frames[ids[index]].map { $0.maxY > view.minY && $0.minY < view.maxY } ?? false
        }
        let above = shown.filter { (spots.frames[ids[$0]]?.midY ?? 0) < finger.y }.count
        ids.insert(new.id, at: min((shown.first ?? 0) + above, ids.count))
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            drag = new
            tileOrder?.removeAll { $0 == new.id }
            order = ids
            members = rest.groups
            finger.width = lane.width
        }
        forms += 1
    }

    /// Back over the grid: a tile again, its place in the list closing and
    /// a spot opening among the tiles, the nearest.
    private func carryTileBack(_ old: Drag) {
        var new = old
        new.tabs = false
        new.reshaping = .now + 0.3
        new.rowSize = old.rowSize ?? CGSize(width: finger.width, height: old.rowHeight)
        waitToForm(over: nil)
        var tiles = (tileOrder ?? store.basecampTabs.map(\.id)).filter { $0 != new.id }
        let nearest = tiles.indices.min { a, b in
            let fa = spots.frames[tiles[a]] ?? .zero, fb = spots.frames[tiles[b]] ?? .zero
            return hypot(fa.midX - finger.x, fa.midY - finger.y) < hypot(fb.midX - finger.x, fb.midY - finger.y)
        }
        let at = nearest.map { index in
            (spots.frames[tiles[index]]?.midX ?? 0) < finger.x ? index + 1 : index
        } ?? tiles.count
        tiles.insert(new.id, at: at)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            drag = new
            order = nil
            members = nil
            tileOrder = tiles
            finger.width = new.start.width
        }
        forms += 1
    }

    /// Let go in the tabs: the store moves the tile there (Move to Tabs, at
    /// that place, or into that group), where its card's place already is,
    /// and the card settles into it. If iOS took the touch, it goes home to
    /// its spot in Basecamp instead.
    private func settleInTabs(_ drag: Drag, cancelled: Bool) {
        finger.solid = false
        if !cancelled, let ids = order, let groups = members,
           let tab = store.basecampTabs.first(where: { $0.id == drag.id }) {
            if let into = groups.first(where: { $0.value.contains(drag.id) }),
               let group = store.tabGroups.first(where: { $0.id == into.key }),
               let at = into.value.firstIndex(of: drag.id) {
                store.removeFromBasecamp(tab, toGroup: group, at: at)
            } else if let at = ids.firstIndex(of: drag.id) {
                store.removeFromBasecamp(tab, toGroup: nil, at: at)
            }
        }
        let landing = cancelled ? drag.start : spots.frames[drag.id] ?? drag.start
        order = nil
        members = nil
        tileOrder = nil
        guard !reduceMotion else {
            self.drag = nil
            finger.held = nil
            lastDrop = .now
            return
        }
        var settling = drag
        settling.lifted = false
        if cancelled {
            settling.tabs = false
            settling.rowSize = drag.rowSize ?? CGSize(width: finger.width, height: drag.rowHeight)
        }
        withAnimation(.smooth(duration: 0.25)) {
            finger.top = landing.minY
            finger.left = landing.minX
            finger.width = landing.width
            self.drag = settling
        } completion: {
            self.drag = nil
            finger.held = nil
            lastDrop = .now
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
        resize(to: lane.minX + GroupCard.side, lane.width - 2 * GroupCard.side)
        forms += 1
    }

    /// While a group is forming, it holds as long as the finger is on its
    /// card, so the tabs moving under the finger don't undo it; the gap
    /// follows the finger past the other tab's middle. Off the card, it
    /// thaws back. True while it holds.
    private func holdForming() -> Bool {
        guard let forming, let frame = spots.frames[forming.other], let drag else { return false }
        let gap = drag.start.height + GroupCard.rowGap
        let cardTop = frame.minY - (forming.above ? gap : 0) - GroupCard.headerHeight
        let cardBottom = frame.maxY + (forming.above ? 0 : gap) + GroupCard.bottom
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
        if drag.tile, drag.tabs { return settleInTabs(drag, cancelled: cancelled) }
        // (A tile moving within a full Basecamp isn't being added to it.)
        let fullBasecamp = !drag.group && !drag.tile && overBasecamp && !store.canAddToBasecamp
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
                if drag?.tile == true { moveTile() } else { rearrange() }
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

/// The overview comes forward as a tab lands, as Safari's does (2h, David,
/// 2026-11-13): the list and the bar start a little smaller and grow to full
/// size around the screen's middle as the page lands (`forward`, on the
/// landing glide's clock, done as the page lands, or as a tile's swap starts
/// at 86% of its glide, so the flying tile and the real one match), and come
/// into focus, dimmed to bright, while a picture of it softened once fades
/// out over it (`FrozenOverview`; David, 2026-11-13: "it would help this
/// settling feel better"). The blur was live here until 2026-11-14: about
/// 200 offscreen passes a frame, half of each swipe up's frames dropped on
/// David's iPhone. The dim runs only while landing. `visualEffect`, not `scaleEffect`: it's
/// drawing only, so nothing in the list moves or re-lays out. The spots the
/// cards and tiles report (`OverviewSpots`) do come in scaled (measured in
/// the Simulator: 96% at the let-go), so `BrowserScreen.fullSize` takes the
/// scale back out and the page lands in the spot's full-size place.
/// Reduce Motion: none.
struct ComesForward: ViewModifier, Animatable {
    /// How far it has grown (0 to 1): on a slower clock than the focus,
    /// still growing after the page lands, so it can be seen coming
    /// forward (David, beside Safari's, 2026-11-13).
    var through: CGFloat
    /// How far it has come into focus (0 to 1): the blur and dim, done as
    /// the page lands, so the card it lands in is sharp when they swap.
    var focus: CGFloat
    let middle: CGPoint?
    let off: Bool
    /// `middle` is in the scroll view's own points, and the content is
    /// placed by its frame there (`.scrollView`), not on screen: for a
    /// scrolling list. The list's frame on screen could be a frame behind
    /// its scroll as it turned to the tab on screen, so the point it grew
    /// around jumped, and the whole list slid several points sideways and
    /// up or down as a tab landed, then snapped back (David's recording,
    /// 2026-11-14). The scroll view's own space moves with the scroll.
    var inScroll = false
    /// The page has been let go (or the overview is up): the blur may run.
    var blurs = true
    /// It may grow: for the list's contents, only once a page is let go.
    var scales = true
    /// How much darker it starts, lifting with the blur: Safari's overview
    /// is there at once, dimmed, and brightens as it comes forward, where
    /// Firn's read as a pale haze fading in (same recording).
    static let dim: Double = 0.2
    /// How much smaller it starts (Safari's is about 4%; 4% on the list's
    /// quick fade couldn't be seen; 94% and 90% tried; 92%, measured from
    /// Safari's, David's recording, 2026-11-13).
    static let depth: CGFloat = 0.08
    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(through, focus) }
        set { through = newValue.first; focus = newValue.second }
    }

    /// The scale at `through` (0 to 1).
    static func scale(_ through: CGFloat, off: Bool) -> CGFloat {
        off ? 1 : 1 - depth * (1 - min(max(through, 0), 1))
    }

    func body(content: Content) -> some View {
        let scale = scales ? Self.scale(through, off: off) : 1
        // Kept longer than the scale (the square root of what's left): on
        // the glide's quick start, a plain share was mostly gone within a
        // tenth of a second (Simulator recording, 2026-11-13), so the cards
        // come into focus over the landing's end instead.
        // Its own curve holds it soft early (`BrowserScreen`), so a plain
        // share here.
        let left = 1 - min(max(focus, 0), 1)
        let dim = off || !blurs ? 0 : -Self.dim * Double(left)
        let middle = middle
        let inScroll = inScroll
        content.visualEffect { view, proxy in
            let frame = inScroll ? proxy.frame(in: .scrollView) : proxy.frame(in: .global)
            let anchor = middle.map {
                UnitPoint(x: frame.width > 0 ? ($0.x - frame.minX) / frame.width : 0.5,
                          y: frame.height > 0 ? ($0.y - frame.minY) / frame.height : 0.5)
            } ?? .center
            return view.scaleEffect(scale, anchor: anchor).brightness(dim)
        }
    }
}

/// Where each tab's spot (a card's picture, or a slim row) sits on screen,
/// in global points. Not observed: rows write it as they move, and only the
/// glide reads it, so scrolling redraws nothing else.
@MainActor final class OverviewSpots {
    var frames: [UUID: CGRect] = [:] {
        didSet { SwipeTiming.sawSpots(frames) }
    }
    /// Open groups in the grid where they're laid out, to bring one to
    /// the middle as it opens.
    var openGroups: [UUID: CGRect] = [:]
    /// Each run of loose cards (`OverviewGridRun.id`) where it's laid out,
    /// to work out the spot of a card that's out of view (`looseSpot`).
    var runs: [String: CGRect] = [:]
    /// Where the list's contents start on screen (they scroll).
    var listOrigin: CGPoint?
    /// The list's own frame, to find the tab under a pinch.
    var viewport: CGRect = .zero
    /// The tabs shown as tall cards (the rest are slim rows): a card's
    /// title line rides on its picture as the page grows out of it.
    var cards: Set<UUID> = []
    /// The list's scroll, for scrolling while a tab is held at an edge.
    var scroll: ScrollGeometry?
    /// The top of the list's view on screen, below the status bar and the
    /// top margin.
    var scrollTop: CGFloat?
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

