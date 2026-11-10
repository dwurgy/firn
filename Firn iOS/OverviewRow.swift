import FirnCore
import SwiftUI
import UIKit

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
    /// VoiceOver's way to reorder (a drag can't be found by it); nil at an end.
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    /// The group it's in, for VoiceOver ("<title>, in <group>"); nil when loose.
    var groupName: String?

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

    /// A slim row is one line on a flat fill; a tall card is the same line on its
    /// page's picture. One view for both, so a pinch glides between them:
    /// the row's fill shrinks into the card's frosted pill as the tile grows
    /// around it, and the picture fades in behind. The tab on screen is ringed
    /// in the space's color on the card's inside edge, as Basecamp's tile on
    /// screen is (`CardRing`), so it reads at a glance.
    private var tile: some View {
        Button(action: open) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight + (Self.cardHeight - Self.rowHeight) * t)
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .background {
            // The page fades in behind the pill as the card grows; the
            // row's fill itself is the line's (it becomes the pill).
            Theme.page
                .overlay(alignment: .top) { pictureView }
                .clipShape(Self.shape)
                .opacity(t)
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
            CardTop(tab: tab, close: close, progress: t, space: space, picture: picture)
                .opacity(lineShown ? 1 : 0)
        }
        .overlay {
            if isOnScreen {
                CardRing(color: ring, radius: Self.cornerRadius)
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
    static let rowHeight: CGFloat = 44

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
/// and a card's pill are one shape (David, 2026-11-05): as the tile grows,
/// the row's flat fill shrinks into the pill in the card's top-left corner
/// and gives way to Firn's frost (the group cards', over a real blur), the
/// icon and title slide with it as one piece, and the row's X moves to the
/// top-right as its round frost forms around it (2026-11-08: one kind of
/// glass in the overview, Firn's own).
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
    /// The page's picture, drawn as wide as the card from its top: blurred
    /// under the pills, so the page's light comes through them.
    var picture: UIImage?

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
                 titleWidth: titleWidth, solid: reduceTransparency, picture: picture)
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
struct CardLine: View, Animatable {
    let tab: FirnCore.Tab
    let close: (() -> Void)?
    var progress: CGFloat
    let space: String
    let titleWidth: CGFloat
    /// Reduce Transparency: the card's frost becomes the solid frame color.
    let solid: Bool
    let picture: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// One font for both sizes (the row's semibold), so the text can't jump.
    /// 13pt, as Safari's tab titles (David, 2026-11-08): smaller pills, more
    /// of the picture.
    static let titleFont = Font.footnote.weight(.semibold)

    // The row's measures, then the card's.
    private static let rowHeight = OverviewRow.rowHeight          // 44
    private static let glassHeight: CGFloat = 30                  // the pill and round X
    private static let inset: CGFloat = 8                         // the pill's and X's distance in
    private static let rowIcon: CGFloat = 20                      // the site icon, row then pill
    private static let pillIcon: CGFloat = 18
    private static let pillPad: CGFloat = 8                       // pill edge to icon
    private static let iconGap: CGFloat = 6                       // icon to title, in the pill
    private static let cardLineHeight: CGFloat = inset + glassHeight + 6
    private static let tapSize: CGFloat = 44
    /// The X's middle, this far in from the right in a row and on a card
    /// alike, so it only moves up and down as the tile grows (David, 2026-11-08).
    private static let xCenterIn: CGFloat = 24
    /// Room on the card's right for the X and a gap before it.
    private static let xRoom: CGFloat = 52

    private var site: String { WebAddress.site(of: tab.url) }

    var body: some View {
        let t = min(max(progress, 0), 1)
        GeometryReader { box in
            let w = box.size.width
            // The fill: the whole row, then the pill.
            let pillLead = Self.pillPad + Self.pillIcon + Self.iconGap
            let pillWidth = min(max(w - Self.xRoom, 0), pillLead + titleWidth + 12)
            let glassWidth = mix(w, pillWidth, t)
            let glassHeight = mix(Self.rowHeight, Self.glassHeight, t)
            let glassShape = RoundedRectangle(cornerRadius: mix(OverviewRow.cornerRadius, Self.glassHeight / 2, t),
                                              style: .continuous)
            // The line's middle: the row's, then the pill's.
            let middle = mix(Self.rowHeight / 2, Self.inset + Self.glassHeight / 2, t)
            let titleX = mix(46, Self.inset + pillLead, t)
            let titleRoom = max(mix(w - 92, pillWidth - pillLead - 12, t), 0)
            ZStack(alignment: .topLeading) {
                ZStack {
                    // A slim row is flat (David, 2026-11-08): only group cards
                    // and a card's pills are frost. As the tile grows, the
                    // row's flat fill shrinks into the pill and gives way to
                    // its frost, one shape all the way. The frost is always
                    // there, only faded: added mid-pinch, SwiftUI gave it a
                    // glide of its own, and it trailed the title (David's
                    // recording, 2026-11-08).
                    // A slim row: flat paper, the same loose and grouped,
                    // with a hairline and a faint shadow so it reads as
                    // something to tap (`Theme.slimRowFill`).
                    glassShape.fill(solid ? Theme.tileSolid : Theme.slimRowFill)
                        .overlay { glassShape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
                        .shadow(color: solid ? .clear : Theme.shadowSoft, radius: 1, y: 0.5)
                        .opacity(1 - t)
                    pillFrost(glassShape, at: CGPoint(x: mix(0, Self.inset, t), y: mix(0, Self.inset, t)),
                              size: CGSize(width: glassWidth, height: glassHeight), cardWidth: w)
                        .opacity(t)
                }
                .frame(width: glassWidth, height: glassHeight)
                .offset(x: mix(0, Self.inset, t), y: mix(0, Self.inset, t))
                .allowsHitTesting(false)
                SiteIconView(icon: tab.icon, size: Self.rowIcon) { LetterMark(site: site, size: Self.rowIcon) }
                    .scaleEffect(mix(1, Self.pillIcon / Self.rowIcon, t))
                    .frame(width: Self.rowIcon, height: Self.rowIcon)
                    .offset(x: mix(24, Self.inset + Self.pillPad + Self.pillIcon / 2, t) - Self.rowIcon / 2,
                            y: middle - Self.rowIcon / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(Self.titleFont)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: titleRoom, height: 30, alignment: .leading)
                    // A change of the row's width (a group forming or
                    // thawing around it) sets the title's room at once: its
                    // width gliding made the title wrap and ride up to the
                    // row's top edge mid-glide (David's recording,
                    // 2026-11-08). The pinch, which changes `t`, still glides.
                    .animation(nil, value: w)
                    .offset(x: titleX, y: middle - 15)
                    // Taps on the icon and title open the tile; only the X is its own.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                closeButton(t, cardWidth: w, middle: middle)
                    .offset(x: (w - Self.xCenterIn) - Self.tapSize / 2,
                            y: middle - Self.tapSize / 2)
            }
        }
        .frame(height: mix(Self.rowHeight, Self.cardLineHeight, t), alignment: .top)
    }

    /// How soft the page is through a pill: enough that no shape can be
    /// made out, while its light and color still come through.
    private static let blurRadius: CGFloat = 10
    /// Frost scatters light, so it's brighter than what's behind it: in
    /// light mode the blurred page is lifted a fixed amount, so a dark
    /// page's pill turns a lighter grey and its dark title reads (David,
    /// 2026-11-08). Bright pages barely change. Dark mode reads as is.
    private static let frostLift: Double = 0.15
    private static let noPicture = UIImage()

    /// A pill's frost: the group cards' recipe, light, over the page's own
    /// picture blurred (David, 2026-11-08: light pouring through frozen
    /// glass). Firn's own blur, not iOS's material, which laid a grey veil
    /// and dulled the colors and can't be tuned. `origin` and `size` are
    /// the pill's spot in the card, so the blur lines up with the picture
    /// around it. Always drawn, even without a picture (an empty image),
    /// so nothing is added mid-pinch.
    private func pillFrost<S: InsettableShape>(_ shape: S, at origin: CGPoint, size: CGSize,
                                               cardWidth: CGFloat) -> some View {
        let image = solid ? Self.noPicture : (picture ?? Self.noPicture)
        let scale = image.size.width > 0 ? cardWidth / image.size.width : 0
        return Frost(shape: shape, space: space, fill: Theme.cardPillVeil, solid: solid)
            .background {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: cardWidth, height: image.size.height * scale)
                    .offset(x: -origin.x, y: -origin.y)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .blur(radius: Self.blurRadius, opaque: true)
                    .brightness(colorScheme == .light ? Self.frostLift : 0)
                    .clipShape(shape)
                    .accessibilityHidden(true)
            }
    }

    /// The row's small X, moving to the card's corner as its round frost
    /// forms around it.
    @ViewBuilder private func closeButton(_ t: CGFloat, cardWidth w: CGFloat, middle: CGFloat) -> some View {
        let size = mix(28, Self.glassHeight, t)
        let formed = min(max((t - 0.3) / 0.7, 0), 1)
        let center = CGPoint(x: (w - Self.xCenterIn), y: middle)
        let mark = ZStack {
            pillFrost(Circle(), at: CGPoint(x: center.x - size / 2, y: center.y - size / 2),
                      size: CGSize(width: size, height: size), cardWidth: w)
                .frame(width: size, height: size)
                .opacity(formed)
            ZStack {
                Image(systemName: "xmark").foregroundStyle(Theme.muted)
                Image(systemName: "xmark").foregroundStyle(Theme.ink).opacity(t)
            }
            .font(.system(size: 12, weight: .semibold))
            .scaleEffect(mix(11 / 12, 1, t))
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
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.tileRingSheen, Theme.tileRingSheen.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .shadow(color: color.opacity(dark ? 0.18 : 0.28), radius: 5)
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
