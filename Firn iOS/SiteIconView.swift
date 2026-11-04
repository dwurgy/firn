import SwiftUI
import UIKit

/// The iOS twin of the Mac's `SiteIconView` (Firn/SiteIconView.swift): a
/// site's icon from its PNG, or the fallback while there's none.
struct SiteIconView<Fallback: View>: View {
    let icon: Data?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if let image = icon.flatMap(Self.image) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            fallback()
        }
    }

    /// Decoded once per icon, not on every redraw of the list.
    @MainActor private static func image(_ png: Data) -> UIImage? {
        let key = png as NSData
        if let image = siteIconImages.object(forKey: key) { return image }
        guard let image = UIImage(data: png) else { return nil }
        siteIconImages.setObject(image, forKey: key)
        return image
    }
}

@MainActor private let siteIconImages: NSCache<NSData, UIImage> = {
    let cache = NSCache<NSData, UIImage>()
    cache.countLimit = 200
    return cache
}()
