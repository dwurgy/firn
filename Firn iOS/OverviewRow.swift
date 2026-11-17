import FirnCore
import SwiftUI
import UIKit

/// A tab in the overview: a slim row (the site's icon and the page's title,
/// one line, as in Safari and Firn's Mac sidebar) or a tall card (the same
/// line over the page's picture). An X closes it in one tap; a swipe left follows the finger and,
/// past a third of the row or with a flick, slides it off and closes it
/// (a short swipe glides back), as in Safari.
struct OverviewRow: View {
    let tab: FirnCore.Tab
    let isOnScreen: Bool
    /// 1 a tall card with the page's picture (the tab on screen, and tabs
    /// looked at in the last day), 0 a slim row, between while a pinch moves.
    let tallness: CGFloat
    /// Where the page's picture comes from, for a tall card (read here, so
    /// a picture arriving runs only its own card), and whether it may be
    /// read from disk on the spot (the tab on screen, while shown);
    /// otherwise only if it's in memory.
    let pictures: PagePictures
    var readsDisk = false
    private var picture: UIImage? {
        readsDisk ? pictures.image(for: tab.id) : pictures.cachedImage(for: tab.id)
    }
    /// Reads the picture from disk when a card comes into view without one.
    let loadPicture: () async -> Void
    /// The ring around the tab on screen: the space's color, calmed (`Theme.spaceRing`).
    let ring: Color
    /// The space's color name.
    let space: String
    /// The page's picture under the line; empty while the page glides.
    var windowShown = true
    let open: () -> Void
    let close: () -> Void
    /// Reports where the card (or the slim row) is on screen.
    let spot: (CGRect) -> Void
    /// VoiceOver's way to reorder (a drag can't be found by it); nil at an end.
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    /// The group it's in, for VoiceOver ("<title>, in <group>"); nil when loose.
    var groupName: String?
    /// What the actions above were made from that the rest doesn't show
    /// (the row's place for Move Up and Move Down, Reduce Motion): rows
    /// are compared on what they show (`==`), and a row found unchanged
    /// keeps its old actions.
    var actionsKey: [Int] = []
    /// A card's height: the list's 240pt, or the grid's, which grows with
    /// its column so the picture stays portrait (TestFlight's grid).
    var cardHeight: CGFloat = OverviewRow.cardHeight
    /// TestFlight's grid: the card is drawn as Safari's (`gridCard`), and
    /// VoiceOver's moves read as Move Left and Move Right.
    var inGrid = false
    /// The grid on iOS 27: iOS's own hold menu, on the picture only, as
    /// Safari's (nil: none here; the list keeps Firn's own menu).
    var holdMenu: (() -> [[HoldMenuItem]])?
    /// Carried by iOS's drag (the grid on iOS 27): its X hides, so the
    /// drag lifts only the picture, as the menu does.
    var carried = false
    /// The grid's UIKit cards are swiped by their collection view
    /// (`GridCards`), not here: one place decides between the swipe and
    /// iOS's press, menu, and drag. Elsewhere the row swipes itself.
    var swipesItself = true
    /// Where such a card is in its swipe: its title and X go while it's
    /// swiped, and its spot waits until it's home.
    var gridSwipe: GridSwipe = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// How far the finger has pulled the row left (0 or less).
    @State private var pull: CGFloat = 0
    @State private var width: CGFloat = 0
    /// Set once the row is on its way out, so it takes no more touches.
    @State private var leaving = false
    /// iOS's hold menu is open on the grid card.
    @State private var menuOpen = false
    /// A grid card being swiped: grown, its title and X gone, from the
    /// first move until it's eased home (or closed), as Safari's.
    @State private var swiped = false

    private var site: String { WebAddress.site(of: tab.url) }
    private var t: CGFloat { min(max(tallness, 0), 1) }
    /// A slim row's corners (and the group cards' are built on them).
    static let cornerRadius: CGFloat = 14
    /// A tall card's corners.
    static let cardCornerRadius: CGFloat = 18
    private static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    /// The top of the page, worth looking at: a fixed 240pt on every
    /// iPhone (David, 2026-11-16: taller, now that only the tab on screen
    /// is a card unless pinched apart; was 160).
    static let cardHeight: CGFloat = 240

    var body: some View {
        Group {
            if inGrid { gridCard } else { tile }
        }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .offset(x: pull)
            .opacity(reduceMotion && leaving ? 0 : 1)
            .gesture(SidewaysPan(enabled: swipesItself, changed: follow, ended: letGo))
            .allowsHitTesting(!leaving)
            // A tab brought back (a shake's Undo) comes back in place. The
            // overview stays built now, and its row could keep the swipe
            // that closed it: slid off the screen and taking no touches
            // (David's iPhone, 2026-11-10). Reopening also picks the tab.
            .onAppear { comeBack() }
            .onChange(of: tab.lastActiveAt) { comeBack() }
    }

    /// Where the card is, for the page's glide, but not while it's being
    /// swiped: its spot moved every frame, and each move ran the whole
    /// overview again, so the ease home stuttered (David, 2026-11-17). It
    /// settles back where it was, so the spot from before still holds.
    private func reportSpot(_ frame: CGRect) {
        guard pull == 0, !swiped, !leaving, gridSwipe == .none else { return }
        spot(frame)
    }

    private func comeBack() {
        guard leaving || pull != 0 else { return }
        var now = Transaction()
        now.disablesAnimations = true
        withTransaction(now) {
            leaving = false
            pull = 0
            swiped = false
        }
    }

    /// A slim row is the tab's line (`TabLine`) on flat paper; a tall card
    /// is the same line, in the same place, on a warm paper card, with the
    /// page's picture in a rounded window below it (David, 2026-11-16: the
    /// frosted pills picked up whatever was under them and were hard to
    /// read on busy pages). One view for both, so a pinch only opens or
    /// folds the window under the line, which never moves. The tab on
    /// screen is ringed in the space's color just outside the card.
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: mix(Self.cornerRadius, Self.cardCornerRadius, t),
                                     style: .continuous)
        let height = Self.rowHeight + (cardHeight - Self.rowHeight) * t
        return Button(action: open) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            // One solid paper for the row and the card (David, 2026-11-16:
            // no see-through), so a pinch only opens or folds the window and
            // the title reads the same over anything.
            shape.fill(Theme.cardPaper)
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
                // Dark: a faint light along the top edge, so cards stand
                // off the blue-hour sky.
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [Theme.cardTopLight, .clear],
                                                      startPoint: .top, endPoint: .center),
                                       lineWidth: 1)
                }
                .shadow(color: reduceTransparency ? .clear : Theme.shadowSoft, radius: 1, y: 0.5)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: reportSpot)
        .accessibilityLabel(groupName.map { "\(tab.title), in \($0)" } ?? tab.title)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
        .accessibilityActions {
            if let moveUp { Button(inGrid ? "Move Left" : "Move Up", action: moveUp) }
            if let moveDown { Button(inGrid ? "Move Right" : "Move Down", action: moveDown) }
        }
        .overlay(alignment: .top) {
            window(height: height)
                // Empty while its page glides out of it or into it; the
                // picture gliding stands in for it.
                .opacity(windowShown ? 1 : 0)
        }
        .overlay(alignment: .top) { TabLine(tab: tab, close: close) }
        .overlay {
            if isOnScreen {
                // Just outside the card's edge, so the line inside sits the same
                // as every other row's (David, 2026-11-16: inside, the title
                // looked off center).
                CardRing(color: ring, radius: mix(Self.cornerRadius, Self.cardCornerRadius, t))
                    .allowsHitTesting(false)
            }
        }
        // An older card's picture is read from disk once it's in view,
        // then fades in over the site's icon.
        // Read as soon as it starts to grow, so it can fade in mid-pinch.
        .task(id: t > 0 && picture == nil) { if t > 0 && picture == nil { await loadPicture() } }
        .animation(.easeOut(duration: 0.15), value: picture != nil)
    }

    /// The window's distance from the card's sides and bottom, and its
    /// corners (the card's 18pt less the inset, so they run evenly). 5pt,
    /// a thin frame of paper, now that the ring sits outside the card
    /// (David, 2026-11-16: 8pt read as too much paper).
    static let windowInset: CGFloat = 5
    static let windowCornerRadius: CGFloat = cardCornerRadius - windowInset
    private var windowHeight: CGFloat { cardHeight - Self.rowHeight - Self.windowInset }

    /// Where a card's picture sits, in a card's frame: what a page glides
    /// out of and into.
    static func window(in card: CGRect) -> CGRect {
        CGRect(x: card.minX + windowInset, y: card.minY + rowHeight,
               width: max(card.width - windowInset * 2, 1),
               height: max(card.height - rowHeight - windowInset, 1))
    }

    /// The page's picture under the line, at the window's width, from just
    /// below the page's header. As the card folds, the window's bottom edge
    /// rises with the card's, so the picture folds away under the line.
    private func window(height: CGFloat) -> some View {
        pictureView
            .frame(maxWidth: .infinity)
            .frame(height: windowHeight, alignment: .top)
            .frame(height: max(height - Self.rowHeight - Self.windowInset, 0), alignment: .top)
            .background(Theme.page)
            .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
            // Light: a hairline inside the window's edge, so a white page
            // doesn't melt into the paper around it.
            .overlay {
                RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous)
                    .strokeBorder(Theme.windowHairline, lineWidth: 1)
            }
            .padding(.horizontal, Self.windowInset)
            .padding(.top, Self.rowHeight)
            .opacity(Double(min(t * 2, 1)))
            .allowsHitTesting(false)
    }

    /// A slim row's height.
    static let rowHeight: CGFloat = 44

    // MARK: The grid's card (TestFlight)

    /// The grid's card, as Safari's (David, 2026-11-16): the page's picture
    /// is the card, with a round X on its corner, and the site's icon and
    /// the title sit under it on the overview's wash, so the title has the
    /// card's whole width (in the paper card's line it had about six
    /// letters). No paper: the wash and the ring are Firn's.
    private var gridCard: some View {
        let shape = RoundedRectangle(cornerRadius: Self.gridCornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            Button(action: open) {
                pictureView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.page)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Theme.windowHairline, lineWidth: 1) }
                    .opacity(windowShown ? 1 : 0)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            // iOS's menu lifts only the picture, as Safari's: the title, the
            // X, and the shadow stay behind under iOS's blur (David,
            // 2026-11-16). The drag that can follow lifts the same shape
            // (`gridPictureShape`, on the whole tile).
            .systemHoldMenu(holdMenu != nil, shape: shape, opened: { menuOpen = $0 },
                            sections: holdMenu ?? { [] })
            .background {
                // Gone while iOS lifts the picture: it sits outside what
                // iOS lifts, so it showed as a dark copy left behind when
                // the lifted picture moved aside for the menu (David's
                // recording, 2026-11-16).
                shape.fill(Theme.page)
                    .shadow(color: reduceTransparency ? .clear : Theme.shadowSoft, radius: 6, y: 2)
                    .opacity(windowShown && !menuOpen && !carried ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                // Hidden while its menu is open too: a drag pulled off the
                // menu takes its picture then, and Safari's carries no X.
                GridCloseButton(title: tab.title, close: close)
                    .opacity(carried || menuOpen || swiped || gridSwipe == .swiping ? 0 : 1)
            }
            // No ring on the tab on screen in the grid, as Safari's: the
            // landing glide and opening scrolled to it already say which
            // it is (David, 2026-11-16); VoiceOver still hears "On screen."
            .frame(height: max(cardHeight - Self.gridTitleHeight, 1))
            // Swiped to close, it grows a touch and its title goes, as
            // Safari's (David's recording, 2026-11-17).
            // Animated where `swiped` changes (`follow`, `letGo`), so it
            // shrinks on the same ease as the slide home, as Safari's.
            .scaleEffect(swiped && !reduceMotion ? Self.swipeGrowth : 1)
            GridTitle(tab: tab)
                .frame(height: Self.gridTitleHeight, alignment: .top)
                .opacity(swiped || gridSwipe == .swiping ? 0 : 1)
                .contentShape(.rect)
                .onTapGesture(perform: open)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: reportSpot)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(groupName.map { "\(tab.title), in \($0)" } ?? tab.title)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
        .accessibilityActions {
            if let moveUp { Button("Move Left", action: moveUp) }
            if let moveDown { Button("Move Right", action: moveDown) }
        }
        .task(id: picture == nil) { if picture == nil { await loadPicture() } }
        .animation(.easeOut(duration: 0.15), value: picture != nil)
    }

    /// How long a grid card takes to ease home after a swipe, shrinking
    /// as it goes: Safari's, about half a second (David's recording,
    /// 2026-11-17).
    private static let swipeHome: Double = 0.45
    /// How much a grid card grows while swiped: Safari's, about 6%,
    /// measured from David's recording (2026-11-17).
    private static let swipeGrowth: CGFloat = 1.06

    /// The grid card's corners: Safari's 15pt, measured from David's
    /// screenshots (2026-11-16); the X's disc sits concentric in the corner.
    static let gridCornerRadius: CGFloat = 15
    /// A grid card's picture within its whole tile (the title under it
    /// left out), for the drag's lift, so it matches the menu's.
    static var gridPictureShape: some Shape {
        UnevenInsetShape(bottom: gridTitleHeight,
                         shape: RoundedRectangle(cornerRadius: gridCornerRadius, style: .continuous))
    }
    /// The icon and title under a grid card.
    nonisolated static let gridTitleHeight: CGFloat = 30

    /// Where a grid card's picture sits in its frame: all but the title
    /// under it.
    static func gridWindow(in card: CGRect) -> CGRect {
        CGRect(x: card.minX, y: card.minY, width: card.width,
               height: max(card.height - gridTitleHeight, 1))
    }

    @ViewBuilder private var pictureView: some View {
        if let picture, picture.size.width > 0 {
            // As wide as the window, from just below the page's header, so
            // it shows what was being read (2j): exactly where the glide
            // lands, so swapping one for the other shows nothing.
            GeometryReader { box in
                let scale = box.size.width / picture.size.width
                Image(uiImage: picture)
                    .resizable()
                    .frame(width: box.size.width, height: picture.size.height * scale)
                    .offset(y: -pictures.headerDepth(for: tab.id) * scale)
            }
            .accessibilityHidden(true)
        } else {
            SiteIconView(icon: tab.icon, size: 40) { LetterMark(site: site) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    /// The row stays under the finger going left; going right it barely
    /// gives, so it's clear that way does nothing.
    private func follow(_ dx: CGFloat) {
        guard inGrid else {
            pull = dx < 0 ? dx : dx * 0.15
            return
        }
        // Once iOS has begun lifting the card (`carried`), a move sideways is
        // its drag's, never a swipe, as Safari's. Both used to run: the swipe
        // slid the card while iOS faded it for the lift, so it went half
        // see-through and seemed to pass under its neighbor, then snapped
        // back as the drag took over (David's recording beside Safari's,
        // 2026-11-17). A swipe already under way eases home.
        if carried {
            if pull != 0 || swiped { easeHome() }
            return
        }
        // The grid's card grows as the swipe starts and stays grown, either
        // way, until it's let go; right, it follows with some give (Safari's).
        if !swiped { withAnimation(.smooth(duration: 0.2)) { swiped = true } }
        pull = dx < 0 ? dx : dx * 0.4
    }

    private func letGo(_ dx: CGFloat, _ speed: CGFloat) {
        let far = width > 0 && -dx > width / 3
        let flick = speed < -700 && dx < -20
        // A card iOS lifted is never closed by the swipe it took over.
        guard (far || flick) && !(inGrid && carried) else {
            easeHome()
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

    /// The grid's card eases home and shrinks together, unhurried; the
    /// list's row glides back as before.
    private func easeHome() {
        withAnimation(.smooth(duration: inGrid ? Self.swipeHome : 0.25)) {
            pull = 0
            swiped = false
        }
    }
}

/// A tab's line: the site's icon, the page's title (13pt semibold, one
/// line), and a plain X, the same in a slim row and at the top of a tall
/// card (David, 2026-11-16), so nothing on it moves as a row opens into a
/// card. Taps on the icon and title fall through to the tile; only the X
/// is its own, 44pt to tap.
struct TabLine: View {
    let tab: FirnCore.Tab
    let close: () -> Void

    static let titleFont = Font.footnote.weight(.semibold)
    private static let icon: CGFloat = 20
    private var site: String { WebAddress.site(of: tab.url) }

    var body: some View {
        HStack(spacing: 0) {
            SiteIconView(icon: tab.icon, size: Self.icon) { LetterMark(site: site, size: Self.icon) }
                .frame(width: Self.icon, height: Self.icon)
                .padding(.leading, 14)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Text(tab.title)
                .font(Self.titleFont)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .accessibilityLabel("Close \(tab.title)")
        }
        .frame(height: OverviewRow.rowHeight)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Under a grid card: the site's icon and the page's title, one line, on
/// the overview's wash (TestFlight's grid, after Safari's).
struct GridTitle: View {
    let tab: FirnCore.Tab
    private static let icon: CGFloat = 16
    private var site: String { WebAddress.site(of: tab.url) }

    var body: some View {
        HStack(spacing: 7) {
            SiteIconView(icon: tab.icon, size: Self.icon) { LetterMark(site: site, size: Self.icon) }
                .frame(width: Self.icon, height: Self.icon)
            Text(tab.title)
                .font(TabLine.titleFont)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.top, 5)
        .accessibilityHidden(true)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// A grid card's X, on the picture's corner as Safari's: a small disc of
/// ink with the X in the page's white, so it reads over any page; 44pt to
/// tap.
struct GridCloseButton: View {
    let title: String
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.closeDiscMark)
                .frame(width: 22, height: 22)
                .background(Theme.closeDisc, in: .circle)
                // Its middle 15pt from the corner, as Safari's, so it sits
                // concentric with the card's 15pt corner; the 44pt
                // to tap reaches past the card's edge.
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(-7)
        .accessibilityLabel("Close \(title)")
    }
}

/// A shape drawn in its rect with the bottom left out.
struct UnevenInsetShape<S: Shape>: Shape {
    let bottom: CGFloat
    let shape: S

    func path(in rect: CGRect) -> Path {
        var r = rect
        r.size.height = max(r.height - bottom, 1)
        return shape.path(in: r)
    }
}

private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

extension Theme {
    /// A tall card's paper: the page's warm white in light; in dark, a
    /// clear step above the overview's wash so cards stand off it as they
    /// do in light (#34302D was too close; David, 2026-11-16). The iPhone's only.
    /// (`Theme`'s own light-and-dark maker is private to the shared file.)
    static let cardPaper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x42 / 255, green: 0x3D / 255, blue: 0x39 / 255, alpha: 1)
            : UIColor(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF8 / 255, alpha: 1)
    })
    /// A grid card's X: a disc of neutral dark grey at 80% (menus and cards
    /// stay neutral, David, 2026-11-15), the X in near-white, light and dark;
    /// stronger than Safari's so it reads over bright pages (David, 2026-11-16).
    static let closeDisc = Color(white: 0.13).opacity(0.8)
    static let closeDiscMark = Color(white: 0.97)
    /// Dark cards' top edge: white at 6%; nothing in light.
    static let cardTopLight = Color(uiColor: UIColor { traits in
        UIColor(white: 1, alpha: traits.userInterfaceStyle == .dark ? 0.06 : 0)
    })
    /// The page window's inside edge in light: ink at 8%; nothing in dark.
    static let windowHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .clear
            : UIColor(red: 0x24 / 255, green: 0x1F / 255, blue: 0x1B / 255, alpha: 0.08)
    })
}

/// A sideways pan for a row in a scrolling list: it starts only when the
/// finger moves more across than up or down, so vertical scrolling is left
/// alone. UIKit's pan, because SwiftUI's DragGesture inside a ScrollView
/// either steals the scroll or never starts.
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var enabled = true
    let changed: (CGFloat) -> Void
    /// The distance moved and the speed across, in points per second.
    let ended: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.isEnabled = enabled
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = enabled
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
/// screen (`BasecampTiles`), just outside the card's edge with light on its top
/// and a faint glow, but always the space's color, never the page's (David,
/// 2026-11-08). Drawn on the card and on the page's picture gliding into it.
struct CardRing: View {
    let color: Color
    let radius: CGFloat
    /// Basecamp's ring width, drawn just outside the card's edge.
    static let width = BasecampTiles.ringWidth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Grown by its width, so it hugs the card's outside edge.
        let shape = RoundedRectangle(cornerRadius: radius + Self.width, style: .continuous)
        let dark = colorScheme == .dark
        shape.strokeBorder(color, lineWidth: Self.width)
            .opacity(reduceTransparency ? 1 : (dark ? 0.95 : 0.9))
            .overlay {
                // Light catching the ring's outer edge along the top, gone by the middle.
                shape.gradientBorder(
                    LinearGradient(colors: [Theme.tileRingSheen, Theme.tileRingSheen.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .shadow(color: color.opacity(dark ? 0.14 : 0.2), radius: 5)
            .padding(-Self.width)
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

/// A row runs again only when what it shows changes (2i step 3, part 2): the
/// overview makes every row anew each time it runs, with new actions, and a
/// closure never compares equal, so all of them ran (the SwiftUI template,
/// 2026-11-14: `OverviewRow` 40 times in 50ms at a gesture's turn, 5 rows).
/// Its actions aren't compared: they act on the same tab through state that
/// stays current, and what they were made from is in `actionsKey`. A tab's
/// title, address, and icon aren't compared either: the row reads them from
/// the tab itself, so it hears of their changes on its own.
extension OverviewRow: @MainActor Equatable {
    static func == (a: Self, b: Self) -> Bool {
        a.tab === b.tab && a.isOnScreen == b.isOnScreen && a.tallness == b.tallness
            && a.pictures === b.pictures && a.readsDisk == b.readsDisk && a.ring == b.ring && a.space == b.space
            && a.windowShown == b.windowShown && a.groupName == b.groupName
            && (a.moveUp == nil) == (b.moveUp == nil) && (a.moveDown == nil) == (b.moveDown == nil)
            && a.actionsKey == b.actionsKey && a.cardHeight == b.cardHeight && a.inGrid == b.inGrid
            && a.carried == b.carried && a.swipesItself == b.swipesItself && a.gridSwipe == b.gridSwipe
    }
}
