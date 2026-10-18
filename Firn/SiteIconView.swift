import AppKit
import FirnCore
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

/// A site icon's own calmed colors (see `IconColor`), or nil for black,
/// white, or grey icons. Worked out once per icon, not on every redraw.
@MainActor func siteIconColors(_ png: Data) -> IconColor.Colors? {
    let key = png as NSData
    if let known = SiteIconCache.colors.object(forKey: key) { return known.colors }
    let color = IconColor.from(png: png)
    SiteIconCache.colors.setObject(SiteIconCache.Found(color), forKey: key)
    return color
}

@MainActor
private enum SiteIconCache {
    static let images: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    /// NSCache keeps objects, and "no color" is worth remembering too.
    final class Found {
        let colors: IconColor.Colors?
        init(_ colors: IconColor.Colors?) { self.colors = colors }
    }

    static let colors: NSCache<NSData, Found> = {
        let cache = NSCache<NSData, Found>()
        cache.countLimit = 200
        return cache
    }()
}
