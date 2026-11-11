import FirnCore
import SwiftUI
import UIKit

/// The pictures of each tab's page that the overview's cards will show
/// (phase 2, step 4), and the glide into the overview will stand in for
/// the page with (step 3b). Taken as the overview opens and as Firn leaves
/// the screen, saved on the device (`PagePictureStore`) so they're still
/// there after iOS ends Firn in the background, and kept in memory once
/// shown. A tab's picture goes with the tab (the session saver prunes).
@MainActor @Observable
final class PagePictures {
    @ObservationIgnored private let store: PagePictureStore
    /// Pictures read or taken since launch, at most `memoryLimit` of them:
    /// the least recently shown go first, and all of them when memory is
    /// short. They come back from disk when next asked for.
    private var images: [UUID: UIImage] = [:]
    /// The tabs in `images`, least recently shown first.
    @ObservationIgnored private var recent: [UUID] = []
    /// About 5MB each once drawn (a page twice its width in pixels), so
    /// two dozen stay near 120MB however many tabs are open; far more than
    /// the overview shows at once, so cards in view are never dropped.
    static let memoryLimit = 24
    /// How wide the page is on screen, in points (set by the screen).
    @ObservationIgnored var pageWidth: CGFloat = 0
    /// The status bar's height, in points (set by the screen): where the
    /// page, and so its picture, starts on screen.
    @ObservationIgnored var topInset: CGFloat = 0
    @ObservationIgnored private var warning: (any NSObjectProtocol)?

    init(store: PagePictureStore) {
        self.store = store
        warning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.images.removeAll()
                self?.recent.removeAll()
            }
        }
    }

    /// The tab's picture: from memory, else from disk, else nil.
    func image(for tabID: UUID) -> UIImage? {
        if let image = cachedImage(for: tabID) { return image }
        guard let picture = store.load(for: tabID) else { return nil }
        let image = UIImage(cgImage: picture, scale: 2, orientation: .up)
        keep(image, for: tabID)
        return image
    }

    /// The tab's picture if it's already in memory; never reads the disk,
    /// so a list of cards can ask while it draws.
    func cachedImage(for tabID: UUID) -> UIImage? {
        guard let image = images[tabID] else { return nil }
        markShown(tabID)
        return image
    }

    /// Keeps `image` in memory as the tab's, letting the least recently
    /// shown picture go once there are more than `memoryLimit`.
    private func keep(_ image: UIImage, for tabID: UUID) {
        images[tabID] = image
        markShown(tabID)
        while recent.count > Self.memoryLimit {
            images[recent.removeFirst()] = nil
        }
    }

    private func markShown(_ tabID: UUID) {
        if recent.last == tabID { return }
        recent.removeAll { $0 == tabID }
        recent.append(tabID)
    }

    /// Reads the tab's picture from disk and decodes it off the main thread
    /// (for the overview's older cards, as they come into view), so
    /// scrolling never waits on it.
    func loadImage(for tabID: UUID) async {
        guard images[tabID] == nil else { return }
        let store = store
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let picture = store.load(for: tabID) else { return nil }
            return UIImage(cgImage: picture, scale: 2, orientation: .up).preparingForDisplay()
        }.value
        if let image, images[tabID] == nil { keep(image, for: tabID) }
    }

    /// Takes a picture of the tab's page as it is now and saves it. A
    /// sleeping tab (no page) or a page that can't be pictured (nothing
    /// loaded, or a load error) keeps the picture it had. The task gives
    /// the new picture once it's in memory (saving goes on after), for the
    /// glide to stand in for the page with; nil if none was taken.
    @discardableResult
    func capture(_ tab: FirnCore.Tab) -> Task<UIImage?, Never>? {
        guard let page = tab.page, pageWidth > 0 else { return nil }
        let id = tab.id
        // Twice the page's width in pixels: sharp on a card a little
        // narrower than the screen, and a quarter of a 3x picture's size.
        let scale = UITraitCollection.current.displayScale
        let width = pageWidth * 2 / max(scale, 1)
        let store = store
        return Task {
            guard let picture = await page.snapshot(width: width) else { return nil }
            let image = UIImage(cgImage: picture, scale: 2, orientation: .up)
            keep(image, for: id)
            // Encoding and writing happen off the main thread.
            Task.detached(priority: .utility) {
                do {
                    try store.save(picture, for: id)
                } catch {
                    // A locked phone can refuse; the picture in memory stays.
                }
            }
            return image
        }
    }
}

extension UIImage {
    /// The color along the picture's top edge, averaged: what was just
    /// under the clock, for the strip there while the picture stands in
    /// for the page. A site's theme color can be quite another color (on
    /// steamdb.info, bright blue over a dark header; David's recording,
    /// 2026-11-11). Drawn down to 32 pixels, so it costs next to nothing.
    var topEdgeColor: CGColor? {
        guard let image = cgImage, image.width > 0, image.height > 0,
              let edge = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: min(6, image.height))),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let count = 32
        var pixels = [UInt8](repeating: 0, count: count * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: count, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: count * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(edge, in: CGRect(x: 0, y: 0, width: count, height: 1))
            return true
        }
        guard drawn else { return nil }
        var sum = [0.0, 0.0, 0.0]
        for i in 0..<count { for c in 0..<3 { sum[c] += Double(pixels[i * 4 + c]) } }
        let n = Double(count) * 255
        return CGColor(colorSpace: space, components: [sum[0] / n, sum[1] / n, sum[2] / n, 1])
    }
}
