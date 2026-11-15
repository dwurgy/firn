import Accelerate
import SwiftUI
import UIKit

/// The overview, softened once (2026-11-14): as a tab lands, the overview
/// starts heavily blurred and comes into focus, as Safari's does (David,
/// 2026-11-13). Blurring the live list every frame took about 200 of the
/// GPU's offscreen passes a frame and dropped half the frames of each swipe
/// up on David's iPhone (Instruments, `docs/IOS-PLAN.md`). Instead, a
/// quarter-size picture of the overview is taken whenever it settles on
/// screen, blurred once off the main thread, and as a tab lands it fades
/// out over the sharp list: blurred to clear in one cross-fade, and nothing
/// blurred per frame.
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
        let rows: Bool
        /// The scroll, to the nearest 16pt: a tab lands a third down the list
        /// (`TabOverview.scroll(to:)`), a point or two off from last time,
        /// which a blur this soft can't show.
        let scroll: Int
        let dark: Bool
    }

    /// How soft it starts (pt). Safari's starts so soft the cards can
    /// hardly be read (David's recording beside Safari's, 2026-11-13).
    static let radius: CGFloat = 26
    /// The picture's scale: a quarter of the points, as the hold menu's
    /// (`ScreenPicture`); it's blurred anyway.
    static let scale: CGFloat = 0.25

    /// The screen as it is now, small, blurred off the main thread.
    /// Its edges fade out over this much (pt): it grows from 92% with the
    /// list, and a hard edge showed against the haze behind it (Simulator,
    /// 2026-11-14); the 8% it starts short is about 16pt a side.
    static let feather: CGFloat = 28

    @MainActor static func take(look: Look) async -> FrozenOverview? {
        guard let picture = ScreenPicture.take(), let source = picture.cgImage else { return nil }
        let pixels = radius * scale
        let feather = Self.feather * scale
        let blurred = await Task.detached(priority: .utility) {
            blur(source, radius: pixels, feather: feather)
        }.value
        guard let blurred else { return nil }
        return FrozenOverview(image: UIImage(cgImage: blurred, scale: scale, orientation: .up), look: look)
    }

    /// Three box blurs, together a Gaussian, edges held (as `PillBackdrop`),
    /// then the edges faded out over `feather` pixels.
    private nonisolated static func blur(_ source: CGImage, radius: CGFloat, feather: CGFloat) -> CGImage? {
        let width = source.width, height = source.height
        guard width > 0, height > 0 else { return nil }
        let rowBytes = width * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        var spare = [UInt8](repeating: 0, count: rowBytes * height)
        // As `PillBackdrop`: boxes about twice the radius wide, odd.
        let box = UInt32(max(Int(radius * 2), 1) | 1)
        let done: Bool = pixels.withUnsafeMutableBytes { raw in
            spare.withUnsafeMutableBytes { other in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: rowBytes, space: space,
                                              bitmapInfo: info) else { return false }
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
                var a = vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(height),
                                      width: vImagePixelCount(width), rowBytes: rowBytes)
                var b = vImage_Buffer(data: other.baseAddress, height: vImagePixelCount(height),
                                      width: vImagePixelCount(width), rowBytes: rowBytes)
                let flags = vImage_Flags(kvImageEdgeExtend)
                return vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, box, box, nil, flags) == kvImageNoError
                    && vImageBoxConvolve_ARGB8888(&b, &a, nil, 0, 0, box, box, nil, flags) == kvImageNoError
                    && vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, box, box, nil, flags) == kvImageNoError
            }
        }
        // The blur ended in `spare`. Premultiplied, so every channel fades.
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
struct FrozenOverviewView: View {
    let image: UIImage

    var body: some View {
        GeometryReader { box in
            let frame = box.frame(in: .global)
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)
                .offset(x: -frame.minX, y: -frame.minY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
