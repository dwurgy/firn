import CoreText
import os
import SwiftUI
import UIKit

/// Firn's type on iPhone and iPad (David, 2026-11-11): Gooper Deck for the
/// brand moments only (the welcome and the empty page), SF for tools
/// (Settings, History, other panel titles, and the scam warning). Fraunces
/// and New York are retired on iOS. The Mac still uses Fraunces through
/// `Theme.fraunces` (Shared/Theme.swift), which this app never calls.
///
/// Gooper Deck is licensed and must never be committed: the repo is public.
/// The files live in `PrivateFonts/` (ignored by git) on David's Mac, and the
/// target's "Copy Private Fonts" build step copies them into the app's
/// `Fonts/` folder only if they're there. Without them (a fork, a fresh
/// clone) brand moments use the system serif instead.
enum BrandFont {
    static let regular = "GooperDeck-Regular"
    static let semiBold = "GooperDeck-SemiBold"

    /// The welcome's headline.
    static let welcomeSize: CGFloat = 30
    /// The empty page's words.
    static let emptyPageSize: CGFloat = 24

    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "fonts")

    /// Registers the bundled Gooper Deck files for this app only, once at
    /// launch. In code rather than Info.plist's UIAppFonts, so a missing file
    /// is simply skipped instead of being something iOS looks for.
    static func register() {
        var found = 0
        for name in [regular, semiBold] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { found += 1 }
        }
        log.debug("Gooper Deck: \(found) of 2 registered")
    }

    /// Gooper Deck at `size`, SemiBold for emphasis, or the system serif when
    /// the font isn't in the app. `size` should already be scaled for
    /// Dynamic Type; `View.brandFont` does that.
    static func font(size: CGFloat, emphasis: Bool) -> Font {
        let name = emphasis ? semiBold : regular
        if UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: emphasis ? .semibold : .regular, design: .serif)
    }

    /// The text style whose default size is nearest `size`, so the font grows
    /// and shrinks with Dynamic Type the way that style does.
    static func textStyle(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case 31...: .largeTitle   // 34
        case 25..<31: .title      // 28
        case 21..<25: .title2     // 22
        case 19..<21: .title3     // 20
        default: .body            // 17
        }
    }
}

/// Firn's tool type: SF, as Apple's own apps title their screens.
enum ToolFont {
    /// Settings, History, and every other panel's title: 22pt semibold
    /// (title 2's size), following Dynamic Type.
    static let panelTitle = Font.title2.weight(.semibold)
    /// The scam warning's headline: 27pt regular, near the title style.
    /// Shown in `Theme.danger`, as before.
    static let scamWarningSize: CGFloat = 27
}

/// Gooper Deck (or the serif fallback) that follows Dynamic Type.
private struct BrandFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let emphasis: Bool

    init(size: CGFloat, emphasis: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: BrandFont.textStyle(near: size))
        self.emphasis = emphasis
    }

    func body(content: Content) -> some View {
        content.font(BrandFont.font(size: size, emphasis: emphasis))
    }
}

/// SF at a fixed design size that follows Dynamic Type.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: BrandFont.textStyle(near: size))
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// Brand-moment text: Gooper Deck at `size` (Regular, or SemiBold for
    /// emphasis), scaling with Dynamic Type. Only for the welcome
    /// (`BrandFont.welcomeSize`) and the empty page (`BrandFont.emptyPageSize`).
    func brandFont(_ size: CGFloat, emphasis: Bool = false) -> some View {
        modifier(BrandFontModifier(size: size, emphasis: emphasis))
    }

    /// The scam warning's headline: SF regular at 27pt, scaling with Dynamic
    /// Type. Pair it with `.foregroundStyle(Theme.danger)`.
    func scamWarningFont() -> some View {
        modifier(ScaledSystemFont(size: ToolFont.scamWarningSize, weight: .regular))
    }
}
