import FirnCore
import SwiftUI

/// The page, edge to edge, with Firn's address bar floating over its bottom
/// edge, and the tab overview behind it (the tabs button, or a swipe up on
/// the bar, shows it).
struct BrowserScreen: View {
    let store: BrowserStore
    let pictures: PagePictures
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
    /// The page's color behind the status bar, which the picture leaves
    /// out: it fades as the picture shrinks and back as it grows, so the
    /// swap with the page shows nothing.
    @State private var standInTop: CGColor?
    @State private var stripOpacity: Double = 1
    /// The picture and its strip fading off a woken page. Its own value:
    /// removing them inside an animation swapped in one frame.
    @State private var standInFade: Double = 1
    /// The tab the picture is of, for the card's line riding on it.
    @State private var standInTab: FirnCore.Tab?
    /// Where the shown part of the picture sits on screen: the page's own
    /// place, a card, a row, or wherever the finger has pulled it. Its
    /// corners, and how much the card's line on it has faded in.
    @State private var box: CGRect = .zero
    @State private var boxRadius: CGFloat = 0
    @State private var lineOnPicture: Double = 0
    /// The page being pulled up from the bar (step 3c), while the finger
    /// is down.
    @State private var pull: Pull?
    /// True while a finger is on the bar's drag; iOS resets it when the
    /// drag is cancelled too, which `onEnded` never hears about.
    @GestureState private var dragging = false
    /// The pull whose page picture may still take the page's place: set
    /// when a pull starts, cleared once it's let go without one. A picture
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
    /// The page menu, grown out of the bar.
    @State private var menuOpen = false
    /// Where the bar's top edge and the page's bottom edge sit on screen, so
    /// the page knows how much of it the bar covers.
    @State private var barTop: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if showingTabs {
                TabOverview(store: store, pictures: pictures, spots: spots, gliding: gliding,
                            lineShown: lineShown, heldCard: heldCard, arrival: arrival, open: openTab,
                            done: { if let tab = store.activeTab { openTab(tab) } else { hideTabs() } },
                            newTab: startNewTab, typing: editing)
                    // Typing from + leaves the overview where it is, under
                    // the dim; its own bar stays behind the keyboard.
                    .ignoresSafeArea(.keyboard)
                    .allowsHitTesting(!editing && gliding == nil)
                    .accessibilityHidden(editing)
                    .transition(.opacity)
            }
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

            if let standIn, standIn.size.width > 0 {
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
                let height = width * standIn.size.height / standIn.size.width
                let cardWidth = max(width - 32, 1)
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
                            .modifier(CardGlide(width: width, box: neighborBox(neighbor.place), radius: boxRadius))
                            .opacity(neighborsOpacity)
                        }
                        Image(uiImage: standIn)
                            .resizable()
                            .frame(width: width, height: height)
                            .modifier(CardGlide(width: width, box: box, radius: boxRadius))
                        // The card's line, drawn at the card's size and
                        // scaled with the picture (no layout while it moves).
                        if let standInTab {
                            CardTop(tab: standInTab, picture: standIn)
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

            // While typing, the page (or the overview) dims a little; a tap
            // on it cancels.
            if editing {
                Theme.lookoutDim
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
                .opacity(editing ? 1 : max(gliding != nil ? 0.002 : 0, 1 - arrival * 2))
                .allowsHitTesting(barShown)
                .accessibilityHidden(!barShown)
        }
        .background(Theme.page.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { pictures.topInset = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: editing)
        .onChange(of: editing) { if !editing { typingNewTab = false } }
        // The bar's buttons wake once the pull's landing is over, not on a
        // timer: waking them redraws the whole bar, and 150ms after the
        // finger lifted that fell mid-landing and froze a frame (David's
        // recordings, 2026-11-04). Every landing ends with gliding = nil,
        // well past the finger's lift.
        .onChange(of: gliding) { if gliding == nil, barQuiet { barQuiet = false } }
    }

    private var barShown: Bool { arrival < 1 || editing }

    /// The glide: quick, then easing gently into place (about 0.3s, as
    /// Safari's). A curve rather than a spring: a spring's last frames
    /// creep (about 0.4s on David's iPhone), and it reports done before it
    /// has landed, so the swap with the page jumped the last few points.
    private static let glide = Animation.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.32)
    private static let fade = Animation.easeOut(duration: 0.2)

    private var bar: some View {
        AddressBar(store: store, editing: $editing, typingNewTab: typingNewTab,
                   showTabs: showTabs, opened: hideTabs, menuOpen: $menuOpen)
            // Once the page is pulled, the bar's buttons let go of the
            // touch: lifting the finger over one mustn't tap it.
            .environment(\.barQuiet, barQuiet)
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
            PageView(page: page, barTop: barTop)
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
        let picture = pictures.capture(tab)
        beginGlide(of: tab)
        Task {
            guard let image = await picture?.value else { return fadeToTabs() }
            putStandIn(image, of: tab, at: pageBox(for: image))
            land(inCardOf: tab, curve: Self.glide)
        }
    }

    /// The overview, laid out behind the page with the tab's card hidden.
    private func beginGlide(of tab: FirnCore.Tab) {
        gliding = tab.id
        lineShown = false
        lineOnPicture = 0
        showingTabs = true
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
        let width = pageFrame.width
        let height = image.size.width > 0 ? width * image.size.height / image.size.width : pageFrame.height
        return CGRect(x: 0, y: pictures.topInset, width: width, height: height)
    }

    /// The picture glides from wherever it is into the tab's card; then the
    /// card takes its place in one frame. A card off screen: a cross-fade.
    private func land(inCardOf tab: FirnCore.Tab, curve: Animation) {
        Task {
            guard let spot = await spot(of: tab.id) else { return fadeToTabs() }
            withAnimation(curve) {
                box = spot
                boxRadius = OverviewRow.cornerRadius
                stripOpacity = 0
                arrival = 1
                neighborsOpacity = 0
            } completion: {
                // The card shows the same picture and line: they swap.
                neighbors = []
                lineShown = true
                gliding = nil
                standIn = nil
                standInTab = nil
            }
            // The line's fade starts on the glide's first frame (where the
            // page has just become its picture, so a hiccup can't show) and
            // eases in, so it's mostly seen over the second half. Started
            // 0.12s in, it froze a frame there (David's recordings,
            // 2026-11-04).
            withAnimation(.easeIn(duration: 0.26)) { lineOnPicture = 1 }
        }
    }

    /// No picture or no card to aim at: the overview fades in.
    private func fadeToTabs() {
        standIn = nil
        standInTab = nil
        neighbors = []
        swiping = false
        withAnimation(Self.fade) {
            arrival = 1
            pageHidden = true
        } completion: {
            gliding = nil
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
        putStandIn(image, of: tab, at: spot, radius: OverviewRow.cornerRadius)
        // A card's line leaves first; a slim row has none on its picture.
        lineOnPicture = fromCard ? 1 : 0
        gliding = tab.id
        Task {
            await Task.yield()
            withAnimation(.easeOut(duration: 0.1)) { lineOnPicture = 0 }
            land(onPage: tab, curve: Self.glide, switching: switching)
        }
    }

    /// The picture glides from wherever it is to the page's own place, and
    /// the page takes over.
    private func land(onPage tab: FirnCore.Tab, curve: Animation, switching: Bool) {
        guard let standIn else { return hideTabs() }
        withAnimation(curve) {
            box = pageBox(for: standIn)
            boxRadius = 0
            stripOpacity = 1
            arrival = 0
        } completion: {
            pageHidden = false
            showingTabs = false
            swiping = false
            neighbors = []
            gliding = nil
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

    /// Back to the page with a cross-fade (a new tab from +, Reduce Motion,
    /// or a card off screen).
    private func hideTabs() {
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
    }

    /// The finger moves on the bar. Going up more than across, it grabs the
    /// page: the overview lays out behind, the page's picture is taken, and
    /// from then on the picture follows the finger.
    private func pullMoved(_ drag: DragGesture.Value) {
        if var pull {
            pull.translation = drag.translation
            self.pull = pull
            if standIn != nil { box = pulledBox(pull); followPull(pull) }
            return
        }
        guard !editing, !menuOpen, !showingTabs, gliding == nil, !reduceMotion,
              let tab = store.activeTab else { return }
        let dx = drag.translation.width, dy = drag.translation.height
        let up = dy < -4 && -dy > abs(dx)
        let across = abs(dx) > 8 && abs(dx) > abs(dy)
        guard up || across else { return }
        let beside = neighbors(of: tab)
        // Sideways with no other tab: nothing to slide to.
        guard up || !beside.isEmpty else { return }
        let picture = pictures.capture(tab)
        let started = Pull(tab: tab, start: drag.startLocation, picture: picture,
                           translation: drag.translation, sideways: !up)
        pull = started
        pullAwaitingPicture = started.id
        barQuiet = true
        neighbors = beside
        neighborsOpacity = 1
        if up {
            beginGlide(of: tab)
        } else {
            // The overview stays out of a sideways swipe.
            gliding = tab.id
            lineOnPicture = 0
            swiping = true
        }
        Task {
            guard let image = await picture?.value ?? pictures.image(for: tab.id) else { return }
            // Still held (or let go but not landed yet): the picture comes
            // in under the finger, a short glide from the page's place.
            guard pullAwaitingPicture == started.id, standIn == nil, gliding == tab.id else { return }
            pullAwaitingPicture = nil
            putStandIn(image, of: tab, at: pageBox(for: image))
            if let pull {
                withAnimation(.easeOut(duration: 0.1)) {
                    box = pulledBox(pull)
                    followPull(pull)
                }
            }
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
        stripOpacity = Double(max(0, 1 - progress * 4))
        boxRadius = min(progress * 4, 1) * 34
    }

    /// Where the picture is while pulled: smaller as it rises (down to
    /// about 58% of the screen, then slower), and the point under the
    /// finger when it came down stays under the finger, in any direction.
    private func pulledBox(_ pull: Pull) -> CGRect {
        guard let standIn else { return box }
        let page = pageBox(for: standIn)
        let lift = lift(pull)
        // Past half the screen, each point of lift shrinks it less.
        let beyond = max(0, lift - 1)
        let scale = 1 - 0.42 * min(lift, 1) - 0.12 * (1 - 1 / (1 + beyond))
        // Pulled down, it barely gives; swiped sideways, it stays level.
        let dy = pull.sideways ? 0
            : pull.translation.height > 0 ? pull.translation.height * 0.15 : pull.translation.height
        // Swiped toward a side with no tab, it gives a little and comes back.
        var dx = pull.translation.width
        if pull.sideways, !neighbors.contains(where: { $0.place == (dx > 0 ? -1 : 1) }) { dx *= 0.3 }
        let finger = CGPoint(x: pull.start.x + dx, y: pull.start.y + dy)
        let anchorX = pull.start.x - page.minX
        let anchorY = pull.start.y - page.minY
        return CGRect(x: finger.x - anchorX * scale, y: finger.y - anchorY * scale,
                      width: page.width * scale, height: page.height * scale)
    }

    /// Let go: pulled far enough or flicked up, it lands in its card;
    /// otherwise (or flicked down) it goes back to being the page. Either
    /// way it starts at the finger's speed.
    private func pullEnded(translation: CGSize, velocity: CGSize) {
        guard var pull else { return }
        pull.translation = translation
        self.pull = nil
        let up = -velocity.height
        let flickedUp = !pull.sideways && up > 500
        let toTabs = !pull.sideways && (flickedUp || (lift(pull) > 0.22 && up > -300))
        Task {
            // The picture may still be on its way.
            for _ in 0..<20 where standIn == nil {
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard standIn != nil else {
                // Too late now: a picture arriving after this is dropped.
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
                land(inCardOf: pull.tab, curve: carrying(velocity, to: spot))
            } else {
                let page = pageBox(for: standIn!)
                land(onPage: pull.tab, curve: carrying(velocity, to: page), switching: false)
            }
        }
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
        box.offsetBy(dx: CGFloat(place) * (box.width + gap(box)), dy: 0)
    }

    /// The tab beside it to open on letting go: moved (or flicked) more
    /// than about two fifths of the way toward the middle.
    private func neighborChosen(_ velocity: CGSize) -> Neighbor? {
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
        let spot = neighborBox(neighbor.place)
        let shift = neighbor.place
        var beside = neighbors.filter { $0.id != neighbor.id }
        for i in beside.indices { beside[i].place -= shift }
        beside.append(Neighbor(id: held.id, tab: held, image: heldImage, place: -shift))
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
    private func carrying(_ velocity: CGSize, to target: CGRect) -> Animation {
        let duration = 0.34
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
private struct CardGlide: ViewModifier {
    let width: CGFloat
    let box: CGRect
    let radius: CGFloat

    func body(content: Content) -> some View {
        let scale = width > 0 && box.width > 0 ? box.width / width : 1
        content
            // One shape throughout, so its size and corners glide.
            .mask(alignment: .top) {
                RoundedRectangle(cornerRadius: radius / scale, style: .continuous)
                    .frame(height: box.height / scale)
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: box.minX, y: box.minY)
    }
}
