import CoreImage
import FirnCore
import SwiftUI

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
    /// Every tab a slim row (pinched together), or cards for tabs looked
    /// at in the last day (pinched apart). Remembered across restarts.
    @AppStorage("overviewSlimRows") private var slimRows = false
    /// What the list shows: 0 every tab a slim row, 1 cards, and anything
    /// between while a pinch moves. Set from `slimRows` as the overview
    /// opens; saved settings change outside any animation, so the list
    /// reads this copy, which follows the fingers and glides.
    @State private var cards: CGFloat = UserDefaults.standard.bool(forKey: "overviewSlimRows") ? 0 : 1
    private var slim: Bool { cards < 0.5 }
    /// Where a pinch began (`cards` then), and the tab held in place under
    /// the fingers with its anchor in the list (see `anchor(at:)`).
    @State private var pinchFrom: CGFloat?
    @State private var pinchHold: (id: UUID, anchor: UnitPoint)?
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

    private var space: String { store.activeSpace.color }
    /// How long a tab stays a tall card after it was last looked at.
    private static let cardAge: TimeInterval = 24 * 60 * 60

    /// How tall a tab's tile is, 0 (slim row) to 1 (card): the tab on
    /// screen is always a card, tabs looked at in the last day follow the
    /// pinch, and older tabs stay rows.
    private func tallness(_ tab: FirnCore.Tab, onScreen: Bool) -> CGFloat {
        if onScreen { return 1 }
        let viewed = lastViewed[tab.id] ?? tab.lastActiveAt
        return openedAt.timeIntervalSince(viewed) < Self.cardAge ? cards : 0
    }

    var body: some View {
        ScrollViewReader { scroller in
            // A plain stack, not a List: List's own swipe can't follow the
            // finger and slide the row away the way Safari's does.
            ScrollView {
                // 12pt apart (David, 2026-11-05: 8 felt a little tight),
                // which also gives the ring around the tab on screen room.
                LazyVStack(spacing: 12) {
                    ForEach(store.openTabs) { tab in
                        let onScreen = tab.id == (heldCard ?? store.activeTab?.id)
                        let tall = tallness(tab, onScreen: onScreen)
                        OverviewRow(
                            tab: tab,
                            isOnScreen: onScreen,
                            tallness: tall,
                            picture: onScreen ? pictures.image(for: tab.id) : pictures.cachedImage(for: tab.id),
                            loadPicture: { await pictures.loadImage(for: tab.id) },
                            ring: Theme.spaceColor(space),
                            space: space,
                            lineShown: !onScreen || lineShown,
                            open: { if !pinchedRecently { open(tab) } },
                            close: { if !pinchedRecently { close(tab) } },
                            spot: { frame in
                                spots.frames[tab.id] = frame
                                if tall == 1 { spots.cards.insert(tab.id) } else { spots.cards.remove(tab.id) }
                            }
                        )
                        .opacity(gliding == tab.id ? 0 : 1)
                        .id(tab.id)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .opacity(listFade)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { spots.viewport = $0 }
            // Pinch together for slim rows, apart for cards, as a photo
            // grid zooms. The list follows the fingers, the tab under them
            // held in place while the rest reflows; let go past halfway and
            // it finishes, short of it and it glides back.
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.02)
                    .onChanged { m in
                        lastPinch = .now
                        pinchMoved(m, scroller)
                    }
                    .onEnded { m in
                        lastPinch = .now
                        pinchEnded(m, scroller)
                    }
            )
            .sensoryFeedback(.selection, trigger: slim)
            // Pinching can't be found by VoiceOver: the same choice as an action.
            .accessibilityAction(named: slim ? "Show Cards" : "Show Rows") {
                setCards(slim ? 1 : 0, scroller)
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
                if let id = store.activeTab?.id { scroller.scrollTo(id, anchor: .center) }
            }
        }
        .background {
            OverviewHaze(picture: store.activeTab.flatMap { pictures.image(for: $0.id) }, space: space)
        }
        .background { ShakeToUndo(undoManager: undoManager, closes: closes) }
    }

    /// How far a pinch moves the list: 1.6 times apart (or 1/1.6 together)
    /// is the whole way from rows to cards.
    private static let pinchSpan = log(1.6)

    private func pinchMoved(_ m: MagnifyGesture.Value, _ scroller: ScrollViewProxy) {
        if pinchFrom == nil {
            pinchFrom = cards
            pinchHold = anchor(at: m.startLocation)
        }
        // With Reduce Motion nothing follows; the switch fades on letting go.
        guard !reduceMotion, let from = pinchFrom else { return }
        let to = min(max(from + log(max(m.magnification, 0.01)) / Self.pinchSpan, 0), 1)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            cards = to
            if let hold = pinchHold { scroller.scrollTo(hold.id, anchor: hold.anchor) }
        }
    }

    private func pinchEnded(_ m: MagnifyGesture.Value, _ scroller: ScrollViewProxy) {
        defer { pinchFrom = nil; pinchHold = nil }
        let from = pinchFrom ?? cards
        let to = min(max(from + log(max(m.magnification, 0.01)) / Self.pinchSpan, 0), 1)
        // Past halfway it finishes; short of it, back where it began.
        let target: CGFloat = abs(to - from) >= 0.5 ? (from < 0.5 ? 1 : 0) : (from < 0.5 ? 0 : 1)
        setCards(target, scroller, hold: pinchHold)
    }

    /// The tab under a point in the list (the nearest if it's between
    /// tabs), and the anchor that keeps it where it is: the point at the
    /// same fraction of its tile and of the list's height, so scrolling to
    /// it leaves it in place now and holds it there as tiles resize.
    private func anchor(at point: CGPoint) -> (id: UUID, anchor: UnitPoint)? {
        let view = spots.viewport
        guard view.height > 0 else { return nil }
        let y = view.minY + point.y
        let shown = store.openTabs.compactMap { tab in spots.frames[tab.id].map { (tab.id, $0) } }
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

    /// Switches between slim rows and cards: every row's glass glides into
    /// its card's pill (0.3s, ease-out, no bounce), the held tab staying in
    /// place, or the tab on screen held in the middle (VoiceOver's action).
    /// With Reduce Motion, the list fades out, changes, and fades back in.
    private func setCards(_ target: CGFloat, _ scroller: ScrollViewProxy,
                          hold: (id: UUID, anchor: UnitPoint)? = nil) {
        slimRows = target < 0.5
        let held = hold ?? store.activeTab.map { ($0.id, UnitPoint.center) }
        if reduceMotion {
            guard cards != target else { return }
            withAnimation(.easeOut(duration: 0.15)) { listFade = 0 } completion: {
                cards = target
                if let held { scroller.scrollTo(held.id, anchor: held.anchor) }
                withAnimation(.easeOut(duration: 0.15)) { listFade = 1 }
            }
            return
        }
        withAnimation(.easeOut(duration: 0.3)) {
            cards = target
            if let held { scroller.scrollTo(held.id, anchor: held.anchor) }
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

    /// A slim row is one line on glass; a tall card is the same line on its
    /// page's picture. One view for both, so a pinch glides between them:
    /// the row's glass shrinks into the card's pill as the tile grows
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
                Color.clear
                    .frame(width: glassWidth, height: glassHeight)
                    .background { veil(t).clipShape(glassShape) }
                    .glassEffect(.regular, in: glassShape)
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
private struct LetterMark: View {
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
