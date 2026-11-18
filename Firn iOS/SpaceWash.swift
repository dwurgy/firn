import SwiftUI

/// The overview's backdrop: Sunrise's horizon band in the space's own color
/// (David, 2026-11-18, `docs/overview-backdrop-design.html`). Safari's
/// overview sits on the wallpaper, blurred hard, and its light and shadow
/// are what make the cards float; Firn can't read the wallpaper, so it uses
/// Sunrise's light and dark instead (a dim upper sky, the glow where the sun
/// peeks, the snow's ridges), blurred, and printed in two tints of the
/// space's color, so every space keeps its own look and no sky blue takes
/// over. It replaced the space wash (2026-11-16), a plain gradient that read
/// as flat beside Safari's.
///
/// Baked once per space and look as a small picture (a quarter of the
/// screen's points, blurred, so nothing is lost scaling it up) and kept in
/// memory: nothing redraws while the overview sits still or scrolls. A space
/// change cross-fades over 600ms, easing out (at once with Reduce Motion).
/// Opaque, so Reduce Transparency keeps it as it is.
struct SpaceWash: View {
    let space: String

    /// Every number worth tuning, in one place. A stop's `mix` is how much
    /// of the space's color goes into its base (0.12 = 12% space color).
    enum Tuning {
        /// The picture's two ends: where Sunrise is lightest (`hi`) and
        /// darkest (`lo`), each a base mixed with this share of the space's
        /// color. The mockup's Color 0.5, Depth 1; dark made darker so it
        /// feels like dark mode (David, 2026-11-18).
        struct End {
            let base: UInt32
            let mix: CGFloat
        }
        static let light = (hi: End(base: 0xF7F3EE, mix: 0.15), lo: End(base: 0xB9AE9F, mix: 0.50))
        static let dark = (hi: End(base: 0x302C28, mix: 0.25), lo: End(base: 0x0F0D0C, mix: 0.15))

        /// The picture's size, a quarter of the design screen's points
        /// (402×874), stretched to fill: it's blurred, so the stretch and
        /// the scale-up don't show.
        static let pictureSize = (width: 101, height: 219)
        /// The blur, in the design screen's points (the mockup's 40).
        static let blur: CGFloat = 40

        /// How long a space change cross-fades.
        static let fade: Double = 0.6

        /// The dither: a fine, fixed noise over the wash that melts the
        /// gradients' 1-shade steps (rings around the dark glow, measured
        /// 2026-11-16) into a smooth fade. Overlay-blended, so its strength
        /// depends on the color under it; these give about ±1.5 shades
        /// (of 255) on each look's mid tones. Too faint to read as texture.
        static let ditherOpacity: (light: Double, dark: Double) = (light: 0.5, dark: 0.7)
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// The space faded from, held under the new one until it's fully in.
    @State private var under: String?
    /// The new space's wash, fading in from 0 to 1 over `Tuning.fade`.
    @State private var over: Double = 1

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // The old space's wash stays fully there while the new one fades
            // in over it, so the screen never dips (a plain opacity
            // transition let both go half see-through, or dropped the old one
            // at once, in the Simulator's recordings).
            if let under, under != space { wash(for: under) }
            wash(for: space)
                .opacity(over)
            Image("PaperGrain")
                .resizable(resizingMode: .tile)
                .opacity(Theme.Sunrise.grainOpacity(dark: dark))
                .blendMode(dark ? .softLight : .multiply)
            // One noise pixel per screen pixel, never smoothed, or it can't
            // dither. A static image: nothing redraws.
            Image(uiImage: Self.dither(scale: displayScale))
                .resizable(resizingMode: .tile)
                .interpolation(.none)
                .opacity(dark ? Tuning.ditherOpacity.dark : Tuning.ditherOpacity.light)
                .blendMode(.overlay)
        }
        // Drawn in 16-bit, so the dither mixes into the gradients before
        // they're rounded to the screen's 256 shades. Drawn in the usual
        // 8 bits, the gradients were rounded first and the noise only sat
        // on top of the steps (boosted crops, 2026-11-16).
        .drawingGroup(opaque: true, colorMode: .linear)
        .onChange(of: space) { old, new in
            guard !reduceMotion else { return under = new }
            under = old
            over = 0
            withAnimation(.easeOut(duration: Tuning.fade)) { over = 1 } completion: {
                if space == new { under = new }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wash(for space: String) -> some View {
        Image(uiImage: Self.backdrop(tint: Theme.spaceHex(space), dark: dark))
            .resizable()
            .interpolation(.high)
    }

    /// Each space's picture, by its color and look, made once.
    @MainActor private static var backdrops: [String: UIImage] = [:]

    @MainActor private static func backdrop(tint: UInt32, dark: Bool) -> UIImage {
        let key = "\(tint)-\(dark)"
        if let kept = backdrops[key] { return kept }
        let ends = dark ? Tuning.dark : Tuning.light
        let hi = mix(ends.hi.base, tint, ends.hi.mix), lo = mix(ends.lo.base, tint, ends.lo.mix)
        func channel(_ hex: UInt32, _ shift: UInt32) -> Float { Float((hex >> shift) & 0xFF) }
        let low = [channel(lo, 16), channel(lo, 8), channel(lo, 0)]
        let span = [channel(hi, 16) - low[0], channel(hi, 8) - low[1], channel(hi, 0) - low[2]]
        let light = lightAndDark
        var pixels = [UInt8](repeating: 255, count: light.count * 4)
        for (i, v) in light.enumerated() {
            for c in 0..<3 { pixels[i * 4 + c] = UInt8(max(0, min(255, (low[c] + span[c] * v).rounded()))) }
        }
        let (w, h) = Tuning.pictureSize
        let image = pixels.withUnsafeMutableBytes { bytes -> UIImage in
            guard let context = CGContext(
                data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ), let cgImage = context.makeImage() else { return UIImage() }
            return UIImage(cgImage: cgImage)
        }
        backdrops[key] = image
        return image
    }

    /// Sunrise's horizon band as light and dark only (0 darkest, 1
    /// lightest), blurred: one picture shared by every space and both looks
    /// (one recipe, only the colors differ). Drawn in the design screen's
    /// points (402×874), from the mockup.
    @MainActor private static let lightAndDark: [Float] = {
        let (w, h) = Tuning.pictureSize
        let scale = CGFloat(w) / 402
        var gray = [UInt8](repeating: 0, count: w * h)
        gray.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            // Top-down, in the design screen's points.
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: scale, y: -scale)
            let space = CGColorSpaceCreateDeviceGray()
            func gradient(_ stops: [(CGFloat, CGFloat, CGFloat)]) -> CGGradient {
                CGGradient(colorSpace: space, colorComponents: stops.flatMap { [$0.1, $0.2] },
                           locations: stops.map(\.0), count: stops.count)!
            }
            let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            // The sky: dim at the top, brightening all the way down to the
            // horizon, so every gap between cards shows a different shade,
            // as Safari's wallpaper does (David, 2026-11-18: held in the
            // middle, the cards hid most of it).
            context.drawLinearGradient(
                gradient([(0, 0.22, 1), (0.35, 0.50, 1), (0.70, 0.80, 1), (1, 0.90, 1)]),
                start: CGPoint(x: 0, y: -60), end: CGPoint(x: 0, y: 700), options: options)
            // The glow where the sun peeks, 62% across, low.
            context.saveGState()
            context.translateBy(x: 250, y: 640)
            context.scaleBy(x: 1, y: 170.0 / 260)
            context.drawRadialGradient(gradient([(0, 1, 1), (1, 1, 0)]),
                                       startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 260,
                                       options: [])
            context.restoreGState()
            // The snow's ridges, each darker toward its shadowed foot.
            func ridge(_ build: (CGMutablePath) -> Void, top: CGFloat, from: CGFloat, to: CGFloat) {
                let path = CGMutablePath()
                build(path)
                path.addLine(to: CGPoint(x: 610, y: 1080))
                path.addLine(to: CGPoint(x: -200, y: 1080))
                path.closeSubpath()
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.drawLinearGradient(gradient([(0, from, 1), (1, to, 1)]),
                                           start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: 1080),
                                           options: options)
                context.restoreGState()
            }
            ridge({
                $0.move(to: CGPoint(x: -200, y: 700))
                $0.addCurve(to: CGPoint(x: 170, y: 690), control1: CGPoint(x: -60, y: 660), control2: CGPoint(x: 60, y: 715))
                $0.addCurve(to: CGPoint(x: 420, y: 685), control1: CGPoint(x: 280, y: 665), control2: CGPoint(x: 330, y: 662))
                $0.addCurve(to: CGPoint(x: 610, y: 680), control1: CGPoint(x: 510, y: 708), control2: CGPoint(x: 560, y: 668))
            }, top: 672, from: 0.70, to: 0.48)
            ridge({
                $0.move(to: CGPoint(x: -200, y: 770))
                $0.addCurve(to: CGPoint(x: 220, y: 770), control1: CGPoint(x: -40, y: 748), control2: CGPoint(x: 90, y: 800))
                $0.addCurve(to: CGPoint(x: 610, y: 778), control1: CGPoint(x: 350, y: 740), control2: CGPoint(x: 420, y: 740))
            }, top: 755, from: 0.84, to: 0.60)
            ridge({
                $0.move(to: CGPoint(x: -200, y: 840))
                $0.addCurve(to: CGPoint(x: 260, y: 832), control1: CGPoint(x: 0, y: 812), control2: CGPoint(x: 140, y: 862))
                $0.addCurve(to: CGPoint(x: 610, y: 840), control1: CGPoint(x: 380, y: 802), control2: CGPoint(x: 470, y: 818))
            }, top: 820, from: 0.92, to: 0.72)
        }
        // Three box blurs each way, close to a Gaussian of `Tuning.blur`
        // (each box about twice the blur's sigma wide), edges held.
        var values = gray.map { Float($0) / 255 }
        let radius = max(1, Int((Tuning.blur * scale).rounded()))
        func box(_ input: [Float], horizontal: Bool) -> [Float] {
            var out = input
            let (lines, length) = horizontal ? (h, w) : (w, h)
            for line in 0..<lines {
                func at(_ i: Int) -> Int {
                    let i = max(0, min(length - 1, i))
                    return horizontal ? line * w + i : i * w + line
                }
                var sum: Float = 0
                for i in -radius...radius { sum += input[at(i)] }
                for i in 0..<length {
                    out[at(i)] = sum / Float(2 * radius + 1)
                    sum += input[at(i + radius + 1)] - input[at(i - radius)]
                }
            }
            return out
        }
        for _ in 0..<3 { values = box(box(values, horizontal: true), horizontal: false) }
        return values
    }()

    /// The dither's tile: 128 pixels of grey noise around middle grey
    /// (±8 of 255), made once per screen scale with a fixed seed, so it's
    /// the same pattern every launch. Middle grey leaves overlay unchanged;
    /// the wash blends in linear light (`drawingGroup`), where middle grey
    /// is 188, not 128 (128 darkened everything by about 8 shades).
    @MainActor private static var dithers: [CGFloat: UIImage] = [:]

    @MainActor private static func dither(scale: CGFloat) -> UIImage {
        if let kept = dithers[scale] { return kept }
        let side = 128
        var seed: UInt32 = 0x9E37_79B9
        var pixels = [UInt8](repeating: 128, count: side * side)
        for i in pixels.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[i] = UInt8(180 + Int(seed >> 24) % 17)
        }
        let image = pixels.withUnsafeMutableBytes { bytes -> UIImage in
            guard let context = CGContext(
                data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let cgImage = context.makeImage() else { return UIImage() }
            return UIImage(cgImage: cgImage, scale: max(scale, 1), orientation: .up)
        }
        dithers[scale] = image
        return image
    }

    /// `share` of `other` mixed into `base`, channel by channel in sRGB.
    private static func mix(_ base: UInt32, _ other: UInt32, _ share: CGFloat) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = CGFloat((base >> shift) & 0xFF), b = CGFloat((other >> shift) & 0xFF)
            return UInt32((a + (b - a) * share).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}
