import CoreImage
import FirnCore
import SwiftUI

/// The overview's backdrop: Sunrise, always, as a haze (David, 2026-11-16).
/// It used to be a blur of the tab you came from, so it looked different
/// every time (often plain white or black); now warm dawn light shines
/// through behind the cards, the way the Mac's window shows the desktop.
/// A deliberate exception to "Sunrise is for moments" (CLAUDE.md).
///
/// The scene (its snow in the space's color, the sky and sun Firn's own) is
/// rendered once, small, blurred off the main thread, and kept per space
/// color, look, and screen shape; on screen it's a plain image under a light
/// wash of the space's color. Nothing redraws while idle or scrolling. A
/// space change cross-fades both over 600ms, as the site's snow does
/// (instantly with Reduce Motion). Reduce Transparency: the plain tinted frame.
struct OverviewHaze: View {
    let space: String
    /// The overview is on screen: the clock goes light over the blue sky.
    let shown: Bool

    /// The haze's own tint: the space's color over the whole blurred scene,
    /// light and dark. One place to tune it.
    static let hazeTint: (light: CGFloat, dark: CGFloat) = (light: 0.06, dark: 0.05)
    /// The band of the scene's height (0 top, 1 bottom) the haze is made
    /// from: where the sky turns lavender, through the dawn glow, into the
    /// top of the snow. The whole scene read as navy above the cards in
    /// every space (David, 2026-11-16); its whole bottom 42% was mostly
    /// snow, a grey fog once blurred, so the band stops partway in.
    static let horizonBand: ClosedRange<CGFloat> = 0.50...0.84
    /// Dark only: how far the haze's bottom (`darkBottomShare` of it) is
    /// darkened toward warm charcoal, baked in, so blue hour never turns
    /// into grey fog over the snow.
    static let darkBottomStrength: CGFloat = 0.85
    static let darkBottomShare: CGFloat = 0.4
    /// Dark only: how far the dawn glow's warm pixels are eased toward the
    /// blue-hour sky (the haze's top), baked in, so the glow reads as a
    /// faint ember, not a brown patch (David, 2026-11-16).
    static let darkGlowReduction: CGFloat = 0.27

    @State private var haze: UIImage?
    /// The screen's height over its width, rounded, so a turned iPad gets a
    /// scene of its own shape (a portrait one, filled in, lost the horizon).
    @State private var aspect: Double = 0
    /// The baked scenes, per space color, look, and shape (a handful at most).
    @MainActor private static var kept: [String: UIImage] = [:]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The space's color at the haze's level for the current look.
    private static func tint(_ space: String) -> Color {
        let hex = Theme.spaceHex(space)
        let red = CGFloat((hex >> 16) & 0xFF) / 255, green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return Color(uiColor: UIColor { traits in
            UIColor(red: red, green: green, blue: blue,
                    alpha: traits.userInterfaceStyle == .dark ? hazeTint.dark : hazeTint.light)
        })
    }

    private var key: String { "\(space)|\(colorScheme == .dark)|\(aspect)" }
    private var fade: Animation? { reduceMotion ? nil : .easeOut(duration: 0.6) }

    var body: some View {
        ZStack {
            Theme.frame
            if reduceTransparency {
                Rectangle()
                    .fill(Theme.frameTint(space))
                    .animation(fade, value: space)
            } else {
                if let haze {
                    // Filling the screen, never sizing the backdrop itself.
                    // Stretched to the screen: the horizon's strip, blurred
                    // to blobs, shows no stretch.
                    Image(uiImage: haze)
                        .resizable()
                        .interpolation(.high)
                        // Each scene its own layer, so a new one cross-fades
                        // in by opacity alone, never blended on the CPU.
                        .id(ObjectIdentifier(haze))
                        .transition(.opacity)
                }
                Rectangle()
                    .fill(Self.tint(space))
                    .animation(fade, value: space)
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(Theme.Sunrise.grainOpacity(dark: colorScheme == .dark))
                    .blendMode(colorScheme == .dark ? .softLight : .multiply)
            }
        }
        .animation(fade, value: haze)
        .ignoresSafeArea()
        .onGeometryChange(for: Double.self) { proxy in
            let size = proxy.size
            return size.width > 0 ? (size.height / size.width * 20).rounded() / 20 : 0
        } action: { aspect = $0 }
        .background(LightStatusBar(on: shown && colorScheme == .dark && !reduceTransparency))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: aspect > 0 && !reduceTransparency ? key : nil) {
            guard aspect > 0, !reduceTransparency else { return }
            let key = key
            if let kept = Self.kept[key] { return haze = kept }
            let width: CGFloat = 200
            let renderer = ImageRenderer(content: SunriseScene(spaceColor: space)
                .frame(width: width, height: (width * aspect).rounded())
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 1
            guard let scene = renderer.cgImage else { return }
            // Only the horizon: from the lavender sky down to the snow.
            let height = CGFloat(scene.height)
            let top = (height * Self.horizonBand.lowerBound).rounded()
            let bottom = (height * Self.horizonBand.upperBound).rounded()
            guard let source = scene.cropping(to: CGRect(x: 0, y: top, width: CGFloat(scene.width),
                                                         height: bottom - top))
            else { return }
            let dark = colorScheme == .dark
            let made = await Task.detached(priority: .userInitiated) {
                Self.blurred(source).flatMap { dark ? Self.cooledGlow($0).flatMap(Self.darkenedBottom) : $0 }
            }.value
            guard !Task.isCancelled, let made else { return }
            let image = UIImage(cgImage: made)
            if Self.kept.count > 16 { Self.kept.removeAll() }
            Self.kept[key] = image
            haze = image
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
        return softener.createCGImage(soft, from: extent)
    }

    /// Dark's haze with its warm glow eased toward the sky at its top, in
    /// proportion to how warm each pixel is (red over blue); cool pixels
    /// stay as they are. A small image (128 wide), so a plain loop.
    private nonisolated static func cooledGlow(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // The sky: the average of the image's top row (first in memory).
        var sky = (r: 0.0, g: 0.0, b: 0.0)
        for x in 0..<width {
            sky.r += Double(pixels[x * 4]); sky.g += Double(pixels[x * 4 + 1]); sky.b += Double(pixels[x * 4 + 2])
        }
        sky = (sky.r / Double(width), sky.g / Double(width), sky.b / Double(width))
        let strength = Double(darkGlowReduction)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            // Fully warm once red leads blue by 24 (of 255).
            let warmth = min(max((r - b) / 24, 0), 1)
            guard warmth > 0 else { continue }
            let k = strength * warmth
            pixels[i] = UInt8((r + (sky.r - r) * k).rounded())
            pixels[i + 1] = UInt8((g + (sky.g - g) * k).rounded())
            pixels[i + 2] = UInt8((b + (sky.b - b) * k).rounded())
        }
        return context.makeImage()
    }

    /// Dark's haze with its bottom eased toward warm charcoal (the dark
    /// frame), so the snow's glow stays blue hour in every space color.
    private nonisolated static func darkenedBottom(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: full)
        let charcoal = CGColor(srgbRed: 0x28 / 255, green: 0x24 / 255, blue: 0x1F / 255, alpha: 1)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [charcoal.copy(alpha: 0)!, charcoal.copy(alpha: darkBottomStrength)!] as CFArray,
            locations: [0, 1]
        ) else { return image }
        // Core Graphics counts up from the bottom.
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height) * darkBottomShare),
                                   end: .zero, options: [.drawsAfterEndLocation])
        return context.makeImage()
    }

    /// One Core Image context, made once: setting one up for every haze
    /// was most of the wait for a page's first haze. Core Image's contexts
    /// are safe to share between threads.
    private nonisolated(unsafe) static let softener = CIContext(options: [.cacheIntermediates: false])
}
