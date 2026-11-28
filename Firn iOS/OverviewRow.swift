import FirnCore
import SwiftUI
import UIKit

/// A tab in the overview's grid, as Safari's: the page's picture is the
/// card, with the site's icon and the title under it. An X closes it in one
/// tap; a swipe left follows the finger and, past a third of the card or
/// with a flick, slides it off and closes it (a short swipe eases home).
struct OverviewRow: View {
    let tab: FirnCore.Tab
    let isOnScreen: Bool
    /// Where the page's picture comes from, for a tall card (read here, so
    /// a picture arriving runs only its own card), and whether it may be
    /// read from disk on the spot (the tab on screen, while shown);
    /// otherwise only if it's in memory.
    let pictures: PagePictures
    /// Read by the card's own small pieces (`CardWindow`), and here only by
    /// the tab on screen's card, for whether the overview is shown.
    let landing: Landing
    private var picture: UIImage? {
        isOnScreen && landing.shown ? pictures.image(for: tab.id) : pictures.cachedImage(for: tab.id)
    }
    /// Reads the picture from disk when a card comes into view without one.
    let loadPicture: () async -> Void
    /// The space's color name.
    let space: String
    let open: () -> Void
    let close: () -> Void
    /// Reports where the card is on screen.
    let spot: (CGRect) -> Void
    /// VoiceOver's way to reorder (a drag can't be found by it); nil at an end.
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    /// Its hold menu's choices, for VoiceOver's actions: nothing of a hold
    /// can be found by it.
    var menu: () -> [[HoldMenuItem]] = { [] }
    /// The group it's in, for VoiceOver ("<title>, in <group>"); nil when loose.
    var groupName: String?
    /// What the actions above were made from that the rest doesn't show
    /// (the row's place for Move Up and Move Down, Reduce Motion): rows
    /// are compared on what they show (`==`), and a row found unchanged
    /// keeps its old actions.
    var actionsKey: [Int] = []
    /// A card's height, which grows with its column so the picture stays
    /// portrait (`OverviewGridMetrics`).
    var cardHeight: CGFloat = OverviewRow.cardHeight
    /// Held by iOS, for its menu or its drag (the grid): its X
    /// hides, so only the picture lifts.
    var carried = false
    /// Drawn as a group folds or opens (`GroupGlideView`): only the
    /// picture, as it is in the folder; the X, title, and shadow fade.
    var bare = false
    /// No title under it: the glide draws the title itself, at full size
    /// beside the growing card, as Safari's.
    var titled = true
    /// The grid's UIKit cards are swiped by their collection view
    /// (`GridCards`), not here: one place decides between the swipe and
    /// iOS's press, menu, and drag. Elsewhere the row swipes itself.
    var swipesItself = true
    /// Where such a card is in its swipe: its spot waits until it's home.
    var gridSwipe: GridSwipe = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// How far the finger has pulled the row left (0 or less).
    @State private var pull: CGFloat = 0
    @State private var width: CGFloat = 0
    /// Set once the row is on its way out, so it takes no more touches.
    @State private var leaving = false
    /// A grid card being swiped: grown, from the
    /// first move until it's eased home (or closed), as Safari's.
    @State private var swiped = false

    private var site: String { WebAddress.site(of: tab.url) }
    private var name: String { tab.title.isEmpty ? site : tab.title }
    /// The corners a group card and a lifted tab are built on.
    static let cornerRadius: CGFloat = 14
    /// The shortest a grid card is (`OverviewGridMetrics`).
    /// `nonisolated`: `OverviewGridMetrics` reads it off the main actor.
    nonisolated static let cardHeight: CGFloat = 240

    var body: some View {
        gridCard
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

    /// A folded group's height (`GroupCard.foldedHeight`).
    static let rowHeight: CGFloat = 44

    // MARK: The grid's card

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
                    .modifier(CardWindow(landing: landing, tab: tab.id, onScreen: isOnScreen))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .background {
                // Gone while iOS lifts the picture: it sits outside what
                // iOS lifts, so it showed as a dark copy left behind when
                // the lifted picture moved aside for the menu (David's
                // recording, 2026-11-16).
                shape.fill(Theme.page)
                    .shadow(color: reduceTransparency ? .clear : Theme.gridCardShadow,
                            radius: Self.gridShadowRadius, y: Self.gridShadowDrop)
                    .modifier(CardWindow(landing: landing, tab: tab.id, onScreen: isOnScreen,
                                         hidden: carried || bare))
                    .animation(.easeOut(duration: Self.bareFade), value: bare)
            }
            .overlay(alignment: .topTrailing) {
                // Hidden while iOS holds the card, for its menu or its drag
                // (`carried`): Safari's lifted picture carries no X.
                GridCloseButton(title: tab.title, close: close)
                    // A swiped card keeps it, riding and growing with the
                    // card, as Safari's (David's recording, 2026-11-17).
                    .opacity(carried || bare ? 0 : 1)
                    .animation(.easeOut(duration: Self.bareFade), value: bare)
            }
            // No ring on the tab on screen in the grid, as Safari's: the
            // landing glide and opening scrolled to it already say which
            // it is (David, 2026-11-16); VoiceOver still hears "On screen."
            .frame(height: max(cardHeight - Self.gridTitleHeight, 1))
            // Swiped to close, it grows a touch, its title and X staying,
            // as Safari's (David's recording, 2026-11-17).
            // Animated where `swiped` changes (`follow`, `letGo`), so it
            // shrinks on the same ease as the slide home, as Safari's.
            .scaleEffect(swiped && !reduceMotion ? Self.swipeGrowth : 1)
            GridTitle(tab: tab)
                .frame(height: Self.gridTitleHeight, alignment: .top)
                .opacity(bare || !titled ? 0 : 1)
                .animation(.easeOut(duration: Self.bareFade), value: bare)
                .contentShape(.rect)
                .onTapGesture(perform: open)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: reportSpot)
        // One thing to VoiceOver, its name first: its X and its menu are
        // actions. As separate pieces, the card's button had no name (its
        // picture and title are hidden) and only "Close" was ever heard
        // (found 2026-11-24).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groupName.map { "\(name), in \($0)" } ?? name)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { open() }
        .accessibilityActions {
            HoldMenuActions(menu: menu)
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
    /// How much a grid card grows while swiped: Safari's, about 9%,
    /// measured from David's recording (2026-11-17).
    private static let swipeGrowth: CGFloat = 1.09

    /// The grid card's corners: Safari's 15pt, measured from David's
    /// screenshots (2026-11-16); the X's disc sits concentric in the corner.
    static let gridCornerRadius: CGFloat = 15
    /// The X, title, and shadow coming and going as a group folds or opens.
    private static let bareFade: TimeInterval = 0.14
    /// The grid card's shadow at rest, as Safari's: about 14pt of blur
    /// (SwiftUI's radius is half that), 5pt down (`Theme.gridCardShadow`).
    /// A swiped card's shadow grows with it (the cell's growth scales it).
    private static let gridShadowRadius: CGFloat = 7
    private static let gridShadowDrop: CGFloat = 5
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
                // As wide as its box; a picture too short for that (taken
                // on a wider screen: an iPad turned, a Duo folded) fills
                // the box's height instead, centered.
                let scale = max(box.size.width / picture.size.width, box.size.height / max(picture.size.height, 1))
                Image(uiImage: picture)
                    .resizable()
                    .frame(width: picture.size.width * scale, height: picture.size.height * scale)
                    .offset(x: (box.size.width - picture.size.width * scale) / 2,
                            y: -pictures.headerDepth(for: tab.id) * scale)
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
        guard (far || flick) && !carried else {
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

    /// The card eases home and shrinks together, unhurried.
    private func easeHome() {
        withAnimation(.smooth(duration: Self.swipeHome)) {
            pull = 0
            swiped = false
        }
    }
}

/// Under a grid card: the page's title alone, one line, on the overview's
/// wash. No site icon (David, 2026-11-19): the card's picture already
/// says which site it is, so the icon only repeated it; unlike Safari's.
/// 12pt words, 7pt under the card, 2pt in from its side (Safari's
/// measures, from David's recordings).
/// A folded group's name sits under its card the same way (David,
/// 2026-11-27).
struct GridTitle: View {
    let text: String
    static let titleFont = Font.caption.weight(.semibold)

    init(text: String) { self.text = text }
    init(tab: FirnCore.Tab) { text = tab.title }

    var body: some View {
        // A short title sits centered under its card; a long one fills the
        // width and truncates.
        Text(text)
            .font(Self.titleFont)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.top, 7)
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

extension Theme {
    /// A grid card's X, neutral (menus and cards stay neutral, David,
    /// 2026-11-15). Dark: a dark grey disc at 80%, the X near-white. Light:
    /// a pale disc with a dark grey X, as Safari's (David, 2026-11-18; the
    /// dark disc read heavy on light pages); solid enough to read over any
    /// page, with no blur to draw per card.
    static let closeDisc = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.13, alpha: 0.8)
            : UIColor(white: 0.90, alpha: 0.9)
    })
    static let closeDiscMark = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.97, alpha: 1) : UIColor(white: 0.25, alpha: 1)
    })
    /// A card's picture edge in light: ink at 8%; nothing in dark.
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
        a.tab === b.tab && a.isOnScreen == b.isOnScreen
            && a.pictures === b.pictures && a.landing === b.landing && a.space == b.space
            && a.groupName == b.groupName
            && (a.moveUp == nil) == (b.moveUp == nil) && (a.moveDown == nil) == (b.moveDown == nil)
            && a.actionsKey == b.actionsKey && a.cardHeight == b.cardHeight
            && a.carried == b.carried && a.bare == b.bare && a.titled == b.titled && a.swipesItself == b.swipesItself && a.gridSwipe == b.gridSwipe
    }
}
