import CoreImage
import FirnCore
import SwiftUI

/// The overview's backdrop, as Firn's Mac window shows a haze of what's
/// behind it: the page you came from, blurred by shrinking its picture to
/// a few pixels and stretching it back up (one still image, no live blur),
/// under a wash of the frame's color, the space's tint, and the paper
/// grain. With no picture (no tab), or Reduce Transparency: the plain
/// tinted frame. Nothing redraws while idle or scrolling; the haze is
/// remade only when the tab on screen or its picture changes, and a space
/// change cross-fades the tint.
struct OverviewHaze: View {
    let tab: UUID?
    let picture: UIImage?
    let space: String
    @State private var haze: UIImage?

    /// Each tab's last haze, kept while Firn runs (a few small images), so
    /// the overview opens with it already there. Made afresh every time, it
    /// came in after the page had landed, a second change once everything
    /// should be still (David's recording, 2026-11-09); a fresh one still
    /// cross-fades in over it when the page has changed.
    @MainActor private static var kept: [UUID: UIImage] = [:]

    init(tab: UUID?, picture: UIImage?, space: String) {
        self.tab = tab
        self.picture = picture
        self.space = space
        _haze = State(initialValue: tab.flatMap { Self.kept[$0] })
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Theme.frame
            if !reduceTransparency, let haze {
                // Filling the screen, never sizing the backdrop itself.
                Color.clear
                    .overlay {
                        Image(uiImage: haze)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                    .clipped()
                    // Each haze its own layer, so a new one cross-fades in
                    // by opacity alone. Changed in place, SwiftUI blended
                    // the two images on the CPU at full screen size every
                    // frame of the glide into the overview: three stalls
                    // of 55–110ms each (David's iPhone, 2026-11-10).
                    .id(ObjectIdentifier(haze))
                    .transition(.opacity)
                // One level for every page, as honest as the Mac's
                // window: whatever is behind is what shows.
                Theme.overviewWash
            }
            Rectangle()
                .fill(Theme.frameTint(space))
                .animation(.easeOut(duration: 0.2), value: space)
            if !reduceTransparency {
                Image("FirstLightGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(Theme.FirstLight.grainOpacity(dark: colorScheme == .dark))
                    .blendMode(colorScheme == .dark ? .softLight : .multiply)
            }
        }
        .animation(.easeOut(duration: 0.2), value: haze)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Another tab on screen: its own kept haze at once, as when the
        // overview was built for each opening (it stays built now).
        .onChange(of: tab) {
            var now = Transaction()
            now.disablesAnimations = true
            withTransaction(now) { haze = tab.flatMap { Self.kept[$0] } }
        }
        .task(id: picture.map(ObjectIdentifier.init)) {
            // No picture in memory (hidden): the kept haze stays.
            guard let source = picture?.cgImage else { return }
            let made = await Task.detached(priority: .userInitiated) { Self.blurred(source) }.value
            guard !Task.isCancelled else { return }
            haze = made.map { UIImage(cgImage: $0) }
            if let tab {
                if Self.kept.count > 30 { Self.kept.removeAll() }
                Self.kept[tab] = haze
            }
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

    /// One Core Image context, made once: setting one up for every haze
    /// was most of the wait for a page's first haze. Core Image's contexts
    /// are safe to share between threads.
    private nonisolated(unsafe) static let softener = CIContext(options: [.cacheIntermediates: false])
}
