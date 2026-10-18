import AppKit
import SwiftUI

/// A site's own icon at `size` points, or `fallback` until there is one.
/// The icon is a small PNG FirnCore already made safe (see `SiteIcon`).
struct SiteIconView<Fallback: View>: View {
    let icon: Data?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if let image = icon.flatMap(Self.image) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            fallback()
        }
    }

    /// Decoded once per icon, not on every redraw of the sidebar.
    @MainActor private static func image(_ png: Data) -> NSImage? {
        let key = png as NSData
        if let image = SiteIconCache.images.object(forKey: key) { return image }
        guard let image = NSImage(data: png) else { return nil }
        SiteIconCache.images.setObject(image, forKey: key)
        return image
    }
}

@MainActor
private enum SiteIconCache {
    static let images: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 200
        return cache
    }()
}
