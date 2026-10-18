import AppKit
import SwiftUI

/// Firn's colors and sizes, in one place (CLAUDE.md, Design tokens).
/// Views never hard-code a color.
enum Theme {
    static let frame = Color(light: 0xE9E3DA, dark: 0x3A3734)
    static let page = Color(light: 0xFBFAF8, dark: 0x2B2826)
    static let ink = Color(light: 0x241F1B, dark: 0xF5F1EC)
    static let muted = Color(light: 0x5E564E, dark: 0xD4CDC5)
    static let faint = Color(light: 0x9D9389, dark: 0x958D85)
    static let frost = Color(light: 0x82A8BE, dark: 0xA0C4D6, opacity: 0.45)

    /// Hover and press: a warm brown wash in light, warm white in dark.
    static let hover = Color(light: 0x463728, lightOpacity: 0.07, dark: 0xF5F1EC, darkOpacity: 0.07)
    static let press = Color(light: 0x463728, lightOpacity: 0.13, dark: 0xF5F1EC, darkOpacity: 0.13)
    /// The tab on screen: lifted to page white in light, a warm-white wash in dark.
    static let activeTab = Color(light: 0xFBFAF8, lightOpacity: 1, dark: 0xF5F1EC, darkOpacity: 0.14)

    /// Shadows are warm brown in light, never grey.
    static let shadowSoft = Color(light: 0x3C2814, lightOpacity: 0.08, dark: 0x000000, darkOpacity: 0.15)
    static let shadowPageFar = Color(light: 0x3C2814, lightOpacity: 0.09, dark: 0x000000, darkOpacity: 0.16)
    /// The peeking sidebar floats over the page, so it casts a deeper shadow.
    static let shadowPeek = Color(light: 0x3C2814, lightOpacity: 0.22, dark: 0x000000, darkOpacity: 0.45)
    /// Its glass edge: a hairline that defines the card, and a lit inner rim.
    static let peekEdgeLine = Color(light: 0x3C2814, lightOpacity: 0.14, dark: 0x000000, darkOpacity: 0.40)
    static let peekEdgeRim = Color(light: 0xFFFFFF, lightOpacity: 0.70, dark: 0xFFFFFF, darkOpacity: 0.16)

    /// Basecamp tiles: frosted pebbles that sit a little lighter than the frame.
    /// Used under macOS 26's Liquid Glass, and on their own before it.
    static let tileFill = Color(light: 0xFFFFFF, lightOpacity: 0.42, dark: 0xF5F1EC, darkOpacity: 0.08)
    static let tileFillHover = Color(light: 0xFFFFFF, lightOpacity: 0.62, dark: 0xF5F1EC, darkOpacity: 0.13)
    /// With Reduce Transparency: the same tile, solid.
    static let tileSolid = Color(light: 0xF4F0EA, dark: 0x45413D)
    /// A tile's edge: lit along the top, a warm hairline around.
    static let tileRimTop = Color(light: 0xFFFFFF, lightOpacity: 0.85, dark: 0xFFFFFF, darkOpacity: 0.16)
    static let tileRimBottom = Color(light: 0xFFFFFF, lightOpacity: 0.15, dark: 0xFFFFFF, darkOpacity: 0.03)
    static let tileHairline = Color(light: 0x3C2814, lightOpacity: 0.07, dark: 0x000000, darkOpacity: 0.30)
    /// A cool, snowy tint that turns Liquid Glass from a bubble into frosted
    /// ice, and the crisp edge that goes with it.
    static let tileFrost = Color(light: 0xF4F8FA, lightOpacity: 0.35, dark: 0xA0C4D6, darkOpacity: 0.08)
    static let tileFrostEdge = Color(light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xC8DCE6, darkOpacity: 0.14)
    /// Tiles are a touch crisper than tab rows (10pt), so the glass reads as ice.
    static let tileRadius: CGFloat = 9

    /// A calm color for a site: its letter mark, and the wash and outline of
    /// its Basecamp tile when chosen. Picked steadily from the address so it
    /// never changes. (When site icons arrive, their own color can take over.)
    static func siteColor(for site: String) -> Color {
        let palette: [UInt32] = [0x7F9CB0, 0xC9A27E, 0x8FAE8B, 0xB88A9E, 0xC4A95B, 0x8E8FB8, 0xB07F6A, 0x6FA3A0]
        // FNV-1a: stable across launches, unlike Swift's hashValue.
        var hash: UInt32 = 2_166_136_261
        for byte in site.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let hex = palette[Int(hash % UInt32(palette.count))]
        return Color(light: hex, dark: hex)
    }

    /// A space's color, by name (Space.color). Unknown names fall back to Glacier.
    static func spaceColor(_ name: String) -> Color {
        Color(light: spaceHex(name), dark: spaceHex(name))
    }

    /// How strongly the active space tints the frame: 16% light, 14% dark.
    static func frameTint(_ name: String) -> Color {
        Color(light: spaceHex(name), lightOpacity: 0.16, dark: spaceHex(name), darkOpacity: 0.14)
    }

    private static func spaceHex(_ name: String) -> UInt32 {
        switch name {
        case "sand": 0xC9A27E
        case "sage": 0x8FAE8B
        case "heather": 0xB88A9E
        case "ochre": 0xC4A95B
        case "dusk": 0x8E8FB8
        case "clay": 0xB07F6A
        case "lagoon": 0x6FA3A0
        default: 0x7F9CB0
        }
    }

    // MARK: Sizes

    /// The page floats this far inside the window frame.
    static let pageInset: CGFloat = 8

    /// 8pt on macOS 26 and later, matching Liquid Glass window corners; 12pt before.
    static var pageCornerRadius: CGFloat {
        if #available(macOS 26, *) { 8 } else { 12 }
    }

    static let rowHeight: CGFloat = 36
    /// Air between the traffic lights and the first button after them.
    static let trafficLightGap: CGFloat = 16
    static let rowSpacing: CGFloat = 4
    static let rowPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    /// How the sidebar slides in and out. The traffic lights follow the same
    /// curve (see `WindowSetup`), so the two stay together.
    static let slideDuration = 0.2
    static func slide(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.3)
            : .timingCurve(0.3, 0, 0.2, 1, duration: slideDuration)
    }

    static let panelRadius: CGFloat = 14

    /// The peeking sidebar card sits this far inside the window edge: just
    /// outside the page's inset, as in Dia.
    static let peekInset: CGFloat = 4
    /// Its corners run parallel to the page's (same center, larger by the
    /// difference in inset), so window, card, and page corners nest.
    static var peekCornerRadius: CGFloat { pageCornerRadius + pageInset - peekInset }
    /// How close to the left edge the pointer must be to bring the card out.
    static let peekEdgeZone: CGFloat = 8
    /// How far past the card's right edge the pointer may drift before it hides.
    static let peekLeaveMargin: CGFloat = 16
    static let tabRadius: CGFloat = 10
    static let fieldRadius: CGFloat = 8
    static let smallRadius: CGFloat = 6

    // MARK: Type

    static let tabFont = Font.system(size: 13)
    static let labelFont = Font.system(size: 12)

    // MARK: Motion

    /// About 200ms, easing out (cubic-bezier(0.33, 1, 0.68, 1)). Nil with
    /// Reduce Motion, so things change in place.
    static func glide(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.2)
    }
}

private extension Color {
    /// A color that follows the system's light and dark appearance.
    init(light: UInt32, dark: UInt32, opacity: CGFloat = 1) {
        self.init(light: light, lightOpacity: opacity, dark: dark, darkOpacity: opacity)
    }

    init(light: UInt32, lightOpacity: CGFloat, dark: UInt32, darkOpacity: CGFloat) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, opacity: darkOpacity) : NSColor(hex: light, opacity: lightOpacity)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, opacity: CGFloat) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
