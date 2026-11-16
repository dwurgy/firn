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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// How far the finger has pulled the row left (0 or less).
    @State private var pull: CGFloat = 0
    @State private var width: CGFloat = 0
    /// Set once the row is on its way out, so it takes no more touches.
    @State private var leaving = false

    private var site: String { WebAddress.site(of: tab.url) }
    private var t: CGFloat { min(max(tallness, 0), 1) }
    /// A slim row's corners (and the group cards' are built on them).
    static let cornerRadius: CGFloat = 14
    /// A tall card's corners.
    static let cardCornerRadius: CGFloat = 18
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
            // A tab brought back (a shake's Undo) comes back in place. The
            // overview stays built now, and its row could keep the swipe
            // that closed it: slid off the screen and taking no touches
            // (David's iPhone, 2026-11-10). Reopening also picks the tab.
            .onAppear { comeBack() }
            .onChange(of: tab.lastActiveAt) { comeBack() }
    }

    private func comeBack() {
        guard leaving || pull != 0 else { return }
        var now = Transaction()
        now.disablesAnimations = true
        withTransaction(now) {
            leaving = false
            pull = 0
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
        let height = Self.rowHeight + (Self.cardHeight - Self.rowHeight) * t
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
                .shadow(color: reduceTransparency ? .clear : Theme.shadowSoft, radius: 1, y: 0.5)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: spot)
        .accessibilityLabel(groupName.map { "\(tab.title), in \($0)" } ?? tab.title)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
        .accessibilityActions {
            if let moveUp { Button("Move Up", action: moveUp) }
            if let moveDown { Button("Move Down", action: moveDown) }
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
                CardRing(color: ring, radius: mix(Self.cornerRadius, Self.cardCornerRadius, t) + BasecampTiles.ringWidth)
                    .padding(-BasecampTiles.ringWidth)
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
    /// corners (the card's 18pt less the 5pt, so they run evenly).
    static let windowInset: CGFloat = 5
    static let windowCornerRadius: CGFloat = cardCornerRadius - windowInset
    private static let windowHeight = cardHeight - rowHeight - windowInset

    /// Where a card's picture sits, in a card's frame: what a page glides
    /// out of and into.
    static func window(in card: CGRect) -> CGRect {
        CGRect(x: card.minX + windowInset, y: card.minY + rowHeight,
               width: max(card.width - windowInset * 2, 1),
               height: max(card.height - rowHeight - windowInset, 1))
    }

    /// The page's picture under the line, cropped from the page's top at
    /// the window's width. As the card folds, the window's bottom edge
    /// rises with the card's, so the picture folds away under the line.
    private func window(height: CGFloat) -> some View {
        pictureView
            .frame(maxWidth: .infinity)
            .frame(height: Self.windowHeight, alignment: .top)
            .frame(height: max(height - Self.rowHeight - Self.windowInset, 0), alignment: .top)
            .background(Theme.page)
            .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
            .padding(.horizontal, Self.windowInset)
            .padding(.top, Self.rowHeight)
            .opacity(Double(min(t * 2, 1)))
            .allowsHitTesting(false)
    }

    /// A slim row's height.
    static let rowHeight: CGFloat = 44

    @ViewBuilder private var pictureView: some View {
        if let picture, picture.size.width > 0 {
            // As wide as the window, from the page's top: exactly where
            // the glide lands, so swapping one for the other shows nothing.
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

private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

extension Theme {
    /// A tall card's paper: the page's warm white in light, a step above
    /// the overview's frame in dark (David, 2026-11-16). The iPhone's only.
    /// (`Theme`'s own light-and-dark maker is private to the shared file.)
    static let cardPaper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2B / 255, green: 0x28 / 255, blue: 0x26 / 255, alpha: 1)
            : UIColor(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF8 / 255, alpha: 1)
    })
}

/// A sideways pan for a row in a scrolling list: it starts only when the
/// finger moves more across than up or down, so vertical scrolling is left
/// alone. UIKit's pan, because SwiftUI's DragGesture inside a ScrollView
/// either steals the scroll or never starts.
struct SidewaysPan: UIGestureRecognizerRepresentable {
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

/// The ring around the tab on screen's card: Basecamp's ring on the tile on
/// screen (`BasecampTiles`), on the card's inside edge with light on its top
/// and a faint glow, but always the space's color, never the page's (David,
/// 2026-11-08). Drawn on the card and on the page's picture gliding into it.
struct CardRing: View {
    let color: Color
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = colorScheme == .dark
        shape.strokeBorder(color, lineWidth: BasecampTiles.ringWidth)
            .opacity(reduceTransparency ? 1 : (dark ? 0.95 : 0.9))
            .overlay {
                // Light catching the ring's outer edge along the top, gone by the middle.
                shape.gradientBorder(
                    LinearGradient(colors: [Theme.tileRingSheen, Theme.tileRingSheen.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .shadow(color: color.opacity(dark ? 0.14 : 0.2), radius: 5)
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
            && a.actionsKey == b.actionsKey
    }
}
