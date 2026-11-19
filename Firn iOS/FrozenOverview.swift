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
        /// The scroll, to the nearest 16pt: a tab lands a third down the list
        /// (`TabOverview.scroll(to:)`), a point or two off from last time,
        /// which a blur this soft can't show.
        let scroll: Int
        let dark: Bool

        /// Close enough to stand in: everything but which tab is on screen.
        /// Opening a tab makes it the one on screen as the page starts to
        /// grow (2k step 3), and only the card's ring moves, which a blur
        /// this soft can't show. `==` still counts it, so a new picture is
        /// taken once the overview rests again.
        func matches(_ other: Look) -> Bool {
            space == other.space && tabs == other.tabs && groups == other.groups && grouped == other.grouped
                && tiles == other.tiles && scroll == other.scroll && dark == other.dark
        }
    }

    /// How soft it starts (pt). Safari's starts so soft the cards can
    /// hardly be read (David's recording beside Safari's, 2026-11-13).
    static let radius: CGFloat = 26
    /// The overview as it is now, its edges faded off the main thread.
    /// They fade out over this much (pt): it grows from 92% with the
    /// list, and a hard edge showed against the haze behind it (Simulator,
    /// 2026-11-14); the 8% it starts short is about 16pt a side.
    static let feather: CGFloat = 28

    /// `picture`: the overview drawn alone (`OverviewCanvas.take`).
    @MainActor static func make(from picture: UIImage, look: Look) async -> FrozenOverview? {
        // At the screen's own scale: it becomes sharp, then swaps with the
        // live list. At one pixel a point, iOS drew it snapped to whole
        // points, about half a point up and left of the real thing, and the
        // swap showed double (Simulator, 2026-11-19).
        guard let source = picture.cgImage else { return nil }
        let scale = picture.scale
        let feather = Self.feather * scale
        let feathered = await Task.detached(priority: .utility) {
            Self.feather(source, over: feather)
        }.value
        guard let feathered else { return nil }
        return FrozenOverview(image: UIImage(cgImage: feathered, scale: scale, orientation: .up), look: look)
    }

    /// The picture with its edges faded out over `feather` pixels.
    private nonisolated static func feather(_ source: CGImage, over feather: CGFloat) -> CGImage? {
        let width = source.width, height = source.height
        guard width > 0, height > 0 else { return nil }
        let rowBytes = width * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var spare = [UInt8](repeating: 0, count: rowBytes * height)
        let done: Bool = spare.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: rowBytes, space: space,
                                          bitmapInfo: info) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        // Premultiplied, so every channel fades.
        guard done else { return nil }
        let reach = max(feather, 1)
        for y in 0..<height {
            let fromY = CGFloat(min(y, height - 1 - y)) + 0.5
            for x in 0..<width {
                let near = min(fromY, CGFloat(min(x, width - 1 - x)) + 0.5)
                guard near < reach else { continue }
                let t = near / reach
                let keep = t * t * (3 - 2 * t)
                let i = y * rowBytes + x * 4
                for c in 0..<4 { spare[i + c] = UInt8(CGFloat(spare[i + c]) * keep) }
            }
        }
        guard let provider = CGDataProvider(data: Data(spare) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The frozen picture, placed where it was taken: it's of the whole window.
/// `effects` (the focus pull and the growth) go on the picture itself,
/// inside the placing: around it, the growth also scaled the place this
/// reads for itself, and the picture slid up and left of the live list by a
/// few points mid-glide, a double image as they swapped (Simulator,
/// 2026-11-19).
struct FrozenOverviewView<Effects: ViewModifier>: View {
    let image: UIImage
    let effects: Effects

    var body: some View {
        GeometryReader { box in
            let frame = box.frame(in: .global)
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)
                .modifier(effects)
                .offset(x: -frame.minX, y: -frame.minY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
