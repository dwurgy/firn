import FirnCore
import SwiftUI

/// The page, edge to edge, with Firn's address bar floating over its bottom
/// edge, and the tab overview behind it (the tabs button, or a swipe up on
/// the bar, shows it).
struct BrowserScreen: View {
    let store: BrowserStore
    let pictures: PagePictures
    /// A link from another app, opened as a new tab once it arrives.
    @Binding var incoming: URL?
    @FocusState private var editing: Bool
    /// Whether the overview is there behind (or instead of) the page.
    @State private var showingTabs = false
    /// How far the overview has arrived, 0 to 1 (animated, or following a
    /// pull): its bar shows, the dim over its cards lifts, and the page's
    /// bar goes.
    @State private var arrival: CGFloat = 0
    /// The glide (step 3b). The page's picture makes the move, standing in
    /// for the page: moving the page itself makes UIKit work out its safe
    /// area again every frame, so WebKit lays the whole page out again and
    /// the glide froze. The live page stays put, hidden, and swaps with the
    /// picture at either end.
    @State private var standIn: UIImage?
    /// The stand-in's size.
    private var standInSize: CGSize? { standIn?.size }
    /// A pull has the live page itself following the finger, until its
    /// picture comes (WebKit takes 50–100ms) and takes its place in the
    /// same spot, in one frame. Moved by its layer only (`PageHold`), so
    /// it never lays out again (`docs/IOS-PLAN.md`, the swipe up's delay,
    /// step 2b).
    @State private var livePull = false
    /// What a pull moves: the picture once it's here, the live page below
    /// the status bar until then (the same size: the picture leaves the
    /// strip out too).
    private var pulledSize: CGSize? {
        if let standInSize { return standInSize }
        guard livePull, pageFrame.width > 0 else { return nil }
        return CGSize(width: pageFrame.width, height: max(pageFrame.height - pictures.topInset, 1))
    }
    /// The page's color behind the status bar, which the picture leaves
    /// out. Never faded: it goes the moment the page starts to move and is
    /// back the moment it's the page again. Fading, it read as a separate
    /// band of color hanging behind the clock (David's recording,
    /// 2026-11-09).
    @State private var standInTop: CGColor?
    @State private var stripOpacity: Double = 1
    /// The picture and its strip fading off a woken page. Its own value:
    /// removing them inside an animation swapped in one frame.
    @State private var standInFade: Double = 1
    /// A Basecamp tile and the page's picture cross-fade where they meet:
    /// 1 shows the tile, 0 the picture. A tile has no title pill, so the
    /// picture can't land as a card does.
    @State private var tileReveal: Double = 1
    /// The tab the picture is of, for the card's line riding on it.
    @State private var standInTab: FirnCore.Tab?
    /// The page is gliding into its own card as the overview opens: the
    /// picture wears the card's ring, fading in over the glide's second
    /// half, so it's there when the card swaps in (David, 2026-11-08: it
    /// came in only after landing).
    @State private var ringOnGlide = false
    /// The width of the card the picture glides into or out of. A tab in a
    /// group is narrower than a loose one (the group card's padding); the
    /// line riding on the picture is laid out at this width, so it matches
    /// the card's own and nothing jumps as they swap (David, 2026-11-08: the
    /// title pill jittered and resized, only in groups).
    @State private var standInCardWidth: CGFloat?
    /// Where the shown part of the picture sits on screen: the page's own
    /// place, a card, a row, or wherever the finger has pulled it. Its
    /// corners, and how much the card's line on it has faded in.
    @State private var box: CGRect = .zero
    @State private var boxRadius: CGFloat = 0
    /// Gliding into a tile: where it started and the tile's size, so the
    /// picture takes the tile's shape early (`CardGlide`).
    @State private var tileCrop: (from: CGRect, to: CGSize)?
    @State private var lineOnPicture: Double = 0
    /// The page being pulled up from the bar (step 3c), while the finger
    /// is down.
    @State private var pull: Pull?
    /// True while a finger is on the bar's drag; iOS resets it when the
    /// drag is cancelled too, which `onEnded` never hears about.
    @GestureState private var dragging = false
    /// The pull (or tabs-button glide) whose page picture may still take
    /// the page's place: set when it starts, cleared once it gives up. A picture
    /// arriving later (WebKit can take a while on a heavy page) is dropped:
    /// it used to land during the fade back and hide the page for good
    /// (David's recordings, 2026-11-04).
    @State private var pullAwaitingPicture: UUID?
    /// The bar's buttons stay still from a pull's start until just after
    /// the finger lifts (the button would see the lift as a tap).
    @State private var barQuiet = false
    /// The tabs beside the one being pulled or swiped (step 3c, step 2),
    /// riding with it a gap apart, and how much they show (they fade as the
    /// page lands in its card).
    @State private var neighbors: [Neighbor] = []
    @State private var neighborsOpacity: Double = 1
    /// How far the tabs beside it have come in (0 to 1). A pull up shows
    /// them only after a short hold, sliding in from the edges, so a quick
    /// flick never does (as in Safari; David, 2026-11-10); a sideways swipe
    /// shows them at once. Only shown can one be picked.
    @State private var neighborsIn: CGFloat = 1
    /// Held after a pull up, the tabs beside it peek in from the screen's
    /// edges rather than sitting beside it, a little bigger than the held
    /// page, and move with it sideways (as in Safari; David, 2026-11-10).
    @State private var neighborsPeek = false
    /// How far the held page has been moved sideways, kept past the
    /// finger's lift for the landing.
    @State private var heldShift: CGFloat = 0
    /// How much of a peeking tab shows at the screen's edge.
    private static let peek: CGFloat = 20
    /// How long a pull up is held before the tabs beside it come in.
    private static let neighborsWait = Duration.milliseconds(450)
    /// A sideways swipe on the bar: the pages slide at full size, over the
    /// frame's sand, with the overview left out.
    @State private var swiping = false
    /// While the overview is up (and while the picture moves).
    @State private var pageHidden = false
    /// The tab whose card is hidden while the picture stands in for it.
    @State private var gliding: UUID?
    /// The tab on screen's title line, faded in after the landing.
    @State private var lineShown = true
    /// The card that keeps its size while another tab grows out of its row.
    @State private var heldCard: UUID?
    @State private var spots = OverviewSpots()
    /// The page's own frame on screen, to aim the glide from.
    @State private var pageFrame: CGRect = .zero
    /// Whether the address being typed opens a new tab (from the overview's
    /// +) rather than replacing the page on screen.
    @State private var typingNewTab = false
    /// A sideways swipe on the last tab, toward where the next would be:
    /// how close it is to starting a new tab (0 to 1). Let go at 1 and the
    /// page settles back while typing for a new tab opens over it, as the
    /// overview's + does: Firn types over the page, never on a blank one.
    @State private var newTabReach: CGFloat = 0
    /// How far the finger has gone left past the last tab (0 or less);
    /// the + slides in from the edge with it. The page itself stays still:
    /// moving it needed a picture of the page first, and waiting for
    /// WebKit made the swipe start late and then jump (David's recording,
    /// 2026-11-06).
    @State private var newTabShift: CGFloat = 0
    /// A swipe past the last tab is under way (instead of a pull).
    @State private var newTabSwipe = false
    /// The page menu, grown out of the bar.
    @State private var menuOpen = false
    /// Where the bar's top edge and the page's bottom edge sit on screen, so
    /// the page knows how much of it the bar covers.
    @State private var barTop: CGFloat = 0
    /// Scrolling down to read has shrunk the bar to a small pill (phase 5).
    @State private var barShrunk = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver always has the whole bar (phase 5): its buttons stay where
    /// a swipe through them finds them.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack(alignment: .bottom) {
            // Always built, hidden behind the page while browsing, so a swipe
            // up only reveals it: building it on each swipe held the screen
            // still for the first ~80ms, and 1.1s the first time after
            // launch (David's iPhone, 2026-11-10).
            TabOverview(store: store, pictures: pictures, spots: spots, gliding: gliding, tileReveal: tileReveal,
                        lineShown: lineShown, heldCard: heldCard, arrival: arrival, open: openTab,
                        done: { if let tab = store.activeTab { openTab(tab) } else { hideTabs() } },
                        newTab: startNewTab, typing: editing, shown: showingTabs)
                // Typing from + leaves the overview where it is, under
                // the dim; its own bar stays behind the keyboard.
                .ignoresSafeArea(.keyboard)
                .opacity(showingTabs ? 1 : 0)
                .allowsHitTesting(showingTabs && !editing && gliding == nil)
                .accessibilityHidden(!showingTabs || editing)
            // Under the page, so it shows only once the page's picture has
            // taken its place (above, it covered the page for a frame).
            if swiping {
                Theme.frame
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            pageLayer
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    pageFrame = $0
                    pictures.pageWidth = $0.width
                }
                .opacity(pageHidden ? 0 : 1)
                .allowsHitTesting(!showingTabs)
                .accessibilityHidden(showingTabs)

            if let standInSize = pulledSize, standInSize.width > 0 {
                if let standInTop {
                    // A fill, so a new tab's color fades in rather than snaps.
                    Rectangle()
                        .fill(Color(cgColor: standInTop))
                        .frame(height: pictures.topInset)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .opacity(stripOpacity * standInFade)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Placed from the screen's top-left corner, in the screen's
                // own points, as the cards report theirs (measured: the
                // layer's own corner isn't the screen's).
                let width = pageFrame.width
                let height = width * standInSize.height / standInSize.width
                let cardWidth = max(standInCardWidth ?? width - 32, 1)
                GeometryReader { layer in
                    let corner = layer.frame(in: .global).origin
                    ZStack(alignment: .topLeading) {
                        // The tabs beside it, the same size, a gap apart.
                        ForEach(neighbors) { neighbor in
                            Group {
                                if let image = neighbor.image {
                                    Image(uiImage: image)
                                        .resizable()
                                        .frame(width: width, height: width * image.size.height / max(image.size.width, 1))
                                } else {
                                    // Never pictured: a plain page.
                                    Color.clear.frame(width: width, height: height)
                                }
                            }
                            .frame(width: width, height: height, alignment: .top)
                            .background(Theme.page)
                            .modifier(CardGlide(width: width, box: neighbor.pinned ?? neighborBox(neighbor.place),
                                                radius: boxRadius))
                            // In from beyond the screen's edge.
                            .offset(x: CGFloat(neighbor.place) * (1 - neighborsIn) * (Self.peek + 40))
                            .opacity(neighborsOpacity * neighborsIn)
                        }
                        Group {
                            if let standIn { Image(uiImage: standIn).resizable() }
                        }
                        .frame(width: width, height: height)
                        .modifier(CardGlide(width: width, box: box, radius: boxRadius,
                                            cropFrom: tileCrop?.from, cropTo: tileCrop?.to))
                        .modifier(ArrivalBand(arrival: standInTab?.place == .basecamp ? tileReveal : 0,
                                              range: BasecampTiles.glideSwap, fadesIn: false))
                        if ringOnGlide, let standInTab, standInTab.place != .basecamp {
                            // The card's ring (`CardRing`), on the picture's inside edge.
                            CardRing(color: Theme.spaceColor(store.activeSpace.color), radius: boxRadius)
                                .frame(width: box.width, height: box.height)
                                .offset(x: box.minX, y: box.minY)
                                .modifier(RingFade(arrival: arrival))
                        }
                        // The card's line, drawn at the card's size and
                        // scaled with the picture (no layout while it moves).
                        // A tile has no line: only cards get it.
                        if let standInTab, standInTab.place != .basecamp {
                            CardTop(tab: standInTab, space: store.activeSpace.color, picture: standIn)
                                .frame(width: cardWidth)
                                .clipShape(CardTop.shape(OverviewRow.cornerRadius))
                                .scaleEffect(box.width / cardWidth, anchor: .topLeading)
                                .offset(x: box.minX, y: box.minY)
                                // Never quite 0 while it rides the
                                // picture: at 0 iOS drops the line's blur,
                                // and building it again (or dropping it)
                                // froze a frame about 100ms into every
                                // glide (David's recording, 2026-11-04).
                                .opacity(max(lineOnPicture, 0.002))
                        }
                    }
                    .offset(x: -corner.x, y: -corner.y)
                }
                .opacity(standInFade)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            // Swiped past the last tab: a frosted + at the edge says a new
            // tab is a let-go away.
            NewTabHint(space: store.activeSpace.color, reach: newTabReach)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                // Just off the screen's edge at rest, sliding in with the
                // finger (trailing-aligned, it starts half its width in).
                .offset(x: newTabShift + BarButton.glassSize)
                // It stays put as the keyboard comes up (it rode up with
                // the bar; David, 2026-11-06).
                .ignoresSafeArea(.keyboard)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // While typing, the page (or the overview) dims a little; a tap
            // on it cancels.
            if editing {
                Theme.typingDim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { editing = false }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }

            // The page menu closes on a tap anywhere else, as iOS's menus
            // do (no dim: it's a small menu, not a mode).
            if menuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { menuOpen = false }
                    .accessibilityHidden(true)
            }

            bar
                // Over the overview, the bar shows only while typing from +.
                // It fades out over the first half of the glide, before the
                // overview's bar fades in, so the two never overlap. During
                // a glide it stays a hair above 0: at 0 iOS lets its glass
                // go, and setting the glass up again froze a frame partway
                // back to the page (David's recording, 2026-11-04).
                // Worked out on every frame (`ArrivalBand`): a plain
                // opacity fades straight from start to end, so both bars
                // faded at once and their words smudged together (David's
                // recording, 2026-11-09).
                .modifier(ArrivalBand(arrival: editing ? 0 : arrival, range: 0...0.2, fadesIn: false,
                                      floor: !editing && gliding != nil ? 0.002 : 0))
                .allowsHitTesting(barShown)
                .accessibilityHidden(!barShown)
        }
        .background(Theme.page.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { pictures.topInset = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: editing)
        .onChange(of: editing) { if !editing { typingNewTab = false } }
        .onChange(of: incoming, initial: true) { openIncoming() }
        // The bar's buttons wake once the pull's landing is over, not on a
        // timer: waking them redraws the whole bar, and 150ms after the
        // finger lifted that fell mid-landing and froze a frame (David's
        // recordings, 2026-11-04). Every landing ends with gliding = nil,
        // well past the finger's lift.
        .onChange(of: gliding) {
            guard gliding == nil else { return }
            if barQuiet { barQuiet = false }
        }
    }

    private var barShown: Bool { arrival < 1 || editing }

    /// The glide: quick, then easing gently into place (about 0.3s, as
    /// Safari's). A curve rather than a spring: a spring's last frames
    /// creep (about 0.4s on David's iPhone), and it reports done before it
    /// has landed, so the swap with the page jumped the last few points.
    private static let glide = Animation.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.32)
    /// Into a Basecamp tile, a far bigger change (the whole screen down to
    /// 56pt): a little longer and a gentler start, so it reads as a glide
    /// rather than a snap (David's recording, 2026-11-09).
    private static let tileGlide = Animation.timingCurve(0.25, 0.7, 0.25, 1, duration: 0.42)
    private static let fade = Animation.easeOut(duration: 0.2)

    private var bar: some View {
        AddressBar(store: store, editing: $editing, typingNewTab: typingNewTab,
                   showTabs: showTabs, opened: hideTabs, menuOpen: $menuOpen, shrunk: $barShrunk)
            // Once the page is pulled, the bar's buttons let go of the
            // touch: lifting the finger over one mustn't tap it.
            .environment(\.barQuiet, barQuiet)
            // A new page or another tab starts with the full bar.
            .onChange(of: store.activeTab?.page.map { ObjectIdentifier($0) }) { barShrunk = false }
            .onChange(of: store.activeTab?.page?.url) { barShrunk = false }
            .onChange(of: voiceOver) { if voiceOver { barShrunk = false } }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                // Only the bar at rest counts: while it rides the keyboard,
                // the page underneath shouldn't lay out again.
                if !editing { barTop = top }
            }
            // A swipe up on the bar pulls the page into the overview, as
            // in Safari. Alongside the bar's own buttons, so a tap still taps.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged(pullMoved)
                    .onEnded { pullEnded(translation: $0.translation, velocity: $0.velocity) }
            )
            .onChange(of: dragging) { _, now in
                if !now, newTabSwipe {
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        if newTabSwipe { newTabSwipeEnded(translation: .zero, velocity: .zero) }
                    }
                    return
                }
                guard !now, pull != nil else { return }
                // The drag stopped without ending: the system took the
                // touch away (David's recording, 2026-11-04: the page's
                // picture stayed parked over the screen, the bar gone,
                // until the next swipe). A beat later, if no end came,
                // let go where it is, with no speed.
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard let pull else { return }
                    pullEnded(translation: pull.translation, velocity: .zero)
                }
            }
            // The bar rises with the keyboard only for typing an address; a
            // page's own fields leave it resting behind the keyboard, as in
            // Safari.
            .ignoresSafeArea(.keyboard, edges: editing ? [] : .bottom)
    }

    @ViewBuilder private var pageLayer: some View {
        if let page = store.activeTab?.page {
            // The page's room follows the bar: shrunk, its end rests just
            // above the small pill (phase 5, step 3).
            PageView(page: page, barTop: barTop > 0 && barShrunk ? barTop + AddressBar.compactTopDrop : barTop,
                     held: livePull ? PageHold(box: box, radius: boxRadius) : nil) { scroll in
                let shrink = scroll == .shrink && !voiceOver
                if barShrunk != shrink { barShrunk = shrink }
            }
                // A new tab gets a new web view, not the last one's.
                .id(ObjectIdentifier(page))
        } else if store.openTabs.isEmpty {
            // A space with no tabs: First light, exactly as the Mac's empty
            // page (no words, no centered mark; only the snow takes the
            // space's color).
            FirstLightScene(spaceColor: store.activeSpace.color)
                .transition(.opacity)
        } else {
            Theme.page
        }
    }

    /// The page shrinks, corners rounding, straight into its own card; the
    /// other cards wait under a dim that lifts as it goes, and the bars
    /// cross-fade in place. The card's line rides on the picture and fades
    /// in over the last stretch, so it's there as it lands. Reduce Motion,
    /// or no tab: a cross-fade.
    private func showTabs() {
        guard !showingTabs else { return }
        openActiveGroup()
        let tab = store.activeTab
        editing = false
        menuOpen = false
        guard let tab, !reduceMotion else {
            // The page as it is, for its card.
            if let tab { pictures.capture(tab) }
            withAnimation(Self.fade) {
                showingTabs = true
                arrival = 1
                pageHidden = true
            }
            return
        }
        // The overview lays out behind the page, scrolled to its card, with
        // the card hidden and its line out until the picture lands; the
        // page's picture is taken meanwhile.
        SwipeTiming.begin("tabs button", tab: tab.id)
        let picture = pictures.capture(tab)
        beginGlide(of: tab)
        // WebKit may never answer (a busy page). Waited on with no limit,
        // the page stayed over the overview and every swipe up after was
        // refused; after half a second the overview fades in instead, and
        // a picture that comes later is dropped.
        let glide = UUID()
        pullAwaitingPicture = glide
        Task {
            let image = await picture?.value
            SwipeTiming.mark(image == nil ? "no picture" : "picture arrived")
            guard let image, pullAwaitingPicture == glide else {
                if pullAwaitingPicture == glide { pullAwaitingPicture = nil; fadeToTabs() }
                return
            }
            pullAwaitingPicture = nil
            putStandIn(image, of: tab, at: pageBox(for: image))
            SwipeTiming.mark("picture set")
            land(inCardOf: tab, curve: tab.place == .basecamp ? Self.tileGlide : Self.glide)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard pullAwaitingPicture == glide else { return }
            pullAwaitingPicture = nil
            SwipeTiming.mark("gave up waiting, faded")
            fadeToTabs()
        }
    }

    /// The overview, laid out behind the page with the tab's card hidden.
    private func beginGlide(of tab: FirnCore.Tab) {
        openActiveGroup()
        gliding = tab.id
        // A tile's spot stays empty until its page lands in it; shown, the
        // tile sat there during the pull, vanished as the finger lifted,
        // and came back (Simulator recording, 2026-11-09).
        if tab.place == .basecamp { tileReveal = 0 }
        ringOnGlide = true
        standInCardWidth = spots.frames[tab.id]?.width
        lineShown = false
        lineOnPicture = 0
        showingTabs = true
    }

    /// The tab on screen's group opens with the overview, before it lays
    /// out, so the page has its card to shrink into (a folded group shows
    /// only its name). It stays open after.
    private func openActiveGroup() {
        guard let id = store.activeTab?.groupID,
              let group = store.tabGroups.first(where: { $0.id == id }), group.folded else { return }
        store.setFolded(group, false)
    }

    /// The picture takes the page's place (or a card's), and the page hides.
    private func putStandIn(_ image: UIImage, of tab: FirnCore.Tab, at frame: CGRect, radius: CGFloat = 0) {
        box = frame
        boxRadius = radius
        stripOpacity = radius == 0 ? 1 : 0
        standInTop = tab.page?.topColor
        standInTab = tab
        standIn = image
        standInFade = 1
        pageHidden = true
    }

    /// The page's own place on screen, for its picture: just below the
    /// status bar, as wide as the page.
    private func pageBox(for image: UIImage) -> CGRect {
        pageBox(size: image.size)
    }

    private func pageBox(size: CGSize) -> CGRect {
        let width = pageFrame.width
        let height = size.width > 0 ? width * size.height / size.width : pageFrame.height
        return CGRect(x: 0, y: pictures.topInset, width: width, height: height)
    }

    /// The picture glides from wherever it is into the tab's card; then the
    /// card takes its place in one frame. A card off screen: a cross-fade.
    private func land(inCardOf tab: FirnCore.Tab, curve: Animation) {
        Task {
            guard let spot = await spot(of: tab.id) else { return fadeToTabs() }
            let tile = tab.place == .basecamp
            if tile {
                tileReveal = 0
                tileCrop = (from: box, to: spot.size)
            }
            standInCardWidth = spot.width
            withTransaction(Transaction(animation: nil)) { stripOpacity = 0 }
            withAnimation(curve) {
                box = spot
                // Into a tile: on the glide's own curve, so the picture and
                // the tile swap as it settles into the tile's spot
                // (`BasecampTiles.glideSwap`).
                if tile { tileReveal = 1 }
                boxRadius = tile ? BasecampTiles.cornerRadius : OverviewRow.cornerRadius
                arrival = 1
                neighborsOpacity = 0
            } completion: {
                // The card shows the same picture and line: they swap.
                neighbors = []
                lineShown = true
                gliding = nil
                ringOnGlide = false
                standIn = nil
                standInTab = nil
                tileCrop = nil
            }
            // The line's fade starts on the glide's first frame (where the
            // page has just become its picture, so a hiccup can't show) and
            // eases in, so it's mostly seen over the second half. Started
            // 0.12s in, it froze a frame there (David's recordings,
            // 2026-11-04). A tile has no line.
            if !tile {
                withAnimation(.easeIn(duration: 0.26)) { lineOnPicture = 1 }
            }
        }
    }

    /// No picture or no card to aim at: the overview fades in.
    private func fadeToTabs() {
        livePull = false
        tileReveal = 1
        standIn = nil
        standInTab = nil
        neighbors = []
        swiping = false
        withAnimation(Self.fade) {
            arrival = 1
            pageHidden = true
        } completion: {
            gliding = nil
            ringOnGlide = false
        }
        lineShown = true
    }

    /// The tapped card (or row) grows to the full screen and the rest dim
    /// behind it; the overview leaves once the page has its room.
    private func openTab(_ tab: FirnCore.Tab) {
        guard showingTabs, gliding == nil else { return }
        let spot = spots.frames[tab.id].flatMap { visible($0) }
        // The tab already on screen is still drawn, hidden, so it swaps in
        // at once; another tab's page is made (or woken) now and can be
        // blank for a moment, so its picture fades off it.
        let switching = tab.id != store.activeTab?.id
        let fromCard = spots.cards.contains(tab.id)
        heldCard = store.activeTab?.id
        store.select(tab)
        guard let spot, let image = pictures.image(for: tab.id), !reduceMotion else {
            heldCard = nil
            hideTabs()
            return
        }
        let tile = tab.place == .basecamp
        // Out of a tile: the tile shows at first, and the picture comes up
        // over it as it starts to grow.
        tileReveal = tile ? 1 : 0
        standInCardWidth = spot.width
        putStandIn(image, of: tab, at: spot,
                   radius: tile ? BasecampTiles.cornerRadius : OverviewRow.cornerRadius)
        // A card's line leaves first; a slim row has none on its picture.
        lineOnPicture = fromCard ? 1 : 0
        ringOnGlide = false
        gliding = tab.id
        Task {
            await Task.yield()
            withAnimation(.easeOut(duration: 0.1)) { lineOnPicture = 0 }
            // On the glide's own curve: the tile and picture swap as it
            // starts to grow (`BasecampTiles.glideSwap`).
            if tile { withAnimation(Self.glide) { tileReveal = 0 } }
            land(onPage: tab, curve: Self.glide, switching: switching)
        }
    }

    /// The picture glides from wherever it is to the page's own place, and
    /// the page takes over.
    private func land(onPage tab: FirnCore.Tab, curve: Animation, switching: Bool) {
        guard let standInSize else { return hideTabs() }
        withAnimation(curve) {
            box = pageBox(size: standInSize)
            boxRadius = 0
            arrival = 0
            // The tabs beside it glide from where they are to beside it.
            neighborsPeek = false
            for i in neighbors.indices { neighbors[i].pinned = nil }
        } completion: {
            stripOpacity = 1
            pageHidden = false
            showingTabs = false
            swiping = false
            neighbors = []
            gliding = nil
            ringOnGlide = false
            heldCard = nil
            lineShown = true
            standInTab = nil
            guard switching, let waiting = self.standIn else {
                self.standIn = nil
                return
            }
            Task {
                // A tab that was asleep (or shown again) gets a new web
                // view, which is plain white until WebKit first draws, in
                // dark mode too. The picture stays until the page has
                // finished loading (2.5s at most), then two frames more for
                // the drawing to reach the screen, then fades off it.
                // Leaving once the page was half loaded showed about three
                // white frames before a dark page (found 2026-11-04).
                for _ in 0..<50 {
                    if let page = store.activeTab?.page, page.url != nil, !page.isLoading { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                try? await Task.sleep(for: .milliseconds(34))
                // A new glide may have started meanwhile, with its own picture.
                guard self.standIn === waiting, gliding == nil else { return }
                withAnimation(Self.fade) { standInFade = 0 } completion: {
                    guard self.standIn === waiting, gliding == nil else { return }
                    self.standIn = nil
                    standInTop = nil
                    standInFade = 1
                }
            }
        }
    }

    /// A link from another app (Firn as the default browser) opens as a new
    /// tab in the space on screen, the space used last, as on the Mac.
    /// Anything but http and https is refused (CLAUDE.md, Security).
    private func openIncoming() {
        guard let url = incoming else { return }
        incoming = nil
        guard WebAddress.isWebURL(url) else { return }
        editing = false
        store.openTab(url)
        if showingTabs { hideTabs() }
    }

    /// Back to the page with a cross-fade (a new tab from +, Reduce Motion,
    /// or a card off screen).
    private func hideTabs() {
        livePull = false
        standIn = nil
        standInTab = nil
        neighbors = []
        swiping = false
        withAnimation(Self.fade) {
            pageHidden = false
            arrival = 0
            showingTabs = false
        } completion: {
            gliding = nil
            ringOnGlide = false
            lineShown = true
        }
    }

    // MARK: The pull (step 3c)

    /// A pull under way: where the finger came down, and the page's picture
    /// being taken for it.
    private struct Pull {
        let id = UUID()
        let tab: FirnCore.Tab
        let start: CGPoint
        let picture: Task<UIImage?, Never>?
        var translation: CGSize = .zero
        /// Started sideways: the page slides at full size between tabs,
        /// and never shrinks.
        var sideways = false
    }

    /// A tab beside the one held: -1 just before it in the list (on the
    /// left), 1 just after it.
    private struct Neighbor: Identifiable {
        let id: UUID
        let tab: FirnCore.Tab
        let image: UIImage?
        var place: Int
        /// Where it's drawn while set, rather than by its place: where it
        /// was as another tab was picked, so it glides on from there.
        var pinned: CGRect? = nil
    }

    /// The finger moves on the bar. Going up more than across, it grabs the
    /// page: the overview lays out behind, the page's picture is taken, and
    /// from then on the picture follows the finger.
    private func pullMoved(_ drag: DragGesture.Value) {
        if var pull {
            pull.translation = drag.translation
            self.pull = pull
            if pulledSize != nil { box = pulledBox(pull); followPull(pull) }
            return
        }
        if newTabSwipe { return followNewTabSwipe(drag.translation) }
        guard !editing, !menuOpen, !showingTabs, gliding == nil, !reduceMotion,
              let tab = store.activeTab else { return }
        let dx = drag.translation.width, dy = drag.translation.height
        let up = dy < -4 && -dy > abs(dx)
        let across = abs(dx) > 8 && abs(dx) > abs(dy)
        guard up || across else { return }
        let beside = neighbors(of: tab)
        // Left on the last tab: a new tab, with the page left where it is.
        if !up, dx < 0, isLast(tab) {
            newTabSwipe = true
            barQuiet = true
            reachedNewTab.prepare()
            return followNewTabSwipe(drag.translation)
        }
        // Sideways with no other tab: nothing to slide to.
        guard up || !beside.isEmpty else { return }
        // A tab just opened keeps its picture over the page until the page
        // has loaded (up to 2.5s). Pulled meanwhile, that picture is the
        // pull's own, taken over at once. Left there, the pull's new
        // picture was refused (one was already up), the page never hid,
        // and after landing in its card the live page stayed over the
        // overview, stuck, with no bar (David, 2026-11-05). No new picture
        // either: the page is likely still blank.
        let lingering = standIn
        let lingeringTop = standInTop
        SwipeTiming.begin(up ? "swipe up" : "sideways swipe", tab: tab.id)
        if lingering != nil { SwipeTiming.mark("used the picture already up") }
        let picture = lingering == nil ? pictures.capture(tab) : nil
        let started = Pull(tab: tab, start: drag.startLocation, picture: picture,
                           translation: drag.translation, sideways: !up)
        pull = started
        pullAwaitingPicture = lingering == nil ? started.id : nil
        barQuiet = true
        neighbors = beside
        neighborsOpacity = 1
        neighborsIn = up ? 0 : 1
        neighborsPeek = up
        heldShift = 0
        if up, !beside.isEmpty {
            Task {
                try? await Task.sleep(for: Self.neighborsWait)
                guard pull?.id == started.id else { return }
                withAnimation(.smooth(duration: 0.3)) { neighborsIn = 1 }
            }
        }
        if up {
            beginGlide(of: tab)
        } else {
            // The overview stays out of a sideways swipe.
            gliding = tab.id
            lineOnPicture = 0
            swiping = true
        }
        if let lingering {
            putStandIn(lingering, of: tab, at: pageBox(for: lingering))
            if lingeringTop != nil { standInTop = lingeringTop }
            box = pulledBox(started)
            followPull(started)
            return
        }
        // The live page moves at once, from this very frame; its picture
        // takes over when it comes.
        livePull = true
        standInTop = tab.page?.topColor
        stripOpacity = 1
        boxRadius = 0
        box = pulledBox(started)
        followPull(started)
        SwipeTiming.mark("live page held")
        Task {
            let fresh = await picture?.value
            SwipeTiming.mark(fresh == nil ? "no new picture" : "picture arrived")
            guard let image = fresh ?? pictures.image(for: tab.id) else { return }
            // Still held (or let go but not landed yet): the picture takes
            // the live page's place exactly where it is, in one frame.
            guard livePull, pullAwaitingPicture == started.id, standIn == nil, gliding == tab.id else { return }
            pullAwaitingPicture = nil
            let held = box, radius = boxRadius, strip = stripOpacity
            putStandIn(image, of: tab, at: held, radius: radius)
            stripOpacity = strip
            livePull = false
            SwipeTiming.mark("picture set")
        }
    }

    /// How far up the page has been pulled, 0 at rest and 1 at half the
    /// screen's height (past that it gives less and less).
    private func lift(_ pull: Pull) -> CGFloat {
        guard !pull.sideways else { return 0 }
        let height = max(pageFrame.height, 1)
        return max(0, -pull.translation.height) / (height * 0.5)
    }

    /// The overview, the bars, and the strip behind the clock follow how
    /// far the page has been pulled.
    private func followPull(_ pull: Pull) {
        if pull.sideways {
            // Corners round as soon as the page moves, so it reads as a
            // page among pages. The strip behind the clock stays: iOS picks
            // the clock's color from what's under it, a moment late, and
            // with the strip gone the clock vanished against the sand
            // (David's recording, 2026-11-04, dark mode).
            boxRadius = min(abs(pull.translation.width) / 60, 1) * 34
            return
        }
        let progress = min(lift(pull), 1)
        arrival = progress * 0.85
        // Gone at once, never faded, even inside the picture's catch-up glide.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { stripOpacity = progress > 0 ? 0 : 1 }
        boxRadius = min(progress * 4, 1) * 34
    }

    /// Where the picture is while pulled: smaller as it rises (down to
    /// about 58% of the screen, then slower), and the point under the
    /// finger when it came down stays under the finger, in any direction.
    private func pulledBox(_ pull: Pull) -> CGRect {
        guard let size = pulledSize else { return box }
        let page = pageBox(size: size)
        let lift = lift(pull)
        // Past half the screen, each point of lift shrinks it less.
        let beyond = max(0, lift - 1)
        let scale = 1 - 0.42 * min(lift, 1) - 0.12 * (1 - 1 / (1 + beyond))
        // Pulled down, it barely gives; swiped sideways, it stays level.
        let dy = pull.sideways ? 0
            : pull.translation.height > 0 ? pull.translation.height * 0.15 : pull.translation.height
        let dx = sidewaysShift(pull)
        let finger = CGPoint(x: pull.start.x + dx, y: pull.start.y + dy)
        let anchorX = pull.start.x - page.minX
        let anchorY = pull.start.y - page.minY
        var top = finger.y - anchorY * scale
        // Held up, its top stays below the clock, giving only a little
        // (Safari's does; Firn's rose under the status bar, David's
        // recording, 2026-11-10). The limit comes in as it shrinks, so
        // nothing moves at the grab.
        if !pull.sideways {
            let limit = pictures.topInset + 20 * min((1 - scale) / 0.42, 1)
            if top < limit { top = limit - 10 * (1 - exp(-(limit - top) / 60)) }
        }
        return CGRect(x: finger.x - anchorX * scale, y: top,
                      width: page.width * scale, height: page.height * scale)
    }

    /// How far the held page goes sideways with the finger. Swiped toward
    /// a side with no tab, it gives a little and comes back.
    private func sidewaysShift(_ pull: Pull) -> CGFloat {
        var dx = pull.translation.width
        if pull.sideways, !neighbors.contains(where: { $0.place == (dx > 0 ? -1 : 1) }) { dx *= 0.3 }
        return dx
    }

    /// Let go: pulled far enough or flicked up, it lands in its card;
    /// otherwise (or flicked down) it goes back to being the page. Either
    /// way it starts at the finger's speed.
    private func pullEnded(translation: CGSize, velocity: CGSize) {
        if newTabSwipe { return newTabSwipeEnded(translation: translation, velocity: velocity) }
        guard var pull else { return }
        SwipeTiming.mark("finger lifted")
        pull.translation = translation
        heldShift = sidewaysShift(pull)
        self.pull = nil
        let up = -velocity.height
        let flickedUp = !pull.sideways && up > 500
        let toTabs = !pull.sideways && (flickedUp || (lift(pull) > 0.22 && up > -300))
        Task {
            // The picture may still be on its way.
            for _ in 0..<20 where standIn == nil {
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard standInSize != nil else {
                // Too late now: a picture arriving after this is dropped.
                // The live page, if it was held, goes back to its place.
                if pullAwaitingPicture == pull.id { pullAwaitingPicture = nil }
                return toTabs ? fadeToTabs() : hideTabs()
            }
            // A tab beside it nearer the middle (or flicked toward) opens;
            // a flick up still goes to the overview.
            if !flickedUp, let neighbor = neighborChosen(velocity) {
                return open(neighbor, carrying: velocity)
            }
            if toTabs {
                guard let spot = await spot(of: pull.tab.id) else { return fadeToTabs() }
                land(inCardOf: pull.tab, curve: carrying(velocity, to: spot,
                                                         duration: pull.tab.place == .basecamp ? 0.42 : 0.34))
            } else {
                let page = pageBox(size: standInSize!)
                land(onPage: pull.tab, curve: carrying(velocity, to: page), switching: false)
            }
        }
    }

    /// How far the finger goes past the last tab for a new one.
    /// 90pt: at 110 a quick flick often stopped just short and had to
    /// travel on before letting go counted (David's recording, 2026-11-06).
    private static let newTabDistance: CGFloat = 90
    /// How far the + travels for each point the finger does.
    private static let newTabGive: CGFloat = 0.6

    /// The + follows the finger, 1:1-ish until it's fully in, then with
    /// resistance; it fills (with a light tap) once letting go would open
    /// a new tab.
    private func followNewTabSwipe(_ translation: CGSize) {
        let dx = min(translation.width, 0)
        let reach = min(-dx / Self.newTabDistance, 1)
        if reach == 1, newTabReach < 1 { reachedNewTab.impactOccurred() }
        newTabReach = reach
        let past = min(dx + Self.newTabDistance, 0)
        newTabShift = (max(dx, -Self.newTabDistance) + past * 0.25) * Self.newTabGive
    }

    /// Let go: far enough (or flicked) starts typing for a new tab at once,
    /// and the + fades where it is; otherwise it slides back off the edge.
    private func newTabSwipeEnded(translation: CGSize, velocity: CGSize) {
        newTabSwipe = false
        // A beat later, so lifting the finger over a button doesn't tap it.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !newTabSwipe, pull == nil { barQuiet = false }
        }
        let wants = newTabReach >= 1
            || (translation.width < -Self.newTabDistance * 0.4 && velocity.width < -400)
        if wants {
            startNewTab()
            // Back off the edge it came from, keeping its color, while the
            // keyboard comes up.
            withAnimation(.easeIn(duration: 0.2)) { newTabShift = 0 } completion: {
                newTabReach = 0
            }
        } else {
            withAnimation(.smooth(duration: 0.25)) {
                newTabReach = 0
                newTabShift = 0
            }
        }
    }
    private let reachedNewTab = UIImpactFeedbackGenerator(style: .light)

    private func isLast(_ tab: FirnCore.Tab) -> Bool {
        store.openTabs.last?.id == tab.id
    }

    /// The tabs just before and after this one in the list, with their
    /// saved pictures.
    private func neighbors(of tab: FirnCore.Tab) -> [Neighbor] {
        let tabs = store.openTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return [] }
        return [-1, 1].compactMap { place in
            let i = index + place
            guard tabs.indices.contains(i) else { return nil }
            return Neighbor(id: tabs[i].id, tab: tabs[i], image: pictures.image(for: tabs[i].id), place: place)
        }
    }

    /// The gap between the held page and the ones beside it: a little
    /// narrower as they shrink.
    private func gap(_ box: CGRect) -> CGFloat {
        12 + 12 * box.width / max(pageFrame.width, 1)
    }

    /// Where a tab beside the held one sits: the held box, moved over.
    private func neighborBox(_ place: Int) -> CGRect {
        guard neighborsPeek else { return box.offsetBy(dx: CGFloat(place) * (box.width + gap(box)), dy: 0) }
        // At the screen's edge, a little bigger than the held page, and
        // moved as far sideways as it has been.
        let screen = pageFrame.width
        let grown = box.insetBy(dx: -box.width * 0.02, dy: -box.height * 0.02)
        let shift = pull.map(sidewaysShift) ?? heldShift
        let x = place > 0 ? screen - Self.peek + shift : Self.peek + shift - grown.width
        return CGRect(x: x, y: grown.minY, width: grown.width, height: grown.height)
    }

    /// The tab beside it to open on letting go: moved (or flicked) more
    /// than about two fifths of the way toward the middle.
    private func neighborChosen(_ velocity: CGSize) -> Neighbor? {
        guard neighborsIn > 0.5 else { return nil }
        if neighborsPeek {
            // Dragged about a quarter of the screen toward one (or flicked).
            let moved = (heldShift + velocity.width * 0.15) / max(pageFrame.width, 1)
            let place = moved > 0.25 ? -1 : moved < -0.25 ? 1 : 0
            return place == 0 ? nil : neighbors.first { $0.place == place }
        }
        let spacing = box.width + gap(box)
        guard spacing > 1 else { return nil }
        let moved = (box.midX - pageFrame.midX + velocity.width * 0.15) / spacing
        let place = moved > 0.4 ? -1 : moved < -0.4 ? 1 : 0
        return place == 0 ? nil : neighbors.first { $0.place == place }
    }

    /// Opens the tab beside: it becomes the held one where it is (the one
    /// that was held rides beside it now), then grows to the full screen,
    /// carrying the finger's speed.
    private func open(_ neighbor: Neighbor, carrying velocity: CGSize) {
        guard let held = standInTab, let heldImage = standIn else { return hideTabs() }
        let image = neighbor.image ?? plainPage(like: heldImage)
        // Each where it's drawn now: the glide carries them on from there.
        let shown = Dictionary(uniqueKeysWithValues: neighbors.map { ($0.id, $0.pinned ?? neighborBox($0.place)) })
        let spot = shown[neighbor.id] ?? neighborBox(neighbor.place)
        let shift = neighbor.place
        var beside = neighbors.filter { $0.id != neighbor.id }
        for i in beside.indices {
            beside[i].place -= shift
            beside[i].pinned = shown[beside[i].id]
        }
        beside.append(Neighbor(id: held.id, tab: held, image: heldImage, place: -shift, pinned: box))
        neighbors = beside
        // Behind a pull, the overview keeps the held tab's card (hidden,
        // as gliding still names it) so nothing there changes size.
        heldCard = held.id
        store.select(neighbor.tab)
        box = spot
        standIn = image
        standInTab = neighbor.tab
        // The strip keeps its color until the glide, then fades to the new
        // tab's. A page asleep or still loading keeps the old one: before
        // it has drawn, its color is black (found 2026-11-04), and the
        // page's own strip takes over as the picture fades.
        let newTop = neighbor.tab.page.flatMap { $0.isLoading || $0.url == nil ? nil : $0.topColor }
        Task {
            // One frame in its new role before the glide, so it starts
            // where it is.
            await Task.yield()
            if let newTop { withAnimation(.easeOut(duration: 0.3)) { standInTop = newTop } }
            land(onPage: neighbor.tab, curve: carrying(velocity, to: pageBox(for: image)), switching: true)
        }
    }

    /// A blank page the size of a picture, for a tab never pictured.
    private func plainPage(like picture: UIImage) -> UIImage {
        let color = UIColor(Theme.page).resolvedColor(with: UITraitCollection.current)
        let format = UIGraphicsImageRendererFormat()
        format.scale = picture.scale
        return UIGraphicsImageRenderer(size: picture.size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: picture.size))
        }
    }

    /// An ease-out glide whose start matches the finger's speed toward
    /// where it's going: a fast flick carries straight on, a slow let-go
    /// starts gently. A curve, not a spring, so it lands exactly on time.
    private func carrying(_ velocity: CGSize, to target: CGRect, duration: Double = 0.34) -> Animation {
        let dx = target.midX - box.midX
        let dy = target.midY - box.midY
        let distance = max(hypot(dx, dy), 1)
        let toward = (velocity.width * dx + velocity.height * dy) / distance
        // The curve's starting slope is y1 / x1, in distance per duration.
        let slope = max(0, toward) * duration / distance
        let x1 = 0.2
        let y1 = min(max(slope * x1, 0.16), 1)
        return .timingCurve(x1, y1, 0.25, 1, duration: duration)
    }

    /// Where the tab's card is once the overview has laid out and scrolled
    /// to it: a few frames at most.
    private func spot(of id: UUID) async -> CGRect? {
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(16))
            if let frame = spots.frames[id], let spot = visible(frame) { return spot }
        }
        return nil
    }

    /// The spot, if it's on screen (a card scrolled away has no glide).
    private func visible(_ frame: CGRect) -> CGRect? {
        guard frame.width > 0, frame.height > 0, pageFrame.intersects(frame) else { return nil }
        return frame
    }

    /// + types right on the overview: an empty address field over it, and
    /// only Go opens a tab (and then shows the page); cancelling stays in
    /// the overview with nothing opened. Step 6's command bar opens here too.
    private func startNewTab() {
        typingNewTab = true
        editing = true
    }
}

/// The page's picture in its box: scaled to the box's width, placed on it,
/// and cut to the box's height with its corners. Transforms and a mask
/// only, so nothing lays out again while it moves.
private struct CardGlide: ViewModifier, Animatable {
    let width: CGFloat
    var box: CGRect
    var radius: CGFloat
    /// Into a tile: where the glide started, and the tile's size. The
    /// shown part takes the tile's shape over the first 60% of the way, so
    /// the page becomes a tile as it shrinks, rather than flying as a tall
    /// mini page and being cut down at the end (David's recording,
    /// 2026-11-09).
    var cropFrom: CGRect? = nil
    var cropTo: CGSize? = nil

    // Worked out on every frame, so the shown part, the ring, and the line
    // all agree on the box mid-glide.
    nonisolated var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(box.animatableData, radius) }
        set { box.animatableData = newValue.first; radius = newValue.second }
    }

    /// The shown part's height on screen.
    private var shownHeight: CGFloat {
        guard let cropFrom, let cropTo, cropTo.width > 0, cropFrom.width > cropTo.width else { return box.height }
        let travel = min(max((cropFrom.width - box.width) / (cropFrom.width - cropTo.width), 0), 1)
        let eased = 1 - pow(1 - min(travel / 0.6, 1), 2)
        let tileShaped = min(box.width * cropTo.height / cropTo.width, box.height)
        return box.height + (tileShaped - box.height) * eased
    }

    func body(content: Content) -> some View {
        let scale = width > 0 && box.width > 0 ? box.width / width : 1
        content
            // One shape throughout, so its size and corners glide.
            .mask(alignment: .top) {
                RoundedRectangle(cornerRadius: radius / scale, style: .continuous)
                    .frame(height: shownHeight / scale)
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: box.minX, y: box.minY)
    }
}

/// The frosted + that shows at the right edge as the last tab is swiped
/// past: it fades in and grows a little with the swipe, and fills with the
/// space's color once letting go would start a new tab.
private struct NewTabHint: View {
    let space: String
    let reach: CGFloat

    var body: some View {
        Image(systemName: "plus")
            .font(BarButton.symbolFont)
            .foregroundStyle(reach >= 1 ? Color.white : Theme.ink)
            .frame(width: BarButton.size, height: BarButton.size)
            .padding(2)
            // Filled once it's a let-go away. A solid fill under the glass,
            // not the glass's tint: a tinted glass that moves every frame
            // drew washed out until it stopped (Simulator recording,
            // 2026-11-06).
            .background(Circle().fill(Theme.spaceVivid(space)).opacity(reach >= 1 ? 1 : 0))
            .glassEffect(.regular.tint(Theme.frameTint(space)), in: .circle)
            .scaleEffect(0.7 + 0.3 * reach)
            .opacity(Double(reach))
            .animation(.smooth(duration: 0.2), value: reach >= 1)
    }
}

/// The gliding card's ring: nothing over the glide's first half, then in
/// with the page's arrival, full as it lands (as `ArrivalFade` does for the
/// rest of the overview).
private struct RingFade: ViewModifier, Animatable {
    var arrival: CGFloat
    nonisolated var animatableData: CGFloat {
        get { arrival }
        set { arrival = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(min(max((arrival - 0.5) / 0.5, 0), 1))
    }
}
