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
    /// Whether the overview has arrived (animated): its bar shows, the dim
    /// over its cards has lifted, and the page's bar has gone.
    @State private var arrived = false
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
    /// Where the picture sits when it's in its card, and whether it's there
    /// now (animated between the page's place and the card).
    @State private var cardSpot: CGRect = .zero
    @State private var inCard = false
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
                            lineShown: lineShown, heldCard: heldCard, arrived: arrived, open: openTab,
                            done: { if let tab = store.activeTab { openTab(tab) } else { hideTabs() } },
                            newTab: startNewTab, typing: editing)
                    // Typing from + leaves the overview where it is, under
                    // the dim; its own bar stays behind the keyboard.
                    .ignoresSafeArea(.keyboard)
                    .allowsHitTesting(!editing && gliding == nil)
                    .accessibilityHidden(editing)
                    .transition(.opacity)
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
                    Color(cgColor: standInTop)
                        .frame(height: pictures.topInset)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .opacity(inCard ? 0 : 1)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Placed from the screen's top-left corner, in the screen's
                // own points, as the cards report theirs (measured: the
                // layer's own corner isn't the screen's); the picture starts
                // where the page does, below the status bar.
                let width = pageFrame.width
                let height = width * standIn.size.height / standIn.size.width
                GeometryReader { layer in
                    let corner = layer.frame(in: .global).origin
                    Image(uiImage: standIn)
                        .resizable()
                        .frame(width: width, height: height)
                        .modifier(CardGlide(width: width, height: height, top: pictures.topInset, card: cardSpot,
                                            inCard: inCard, cornerRadius: OverviewRow.cornerRadius))
                        .offset(x: -corner.x, y: -corner.y)
                }
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
                .opacity(barShown ? 1 : 0)
                .allowsHitTesting(barShown)
                .accessibilityHidden(!barShown)
        }
        .background(Theme.page.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { pictures.topInset = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: editing)
        .onChange(of: editing) { if !editing { typingNewTab = false } }
    }

    private var barShown: Bool { !arrived || editing }

    /// The glide: quick, then easing gently into place (about 0.3s, as
    /// Safari's). A curve rather than a spring: a spring's last frames
    /// creep (about 0.4s on David's iPhone), and it reports done before it
    /// has landed, so the swap with the page jumped the last few points.
    private static let glide = Animation.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.32)
    private static let fade = Animation.easeOut(duration: 0.2)

    private var bar: some View {
        AddressBar(store: store, editing: $editing, typingNewTab: typingNewTab,
                   showTabs: showTabs, opened: hideTabs, menuOpen: $menuOpen)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                // Only the bar at rest counts: while it rides the keyboard,
                // the page underneath shouldn't lay out again.
                if !editing { barTop = top }
            }
            // A swipe up on the bar shows the overview, as in Safari.
            // Alongside the bar's own buttons, so a tap still taps.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { drag in
                    if !editing, !menuOpen, drag.translation.height < -40,
                       abs(drag.translation.height) > abs(drag.translation.width) {
                        showTabs()
                    }
                }
            )
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
        } else {
            Theme.page
        }
    }

    /// The page shrinks, corners rounding, straight into its own card; the
    /// other cards wait under a dim that lifts as it goes, and the bars
    /// cross-fade in place. Once it lands the card takes its place and its
    /// title line fades in. Reduce Motion, or no tab: a cross-fade.
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
                arrived = true
                pageHidden = true
            }
            return
        }
        // The overview lays out behind the page, scrolled to its card, with
        // the card hidden and its line out until the picture lands; the
        // page's picture is taken meanwhile.
        let picture = pictures.capture(tab)
        gliding = tab.id
        lineShown = false
        showingTabs = true
        Task {
            let spot = await spot(of: tab.id)
            guard let spot, let image = await picture?.value else {
                withAnimation(Self.fade) { arrived = true; pageHidden = true } completion: { gliding = nil }
                lineShown = true
                return
            }
                // The picture takes the page's place, then glides.
            cardSpot = spot
            inCard = false
            standInTop = tab.page?.topColor
            standIn = image
            pageHidden = true
            await Task.yield()
            withAnimation(Self.glide) {
                inCard = true
                arrived = true
            } completion: {
                // The card shows the same picture: they swap in one frame.
                gliding = nil
                standIn = nil
                withAnimation(Self.fade) { lineShown = true }
            }
        }
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
        heldCard = store.activeTab?.id
        store.select(tab)
        guard let spot, let image = pictures.image(for: tab.id), !reduceMotion else {
            heldCard = nil
            hideTabs()
            return
        }
        cardSpot = spot
        inCard = true
        standInTop = tab.page?.topColor
        standIn = image
        gliding = tab.id
        Task {
            await Task.yield()
            withAnimation(Self.glide) {
                inCard = false
                arrived = false
            } completion: {
                pageHidden = false
                showingTabs = false
                gliding = nil
                heldCard = nil
                lineShown = true
                guard switching else {
                    standIn = nil
                    return
                }
                Task {
                    // A tab that was asleep (or shown again) draws nothing
                    // until its page comes: the picture stays until then
                    // (1.5s at most), then fades off it.
                    for _ in 0..<30 {
                        if let page = store.activeTab?.page, page.url != nil,
                           !page.isLoading || page.progress > 0.5 { break }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    withAnimation(Self.fade) { standIn = nil }
                }
            }
        }
    }

    /// Back to the page with a cross-fade (a new tab from +, Reduce Motion,
    /// or a card off screen).
    private func hideTabs() {
        standIn = nil
        inCard = false
        withAnimation(Self.fade) {
            pageHidden = false
            arrived = false
            showingTabs = false
        } completion: {
            gliding = nil
            lineShown = true
        }
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

/// The page's picture in its card: scaled to the card's width, placed on
/// it, and cut to the card's height with its corners. Full size, it sits
/// where the page does, just below the status bar (`top`). Transforms and a
/// mask only, so nothing lays out again while it glides.
private struct CardGlide: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    let top: CGFloat
    let card: CGRect
    let inCard: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let ready = inCard && width > 0 && card.width > 0
        let scale = ready ? card.width / width : 1
        content
            // One shape throughout, so its size and corners glide.
            .mask(alignment: .top) {
                RoundedRectangle(cornerRadius: ready ? cornerRadius / scale : 0, style: .continuous)
                    .frame(height: ready ? card.height / scale : height)
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: ready ? card.minX : 0, y: ready ? card.minY : top)
    }
}
