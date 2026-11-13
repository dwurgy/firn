import CoreText
import SwiftUI

/// Gooper Deck, the brand's headline face (BRAND.md, "Type"), for the Mac's
/// welcome: Hello, the steps' titles, and "Welcome in." (David, 2026-11-13).
/// Settings, History, and the other panel titles keep Fraunces for now
/// (`Theme.fraunces`).
///
/// Gooper Deck is licensed and must never be committed: the repo is public.
/// The files live in `PrivateFonts/` (ignored by git) on David's Mac, and the
/// target's "Copy Private Fonts" build step copies them into the app's
/// `Fonts/` folder only if they're there. Without them (a fork, a fresh
/// clone) the welcome uses the bundled Fraunces instead.
enum BrandFont {
    /// Gooper Deck at `size`: Regular (400), or SemiBold (600) for emphasis,
    /// never heavier and never a color (BRAND.md).
    @MainActor static func gooper(_ size: CGFloat, emphasis: Bool = false) -> Font {
        if let descriptor = emphasis ? semiBold : regular {
            return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        }
        return Theme.fraunces(size, weight: emphasis ? 600 : 360)
    }

    /// Read once from the app's own files, for Firn only (not registered
    /// with the system); nil if the file isn't there.
    @MainActor private static let regular = descriptor("GooperDeck-Regular")
    @MainActor private static let semiBold = descriptor("GooperDeck-SemiBold")

    private static func descriptor(_ name: String) -> CTFontDescriptor? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "otf", subdirectory: "Fonts") else { return nil }
        return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
    }
}
