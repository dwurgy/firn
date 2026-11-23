import FirnCore
import SwiftUI
import os

/// The page, edge to edge, with Firn's address bar floating over its bottom
/// edge, and the tab overview behind it (the tabs button, or a swipe up on
/// the bar, shows it).
struct BrowserScreen: View {
    let store: BrowserStore
    let pictures: PagePictures
    let sync: ICloudSync
    let sending: Sending
    /// A link from another app, opened as a new tab once it arrives.
    @Binding var incoming: URL?
    @FocusState private var editing: Bool
    /// Whether the overview is there behind (or instead of) the page. Kept
    /// in the landing and never read in the body: a grab then runs only the
    /// small pieces that read it (`OverviewVisible`, `PageBehindOverview`).
    private var showingTabs: Bool {
        get { landing.shown }
        nonmutating set { if landing.shown != newValue { landing.shown = newValue } }
    }
    /// What a swipe up or a tab opening moves, handed to the overview as
    /// one object (`Landing`, 2i step 3). The values keep their own names
    /// here (`arrival`, `gliding`, …), each passing through to it.
    /// Why a close faded instead of gliding (David's recording, 2026-11-19:
    /// one tile close did, and it didn't happen again). Step names only.
    private static let landingLog = Logger(subsystem: "com.firnbrowser.Firn", category: "landing")
    @State private var landing = Landing()
    /// The overview's own view, drawn alone for its picture (`OverviewHost`).
    @State private var canvas = OverviewCanvas()
    /// What a pull and the page's picture move, read only by the small
    /// pieces that draw them (`Hold`, 2i step 4). The values keep their own
    /// names here (`box`, `pull`, …), each passing through to it.
    @State private var hold = Hold()
    /// How far the overview has arrived, 0 to 1 (animated, or following a
    /// pull): its bar shows, the dim over its cards lifts, and the page's
    /// bar goes.
    private var arrival: CGFloat {
        get { landing.arrival }
        nonmutating set { if landing.arrival != newValue { landing.arrival = newValue } }
    }
    /// How much of the overview's list shows: 0 while a page is held, in
    /// from the let-go (`listComes`), out as a tab opens.
    private var listIn: CGFloat {
        get { landing.listIn }
        nonmutating set { if landing.listIn != newValue { landing.listIn = newValue } }
    }
    /// How far the overview has come forward (0, a little smaller, to 1,
    /// full size; `ComesForward`): on the landing glide's own clock, so
    /// it's still growing as the page settles into its card.
    private var forward: CGFloat {
        get { landing.forward }
        nonmutating set { if landing.forward != newValue { landing.forward = newValue } }
    }
    /// How far the overview has come into focus (0, blurred and dimmed, to
    /// 1; `ComesForward`): on the glide's clock, done as the page lands.
    private var focus: CGFloat {
        get { landing.focus }
        nonmutating set { if landing.focus != newValue { landing.focus = newValue } }
    }
    /// The glide (step 3b). The page's picture makes the move, standing in
    /// for the page: moving the page itself makes UIKit work out its safe
    /// area again every frame, so WebKit lays the whole page out again and
    /// the glide froze. The live page stays put, hidden, and swaps with the
    /// picture at either end.
    private var standIn: UIImage? {
        get { hold.standIn }
        nonmutating set { if hold.standIn !== newValue { hold.standIn = newValue } }
    }
    /// The stand-in's size.
    private var standInSize: CGSize? { standIn?.size }

    /// A pull has the live page itself following the finger, until its
    /// picture comes (WebKit takes 50–100ms) and takes its place in the
    /// same spot, in one frame. Moved by its layer only (`PageHold`), so
    /// it never lays out again (`docs/IOS-PLAN.md`, the swipe up's delay,
    /// step 2b).
    private var livePull: Bool {
        get { hold.livePull }
        nonmutating set { if hold.livePull != newValue { hold.livePull = newValue } }
    }
    private var pulledSize: CGSize? { hold.pulledSize(topInset: pictures.topInset) }
    /// The page's color behind the status bar, which the picture leaves
    /// out. Never faded: it goes the moment the page starts to move and is
    /// back the moment it's the page again. Fading, it read as a separate
    /// band of color hanging behind the clock (David's recording,
    /// 2026-11-09).
    private var standInTop: CGColor? {
        get { hold.standInTop }
        nonmutating set { if hold.standInTop != newValue { hold.standInTop = newValue } }
    }
    private var stripOpacity: Double {
        get { hold.stripOpacity }
        nonmutating set { if hold.stripOpacity != newValue { hold.stripOpacity = newValue } }
    }
    /// The picture and its strip fading off a woken page. Its own value:
    /// removing them inside an animation swapped in one frame.
    private var standInFade: Double {
        get { hold.standInFade }
        nonmutating set { if hold.standInFade != newValue { hold.standInFade = newValue } }
    }
    /// A Basecamp tile and the page's picture cross-fade where they meet:
    /// 1 shows the tile, 0 the picture. A tile has no title pill, so the
    /// picture can't land as a card does.
    private var tileReveal: Double {
        get { landing.tileReveal }
        nonmutating set { if landing.tileReveal != newValue { landing.tileReveal = newValue } }
    }
    /// The tab the picture is of, for the card's line riding on it.
    private var standInTab: FirnCore.Tab? {
        get { hold.standInTab }
        nonmutating set { if hold.standInTab !== newValue { hold.standInTab = newValue } }
    }
    /// Where the shown part of the picture sits on screen: the page's own
    /// place, a card, a row, or wherever the finger has pulled it. Its
    /// corners, and how much the card's line on it has faded in.
    private var box: CGRect {
        get { hold.box }
        nonmutating set {
            guard hold.box != newValue else { return }
            // Placed from here, not by the pull's follower any more.
            hold.follower.stop()
            hold.box = newValue
        }
    }
    private var boxRadius: CGFloat {
        get { hold.boxRadius }
        nonmutating set { if hold.boxRadius != newValue { hold.boxRadius = newValue } }
    }
    /// The strip under the clock riding on the flying page (`Hold.band`).
    private var band: CGFloat {
        get { hold.band }
        nonmutating set { if hold.band != newValue { hold.band = newValue } }
    }
    /// The screen's corners: the flying page's at full size.
    private var screenRadius: CGFloat { Hold.screenRadius(topInset: pictures.topInset) }
    /// How much of the page's top the picture leaves out (`CardGlide.skip`):
    /// the header's depth in a tall card, 0 on the page.
    private var boxSkip: CGFloat {
        get { hold.boxSkip }
        nonmutating set { if hold.boxSkip != newValue { hold.boxSkip = newValue } }
    }
    /// Gliding into a tile: where it started and the tile's size, so the
    /// picture takes the tile's shape early (`CardGlide`).
    private var tileCrop: (from: CGRect, to: CGSize)? {
        get { hold.tileCrop }
        nonmutating set { hold.tileCrop = newValue }
    }
    /// The set-down (David, 2026-11-13, in place of Safari's little
    /// bounce): landing in its card, the page comes in a hair large and
    /// lifted (`settleLift`, with a soft shadow under it), then settles the
    /// last hair down into place as its shadow sinks in. It never turns
    /// back, so it never bounces. 1 at rest.
    private var settle: CGFloat {
        get { landing.settle }
        nonmutating set { if landing.settle != newValue { landing.settle = newValue } }
    }
    /// The page being pulled up from the bar (step 3c), while the finger
    /// is down.
    private var pull: Pull? {
        get { hold.pull }
        nonmutating set { hold.pull = newValue }
    }
    /// The pull (or tabs-button glide) whose page picture may still take
    /// the page's place: set when it starts, cleared once it gives up. A picture
    /// arriving later (WebKit can take a while on a heavy page) is dropped:
    /// it used to land during the fade back and hide the page for good
    /// (David's recordings, 2026-11-04).
    @State private var pullAwaitingPicture: UUID?
    /// The bar's buttons stay still from a pull's start until just after
    /// the finger lifts (the button would see the lift as a tap).
    /// A plain box, asked as a button is tapped (`BarQuiet`).
    @State private var quiet = BarQuiet()
    private var barQuiet: Bool {
        get { quiet.on }
        nonmutating set { quiet.on = newValue }
    }
    /// The tabs beside the one being pulled or swiped (step 3c, step 2),
    /// riding with it a gap apart, and how much they show (they fade as the
    /// page lands in its card).
    private var neighbors: [Neighbor] {
        get { hold.neighbors }
        nonmutating set { hold.neighbors = newValue }
    }
    private var neighborsOpacity: Double {
        get { hold.neighborsOpacity }
        nonmutating set { if hold.neighborsOpacity != newValue { hold.neighborsOpacity = newValue } }
    }
    /// How far the tabs beside it have come in (0 to 1). A pull up shows
    /// them only after a short hold, sliding in from the edges, so a quick
    /// flick never does (as in Safari; David, 2026-11-10); a sideways swipe
    /// shows them at once. Only shown can one be picked.
    private var neighborsIn: CGFloat {
        get { hold.neighborsIn }
        nonmutating set { if hold.neighborsIn != newValue { hold.neighborsIn = newValue } }
    }
    /// Held after a pull up, the tabs beside it peek in from the screen's
    /// edges rather than sitting beside it, a little bigger than the held
    /// page, and move with it sideways (as in Safari; David, 2026-11-10).
    private var neighborsPeek: Bool {
        get { hold.neighborsPeek }
        nonmutating set { if hold.neighborsPeek != newValue { hold.neighborsPeek = newValue } }
    }
    /// How far the held page has been moved sideways, kept past the
    /// finger's lift for the landing.
    private var heldShift: CGFloat {
        get { hold.heldShift }
        nonmutating set { if hold.heldShift != newValue { hold.heldShift = newValue } }
    }
    /// How long a pull up is held before the tabs beside it come in.
    private static let neighborsWait = Duration.milliseconds(450)
    /// A sideways swipe on the bar: the pages slide at full size, over the
    /// frame's sand, with the overview left out.
    private var swiping: Bool {
        get { hold.swiping }
        nonmutating set { if hold.swiping != newValue { hold.swiping = newValue } }
    }
    /// While the overview is up (and while the picture moves).
    @State private var pageHidden = false
    /// The tab whose card is hidden while the picture stands in for it.
    private var gliding: UUID? {
        get { landing.gliding }
        nonmutating set {
            if landing.gliding != newValue { landing.gliding = newValue }
            // The glide is over: the picture behind a held page goes with it.
            if newValue == nil, landing.behind {
                landing.behind = false
                landing.heldHigh = false
                landing.heldSeen = false
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { landing.heldIn = 0 }
            }
        }
    }
    /// The tab on screen's title line, faded in after the landing.
    private var lineShown: Bool {
        get { landing.lineShown }
        nonmutating set { if landing.lineShown != newValue { landing.lineShown = newValue } }
    }
    /// The card that keeps its size while another tab grows out of its row.
    private var heldCard: UUID? {
        get { landing.heldCard }
        nonmutating set { if landing.heldCard != newValue { landing.heldCard = newValue } }
    }
    @State private var spots = OverviewSpots()
    /// A tab was opened or tapped: the space's other open groups fold once
    /// the overview is out of sight (`foldOtherGroups`).
    @State private var foldWaiting = false
    /// The page's own frame on screen, to aim the glide from.
    private var pageFrame: CGRect {
        get { hold.pageFrame }
        nonmutating set { if hold.pageFrame != newValue { hold.pageFrame = newValue } }
    }
    /// Whether the address being typed opens a new tab (from the overview's
    /// +) rather than replacing the page on screen.
    @State private var typingNewTab = false
    /// A sideways swipe on the last tab, toward where the next would be:
    /// how close it is to starting a new tab (0 to 1). Let go at 1 and the
    /// page settles back while typing for a new tab opens over it, as the
    /// overview's + does: Firn types over the page, never on a blank one.
    private var newTabReach: CGFloat {
        get { hold.newTabReach }
        nonmutating set { if hold.newTabReach != newValue { hold.newTabReach = newValue } }
    }
    /// How far the finger has gone left past the last tab (0 or less);
    /// the + slides in from the edge with it. The page itself stays still:
    /// moving it needed a picture of the page first, and waiting for
    /// WebKit made the swipe start late and then jump (David's recording,
    /// 2026-11-06).
    private var newTabShift: CGFloat {
        get { hold.newTabShift }
        nonmutating set { if hold.newTabShift != newValue { hold.newTabShift = newValue } }
    }
    /// How far the bar's field pulls in toward the thumb meanwhile (pt),
    /// as the pills give in an ordinary sideways swipe (David, 2026-11-11).
    private var newTabGive: CGFloat {
        get { hold.newTabGive }
        nonmutating set { if hold.newTabGive != newValue { hold.newTabGive = newValue } }
    }
    /// A swipe past the last tab is under way (instead of a pull).
    @State private var newTabSwipe = false
    /// The page menu, grown out of the bar.
    @State private var menuOpen = false
    /// The page whose find bar (iOS's own, Find on Page) is open, so it can
    /// be ended when another tab comes on screen.
    @State private var findingPage: (any PageController)?
    private var finding: Bool { store.activeTab?.page?.isFinding ?? false }
    /// Where the bar's top edge and the page's bottom edge sit on screen, so
    /// the page knows how much of it the bar covers.
    @State private var barTop: CGFloat = 0
    /// Scrolling down to read has shrunk the bar to a small pill (phase 5).
    @State private var barShrunk = false
    /// New Space or Settings is up. An object, not plain flags: the actions
    /// that set them live on in the environment (always equal, so they never
    /// redraw the overview), and a flag set through one didn't wake the
    /// screen until something else did.
    @State private var sheets = SpaceSheets()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The grid's cards: their pictures sit above their titles, so a page
    /// glides into and out of them there.
    private var cardRadius: CGFloat { OverviewRow.gridCornerRadius }
    /// VoiceOver always has the whole bar (phase 5): its buttons stay where
    /// a swipe through them finds them.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack(alignment: .bottom) {
            // Always built, hidden behind the page while browsing, so a swipe
            // up only reveals it: building it on each swipe held the screen
            // still for the first ~80ms, and 1.1s the first time after
            // launch (David's iPhone, 2026-11-10).
            // In a view of its own, so it can be drawn while the page covers it
            // (`OverviewHost`); its surroundings handed on by hand.
            OverviewHost(canvas: canvas) {
                TabOverview(store: store, pictures: pictures, spots: spots, landing: landing, canvas: canvas,
                            screenMiddle: pageFrame.width > 0 ? CGPoint(x: pageFrame.midX, y: pageFrame.midY) : nil,
                            actions: OverviewActions(
                                open: openTab,
                                done: { if let tab = store.activeTab { openTab(tab) } else { hideTabs() } },
                                newTab: startNewTab, key: [reduceMotion, voiceOver]),
                            typing: editing)
                    .environment(\.newSpace, SheetAction { [sheets] in sheets.newSpace = true })
                    .environment(\.spaceSettings, SheetAction { [sheets] in sheets.settings = true })
                    .environment(sending)
            }
                .ignoresSafeArea()
                .modifier(OverviewVisible(landing: landing, editing: editing))
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
                    pictures.pageHeight = $0.height
                }
                .opacity(pageHidden ? 0 : 1)
                .modifier(PageBehindOverview(landing: landing))
            ReaderPill(store: store, hold: hold, away: pageHidden || editing, landing: landing)

            // Just above the bar while a download saves, then "Saved to
            // Files" (phase 6); a tap opens Downloads.
            DownloadPill(store: store, hold: hold, away: pageHidden || editing || menuOpen, landing: landing,
                         barTop: barTop > 0 && barShrunk ? barTop + AddressBar.compactTopDrop : barTop) {
                sheets.downloads = true
            }

            // Just above the bar as a sent tab arrives ("From Mac"), or as
            // one is sent ("Sent to Mac"; sync step 6).
            SentPill(sending: sending, hold: hold, away: pageHidden || editing || menuOpen, landing: landing,
                     barTop: barTop > 0 && barShrunk ? barTop + AddressBar.compactTopDrop : barTop)

            StandInLayer(hold: hold, landing: landing, store: store, pictures: pictures)

            NewTabHintLayer(hold: hold, space: store.activeSpace.color)

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

            BarHost(hold: hold, landing: landing, editing: editing) { bar }
                // iOS's find bar (Find on Page) takes the bottom while it's
                // open: Firn's bar fades aside, as Safari's does, so there's
                // one bar at a time.
                .opacity(finding ? 0 : 1)
                .allowsHitTesting(!finding)
                .accessibilityHidden(finding)
                .animation(.easeOut(duration: 0.2), value: finding)
        }
        .onChange(of: finding) { _, now in findingPage = now ? store.activeTab?.page : nil }
        // Another tab on screen: the find bar was the last one's.
        .onChange(of: store.activeTab?.page.map { ObjectIdentifier($0) }) {
            findingPage?.endFind()
            findingPage = nil
        }
        .background(Theme.page.ignoresSafeArea())
        // New Space…, from the space menu or the command bar (phase 4, step 2),
        // and Space Settings…, from the space menu (step 3).
        .environment(\.newSpace, SheetAction { [sheets] in sheets.newSpace = true })
        .environment(\.spaceSettings, SheetAction { [sheets] in sheets.settings = true })
        .environment(\.showDownloads, SheetAction { [sheets] in sheets.downloads = true })
        .onChange(of: sheets.newSpace || sheets.settings || sheets.downloads) {
            if sheets.newSpace || sheets.settings || sheets.downloads { editing = false }
        }
        .sheet(isPresented: $sheets.newSpace) { NewSpaceSheet(store: store) }
        .sheet(isPresented: $sheets.settings) { SettingsSheet(store: store, sync: sync) }
        .sheet(isPresented: $sheets.downloads) { DownloadsSheet(store: store) }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { pictures.topInset = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: editing)
        .onChange(of: editing) { if !editing { typingNewTab = false } }
        .onChange(of: incoming, initial: true) { openIncoming() }
        // The bar's buttons wake once the pull's landing is over, not on a
        // timer: waking them redraws the whole bar, and 150ms after the
        // finger lifted that fell mid-landing and froze a frame (David's
        // recordings, 2026-11-04). Every landing ends with gliding = nil,
        // well past the finger's lift. Watched from a small piece, so a
        // glide starting or the overview showing doesn't run this body.
        .background {
            LandingWatch(landing: landing, shownChanged: { _ in foldOtherGroups() }, glideEnded: {
                if landing.warm { landing.warm = false }
                if barQuiet { barQuiet = false }
                foldOtherGroups()
            })
        }
        .onChange(of: store.activeTabID) { old, new in tabCameOnScreen(from: old, to: new) }
        .task(id: store.activeTabID) { await readyNeighborPictures() }
    }

    // MARK: Groups fold themselves (step 3b)

    /// A tab opened (+, a link, the command bar) or picked: open groups
    /// lean toward staying out of the way, as Safari's (David, 2026-11-18).
    /// Not when the tab on screen went because it closed (its neighbor
    /// takes over, nothing was opened), or for a space switch.
    private func tabCameOnScreen(from old: UUID?, to new: UUID?) {
        guard let new, let tab = store.tabs.first(where: { $0.id == new }) else { return }
        if let old {
            guard let was = store.tabs.first(where: { $0.id == old }), was.spaceID == tab.spaceID
            else { return }
        }
        foldWaiting = true
        foldOtherGroups()
    }

    /// Folds every open group in the space but the tab on screen's, once
    /// the overview is gone and nothing glides, so the grid never moves
    /// under a page growing out of it. Out of sight, so at once; the next
    /// overview shows them folded (the tab on screen's still opens with it).
    private func foldOtherGroups() {
        guard foldWaiting, !showingTabs, gliding == nil else { return }
        foldWaiting = false
        let keep = store.activeTab?.groupID
        let folding = store.tabGroups.filter { !$0.folded && $0.id != keep }
        guard !folding.isEmpty else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            for group in folding {
                // As the overview's own fold: folded tabs forget their spots.
                for tab in store.tabs(in: group) {
                    spots.frames[tab.id] = nil
                    spots.cards.remove(tab.id)
                }
                store.setFolded(group, true)
            }
        }
    }

    /// Opening a tab (a card or tile growing into the page) and closing
    /// one (the page landing in its card or tile) at Safari's own pace, so
    /// they feel as people expect (David, 2026-11-13). Both measured from
    /// his recording of Safari, frame by frame, on the page's width:
    /// opening is halfway at 77ms, 90% at 200ms, 97% at 275ms, about 0.4s
    /// in all; closing is quicker and starts gently, halfway at 83ms, 90% at
    /// 180ms, 97% at 220ms, about 0.28s. These curves match each within a
    /// few milliseconds. Curves, not springs: a spring's last frames creep
    /// and it reports done before it has landed, so the swap with the page
    /// jumped the last few points.
    /// About 15% slower than Safari's (0.4s and 0.28s): Safari's page
    /// shrinks evenly, while Firn's wide card mostly loses height, so its
    /// bottom edge travels about twice as far and the same clock felt
    /// faster (David, 2026-11-13).
    /// Measured again (2026-11-19, the plan's step 3; two opens in David's
    /// recording, the page's left edge and width in every frame): Safari's
    /// open is a spring with no bounce, about `response 0.35`: halfway at
    /// 0.10s, 90% at 0.23s, 97% at 0.32s, 99% at 0.40s, and still for good
    /// at about 0.55s. Firn's curve before (0.25, 0.4, 0.1, 1 over 0.46s)
    /// began too briskly (13% ahead of Safari's at 80ms) and ended early.
    /// This one is within 2.5% of Safari's in every frame measured, long
    /// tail included (the last tenth of a second moves the page's edge
    /// under a point). The grid's cards have Safari's proportions now, so the same
    /// clock, not the 15% slower one above.
    private static let glide = Animation.timingCurve(0.35, 0.475, 0.025, 1, duration: glideDuration)
    private static let glideDuration = 0.50
    /// Out of a Basecamp tile, as iOS opens an app (2k step 3, David's
    /// recording of the App Library, 2026-11-18): full screen in about
    /// 0.2s, then a short settle, everything ending together. On the card's
    /// curve the page popped to about 90% in a tenth of a second and crept
    /// the last points for 0.35s more. This one starts gently (a 56pt tile
    /// growing is seen in ratios, so its first points are the most visible),
    /// is about 90% there at 0.2s, and done at 0.38s. A curve, not a spring,
    /// for the reason above.
    private static let tileOpenDuration = 0.38
    private static let tileOpen = Animation.timingCurve(0.35, 0.1, 0.2, 1, duration: tileOpenDuration)
    private static let closeDuration = 0.32
    /// How far above its card the page arrives (1.5% larger, about 5pt on
    /// a card), and how long the settle runs on after the glide ends.
    static let settleLift: CGFloat = 1.015
    /// The set-down, switched off (Safari's closing tab has none; David,
    /// 2026-11-13). A property, not a local, so the build doesn't warn.
    static let setsDown = false
    private static let settleTime = 0.09
    private static let closeGlide = Animation.timingCurve(0.25, closeStart, 0.35, 1, duration: closeDuration)
    private static let closeStart = 0.25
    /// Let go after a hold, the page lands more softly than from the tabs
    /// button or a short swipe, as Safari's (the plan's step 3; three slow
    /// swipe ups in David's recording, 2026-11-19, alike to the frame): an
    /// even pace to about 60% of the way, then a gentle ease, halfway at
    /// 0.115s, 90% at 0.24s, at rest by 0.40s. On the button's curve Firn's
    /// was halfway at 0.095s and at rest by 0.32s. Since the let-go's
    /// spring (`Flight`, 2026-11-20) this curve moves only the corners, the
    /// strip, and what fades, over the flight's time.
    private static let heldCloseX1 = 0.35
    private static let heldCloseStart = 0.40
    private static let heldCloseTail = 0.30
    /// Into a Basecamp tile: slower and more even (2g, step 2). A page
    /// going down to 56pt travels much further than one landing in a card,
    /// and on the card's curve the whole landing showed for about 6 frames,
    /// the tile forming in 2 or 3 (David's recording, 2026-11-13). A flick
    /// may quicken its start only a little.
    /// 0.46s was too slow (David's recording, 2026-11-13): between the two.
    private static let tileCloseDuration = 0.38
    /// Shaped so the tile shrinks at an even pace to the eye: a size is
    /// seen in ratios, so going from the page's width to 90pt evenly in
    /// points packs the most visible change into the end. The slow-start
    /// curve before (0.3, 0.2, 0.55, 1) barely moved for 9 frames, then
    /// crossed most of the way in 2 or 3, the tile forming in that rush
    /// (David's recording at 120fps, 2026-11-13). This one is about 40% of
    /// the way at a quarter of the time and 75% at half, close to an even
    /// ratio's 40% and 68%, with a gentle end.
    private static let tileCloseStart = 0.35
    private static let tileCloseStartLimit = 0.45
    private static let tileCloseTail = 0.45
    private static let tileCloseGlide = Animation.timingCurve(0.3, tileCloseStart, tileCloseTail, 1,
                                                              duration: tileCloseDuration)
    private static let fade = Animation.easeOut(duration: 0.2)
    /// The cards coming in around a landing page: started with the glide,
    /// mostly there by its middle, so the page lands among them.
    /// Quick: Safari's overview is behind the page from the let-go's first
    /// frame, blurred and dimmed (David's recording, 2026-11-13).
    /// The overview's picture fades in on this too (`LandingHeldStep`):
    /// Safari's grid builds over 6 to 8 frames from the let-go (David's
    /// recording, 2026-11-22); at a tenth of a second eased out, Firn's was
    /// there in 2 ("fades kinda quick").
    private static let listComes = Animation.linear(duration: 0.13)
    /// The overview growing to full size as a tab lands (`ComesForward`),
    /// as Safari's (David's recording, frame by frame, 2026-11-13): an
    /// even ease through the glide, running on about 0.12s past the
    /// landing while the closing tab holds still.
    private static let forwardTime = closeDuration + 0.12
    private static let forwardCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1),
                                                       endControlPoint: UnitPoint(x: 0.25, y: 1))
    /// The cards leaving as a tab grows out of its card.
    private static let listGoes = Animation.easeOut(duration: 0.1)
    /// Pages sliding sideways round to about the screen's own corners.
    private static let slideRadius: CGFloat = 50

    private var bar: some View {
        AddressBar(store: store, editing: $editing, typingNewTab: typingNewTab,
                   showTabs: showTabs, opened: hideTabs, menuOpen: $menuOpen, shrunk: $barShrunk,
                   otherDeviceTabs: { [sync] in sync.otherDeviceTabs() })
            // Once the page is pulled, the bar's buttons let go of the
            // touch: lifting the finger over one mustn't tap it.
            .environment(\.barQuiet, quiet)
            // A new page or another tab starts with the full bar.
            .onChange(of: store.activeTab?.page.map { ObjectIdentifier($0) }) { barShrunk = false }
            .onChange(of: store.activeTab?.page?.url) { barShrunk = false }
            .onChange(of: voiceOver) { if voiceOver { barShrunk = false } }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                // Only the bar at rest counts: while it rides the keyboard,
                // the page underneath shouldn't lay out again.
                if !editing {
                    barTop = top
                    if pageFrame.height > 0 { pictures.bottomRoom = pageFrame.maxY - top }
                }
            }
            // A swipe up on the bar pulls the page into the overview, as
            // in Safari. Alongside the bar's own buttons, so a tap still taps.
            // Only the full bar: the small pill is tap-only, as Safari's
            // (David, 2026-11-11); a tap grows the bar, and then it swipes.
            .modifier(BarPull(including: barShrunk ? .subviews : .all, moved: pullMoved,
                              ended: { pullEnded(translation: $0.translation, velocity: $0.velocity) },
                              touched: warmOverview) {
                if newTabSwipe {
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        if newTabSwipe { newTabSwipeEnded(translation: .zero, velocity: .zero) }
                    }
                    return
                }
                guard pull != nil else { return }
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
            })
            // The bar rises with the keyboard only for typing an address; a
            // page's own fields leave it resting behind the keyboard, as in
            // Safari.
            .ignoresSafeArea(.keyboard, edges: editing ? [] : .bottom)
    }

    /// A finger on the bar readies the hidden overview (`Landing.warm`);
    /// lifted with no pull under way, it rests again. A glide's end rests
    /// it too (`LandingWatch`).
    private func warmOverview(_ down: Bool) {
        let warm = down ? !showingTabs && !reduceMotion && !editing : gliding != nil
        if landing.warm != warm { landing.warm = warm }
    }

    @ViewBuilder private var pageLayer: some View {
        if let page = store.activeTab?.page {
            // The page's room follows the bar: shrunk, its end rests just
            // above the small pill (phase 5, step 3).
            HeldPage(page: page, barTop: barTop > 0 && barShrunk ? barTop + AddressBar.compactTopDrop : barTop,
                     barTopSpan: barTop > 0 ? barTop...(barTop + max(AddressBar.compactTopDrop, 0)) : nil,
                     hold: hold) { scroll in
                let shrink = scroll == .shrink && !voiceOver
                if barShrunk != shrink { barShrunk = shrink }
            }
                // A failed load covers the page with Firn's own words.
                .overlay {
                    LoadErrorCover(page: page, hold: hold, topRoom: pictures.topInset,
                                   bottomRoom: barTop > 0 && pageFrame.height > 0 ? pageFrame.maxY - barTop : 0)
                }
                // A new tab gets a new web view, not the last one's.
                .id(ObjectIdentifier(page))
                // Every reader follows the one look, on screen or coming back to it.
                .task(id: ReaderStyle.shared.look) {
                    if page.isReading { page.setReaderLook(ReaderStyle.shared.look) }
                }
        } else if store.openTabs.isEmpty {
            // A space with no tabs: Sunrise, exactly as the Mac's empty
            // page (no words, no centered mark; only the snow takes the
            // space's color).
            SunriseScene(spaceColor: store.activeSpace.color)
                // The clock goes light over the blue-hour sky, in both looks.
                .background(LightStatusBar(on: !showingTabs && !pageHidden))
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
        tab?.page?.endFind()
        guard let tab, !reduceMotion else {
            // The page as it is, for its card.
            if let tab { pictures.capture(tab) }
            withAnimation(Self.fade) {
                showingTabs = true
                arrival = 1
                listIn = 1
                forward = 1
                focus = 1
                pageHidden = true
            }
            return
        }
        // The overview lays out behind the page, scrolled to its card, with
        // the card hidden and its line out until the picture lands; the
        // page's picture is taken meanwhile.
        SwipeTiming.begin("tabs button", tab: tab.id)
        landing.unpose()
        // A tab just opened keeps its picture over the page until the page
        // has loaded (`land(onPage:)`). That picture is what's on screen,
        // so it closes at once, as a pull takes it over; a new one would be
        // of the blank page under it.
        let lingering = standIn
        let picture = lingering == nil ? pictures.capture(tab) : nil
        beginGlide(of: tab)
        let glide = UUID()
        pullAwaitingPicture = glide
        /// The picture takes the page's place and glides into the card.
        func close(with image: UIImage) {
            pullAwaitingPicture = nil
            // The whole screen, with the screen's corners, from the first
            // frame (the plan's step 2).
            putStandIn(image, of: tab, at: pageBox(for: image), radius: screenRadius)
            band = 1
            SwipeTiming.mark("picture set")
            Task {
                // The picture has to reach the screen, in the page's place,
                // before it's told to move. When the card's spot was already
                // known (a tab or tile opened from the overview since launch,
                // which stays laid out behind the page), the landing began in
                // the same instant: the picture was first drawn already
                // landed, a tile's faded out for its swap, so the page just
                // vanished and the overview came in with no glide. A tab
                // there since launch had to wait a frame for its spot, and
                // glided: hence "sometimes" (David's iPhone, 2026-11-19;
                // caught in the Simulator, the values logged).
                try? await Task.sleep(for: .milliseconds(16))
                // Still this close (no pull or pick began meanwhile).
                guard gliding == tab.id, standIn === image, showingTabs else { return }
                if tab.place == .basecamp {
                    land(inCardOf: tab, curve: Self.tileCloseGlide, duration: Self.tileCloseDuration)
                } else {
                    land(inCardOf: tab, curve: Self.closeGlide, duration: Self.closeDuration)
                }
            }
        }
        if let lingering {
            SwipeTiming.mark("used the picture already up")
            return close(with: lingering)
        }
        /// With no new picture: the one the tab had, else plain paper the
        /// page's size, so the close always glides. Faded instead, a tile
        /// whose page was still loading sometimes closed with no glide
        /// (David's iPhone, 2026-11-19).
        func standBy() -> UIImage? {
            if let kept = pictures.image(for: tab.id) { return kept }
            Self.landingLog.notice("close had no picture of the page: plain paper")
            return plainPicture()
        }
        Task {
            // No new picture (a page still loading, as a tile just opened
            // is): the one it had stands in, as on a swipe up.
            let fresh = await picture?.value
            SwipeTiming.mark(fresh == nil ? "no new picture" : "picture arrived")
            // Given up on meanwhile: the close is already on its way.
            guard pullAwaitingPicture == glide else { return }
            guard let image = fresh ?? standBy() else {
                pullAwaitingPicture = nil
                return fadeToTabs()
            }
            close(with: image)
        }
        // WebKit may never answer (a busy page). Waited on with no limit,
        // the page stayed over the overview and every swipe up after was
        // refused; after half a second the close goes on without the new
        // picture, which is dropped if it comes later. A page still loading
        // has little to picture and can keep WebKit waiting, so it gets
        // only a few frames.
        let patience = tab.page?.isLoading == true ? 100 : 500
        Task {
            try? await Task.sleep(for: .milliseconds(patience))
            guard pullAwaitingPicture == glide else { return }
            SwipeTiming.mark("gave up waiting for the picture")
            Self.landingLog.notice("close gave up waiting for the page's picture")
            guard let image = standBy() else {
                pullAwaitingPicture = nil
                return fadeToTabs()
            }
            close(with: image)
        }
    }

    /// Plain paper the size of the page below the status bar, to stand in
    /// for a page that has no picture yet (never kept as the tab's).
    private func plainPicture() -> UIImage? {
        let size = CGSize(width: pageFrame.width, height: pageFrame.height - pictures.topInset)
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        let paper = UIColor(Theme.page).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            paper.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// The overview, laid out behind the page with the tab's card hidden.
    private func beginGlide(of tab: FirnCore.Tab) {
        openActiveGroup()
        gliding = tab.id
        endBarReturn()
        // A tile's spot stays empty until its page lands in it; shown, the
        // tile sat there during the pull, vanished as the finger lifted,
        // and came back (Simulator recording, 2026-11-09).
        // Hidden at the start of its swap's stretch, not 0, so the swap
        // can later run on its own clock from here (`land(inCardOf:)`).
        if tab.place == .basecamp { tileReveal = BasecampTiles.glideSwap.lowerBound }
        lineShown = false
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
    private func putStandIn(_ image: UIImage, of tab: FirnCore.Tab, at frame: CGRect, radius: CGFloat = 0,
                            skip: CGFloat = 0) {
        endFlight()
        box = frame
        boxRadius = radius
        boxSkip = skip
        if hold.bandFade != 1 { hold.bandFade = 1 }
        stripOpacity = radius == 0 ? 1 : 0
        standInTop = image.topEdgeColor ?? tab.page?.topColor
        standInTab = tab
        standIn = image
        standInFade = 1
        settle = 1
        pageHidden = true
    }

    /// No flight is under way: `box` places the picture again, and the
    /// flight's clock is back at its start, where the next one begins.
    private func endFlight() {
        guard hold.flight != nil || hold.flightTime != 0 else { return }
        withTransaction(Transaction(animation: nil)) {
            hold.flight = nil
            hold.flightTime = 0
        }
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
    /// `finger`: let go on a pull, the page flies there on a spring that
    /// starts at the finger's speed (`Flight`); `curve` then moves only its
    /// corners, strip, and what fades.
    private func land(inCardOf tab: FirnCore.Tab, curve: Animation, duration: Double, finger: CGSize? = nil) {
        Task {
            // The page keeps closing on the finger's place while the card's
            // spot is found; the flight starts from where it is by then.
            let found = await spot(of: tab)
            SwipeTiming.mark("let-go: card's spot found")
            hold.follower.stop()
            guard let measured = found else {
                Self.landingLog.notice("close faded: no spot on screen (known: \(spots.frames[tab.id] != nil, privacy: .public), tile: \(tab.place == .basecamp, privacy: .public))")
                return fadeToTabs()
            }
            let tile = tab.place == .basecamp
            // Aimed at its card's full-size place, and it stays there: the
            // closing tab is its own thing, never part of the overview
            // coming forward behind it (David, 2026-11-13). The picture
            // stands in until the overview is full size (`forwardTime`),
            // then the card, now in the same place, takes over.
            let spot = measured
            if tile {
                tileCrop = (from: box, to: spot.size)
            }
            withTransaction(Transaction(animation: nil)) { stripOpacity = 0 }
            withAnimation(Self.listComes) { listIn = 1 }
            // The overview comes forward over the glide itself, finishing
            // as the page lands (as a tile's swap starts), on a curve that
            // keeps some of the growth for the end: tied to the list's
            // quick fade, it was used up while the page still covered the
            // screen, and couldn't be seen (David's recording, 2026-11-13).
            // Into focus over the glide itself, done as the page lands (as
            // a tile's swap starts), on a curve that keeps some of it for
            // the end, so the card it lands in is sharp when they swap.
            // As Safari's: fully soft for about the first third, then
            // clearing, sharp as the page lands.
            // Let go by a finger, the overview is in plain sight around a
            // small page from the first frame, and on that curve it stayed
            // fully soft for about 12 frames, then went sharp within 3;
            // Safari's can be read about 9 frames after the let-go and
            // clears evenly (David's recordings side by side, 2026-11-22).
            // Eased out, the blur is down to about 5pt by then.
            let focusCurve: Animation = finger != nil && !tile
                ? .timingCurve(0.25, 0.46, 0.45, 0.94, duration: duration)
                : .timingCurve(0.45, 0, 0.55, 1, duration: duration * (tile ? 0.86 : 1))
            withAnimation(focusCurve) {
                focus = 1
            }
            // Growing on a slower clock of its own, still coming forward
            // after the page lands: done with the focus, it was forward
            // before you had a chance to notice; Safari's can be seen coming
            // (David's recording beside Safari's, 2026-11-13).
            // A softer landing (let go after a hold) keeps the same lead.
            let forwardTime = tile ? Self.forwardTime : duration + (Self.forwardTime - Self.closeDuration)
            withAnimation(.timingCurve(Self.forwardCurve, duration: forwardTime)) {
                forward = 1
            } completion: {
                // Still this landing (nothing opened meanwhile).
                if gliding == tab.id, showingTabs { swapIntoCard() }
            }
            if tile {
                // Into a tile: the flying tile and the real one swap
                // (`BasecampTiles.glideSwap`) on a short clock of their own,
                // not the glide's curve, whose slow tail kept a tiny page in
                // the tile's spot for about 200ms (David's recording,
                // 2026-11-13).
                // Since the picture now becomes the tile on the way
                // (`CardGlide.face`), the two look the same by then, so the
                // swap is quick (two or three frames), as the picture
                // reaches the spot: a long cross-fade of two glass tiles dips
                // in strength midway.
                // Once the overview is full size, so the real tile is where
                // the flying one waits.
                let reveal = duration * 0.08
                withAnimation(.easeInOut(duration: reveal).delay(max(duration * 0.86, forwardTime - reveal))) {
                    tileReveal = 1
                }
            }
            // Cards and tiles are set down (`settle`, David, 2026-11-13). A
            // tile turns to glass before it lands, so the glass tile takes
            // the same scale (`BasecampTiles.settle`) and keeps it until the
            // settle ends (`gliding` clears in `swapIntoCard`).
            // The swap waits for the overview to be full size (`forward`'s
            // completion), so the set-down is the closing tab's alone.
            // Safari's closing tab simply eases in, with no set-down
            // (David, 2026-11-13: "just copy it exactly"). The set-down's
            // code stays, switched off.
            let setsDown = Self.setsDown
            // A tile forms inside the shrinking page (`CardGlide.face`);
            // the strip is gone before it does.
            if tile { withAnimation(.easeOut(duration: duration * 0.3)) { hold.bandFade = 0 } }
            // Into a tall card: from just below the header, as the card shows.
            let skip = !tile && spots.cards.contains(tab.id) ? pictures.headerDepth(for: tab.id) : 0
            if let finger, !tile {
                // Each point the finger rises takes this much off the width.
                let shrink = Self.heldPace / max(pageFrame.height / 2, 1) * pageFrame.width * Self.flickCarry
                withTransaction(Transaction(animation: nil)) {
                    hold.flight = Flight(from: box, to: spot, finger: finger, shrink: shrink,
                                         radius: .init(boxRadius, cardRadius), skip: .init(boxSkip, skip),
                                         band: band)
                    hold.flightTime = 0
                }
                SwipeTiming.mark("flight begins")
                withAnimation(curve) { arrival = 1 }
                // The flight's clock runs evenly, and everything the
                // picture's layer reads is set with it, last: what's
                // animated in one turn reaches a view as one animation, the
                // last one's, and on the landing's ease-out curve the clock
                // ran ahead and the spring with it (logged in the
                // Simulator, 2026-11-20). The flight itself places the
                // picture and shapes its corners and strip (`Flight`).
                withAnimation(.linear(duration: Flight.duration)) {
                    hold.flightTime = 1
                    box = spot
                    boxRadius = cardRadius
                    band = 0
                    boxSkip = skip
                    neighborsOpacity = 0
                }
            } else {
                withAnimation(curve) {
                    box = spot
                    boxRadius = tile ? BasecampTiles.cornerRadius : cardRadius
                    band = 0
                    boxSkip = skip
                    arrival = 1
                    neighborsOpacity = 0
                }
            }
            if setsDown {
                // Part of the glide, not after it: the lift builds while the
                // page flies, and the settle starts at 60% of the glide's
                // time, so the glide's last stretch and the settle are one
                // motion ending about 90ms after the glide. Settling once
                // the page had stopped read as a second little move
                // (David's recording, 2026-11-13). The two add up, as
                // SwiftUI's timed animations do.
                // A tile lifts further (1.5% of 56pt is under a point,
                // `BasecampTiles.settleLift`), and only once the picture is
                // nearly its size (from 30% of the time, about 80% of the
                // way): 4% of the whole page would read as a swell.
                if tile {
                    withAnimation(.easeOut(duration: duration * 0.3).delay(duration * 0.3)) {
                        settle = BasecampTiles.settleLift
                    }
                } else {
                    withAnimation(.easeOut(duration: duration * 0.5)) { settle = Self.settleLift }
                }
                withAnimation(.easeInOut(duration: duration * 0.4 + Self.settleTime).delay(duration * 0.6)) {
                    settle = 1
                }
            }
        }
    }

    /// The card shows the same picture and line: they swap.
    private func swapIntoCard() {
        neighbors = []
        lineShown = true
        gliding = nil
        standIn = nil
        standInTab = nil
        tileCrop = nil
        boxSkip = 0
        settle = 1
        endFlight()
    }

    /// No picture or no card to aim at: the overview fades in.
    private func fadeToTabs() {
        hold.follower.stop()
        endFlight()
        livePull = false
        tileReveal = 1
        standIn = nil
        standInTab = nil
        neighbors = []
        swiping = false
        withAnimation(Self.fade) {
            arrival = 1
            listIn = 1
            forward = 1
            focus = 1
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
        // Tapping the tab already on screen is a pick too (step 3b).
        foldWaiting = true
        let spot = spots.frames[tab.id].flatMap { visible($0) }.map { pictureSpot($0, of: tab) }
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
        putStandIn(image, of: tab, at: spot,
                   radius: tile ? BasecampTiles.cornerRadius
                       : fromCard ? cardRadius : OverviewRow.cornerRadius,
                   skip: fromCard && !tile ? pictures.headerDepth(for: tab.id) : 0)
        // Out of a tile, as an app opens (2k step 3): the growing window
        // starts as the tile itself, its glass and icon drawn in it
        // (`CardGlide.face`, closing's forming run backward), and takes the
        // page's shape as it grows. The face matches the real tile, so they
        // swap at once: no cross-fade of two glass tiles.
        if tile { tileCrop = (from: pageBox(for: image), to: spot.size) }
        band = 0
        // Out of a tile the strip comes late, once the tile's face has gone.
        if tile { hold.bandFade = 0 }
        tileReveal = 0
        gliding = tab.id
        Task {
            await Task.yield()
            if tile { withAnimation(.easeIn(duration: Self.tileOpenDuration * 0.6)) { hold.bandFade = 1 } }
            land(onPage: tab, curve: tile ? Self.tileOpen : Self.glide, switching: switching,
                 stepsBack: tile ? Self.tileOpenDuration : Self.glideDuration)
        }
    }

    /// The picture glides from wherever it is to the page's own place, and
    /// the page takes over.
    /// `stepsBack`: opening from the overview, over this many seconds. The
    /// overview steps back behind the page (2k step 3, David's rule: one
    /// treatment behind tiles and tabs, opening and closing): closing's
    /// coming forward run backward, so it shrinks to 92%, dims, and its
    /// softened picture fades in over it (`FrozenOverview`), all on the
    /// glide's clock; the list goes once the page covers it. Without it
    /// (a pull let go, a sideways swipe), the list just fades.
    private func land(onPage tab: FirnCore.Tab, curve: Animation, switching: Bool,
                      stepsBack: Double? = nil) {
        hold.follower.stop()
        guard let standInSize else { return hideTabs() }
        // The bar comes back on its own clock (`BarReturn`), unless it's
        // still partly there (a pull let go early): the switch would cut it.
        if arrival >= 0.2 {
            let time = stepsBack ?? Self.glideDuration
            landing.barLate = true
            withAnimation(.linear(duration: time * BarReturn.fade).delay(time * BarReturn.wait)) {
                landing.barIn = 1
            }
        }
        if let stepsBack {
            withAnimation(.easeOut(duration: stepsBack)) {
                forward = 0
                focus = 0
            }
        } else {
            withAnimation(Self.listGoes) {
                listIn = 0
                forward = 0
                focus = 0
                // Let go back onto the page from a high hold.
                if landing.heldIn != 0 { landing.heldIn = 0 }
            }
            landing.heldHigh = false
        }
        withAnimation(curve) {
            box = pageBox(size: standInSize)
            // The screen's corners as it arrives, the strip grown back.
            boxRadius = screenRadius
            band = 1
            boxSkip = 0
            arrival = 0
            // The tabs beside it glide from where they are to beside it.
            neighborsPeek = false
            for i in neighbors.indices { neighbors[i].pinned = nil }
        } completion: {
            // Stepped back: the list goes now, under the full-screen page.
            withTransaction(Transaction(animation: nil)) { listIn = 0 }
            endBarReturn()
            stripOpacity = 1
            pageHidden = false
            showingTabs = false
            swiping = false
            neighbors = []
            gliding = nil
            heldCard = nil
            lineShown = true
            standInTab = nil
            tileCrop = nil
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

    /// The bar is the band's again (`BarHost`), and its return's clock is
    /// back at the start for the next opening.
    private func endBarReturn() {
        guard landing.barLate || landing.barIn != 0 else { return }
        withTransaction(Transaction(animation: nil)) {
            landing.barLate = false
            landing.barIn = 0
        }
    }

    /// Back to the page with a cross-fade (a new tab from +, Reduce Motion,
    /// or a card off screen).
    private func hideTabs() {
        hold.follower.stop()
        livePull = false
        standIn = nil
        standInTab = nil
        neighbors = []
        swiping = false
        withAnimation(Self.fade) {
            pageHidden = false
            arrival = 0
            listIn = 0
            forward = 0
            focus = 0
            showingTabs = false
        } completion: {
            gliding = nil
            lineShown = true
        }
    }

    // MARK: The pull (step 3c)

    private typealias Pull = Hold.Pull
    private typealias Neighbor = Hold.Neighbor

    /// The finger moves on the bar. Going up more than across, it grabs the
    /// page: the overview lays out behind, the page's picture is taken, and
    /// from then on the picture follows the finger.
    private func pullMoved(_ drag: DragGesture.Value) {
        if var pull {
            pull.translation = drag.translation
            self.pull = pull
            if pulledSize != nil {
                if pull.sideways { box = pulledBox(pull) } else { hold.follower.aim(pulledBox(pull)) }
                followPull(pull)
            }
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
        landing.unpose()
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
        hold.neighborsLeft = false
        heldShift = 0
        if up, !beside.isEmpty {
            Task {
                try? await Task.sleep(for: Self.neighborsWait)
                guard pull?.id == started.id, !hold.neighborsLeft else { return }
                withAnimation(.smooth(duration: 0.3)) { neighborsIn = 1 }
            }
        }
        if up {
            beginGlide(of: tab)
            // The overview's picture, blurred and dimmed, ready behind the
            // held page; it shows only from high up (`followPull`).
            if !landing.behind { landing.behind = true }
        } else {
            // The overview stays out of a sideways swipe.
            gliding = tab.id
            swiping = true
            // The page carries its own strip now (`topBand`).
            stripOpacity = 0
        }
        if let lingering {
            putStandIn(lingering, of: tab, at: pageBox(for: lingering))
            if lingeringTop != nil { standInTop = lingeringTop }
            if !up { stripOpacity = 0 }
            place(started)
            return
        }
        // The live page moves at once, from this very frame; its picture
        // takes over when it comes.
        livePull = true
        standInTop = pictures.cachedImage(for: tab.id)?.topEdgeColor ?? tab.page?.topColor
        // Sideways, the page carries its own strip (`topBand`).
        stripOpacity = up ? 1 : 0
        boxRadius = 0
        place(started)
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

    /// A pull's first placing. Sideways, the page is under the finger at
    /// once. Pulled up, it starts where it rests and closes on the finger's
    /// place over the next frames (`Follower`): the finger has already
    /// travelled by the time the grab's first frame is drawn, and tied to
    /// it the page jumped there.
    private func place(_ started: Pull) {
        guard !started.sideways else {
            box = pulledBox(started)
            return followPull(started)
        }
        var resting = started
        resting.translation = .zero
        box = pulledBox(resting)
        hold.follower.start(at: box) { [hold] placed in
            if hold.box != placed { hold.box = placed }
            // Its corners and the grid behind follow its size.
            if let pull = hold.pull { followPull(pull) }
        }
        hold.follower.aim(pulledBox(started))
        followPull(started)
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
            boxRadius = min(abs(pull.translation.width) / 60, 1) * Self.slideRadius
            return
        }
        let progress = min(lift(pull), 1)
        endBarReturn()
        arrival = progress * 0.85
        // Gone at once, never faded, even inside the picture's catch-up glide.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { stripOpacity = progress > 0 ? 0 : 1 }
        // The screen's corners at the grab, shrinking with the page; the
        // strip rides on it and is gone a quarter of the way up, since a
        // held page stays below the clock.
        let scale = pageFrame.width > 0 ? box.width / pageFrame.width : 1
        boxRadius = max(screenRadius * scale, min(progress * 4, 1) * 34)
        // The blurred grid fades in behind a page pulled nearly all the way
        // up, and out again below that, as Safari's (`Landing.heldIn`). A
        // little give between the two, so a finger resting there doesn't
        // flutter it.
        let high = scale < (landing.heldHigh ? Self.heldGridScale + 0.015 : Self.heldGridScale)
        if high != landing.heldHigh {
            landing.heldHigh = high
            if high, !landing.heldSeen { landing.heldSeen = true }
            withAnimation(.easeOut(duration: Self.heldGridFade)) { landing.heldIn = high ? 1 : 0 }
            // The tabs beside the page belong to a hold lower down: they
            // leave as the grid comes in, and stay out for the rest of
            // this pull, as Safari's (David's recording, 2026-11-20).
            if high, !hold.neighborsLeft {
                hold.neighborsLeft = true
                if neighborsIn != 0 { withAnimation(.smooth(duration: 0.25)) { neighborsIn = 0 } }
            }
        }
        band = max(0, 1 - progress * 4)
    }

    /// The held page's width, as a share of the screen's, below which the
    /// blurred grid comes in behind it, and how long its fade takes (s):
    /// Safari's, measured from David's recording (2026-11-19). Here that's
    /// a finger pulled up about a third of the screen's height.
    private static let heldGridScale: CGFloat = 0.54
    private static let heldGridFade = 0.7

    /// How much of its size the held page loses for each unit of lift.
    private static let heldPace: CGFloat = 0.44 / (2 * 270 / 759)
    /// How much faster than that the size is taken to be changing as the
    /// finger lets go. A guess (2026-11-20); the flight caps what comes of
    /// it (`Flight.mostCarry`, measured from Safari's, 2026-11-22), and a
    /// quick flick reaches that cap either way.
    private static let flickCarry: CGFloat = 1.6

    /// The held page's size, as a share of its full size, for a lift (the
    /// finger's travel up over half the page's height): Safari's,
    /// measured from David's recording (2026-11-20). It shrinks evenly,
    /// to 56% after about a third of the way up (270pt on his iPhone,
    /// where the page between the clock and the home bar is 759pt tall),
    /// then eases to a stop at 47%, a little larger than a card, however
    /// far the finger goes.
    static func heldScale(lift: CGFloat) -> CGFloat {
        let pace = heldPace
        let floor: CGFloat = 0.47, knee: CGFloat = 0.53
        let straight = 1 - pace * max(lift, 0)
        guard straight < knee else { return straight }
        // Past the knee, the same pace at first, then less and less.
        let past = lift - (1 - knee) / pace
        return floor + (knee - floor) * exp(-past * pace / (knee - floor))
    }

    /// Where the picture is while pulled: smaller as it rises (see
    /// `heldScale`), and the point under the finger when it came down
    /// stays under the finger, in any direction.
    private func pulledBox(_ pull: Pull) -> CGRect {
        guard let size = pulledSize else { return box }
        let page = pageBox(size: size)
        let scale = Self.heldScale(lift: lift(pull))
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

    private func sidewaysShift(_ pull: Pull) -> CGFloat { hold.sidewaysShift(pull) }

    /// Let go: pulled far enough or flicked up, it lands in its card;
    /// otherwise (or flicked down) it goes back to being the page. Either
    /// way it starts at the finger's speed.
    private func pullEnded(translation: CGSize, velocity: CGSize) {
        if newTabSwipe { return newTabSwipeEnded(translation: translation, velocity: velocity) }
        guard var pull else { return }
        SwipeTiming.mark("finger lifted")
        pull.translation = translation
        heldShift = sidewaysShift(pull)
        // The page keeps closing on where the finger left, until it flies.
        if !pull.sideways, pulledSize != nil { hold.follower.aim(pulledBox(pull)) }
        self.pull = nil
        let up = -velocity.height
        let flickedUp = !pull.sideways && up > 500
        let toTabs = !pull.sideways && (flickedUp || (lift(pull) > 0.22 && up > -300))
        Task {
            // The picture may still be on its way.
            for _ in 0..<20 where standIn == nil {
                try? await Task.sleep(for: .milliseconds(16))
            }
            SwipeTiming.mark("let-go: picture in hand")
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
                guard let spot = await spot(of: pull.tab) else { return fadeToTabs() }
                if pull.tab.place == .basecamp {
                    land(inCardOf: pull.tab,
                         curve: carrying(velocity, to: spot, duration: Self.tileCloseDuration, x1: 0.3,
                                         least: Self.tileCloseStart, most: Self.tileCloseStartLimit,
                                         tail: Self.tileCloseTail),
                         duration: Self.tileCloseDuration)
                } else {
                    // On a spring that starts at the finger's speed
                    // (`Flight`): held still it eases in, flicked it passes
                    // its card and comes back. The corners and the strip
                    // follow on the soft landing's curve over the same time.
                    land(inCardOf: pull.tab,
                         curve: .timingCurve(Self.heldCloseX1, Self.heldCloseStart, Self.heldCloseTail, 1,
                                             duration: Flight.duration),
                         duration: Flight.duration, finger: velocity)
                }
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
        // The field gives about half as much as the + moves: about 30pt
        // by the point a new tab is ready, little more past it.
        newTabGive = -newTabShift * 0.55
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
        // Either way, the field glides back to its full width.
        withAnimation(.smooth(duration: 0.25)) { newTabGive = 0 }
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

    /// The order a sideways swipe moves through: Basecamp's tiles in their
    /// grid order, then the tabs, as Safari's pinned tabs lead into its
    /// others (David, 2026-11-11). So a tile swipes like any tab, and the
    /// last tile swipes on to the first tab.
    private var swipeTabs: [FirnCore.Tab] {
        store.basecampTabs + store.openTabs
    }

    private func isLast(_ tab: FirnCore.Tab) -> Bool {
        swipeTabs.last?.id == tab.id
    }

    /// The tabs just before and after this one in the swipe order, with
    /// their saved pictures.
    private func neighbors(of tab: FirnCore.Tab) -> [Neighbor] {
        let tabs = swipeTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return [] }
        return [-1, 1].compactMap { place in
            let i = index + place
            guard tabs.indices.contains(i) else { return nil }
            // Only a picture already in memory: read from disk here, at the
            // grab, it was decoded on the main thread and held the pull
            // still for up to 140ms (David's iPhone, 2026-11-19). One not
            // in memory is read off the main thread and set when it comes.
            let image = pictures.cachedImage(for: tabs[i].id)
            if image == nil { fillIn(tabs[i]) }
            return Neighbor(id: tabs[i].id, tab: tabs[i], image: image, place: place, top: stripColor(tabs[i], image))
        }
    }

    /// A tab beside's picture, read off the main thread, set once it's in.
    private func fillIn(_ tab: FirnCore.Tab) {
        Task {
            await pictures.loadImage(for: tab.id)
            guard let image = pictures.cachedImage(for: tab.id),
                  let i = neighbors.firstIndex(where: { $0.id == tab.id && $0.image == nil }) else { return }
            neighbors[i].image = image
            neighbors[i].top = stripColor(tab, image)
        }
    }

    /// The pictures of the tabs beside the one on screen, in memory before
    /// a swipe asks for them.
    private func readyNeighborPictures() async {
        guard let tab = store.activeTab else { return }
        let tabs = swipeTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        for i in [index - 1, index + 1] where tabs.indices.contains(i) {
            await pictures.loadImage(for: tabs[i].id)
        }
    }

    private func gap(_ box: CGRect) -> CGFloat { hold.gap(box) }
    private func neighborBox(_ place: Int) -> CGRect { hold.neighborBox(place) }

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
        hold.follower.stop()
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
        beside.append(Neighbor(id: held.id, tab: held, image: heldImage, place: -shift,
                               top: standInTop, pinned: box))
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
        let newTop = neighbor.top
        Task {
            // One frame in its new role before the glide, so it starts
            // where it is.
            await Task.yield()
            if let newTop { withAnimation(.easeOut(duration: 0.3)) { standInTop = newTop } }
            land(onPage: neighbor.tab, curve: carrying(velocity, to: pageBox(for: image)), switching: true)
        }
    }

    /// The strip under the clock for a tab beside: its picture's top edge,
    /// else the page's own color unless it's asleep or loading.
    private func stripColor(_ tab: FirnCore.Tab, _ image: UIImage?) -> CGColor? {
        image?.topEdgeColor ?? tab.page.flatMap { $0.isLoading || $0.url == nil ? nil : $0.topColor }
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
    private func carrying(_ velocity: CGSize, to target: CGRect, duration: Double = 0.34,
                          x1: Double = 0.2, least: Double = 0.16, most: Double = 1,
                          tail: Double = 0.25) -> Animation {
        let dx = target.midX - box.midX
        let dy = target.midY - box.midY
        let distance = max(hypot(dx, dy), 1)
        let toward = (velocity.width * dx + velocity.height * dy) / distance
        // The curve's starting slope is y1 / x1, in distance per duration.
        let slope = max(0, toward) * duration / distance
        let y1 = min(max(slope * x1, least), most)
        return .timingCurve(x1, y1, tail, 1, duration: duration)
    }

    /// Where the tab's card is once the overview has laid out and scrolled
    /// to it: a few frames at most.
    /// Asked at once first: it always waited a frame, and the let-go asks
    /// twice, so the page sat still under the lifted finger for two or
    /// three frames before it moved (David's recording, 2026-11-13).
    private func spot(of tab: FirnCore.Tab) async -> CGRect? {
        for attempt in 0..<7 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(16)) }
            if let frame = spots.frames[tab.id], let spot = visible(frame) { return pictureSpot(spot, of: tab) }
        }
        return nil
    }

    /// Where a tab's picture sits in the overview: a card's picture above
    /// its title (`OverviewRow.gridWindow(in:)`), or a whole Basecamp tile.
    private func pictureSpot(_ frame: CGRect, of tab: FirnCore.Tab) -> CGRect {
        guard spots.cards.contains(tab.id), tab.place != .basecamp else { return frame }
        return OverviewRow.gridWindow(in: frame)
    }

    /// The spot, if it's on screen (a card scrolled away has no glide).
    private func visible(_ frame: CGRect) -> CGRect? {
        let frame = fullSize(frame)
        guard frame.width > 0, frame.height > 0, pageFrame.intersects(frame) else { return nil }
        return frame
    }

    /// A spot as it will be at full size: the overview comes forward from a
    /// little smaller as a tab lands (`ComesForward`), and its spots are
    /// measured as drawn, so the page would land short of its card.
    private func fullSize(_ frame: CGRect) -> CGRect {
        // The list is smaller only once a page is let go (`listIn`).
        let scale = listIn > 0 ? ComesForward.scale(forward, off: reduceMotion) : 1
        return scaled(frame, by: 1 / scale)
    }

    /// A spot scaled around the screen's middle, as `ComesForward` draws it.
    private func scaled(_ frame: CGRect, by scale: CGFloat) -> CGRect {
        guard scale != 1, pageFrame.width > 0 else { return frame }
        let x = pageFrame.midX, y = pageFrame.midY
        return CGRect(x: x + (frame.minX - x) * scale, y: y + (frame.minY - y) * scale,
                      width: frame.width * scale, height: frame.height * scale)
    }

    /// + types right on the overview: an empty address field over it, and
    /// only Go opens a tab (and then shows the page); cancelling stays in
    /// the overview with nothing opened. Step 6's command bar opens here too.
    private func startNewTab() {
        typingNewTab = true
        editing = true
    }
}
