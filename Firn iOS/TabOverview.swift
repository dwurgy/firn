import FirnCore
import SwiftUI

/// The overview behind the page (phase 2, step 2: plain): one column of
/// slim rows, opening scrolled to the tab on screen, which carries a frost
/// ring. Tap a row to show it; its X or a swipe left closes it, and a shake
/// brings it back (phase 2, step 2b, part 2). The glass bar
/// at the bottom: + for a new tab, the space's name in a pill, and a check
/// to go back. Behind it all, the space glow (step 2b). Looks from
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

    private var space: String { store.activeSpace.color }

    var body: some View {
        ScrollViewReader { scroller in
            // A plain stack, not a List: List's own swipe can't follow the
            // finger and slide the row away the way Safari's does.
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.openTabs) { tab in
                        let onScreen = tab.id == (heldCard ?? store.activeTab?.id)
                        OverviewRow(
                            tab: tab,
                            isOnScreen: onScreen,
                            picture: onScreen ? pictures.image(for: tab.id) : nil,
                            lineShown: !onScreen || lineShown,
                            open: { open(tab) },
                            close: { close(tab) },
                            spot: { spots.frames[tab.id] = $0 }
                        )
                        .opacity(gliding == tab.id ? 0 : 1)
                        .id(tab.id)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
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
                    .opacity(typing ? 0 : arrival)
            }
            .onAppear {
                if let id = store.activeTab?.id { scroller.scrollTo(id, anchor: .center) }
            }
        }
        .background { SpaceGlow(space: space) }
        .background { ShakeToUndo(undoManager: undoManager, closes: closes) }
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

/// The overview's backdrop: a still mesh in the space's color with Firn's
/// glacier and apricot glow, so the glass rows have something to show.
/// Nothing animates while idle; a space change cross-fades.
private struct SpaceGlow: View {
    let space: String

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.42], [0.58, 0.5], [1, 0.38],
                [0, 1], [0.45, 1], [1, 1],
            ],
            colors: Theme.overviewGlow(space)
        )
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: space)
        .accessibilityHidden(true)
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
    /// The page's picture, for the tab on screen's tall card.
    let picture: UIImage?
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
    static let cornerRadius: CGFloat = 14
    private static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    /// A card is the mockup's height (docs/ios-overview-design.html): the
    /// top of the page, a glance rather than a screenshot.
    static let cardHeight: CGFloat = 148

    var body: some View {
        Group {
            if isOnScreen { card } else { row }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .offset(x: pull)
        .opacity(reduceMotion && leaving ? 0 : 1)
        .gesture(SidewaysPan(changed: follow, ended: letGo))
        .allowsHitTesting(!leaving)
    }

    /// The tab on screen: its page's picture fills the card, rounded and
    /// ringed in frost. Its icon, title, and X sit on the picture's top
    /// (`CardTop`, the same one that rides on the gliding picture).
    private var card: some View {
        Button(action: open) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.cardHeight)
                .background(Theme.page)
                .overlay(alignment: .top) { pictureView }
                .clipShape(Self.shape)
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: spot)
        .accessibilityLabel(tab.title)
        .accessibilityValue("On screen")
        .accessibilityAddTraits(.isSelected)
        .overlay(alignment: .top) {
            CardTop(tab: tab, picture: picture, close: close)
                .clipShape(CardTop.shape(Self.cornerRadius))
                .opacity(lineShown ? 1 : 0)
        }
        .overlay {
            Self.shape.strokeBorder(Theme.frost, lineWidth: 2).allowsHitTesting(false)
        }
    }

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
                .padding(.top, CardTop.lineHeight / 2)
                .accessibilityHidden(true)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                // The whole row's height, so the X is easy to hit.
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .accessibilityLabel("Close \(tab.title)")
    }

    private var row: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    SiteIconView(icon: tab.icon, size: 24) { LetterMark(site: site) }
                    Text(tab.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 14)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.title)

            closeButton
        }
        .frame(minHeight: 48)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Self.shape)
        // Other tabs sit on glass over the space glow.
        .glassEffect(.regular, in: Self.shape)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: spot)
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

/// A card's top: the icon, title, and X on the picture's top, where the
/// page softly blurs and fades under them, as a page does under a bar.
/// Drawn on the card, and on the page's picture as it glides into the card
/// (there without a working X), so the two match when they swap. Still
/// images and gradients; the blur covers only this strip.
struct CardTop: View {
    let tab: FirnCore.Tab
    let picture: UIImage?
    /// Closes the tab; nil draws the X without one (on the gliding picture).
    var close: (() -> Void)?

    static let lineHeight: CGFloat = 44
    static let veilHeight: CGFloat = lineHeight + 14

    /// Rounded at the top only, as the card's corners.
    static func shape(_ radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
    }

    private var site: String { WebAddress.site(of: tab.url) }

    var body: some View {
        ZStack(alignment: .top) {
            veil
            HStack(spacing: 12) {
                SiteIconView(icon: tab.icon, size: 24) { LetterMark(site: site) }
                Text(tab.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 46)
            .frame(height: Self.lineHeight)
            // Taps on the icon and title open the card; only the X is its own.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay(alignment: .trailing) { xMark }
        }
        .frame(height: Self.veilHeight, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder private var xMark: some View {
        let mark = Image(systemName: "xmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .frame(width: 44, height: Self.lineHeight)
            .contentShape(.rect)
            .padding(.trailing, 2)
        if let close {
            Button(action: close) { mark }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(tab.title)")
        } else {
            mark.accessibilityHidden(true)
        }
    }

    /// The picture's top, blurred and fading out below the line, with a
    /// wash of page color so the title always reads.
    private var veil: some View {
        ZStack(alignment: .top) {
            if let picture, picture.size.width > 0 {
                GeometryReader { box in
                    let scale = box.size.width / picture.size.width
                    Image(uiImage: picture)
                        .resizable()
                        .frame(width: box.size.width, height: picture.size.height * scale)
                        // Cut to the strip before blurring, so only it blurs.
                        .frame(width: box.size.width, height: box.size.height, alignment: .top)
                        .clipped()
                        .blur(radius: 10, opaque: true)
                }
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.45),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            LinearGradient(stops: [.init(color: Theme.page.opacity(0.78), location: 0),
                                   .init(color: Theme.page.opacity(0.5), location: 0.5),
                                   .init(color: Theme.page.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: Self.veilHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
