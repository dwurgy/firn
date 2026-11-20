import SwiftUI
import UIKit

/// The overview's picture for the focus pull (2026-11-19; softened once
/// and cross-faded before, 2026-11-14): as a tab lands, the overview starts
/// heavily blurred and comes into focus, as Safari's does (David,
/// 2026-11-13). Blurring the live list every frame took about 200 of the
/// GPU's offscreen passes a frame and dropped half the frames of each swipe
/// up on David's iPhone (Instruments, `docs/IOS-PLAN.md`). Instead, one flat
/// picture of the overview, its bar included, is taken whenever it settles,
/// on screen or behind the page (its own view drawn alone, `OverviewCanvas`;
/// step 1b), and as a tab lands that one picture is blurred each frame,
/// less and less (`FocusPull`), until the live list takes over.
///
/// The picture is only used while it still matches what the overview will
/// show (`Look`); otherwise the landing simply has no blur (the dim and the
/// growth still run). Kept in memory only, never saved.
struct FrozenOverview {
    let image: UIImage
    let look: Look

    /// What the overview showed when its picture was taken: if any of it
    /// changes, the picture is out of date.
    struct Look: Equatable {
        let space: UUID
        let onScreen: UUID?
        let tabs: [UUID]
        let groups: [UUID: Bool]
        let grouped: [UUID: UUID]
        let tiles: [UUID]
        /// The scroll (pt). A tab lands a third down the list
        /// (`TabOverview.scroll(to:)`), a point or two off from last time.
        let scroll: CGFloat
        /// How far off the scroll may be and the picture still stand in:
        /// the hand-over's last blur hides it. (Whole 16pt steps before:
        /// two scrolls a point apart could fall either side of a step.)
        static let scrollGive: CGFloat = 8
        let dark: Bool

        /// Close enough to stand in: everything but which tab is on screen.
        /// Opening a tab makes it the one on screen as the page starts to
        /// grow (2k step 3), and only the card's ring moves, which a blur
        /// this soft can't show. `==` still counts it, so a new picture is
        /// taken once the overview rests again.
        func matches(_ other: Look) -> Bool {
            space == other.space && tabs == other.tabs && groups == other.groups && grouped == other.grouped
                && tiles == other.tiles && abs(scroll - other.scroll) <= Self.scrollGive && dark == other.dark
        }
    }

    /// How soft it starts (pt). Safari's starts so soft the cards can
    /// hardly be read (David's recording beside Safari's, 2026-11-13).
    static let radius: CGFloat = 26
    /// How far the picture runs past the window on each side (pt), filled
    /// with the picture mirrored. It grows from 92% with the list
    /// (`ComesForward.depth`), and stopped at its own faded edges before,
    /// so a frame of bare wash showed around the blurred grid for a whole
    /// hold; Safari's fills the screen (David's second recording,
    /// 2026-11-19). Mirrored, not smeared: under the blur a card cut by the
    /// edge carries on as a card. Enough for the 8% it starts short, plus
    /// room for the blur to thin out in, off screen.
    let pad: CGSize

    /// The room the blur thins out in, past what the shrink shows (pt).
    static let blurRoom: CGFloat = 44

    @MainActor static func pad(for size: CGSize) -> CGSize {
        let depth = ComesForward.depth
        func side(_ length: CGFloat) -> CGFloat { ((length * depth / 2 + blurRoom) / (1 - depth)).rounded(.up) }
        return CGSize(width: side(size.width), height: side(size.height))
    }

    /// `picture`: the overview drawn alone (`OverviewCanvas.take`). Padded
    /// off the main thread.
    @MainActor static func make(from picture: UIImage, look: Look) async -> FrozenOverview? {
        // At the screen's own scale: it becomes sharp, then swaps with the
        // live list. At one pixel a point, iOS drew it snapped to whole
        // points, about half a point up and left of the real thing, and the
        // swap showed double (Simulator, 2026-11-19).
        guard let source = picture.cgImage else { return nil }
        let scale = picture.scale
        let pad = Self.pad(for: picture.size)
        // Whole pixels, so the middle stays exactly where it was.
        let padX = Int((pad.width * scale).rounded()), padY = Int((pad.height * scale).rounded())
        let padded = await Task.detached(priority: .utility) {
            Self.mirrored(source, padX: padX, padY: padY)
        }.value
        guard let padded else { return nil }
        return FrozenOverview(image: UIImage(cgImage: padded, scale: scale, orientation: .up), look: look,
                              pad: CGSize(width: CGFloat(padX) / scale, height: CGFloat(padY) / scale))
    }

    /// The picture with a border around it of itself mirrored at each edge.
    private nonisolated static func mirrored(_ source: CGImage, padX: Int, padY: Int) -> CGImage? {
        let width = source.width, height = source.height
        guard width > 0, height > 0, padX <= width, padY <= height else { return nil }
        guard let context = CGContext(data: nil, width: width + 2 * padX, height: height + 2 * padY,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        let whole = CGRect(x: 0, y: 0, width: w, height: h)
        for row in -1...1 {
            for column in -1...1 {
                context.saveGState()
                context.translateBy(x: CGFloat(padX) + CGFloat(column) * w, y: CGFloat(padY) + CGFloat(row) * h)
                if column != 0 {
                    context.translateBy(x: w, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                if row != 0 {
                    context.translateBy(x: 0, y: h)
                    context.scaleBy(x: 1, y: -1)
                }
                context.draw(source, in: whole)
                context.restoreGState()
            }
        }
        return context.makeImage()
    }
}

/// The frozen picture, placed where it was taken: it's of the whole window,
/// and runs past it by `pad` on every side.
/// `effects` (the focus pull and the growth) go on the picture itself,
/// inside the placing: around it, the growth also scaled the place this
/// reads for itself, and the picture slid up and left of the live list by a
/// few points mid-glide, a double image as they swapped (Simulator,
/// 2026-11-19).
struct FrozenOverviewView<Effects: ViewModifier>: View {
    let image: UIImage
    let pad: CGSize
    let effects: Effects

    var body: some View {
        GeometryReader { box in
            let frame = box.frame(in: .global)
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)
                .modifier(effects)
                .offset(x: -frame.minX - pad.width, y: -frame.minY - pad.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
