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
    /// `heldCard` are read here, and `posed`: they change which card shows what.
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
    /// Set on the copy that draws the coming space during a swipe between
    /// spaces (`SpaceSlide`): the same list, laid out the same, with no
    /// bar, backdrop, or pictures of its own, and nothing to touch.
    var peeking: SpaceSlide?
    /// The side a copy waits on (`SpaceSlide.Peek.side`).
    var peekSide: CGFloat = 0
    private var isPeek: Bool { peeking != nil }
    private var slides: SlidesWithSpace {
        SlidesWithSpace(slide: slide, copyOf: isPeek ? store.activeSpace.id : nil, side: peekSide,
                        laidOut: !isPeek || copyLaidOut, width: laidSize.width)
    }
    /// A copy has had its first few frames (`SlidesWithSpace.laidOut`).
    @State private var copyLaidOut = false
    /// The wait before the copies are made (`copySoon`).
    @State private var copying: Task<Void, Never>?
    /// The overview's size; a copy's first layout borrows the real one's,
    /// so it's right from its first frame.
    private var laidSize: CGSize { size == .zero ? (peeking?.size ?? .zero) : size }
    /// A swipe between spaces on the name (the real overview's own).
    @State private var ownSlide = SpaceSlide()
    private var slide: SpaceSlide { peeking ?? ownSlide }
    /// On screen. The overview stays built behind the page while browsing
    /// (hidden), so a swipe up only reveals it; whatever it remembers
    /// resets as it hides. Never read in the body: showing runs only the
    /// small pieces that read the landing (`LandingWatch`, `CardWindow`).
    private var shown: Bool { landing.shown }

    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Send to My Mac, in a tab's menu (sync step 6).
    @Environment(Sending.self) private var sending: Sending?

    /// Counts closes, so the shake listener takes focus again after each.
    @State private var closes = 0

    /// Add to Basecamp was picked with 12 tiles already there.
    @State private var basecampFull = false
    @Environment(\.newSpace) private var newSpace
    @Environment(\.spaceSettings) private var spaceSettings
    /// The group being renamed (Rename from its menu).
    @State private var naming: TabGroup?
    @State private var name = ""
    /// The cards iOS has lifted, for its menu or its
    /// drag (`GridCards.held`), so their X hides (the lift is only the
    /// picture).
    @State private var systemDragged: Set<UUID> = []
    /// A group folding into its cell or opening out of it drawn over the list until it's done (`GroupGlideView`),
    /// and how far open it's drawn (0 folded, 1 open).
    @State private var glide: GroupGlide?
    @State private var glideShare: CGFloat = 0
    /// The grid's UIKit cards being swiped to close (`GridCards`).
    @State private var gridSwipes: [UUID: GridSwipe] = [:]
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    /// Done was tapped: nothing opens, closes, or folds on the way out.
    private var busy: Bool { finishing }
    /// Done was tapped and the tab on screen's group is opening first.
    @State private var finishing = false
    /// The overview softened once, for the landing (`FrozenOverview`), and
    /// the wait before the next picture is taken.
    @State private var frozen: FrozenOverview?
    /// Whether that picture was taken behind the page (`freezeSoon`).
    @State private var frozenBehind = false
    /// The picture drawn as a tab opened, its place empty, and its making
    /// (`pictureWithout`).
    @State private var openedPicture: FrozenOverview?
    @State private var opened: Task<Void, Never>?
    @State private var freezing: Task<Void, Never>?
    @State private var scrolling = false
    @Environment(\.colorScheme) private var colorScheme
    /// The overview's size, for the grid's columns and card height.
    @State private var size: CGSize = .zero
    private var gridMetrics: OverviewGridMetrics {
        OverviewGridMetrics(width: laidSize.width, height: laidSize.height)
    }
    /// A card's height in the grid.
    private var cardHeight: CGFloat { gridMetrics.cardHeight }

    /// Groups and loose tabs in the order shown: the store's.
    private var shownItems: [TabListItem] { store.tabListItems }

    /// The tabs a group shows: all of them, or none while it's folded. The
    /// tab on screen's group opens with the overview, and again just before
    /// the page grows back (`finish`), so the page always has its card.
    private func shownTabs(in group: TabGroup) -> [FirnCore.Tab] {
        group.folded ? [] : store.tabs(in: group)
    }

    private var space: String { store.activeSpace.color }
    /// Between the list's items: Basecamp, runs of loose tabs, and groups.
    private static let listSpacing: CGFloat = 12
    /// The room above the list's first item.
    private static let topMargin: CGFloat = 8
    var body: some View {
        // Read here so the pose runs this body: the grid's cards are made
        // from UIKit's side, where reading it isn't noticed, and the tab
        // on screen's card stayed in the picture unless something else
        // happened to run the body in time (David's iPhone, 2026-11-20).
        let _ = landing.posed
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
                    // The tiles are the grid's first section (`systemGrid`).
                    systemGrid(shownItems)
                }
                // Where the list's contents start on screen, to place a
                // group's fold over them (`glidePlan`).
                .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).origin }) { spots.listOrigin = $0 }
                .overlay(alignment: .topLeading) { glideDrawing }
                .padding(.horizontal, 16)
                // A swipe between spaces slides the tabs off with the
                // finger, the coming space's in beside them.
                .modifier(slides)
                // Where the top of the list's view is on screen, below the
                // status bar and the top margin (the scroll view's own
                // space starts there), to turn a card's spot into the list's
                // offset (`scroll(to:)`). Not `spots.viewport`: the scroll
                // view runs up under the status bar, above its laid-out frame.
                .onGeometryChange(for: CGFloat.self, of: {
                    $0.frame(in: .global).minY - $0.frame(in: .scrollView).minY
                }) { spots.scrollTop = $0 }
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
            .onGeometryChange(for: CGSize.self, of: \.size) {
                size = $0
                if !isPeek { ownSlide.size = $0 }
            }
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
                    // With its space, whole: fading on its own, it lingered
                    // over the next space's cards (David's recording,
                    // 2026-11-22).
                    .transition(.identity)
                    .modifier(slides)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // A copy keeps the bar's room and nothing else: with a
                // hidden bar of its own, the real name's pill vanished for
                // half a second as the copies were dropped (David's iPhone,
                // 2026-11-23; glass under glass).
                if let peeking {
                    Color.clear.frame(height: peeking.barHeight)
                } else {
                OverviewBar(space: store.activeSpace, spaces: store.spaces, newTab: newTab, done: finish,
                            select: showSpace(_:), newSpace: newSpace, spaceSettings: spaceSettings,
                            slide: ownSlide, aim: aim(at:), ready: readySpaces(_:))
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { ownSlide.barHeight = $0 }
                    // In over the glide's second half, once the page's bar
                    // is gone (see BrowserScreen's bar), never both at once;
                    // a hair above 0 while gliding keeps its glass ready.
                    .modifier(LandingBand(landing: landing, value: \.arrival, range: 0.55...1,
                                          glidingFloor: 0.002, off: typing))
                    .modifier(LandingUnderPicture(landing: landing, pictured: pictured))
                    .modifier(LandingForward(landing: landing, middle: screenMiddle, off: reduceMotion))
                }
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
            .task {
                guard isPeek else { return }
                try? await Task.sleep(for: .milliseconds(100))
                copyLaidOut = true
            }
            // Hidden again: a picture from behind the page, once it's still.
            .background {
                LandingWatch(landing: landing, shownChanged: { now in
                    if !now { forgetOpening() }
                    if !now, !isPeek {
                        copying?.cancel()
                        slide.clear()
                    }
                    getReady(scroller)
                    if !now { handOverPicture() }
                    freezeSoon()
                })
            }
            .onChange(of: store.activeTab?.id) { if !shown { getReady(scroller) } }
            .onChange(of: store.activeSpace.id) {
                if !shown { getReady(scroller) }
                // Changed some other way (the menu, the command bar) while
                // a swipe's copy was up.
                if !isPeek, !slide.settling { slide.clear() }
            }
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
            LandingRest(landing: landing, still: !typing && !scrolling,
                        rested: {
                            freezeSoon()
                            copySoon()
                        })
        }
        .onChange(of: look(scroll: 0)) { freezeSoon() }
        .background {
            // The coming space's tabs during a swipe between spaces, under
            // this list and over the backdrop.
            if !isPeek { SpacePeekLayer(slide: slide, pictures: pictures, screenMiddle: screenMiddle) }
        }
        .background {
            // The space wash: the space's color, as the Mac's tinted frame.
            if !isPeek { SpaceWash(space: space, slide: slide) }
        }
        // It takes the keyboard's focus to hear a shake, only while shown.
        .background { if !isPeek { ShakeHost(landing: landing, undoManager: undoManager, closes: closes) } }
        .basecampFullAlert(isPresented: $basecampFull)
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
        shown && gliding == nil && landing.arrival >= 1 && landing.focus >= 1 && heldCard == nil
            && !typing && !scrolling
    }

    /// What the overview shows now, for `FrozenOverview` (its scroll from
    /// `spots`, which isn't observed; `scroll` stands in where only the
    /// rest matters).
    private func look(scroll: CGFloat? = nil, onScreen: UUID? = nil) -> FrozenOverview.Look {
        let tabs = store.openTabs
        return FrozenOverview.Look(
            space: store.activeSpace.id,
            onScreen: onScreen ?? store.activeTab?.id,
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
        guard !reduceMotion, !isPeek else { return }
        let shown = shown
        freezing = Task {
            // Behind the page there's less to wait out, and a tab is often
            // closed within a second of opening (David's recording,
            // 2026-11-19: no picture yet, so no blur).
            try? await Task.sleep(for: .milliseconds(shown ? 350 : 120))
            guard !Task.isCancelled else { return }
            if !shown {
                // A tab just opened is still gliding to the screen: wait
                // it out, or the picture kept would be the one from on
                // screen, with that tab's card in it (David's iPhone,
                // 2026-11-20: the held tab's copy still behind the blur).
                var waits = 0
                while !hiddenAtRest, waits < 20 {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    waits += 1
                }
            }
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

    /// UIKit's grid in the list and a card's place in it (`GridPlan`): how
    /// far below the grid's top, and how tall. Its cards are cells of a
    /// collection view, which the SwiftUI list can't look up by id, and a
    /// cell out of view has no spot of its own: the last of many tabs was
    /// never scrolled to, so the overview opened at the top with no card
    /// for its page to land in (Simulator, 2026-11-19). Nil for a tab in a
    /// folded group and the SwiftUI grid, whose cards the list knows.
    private func looseSpot(of id: UUID) -> (run: String, top: CGFloat, height: CGFloat)? {
        let metrics = gridMetrics
        let plan = GridPlan(sections: gridSections(shownItems),
                            width: laidSize.width - 2 * OverviewGridMetrics.margin, columns: metrics.columns,
                            cardHeight: metrics.cardHeight, groupCardHeight: metrics.groupCardHeight)
        guard store.openTabs.contains(where: { $0.id == id }) || store.basecampTabs.contains(where: { $0.id == id }),
              let frame = plan.frame(of: id) else { return nil }
        return (Self.gridID, frame.minY, frame.height)
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
        pictureWithout(tab)
        open(tab)
    }

    /// A tab is about to open from the grid: the overview's picture for
    /// the next swipe up, drawn now with that tab's place empty, so it's
    /// ready by the time the page has landed. Taken only afterward, behind
    /// the page, it came a few tenths of a second after the landing, and a
    /// page grabbed sooner had the on-screen picture behind it, its own
    /// card included (David's iPhone, 2026-11-20; reproduced in the
    /// Simulator by delaying the retake).
    private func pictureWithout(_ tab: FirnCore.Tab) {
        opened?.cancel()
        openedPicture = nil
        guard shown, !reduceMotion, atRest, let spot = spots.frames[tab.id],
              let picture = canvas.take(without: CGPoint(x: spot.midX, y: spot.midY)) else { return }
        let now = look(onScreen: tab.id)
        opened = Task {
            guard let made = await FrozenOverview.make(from: picture, look: now, quick: true), !Task.isCancelled
            else { return }
            if self.shown {
                // Still opening: handed over as the overview hides.
                openedPicture = made
            } else if look().matches(now), store.activeTab?.id == tab.id {
                frozen = made
                frozenBehind = true
            }
        }
    }

    /// The overview has just gone behind the page: the picture taken on
    /// screen has every card in it, the page's own too, so it never stands
    /// behind a held page. The one drawn as the tab opened takes its
    /// place; without one there's no picture until the next is taken.
    private func handOverPicture() {
        if let next = openedPicture, next.look.onScreen == store.activeTab?.id {
            frozen = next
            frozenBehind = true
        } else if !frozenBehind {
            frozen = nil
        }
        openedPicture = nil
    }

    /// Hidden: everything a visit leaves behind goes, as when the
    /// overview was built afresh for each one (a hold, a menu, a drag and
    /// its moved order, a forming group, a rename).
    private func forgetOpening() {
        finishing = false
        naming = nil
        basecampFull = false
    }

    private func isOnScreen(_ tab: FirnCore.Tab) -> Bool {
        tab.id == (heldCard ?? store.activeTab?.id)
    }

    /// A tab's tile: in the list, or lifted under the finger.
    private func tile(_ tab: FirnCore.Tab, spot: @escaping (CGRect) -> Void, at index: Int? = nil,
                      moveUp: (() -> Void)? = nil, moveDown: (() -> Void)? = nil,
                      inCollection: Bool = false,
                      height: CGFloat? = nil, bare: Bool = false, titled: Bool = true) -> some View {
        let onScreen = isOnScreen(tab)
        return OverviewRow(
            tab: tab,
            isOnScreen: onScreen,
            pictures: pictures,
            landing: landing,
            loadPicture: { await pictures.loadImage(for: tab.id) },
            space: space,
            open: { openCard(tab) },
            close: { if !busy { close(tab) } },
            spot: spot,
            moveUp: moveUp,
            moveDown: moveDown,
            menu: { menu(for: tab) },
            // From every group directly: `tabGroups` walks the whole tab
            // list, and this runs for every tile on every redraw.
            groupName: tab.groupID.flatMap { id in store.groups.first(where: { $0.id == id })?.name },
            actionsKey: [index ?? -1, reduceMotion ? 1 : 0],
            cardHeight: height ?? cardHeight,
            carried: systemDragged.contains(tab.id),
            bare: bare,
            titled: titled,
            swipesItself: !inCollection,
            gridSwipe: gridSwipes[tab.id] ?? .none
        )
        // Runs again only when what it shows changes (`OverviewRow.==`).
        .equatable()
    }

    /// The grid's one collection view in the list, by this name: for
    /// scrolling to it, and for where it's laid out (`spots.runs`).
    private static let gridID = "grid"

    /// The grid's sections: Basecamp's tiles, each run of loose cards and
    /// folded groups, and each open group with the tabs it shows.
    private func gridSections(_ items: [TabListItem]) -> [GridPlan.Section] {
        let tiles = store.basecampTabs.map(\.id)
        let basecamp = tiles.isEmpty ? [] : [GridPlan.Section(group: nil, after: nil, ids: tiles, basecamp: true)]
        return basecamp + OverviewGridRun.runs(items, inRun: { folderCell($0) }).map { run in
            switch run {
            case let .tabs(after, entries): GridPlan.Section(group: nil, after: after, ids: entries.map(\.id))
            case let .group(_, group): GridPlan.Section(group: group.id, after: nil, ids: shownTabs(in: group).map(\.id))
            }
        }
    }

    /// The grid as one UIKit collection view (`OverviewGridCards.swift`):
    /// iOS's menu and iOS's drag, the card full size as it's carried. Loose
    /// cards and folded groups in runs, each open group a section: its name
    /// line, its tabs, and its glass card behind them.
    @ViewBuilder private func systemGrid(_ items: [TabListItem]) -> some View {
        let metrics = gridMetrics
        let inRun: @MainActor (TabGroup) -> Bool = { group in folderCell(group) }
        let runs = OverviewGridRun.runs(items, inRun: inRun)
        let sections = gridSections(items)
        // What each cell is: a loose card or folded group, an open group's
        // name line, or a tab in an open group.
        let loose: [UUID: GridRunItem] = Dictionary(runs.flatMap { run -> [(UUID, GridRunItem)] in
            if case let .tabs(_, entries) = run { return entries.map { ($0.id, $0) } }
            return []
        }) { a, _ in a }
        let open: [UUID: (index: Int, group: TabGroup, tabs: [FirnCore.Tab])] = Dictionary(
            runs.compactMap { run -> (UUID, (index: Int, group: TabGroup, tabs: [FirnCore.Tab]))? in
                if case let .group(index, group) = run { return (group.id, (index, group, shownTabs(in: group))) }
                return nil
            }) { a, _ in a }
        let grouped: [UUID: (tab: FirnCore.Tab, place: Int, group: UUID)] = Dictionary(
            open.values.flatMap { entry in
                entry.tabs.enumerated().map { ($0.element.id, (tab: $0.element, place: $0.offset, group: entry.group.id)) }
            }) { a, _ in a }
        let basecamp = store.basecampTabs
        let tiles: [UUID: (tab: FirnCore.Tab, place: Int)] = Dictionary(
            basecamp.enumerated().map { ($0.element.id, (tab: $0.element, place: $0.offset)) }) { a, _ in a }
        let tileGlide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        if !sections.isEmpty {
            GridCards(sections: sections, columns: metrics.columns, cardHeight: metrics.cardHeight,
                      groupCardHeight: metrics.groupCardHeight,
                      groupCard: { id in
                          guard let entry = open[id] else { return AnyView(EmptyView()) }
                          return AnyView(groupGlass(entry.group, tabs: entry.tabs))
                      },
                      card: { id in
                          if let entry = tiles[id] {
                              let tab = entry.tab, place = entry.place
                              return AnyView(BasecampCell(
                                  tab: tab, space: space, spots: spots, landing: landing,
                                  onScreen: heldCard ?? store.activeTab?.id,
                                  open: { openCard(tab) },
                                  menu: tileMenu(for: tab),
                                  moveLeft: place > 0
                                      ? { withAnimation(tileGlide) { store.move(tab, to: place - 1) } } : nil,
                                  moveRight: place < basecamp.count - 1
                                      ? { withAnimation(tileGlide) { store.move(tab, to: place + 1) } } : nil))
                          }
                          if let entry = open[id] {
                              return AnyView(groupLine(entry.group, tabs: entry.tabs, at: entry.index, of: items.count))
                          }
                          if let entry = grouped[id], let group = open[entry.group] {
                              return AnyView(groupedCell(entry.tab, at: entry.place, in: group.group,
                                                         showing: group.tabs.count))
                          }
                          guard let entry = loose[id] else { return AnyView(EmptyView()) }
                          if let group = entry.group {
                              return AnyView(folder(group, at: entry.index, of: items.count))
                          }
                          guard let tab = entry.tab else { return AnyView(EmptyView()) }
                          return AnyView(gridCell(tab, at: entry.index, of: items.count))
                      },
                      menu: { id in
                          if let entry = tiles[id] { return tileMenu(for: entry.tab) }
                          if let entry = open[id] { return groupMenu(entry.group).sections }
                          if let entry = grouped[id] { return menu(for: entry.tab) }
                          guard let entry = loose[id] else { return [] }
                          if let group = entry.group { return groupMenu(group).sections }
                          return entry.tab.map { menu(for: $0) } ?? []
                      },
                      held: { id, held in
                          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                              if held { systemDragged.insert(id) } else { systemDragged.remove(id) }
                          }
                      },
                      move: { id, before, group, after in
                          GridMove(sources: [id], collection: group.map { .tabs($0) } ?? .loose(after: after),
                                   before: before, inRun: inRun).apply(to: store)
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
                          if !busy, let tab = loose[id]?.tab ?? grouped[id]?.tab { close(tab) }
                      },
                      moveTile: { id, place in
                          if let tab = tiles[id]?.tab {
                              store.move(tab, to: place)
                          } else if let tab = loose[id]?.tab ?? grouped[id]?.tab {
                              // A tab let go among the tiles: a tile there.
                              _ = store.addToBasecamp(tab, at: place)
                          }
                      },
                      fitsBasecamp: { id in
                          store.canAddToBasecamp && (loose[id]?.tab ?? grouped[id]?.tab)?.url != nil
                      },
                      basecampRefused: {
                          if !store.canAddToBasecamp { basecampFull = true }
                      },
                      kind: { id in
                          if tiles[id] != nil { return .tile }
                          if open[id] != nil { return .line }
                          return loose[id]?.group != nil ? .folder : .card
                      },
                      join: { id, groupID in
                          guard let tab = loose[id]?.tab, let group = loose[groupID]?.group else { return }
                          store.move(tab, toGroup: group, at: store.tabs(in: group).count)
                      },
                      folderPicture: { id in
                          guard let group = open[id]?.group else { return AnyView(EmptyView()) }
                          return AnyView(GroupFolder(group: group, tabs: store.tabs(in: group), pictures: pictures,
                                                     cardHeight: metrics.cardHeight, naming: store.isNaming(group),
                                                     open: {}, flat: true))
                      },
                      carry: { id in
                          if let group = open[id]?.group { foldForCarry(group) }
                      },
                      landed: { id in
                          if let group = store.tabGroups.first(where: { $0.id == id }), group.folded { fold(group) }
                      },
                      fold: glide?.token,
                      reduceMotion: reduceMotion)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.runs[Self.gridID] = $0 }
                .id(Self.gridID)
                // Its cards glide on their own (`GridCards`), so the grid
                // itself never fades.
                .transition(.identity)
        }
    }

    /// An open group's name line in UIKit's grid. A tap folds the group;
    /// holding it is iOS's menu, from the grid.
    private func groupLine(_ group: TabGroup, tabs: [FirnCore.Tab], at index: Int, of count: Int) -> some View {
        GroupLine(group: group, height: GroupCard.headerHeight, naming: store.isNaming(group),
                         toggle: { fold(group) })
            .modifier(groupMenu(group).actions)
            .modifier(GroupMoveActions(moves: GroupMoves(
                up: index > 0 ? { move(group, to: index - 1) } : nil,
                down: index < count - 1 ? { move(group, to: index + 1) } : nil)))
            .padding(.horizontal, GroupCard.side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Folding or opening, it's drawn over the list (`glideDrawing`).
            .opacity(glide?.id == group.id ? 0 : 1)
    }

    /// An open group's glass card in UIKit's grid, behind its name line and
    /// its tabs (a view of its own there, `GridPlanLayout.cardKind`).
    private func groupGlass(_ group: TabGroup, tabs: [FirnCore.Tab]) -> some View {
        GroupCard(space: space)
            // Gathers as the page shrinks into its card (`groupCard`).
            .modifier(LandingGroupFade(landing: landing, holdsOnScreen: tabs.contains(where: isOnScreen)))
            .animation(.easeInOut(duration: 0.4), value: space)
            // Where the group is: to fold it from (`glidePlan`), and to
            // bring it to the middle as it opens (`center`).
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                spots.frames[group.id] = frame
                spots.openGroups[group.id] = frame
            }
            .opacity(glide?.id == group.id ? 0 : 1)
    }

    /// A tab in an open group, in UIKit's grid: a little shorter than a
    /// loose card, its menu and swipe the collection view's.
    private func groupedCell(_ tab: FirnCore.Tab, at place: Int, in group: TabGroup, showing count: Int) -> some View {
        let spot: (CGRect) -> Void = { frame in
            spots.frames[tab.id] = frame
            spots.cards.insert(tab.id)
        }
        // Tabs move within their group only while it shows them all.
        let movable = count == store.tabs(in: group).count
        return tile(tab, spot: spot, at: movable ? place : nil,
                    moveUp: movable && place > 0 ? { move(tab, to: place - 1) } : nil,
                    moveDown: movable && place < count - 1 ? { move(tab, to: place + 1) } : nil,
                    inCollection: true, height: gridMetrics.groupCardHeight)
            .opacity(glide?.id == group.id || glide?.hidden.contains(tab.id) == true ? 0 : 1)
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

    /// A group's long-press menu (Rename, Ungroup, Close Group), also
    /// VoiceOver's actions.
    private func groupMenu(_ group: TabGroup) -> GroupMenu {
        GroupMenu(rename: { askForName(group) },
                  ungroup: { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.ungroup(group) } },
                  close: { close(group) })
    }

    /// Folds or unfolds a group: the card glides to its new size (0.25s, no
    /// bounce) and its tabs fade over the second half (`FoldFade`); with
    /// Reduce Motion everything changes at once.
    /// Folded tabs forget their spots, so nothing glides to a place that's
    /// gone; folding the tab on screen's group is fine, since `finish`
    /// opens it again before the page grows back.
    private func fold(_ group: TabGroup) {
        guard !busy else { return }
        // One fold at a time: a tap during a glide waits for the next.
        if glide != nil { return }
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
        // The group shrinks into its cell, or grows
        // out of it, as Safari's (David, 2026-11-18), drawn over the list
        // (`glideDrawing`). The drawing shows first, as things are; then
        // the list changes under it on the same curve (`startGlide`).
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
        // Reduce Motion, or nowhere to draw it from. With Reduce Motion it
        // changes at once: the collection view's cards never faded, and the
        // grid still growing over 0.2s showed the opened group's tabs piece
        // by piece as it reached them (the Simulator, 2026-11-24).
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.setFolded(group, folding) }
        if !folding { center(group) }
    }

    /// An open group picked up by its name line folds at once, with no
    /// glide: what's carried is its folder card (`GridCards.carry`), and
    /// the cards around it close up as for any change. It opens again
    /// where it lands (`fold`, from `GridCards.landed`).
    private func foldForCarry(_ group: TabGroup) {
        guard !group.folded else { return }
        if let scroll = spots.scroll {
            scrollPosition.scrollTo(point: CGPoint(x: 0, y: scroll.contentOffset.y + scroll.contentInsets.top))
        }
        for tab in store.tabs(in: group) {
            spots.frames[tab.id] = nil
            spots.cards.remove(tab.id)
        }
        store.setFolded(group, true)
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

    /// A tab's menu: short, in the Mac's words.
    private func menu(for tab: FirnCore.Tab) -> [[HoldMenuItem]] {
        let glide: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)
        var link: [HoldMenuItem] = []
        var keep: [HoldMenuItem] = []
        if let url = tab.url {
            link.append(HoldMenuItem(title: "Copy Link", systemImage: "link") { UIPasteboard.general.url = url })
            keep.append(HoldMenuItem(title: "Add to Basecamp", systemImage: "mountain.2") { addToBasecamp(tab) })
        }
        // Move to Group reads the same in every menu: New Group first, then
        // this space's other groups (nothing crosses between spaces), and
        // Remove from Group last for a tab that's in one.
        var groups = [HoldMenuItem(title: "New Group", systemImage: "folder.badge.plus") { newGroup(with: tab) }]
        groups += store.tabGroups.filter { $0.id != tab.groupID }.map { group in
            HoldMenuItem(title: group.name, systemImage: nil) {
                withAnimation(glide) { store.move(tab, toEndOf: group) }
            }
        }
        if tab.groupID != nil {
            groups.append(HoldMenuItem(title: "Remove from Group", systemImage: "folder.badge.minus") {
                withAnimation(glide) { store.takeOutOfGroup(tab) }
            })
        }
        keep.append(HoldMenuItem(title: "Move to Group", systemImage: "folder", children: groups))
        if tab.url != nil {
            keep.append(HoldMenuItem(title: "Duplicate Tab", systemImage: "plus.square.on.square") {
                withAnimation(glide) { _ = store.duplicate(tab) }
            })
        }
        // Any tab, not only the one on screen (David, 2026-11-17).
        let send = sending?.menuItems(for: tab) ?? []
        // No line under Copy Link, so a pointing finger's highlight glides
        // through every row down to Close Tab (David, 2026-11-09). Close
        // Other Tabs is gone: the menu has room for 8 rows (David, 2026-11-17).
        return [link + keep + send, [HoldMenuItem(title: "Close Tab", systemImage: "xmark", closes: true) { self.close(tab) }]]
    }

    /// A Basecamp tile's menu: the Mac's, less what the iPhone has no
    /// place for (split view, sound), in the Mac's words: Move to Tabs
    /// keeps it as a tab, Close removes it (David, 2026-11-19). iOS's own
    /// menu, from the grid.
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
            HoldMenuItem(title: "Close", systemImage: "xmark", closes: true) { removeTile(tab) },
        ]]
    }

    /// Close: the tile goes altogether, and a shake brings it
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
        undoManager?.setActionName("Close")
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

    // MARK: - VoiceOver's moves

    /// VoiceOver's Move Up and Move Down: the same move as a drag.
    private func move(_ tab: FirnCore.Tab, to position: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            store.move(tab, to: position)
        }
    }

    /// VoiceOver's Move Up and Move Down for a group: the same move as
    /// dragging its name line.
    private func move(_ group: TabGroup, to position: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            store.move(group, to: position)
        }
    }

    // MARK: - Spaces

    /// Another space: its tabs take the list's place and the glow and tint
    /// cross-fade (a plain fade with Reduce Motion).
    private func showSpace(_ space: Space) {
        guard slide.settling, let peek = slide.comingPeek, peek.id == space.id else {
            slide.clear()
            withAnimation(.easeOut(duration: 0.25)) { store.selectSpace(space) }
            return
        }
        // A swipe has landed: the copy is standing where this list will
        // be. Unseen, the list takes the space's tabs and the copy's own
        // scroll; a few frames later, laid out, it takes the copy's place
        // with nothing to see.
        let scroll = peek.spots.scroll
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            store.selectSpace(space)
            if let scroll { scrollPosition.scrollTo(point: Self.pin(scroll.contentOffset.y, in: scroll)) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.swapWait))
            if let scroll { scrollPosition.scrollTo(point: Self.pin(scroll.contentOffset.y, in: scroll)) }
            try? await Task.sleep(for: .milliseconds(Self.swapWait))
            guard slide.coming?.id == space.id else { return }
            withTransaction(quiet) { slide.clear() }
            copySoon()
        }
    }

    /// Two waits of this long (milliseconds) between a swipe landing and
    /// the real list taking the copy's place: time to lay out and scroll.
    private static let swapWait = 34

    /// A swipe on the name is heading for `space` (nil: for none, it has
    /// settled back): its copy is made, or dropped.
    private func aim(at space: Space?) {
        guard slide.coming?.id != space?.id, !slide.settling else { return }
        guard let space else { return slide.clear() }
        makeCopies()
        slide.coming = space
    }

    /// A finger has come down on the name: the spaces to either side are
    /// made now if they aren't there yet (they usually are: `copySoon`).
    private func readySpaces(_ on: Bool) {
        guard on, !reduceMotion, !slide.settling else { return }
        makeCopies()
    }

    /// Once the overview has been at rest a moment, the spaces to either
    /// side are drawn a screen away, ready for a swipe: made only as the
    /// swipe began, a flick showed them late, popping in as it landed
    /// (David's recording, 2026-11-23). Made again only when what they
    /// show has changed; dropped as the overview hides.
    private func copySoon() {
        copying?.cancel()
        guard !isPeek, !reduceMotion, store.spaces.count > 1 else { return }
        copying = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, shown, slide.progress == 0, !slide.settling, slide.coming == nil else { return }
            let stamp = copyStamp
            guard slide.peeks.isEmpty || slide.stamp != stamp else { return }
            slide.clear()
            makeCopies()
        }
    }

    /// What the copies show, in short: the space on screen, and every other
    /// space's tabs and groups as they're laid out. (Titles, icons, and
    /// pictures aren't in it: the copies share the real tabs.)
    private var copyStamp: Int {
        var hasher = Hasher()
        let here = store.activeSpace.id
        hasher.combine(here)
        hasher.combine(store.spaces.map(\.id))
        for tab in store.tabs where tab.spaceID != here {
            hasher.combine(tab.id)
            hasher.combine(tab.place)
            hasher.combine(tab.groupID)
        }
        for group in store.groups where group.spaceID != here {
            hasher.combine(group.id)
            hasher.combine(group.folded)
            hasher.combine(group.name)
        }
        return hasher.finalize()
    }

    private func makeCopies() {
        guard slide.peeks.isEmpty, let here = store.spaces.firstIndex(where: { $0.id == store.activeSpace.id })
        else { return }
        slide.stamp = copyStamp
        slide.peeks = [(here - 1, CGFloat(1)), (here + 1, CGFloat(-1))].compactMap { index, side in
            guard store.spaces.indices.contains(index) else { return nil }
            let space = store.spaces[index]
            return SpaceSlide.Peek(space: space, store: store.peek(at: space), side: side)
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
    /// Behind a page pulled up high and held, no darker at all: the
    /// picture comes in over the haze there, and a fifth darker took dark
    /// mode's charcoal wash to black, where Safari's grid is as light as
    /// its wallpaper (David's screenshots side by side, 2026-11-20).
    static let heldDim: Double = 0
    /// The grid came in behind a held page on this pull (`Landing.heldSeen`).
    var held = false
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
        let dim = off || !blurs ? 0 : -(held ? Self.heldDim : Self.dim) * Double(left)
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
}

/// UIKit offers "Undo Close Tab" on a shake only when something holds
/// keyboard focus, and the overview has no text field. This invisible view
/// takes that focus (giving it back to any field that wants it) and hands
/// UIKit SwiftUI's undo list. UIKit, because SwiftUI has no say in shakes.
///
/// Always installed, taking focus only while `on`: put in as the overview
/// showed, it cost 2 to 3ms inside every grab's turn (the trace of
/// 2026-11-20). It takes focus once the page has landed, not at the grab.
struct ShakeToUndo: UIViewRepresentable {
    let undoManager: UndoManager?
    let closes: Int
    let on: Bool

    func makeUIView(context: Context) -> Listener { Listener() }

    func updateUIView(_ view: Listener, context: Context) {
        view.undo = undoManager
        if on != view.on {
            view.on = on
            if !on {
                view.closes = closes
                if view.isFirstResponder { view.resignFirstResponder() }
                return
            }
            if view.window != nil { view.becomeFirstResponder() }
        }
        guard on else { return }
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
        var on = false
        override var canBecomeFirstResponder: Bool { on }
        override var undoManager: UndoManager? { undo }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, on { becomeFirstResponder() }
        }
    }
}

/// The shake listener, listening from the moment the overview has come to
/// rest (a page still gliding in has nothing to undo yet) until it hides.
/// Reads the landing here, so the overview's body doesn't.
struct ShakeHost: View {
    let landing: Landing
    let undoManager: UndoManager?
    let closes: Int
    /// Listening on this visit: on at the first rest, off only on hiding.
    @State private var listening = false

    var body: some View {
        ShakeToUndo(undoManager: undoManager, closes: closes, on: listening && landing.shown)
            .onChange(of: landing.shown && landing.gliding == nil, initial: true) { _, rested in
                if rested { listening = true }
            }
            .onChange(of: landing.shown) { _, shown in if !shown { listening = false } }
    }
}

