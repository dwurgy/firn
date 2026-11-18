import SwiftUI
import UIKit

/// The iOS twin of the Mac's `SiteIconView` (Firn/SiteIconView.swift): a
/// site's icon from its PNG, or the fallback while there's none. An icon
/// that fills its whole square (a touch icon, or a favicon with its own
/// background) gets the letter marks' rounded corners, so it reads as a
/// small app icon rather than a hard-edged square (David, 2026-11-18).
struct SiteIconView<Fallback: View>: View {
    let icon: Data?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if let decoded = icon.flatMap(Self.decoded) {
            Image(uiImage: decoded.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: decoded.fillsSquare ? size * 5 / 18 : 0,
                                            style: .continuous))
                .accessibilityHidden(true)
        } else {
            fallback()
        }
    }

    /// Decoded once per icon, not on every redraw of the list.
    @MainActor private static func decoded(_ png: Data) -> DecodedIcon? {
        let key = png as NSData
        if let decoded = siteIconImages.object(forKey: key) { return decoded }
        guard let image = UIImage(data: png) else { return nil }
        let decoded = DecodedIcon(image: image, fillsSquare: fillsSquare(image))
        siteIconImages.setObject(decoded, forKey: key)
        return decoded
    }

    /// Square, and solid in all four corners: drawn to a 16×16 copy and the
    /// corner pixels' alpha read back.
    private static func fillsSquare(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage, cgImage.width == cgImage.height else { return false }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        let corners = [0, side - 1, side * (side - 1), side * side - 1]
        return corners.allSatisfy { pixels[$0 * 4 + 3] > 230 }
    }
}

private final class DecodedIcon {
    let image: UIImage
    let fillsSquare: Bool
    init(image: UIImage, fillsSquare: Bool) {
        self.image = image
        self.fillsSquare = fillsSquare
    }
}

@MainActor private let siteIconImages: NSCache<NSData, DecodedIcon> = {
    let cache = NSCache<NSData, DecodedIcon>()
    cache.countLimit = 200
    return cache
}()
