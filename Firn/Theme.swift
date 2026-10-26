import AppKit
import FirnCore
import SwiftUI

/// Firn's colors and sizes, in one place (CLAUDE.md, Design tokens).
/// Views never hard-code a color.
enum Theme {
    static let frame = Color(light: 0xE9E3DA, dark: 0x3A3734)
    /// The frame over the window's glass: mostly frame, a little desktop showing through.
    static let frameWash = Color(light: 0xE9E3DA, lightOpacity: 0.45, dark: 0x3A3734, darkOpacity: 0.55)
    static let page = Color(light: 0xFBFAF8, dark: 0x2B2826)
    static let ink = Color(light: 0x241F1B, dark: 0xF5F1EC)
    static let muted = Color(light: 0x5E564E, dark: 0xD4CDC5)
    static let faint = Color(light: 0x9D9389, dark: 0x958D85)
    static let frost = Color(light: 0x82A8BE, dark: 0xA0C4D6, opacity: 0.45)
    /// The system accent (radio buttons, switches, focus): a slightly more
    /// saturated Glacier, from the asset catalog. Set on controls in sheets
    /// by hand, where macOS otherwise draws them in its own blue.
    static let accent = Color("AccentColor")

    /// Hover and press: a warm brown wash in light, warm white in dark.
    static let hover = Color(light: 0x463728, lightOpacity: 0.07, dark: 0xF5F1EC, darkOpacity: 0.07)
    static let press = Color(light: 0x463728, lightOpacity: 0.13, dark: 0xF5F1EC, darkOpacity: 0.13)
    /// The tab on screen: lifted to page white in light, a warm-white wash in dark.
    static let activeTab = Color(light: 0xFBFAF8, lightOpacity: 1, dark: 0xF5F1EC, darkOpacity: 0.17)
    /// Its edge: a warm hairline, so it reads as a sheet, not a lighter patch.
    static let activeTabHairline = Color(light: 0x3C2814, lightOpacity: 0.08, dark: 0x000000, darkOpacity: 0.25)
    /// Under anything lifted off the sidebar (a tab, a tile, a group's card):
    /// the frame itself, nearly opaque, so the glass on top looks as it does
    /// at rest but never turns see-through over the page (`LiftBacking`).
    static let liftBacking = Color(light: 0xE9E3DA, lightOpacity: 0.88, dark: 0x3A3734, darkOpacity: 0.88)
    /// The other tabs' titles rest a step back, so the tab on screen leads.
    static let tabRest = Color(light: 0x5E564E, dark: 0xBDB5AC)

    /// Shadows are warm brown in light, never grey.
    static let shadowSoft = Color(light: 0x3C2814, lightOpacity: 0.08, dark: 0x000000, darkOpacity: 0.15)
    /// The tab on screen's wider, fainter shadow, under its contact shadow.
    static let shadowLift = Color(light: 0x3C2814, lightOpacity: 0.07, dark: 0x000000, darkOpacity: 0.20)
    static let shadowPageFar = Color(light: 0x3C2814, lightOpacity: 0.09, dark: 0x000000, darkOpacity: 0.16)
    /// The peeking sidebar floats over the page, so it casts a deeper shadow.
    static let shadowPeek = Color(light: 0x3C2814, lightOpacity: 0.22, dark: 0x000000, darkOpacity: 0.45)
    /// Its glass edge: a hairline that defines the card, and a lit inner rim.
    static let peekEdgeLine = Color(light: 0x3C2814, lightOpacity: 0.14, dark: 0x000000, darkOpacity: 0.40)
    static let peekEdgeRim = Color(light: 0xFFFFFF, lightOpacity: 0.70, dark: 0xFFFFFF, darkOpacity: 0.16)
    /// The page behind a Lookout: a warm brown veil in light, deeper in dark.
    static let lookoutDim = Color(light: 0x3C2814, lightOpacity: 0.16, dark: 0x000000, darkOpacity: 0.35)
    /// The page behind the command bar: lighter than a Lookout's, since the
    /// bar is small and quick.
    static let commandDim = Color(light: 0x3C2814, lightOpacity: 0.22, dark: 0x000000, darkOpacity: 0.45)
    /// The page's own color inside the command bar's glass, so the glass
    /// keeps the system's light or dark whatever page is behind it (glass
    /// alone turns mid-grey over a bright page in dark mode, and the ink
    /// washes out).
    static let commandVeil = Color(light: 0xFBFAF8, lightOpacity: 0.62, dark: 0x2B2826, darkOpacity: 0.62)

    /// Basecamp tiles: frosted pebbles that sit a little lighter than the frame.
    static let tileFill = Color(light: 0xFFFFFF, lightOpacity: 0.42, dark: 0xF5F1EC, darkOpacity: 0.08)
    static let tileFillHover = Color(light: 0xFFFFFF, lightOpacity: 0.62, dark: 0xF5F1EC, darkOpacity: 0.13)
    /// With Reduce Transparency: the same tile, solid.
    static let tileSolid = Color(light: 0xF4F0EA, dark: 0x45413D)
    /// A tile's edge: lit along the top, a warm hairline around.
    static let tileRimTop = Color(light: 0xFFFFFF, lightOpacity: 0.85, dark: 0xFFFFFF, darkOpacity: 0.16)
    static let tileRimBottom = Color(light: 0xFFFFFF, lightOpacity: 0.15, dark: 0xFFFFFF, darkOpacity: 0.03)
    static let tileHairline = Color(light: 0x3C2814, lightOpacity: 0.07, dark: 0x000000, darkOpacity: 0.30)
    /// The crisp, frosty edge on Liquid Glass (the command bar).
    static let tileFrostEdge = Color(light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xC8DCE6, darkOpacity: 0.14)
    /// Tiles are a touch crisper than tab rows (10pt), so the glass reads as ice.
    static let tileRadius: CGFloat = 9

    /// Group cards: frosted like the tiles, a touch more see-through, and
    /// washed with the space's color.
    static let groupFill = Color(light: 0xFFFFFF, lightOpacity: 0.34, dark: 0xF5F1EC, darkOpacity: 0.05)
    static let groupTint = 0.10
    /// The frost where a tab dragged over the page would open: a little stronger, so it reads over a page.
    static let dropTint = 0.18
    /// The frost that forms across the address field while a page loads, in
    /// the space's color: a touch stronger than first tried (22%), so it shows.
    static let loadingTint = 0.32
    static let loadingTintDark = 0.28
    /// How far the glow at the loading frost's front edge reaches.
    static let glowRadius: CGFloat = 34

    /// A chosen Basecamp tile's colors: a main color for its wash and glow,
    /// and a ring of eight for its edge, clockwise from the right.
    struct TileAccent: Equatable {
        let main: Color
        let ring: [Color]

        init(_ color: Color) { main = color; ring = Array(repeating: color, count: 8) }
        init(main: Color, ring: [Color]) { self.main = main; self.ring = ring }
    }

    /// The site icon's own colors, calmed, each where it sits in the icon; a
    /// warm neutral for black, white, or grey icons; and the address's color
    /// while there's no icon (matching its letter mark).
    @MainActor static func tileAccent(site: String, icon: Data?) -> TileAccent {
        guard let icon else { return TileAccent(siteColor(for: site)) }
        guard let colors = siteIconColors(icon) else { return TileAccent(faint) }
        func color(_ rgb: IconColor.RGB) -> Color { Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue) }
        return TileAccent(main: color(colors.main), ring: colors.ring.map(color))
    }

    /// The chosen tile's ring is a little thicker than a hairline, so it reads
    /// as a lip of colored glass.
    static let tileRingWidth: CGFloat = 2.5
    /// The thin sheen along the ring's outer top edge.
    static let tileRingSheen = Color(light: 0xFFFFFF, lightOpacity: 0.65, dark: 0xFFFFFF, darkOpacity: 0.4)

    /// A calm color for a site's letter mark (and its tile, until the site's
    /// icon arrives). Picked steadily from the address so it never changes.
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

    /// Firn's space colors, by name, in the order new spaces take them.
    static let spaceColorNames = ["glacier", "sand", "sage", "heather", "ochre", "dusk", "clay", "lagoon"]

    /// How strongly the active space tints the frame: 16% light, 14% dark.
    static func frameTint(_ name: String) -> Color {
        Color(light: spaceHex(name), lightOpacity: 0.16, dark: spaceHex(name), darkOpacity: 0.14)
    }

    /// The space row's one color: the active space's color, deepened toward
    /// ink so it reads clearly on the tinted frame (half ink in light, a
    /// third in dark). The name and every dot use it, so the row never
    /// turns rainbow.
    static func spaceInk(_ name: String) -> Color {
        let hex = spaceHex(name)
        return Color(light: mix(hex, 0x241F1B, 0.5), dark: mix(hex, 0xF5F1EC, 0.35))
    }

    /// `a` blended toward `b` by `amount` (0 is all `a`, 1 is all `b`).
    private static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
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

    // MARK: First light

    /// The welcome's and the empty page's scene (docs/electron-welcome/styles.css,
    /// "First light"). Dark is "blue hour". The sky and sun are always Firn's
    /// own; only the snow takes the space's color.
    enum FirstLight {
        static let skyTop = Color(light: 0xF2F5F6, dark: 0x2E2F31)
        static let cool = Color(light: 0x9DB7C8, lightOpacity: 0.34, dark: 0x6E98B2, darkOpacity: 0.24)
        static let warm = Color(light: 0xF2C4A0, lightOpacity: 0.42, dark: 0xD69268, darkOpacity: 0.16)
        static let warm2 = Color(light: 0xECCEBA, lightOpacity: 0.28, dark: 0xA0786E, darkOpacity: 0.10)
        static let sun = Color(light: 0xF4C298, lightOpacity: 0.62, dark: 0xD68C60, darkOpacity: 0.32)
        static let sunMid = Color(light: 0xF4C298, lightOpacity: 0.22, dark: 0xD68C60, darkOpacity: 0.10)
        /// The flakes: Firn's small mark in Glacier, faint, in both looks.
        static let flake = NSColor(hex: 0x7F9CB0, opacity: 1)
        static let flakeOpacity: Float = 0.22
        /// The paper grain: multiplied in light, soft light in dark.
        static func grainOpacity(dark: Bool) -> Double { dark ? 0.5 : 0.13 }

        /// The five snow bands, back to front: Firn's glacier blues for a
        /// Glacier space, otherwise the space's color mixed into the page.
        static func snow(_ space: String) -> [Color] {
            let tint = spaceHex(space)
            if tint == spaceHex("glacier") {
                return zip([0xDCE5EB, 0xC3D3DE, 0xA6BFCF, 0x8AABC0, 0x6E98B2] as [UInt32],
                           [0x34353A, 0x3A3F46, 0x414B55, 0x495865, 0x536777] as [UInt32])
                    .map { Color(light: $0, dark: $1) }
            }
            return zip([0.20, 0.33, 0.47, 0.62, 0.78], [0.12, 0.20, 0.29, 0.38, 0.48])
                .map { Color(light: mix(0xFBFAF8, tint, $0), dark: mix(0x2B2826, tint, $1)) }
        }
    }

    /// The welcome's own colors over First light; its card is the command
    /// bar's glass (`CommandBarGlass`).
    enum Welcome {
        /// The little window drawings' bars.
        static let pill = Color(light: 0xFFFFFF, lightOpacity: 0.6, dark: 0xFFFAF5, darkOpacity: 0.12)
        /// The Hello screen's mark: glacier, lighter at the top.
        static let markTop = Color(light: 0x9DB7C8, dark: 0x9DB7C8)
        static let markBottom = Color(light: 0x6E98B2, dark: 0x6E98B2)
        static let markShadow = Color(light: 0x3C5A6E, lightOpacity: 0.22, dark: 0x000000, darkOpacity: 0.35)
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
    /// A group's name line is a tab row's height, so a folded group is a
    /// tab's size and the list keeps one rhythm; its frost sets it apart
    /// (David, 2026-10-22).
    static let groupHeaderHeight: CGFloat = rowHeight
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
    /// The small picture a tab becomes out over the page (16:10, as in Dia).
    static let liftedCard = CGSize(width: 168, height: 105)
    static let fieldRadius: CGFloat = 8
    static let smallRadius: CGFloat = 6

    // MARK: Type

    static let tabFont = Font.system(size: 13)
    static let labelFont = Font.system(size: 12)
    static let groupNameFont = Font.system(size: 12, weight: .medium)
    static let hintFont = Font.system(size: 11)
    /// Panel titles (sheets, and the Settings and History windows' titles):
    /// Fraunces at 22pt.
    @MainActor static let panelTitleFont = fraunces(22, weight: 360)

    /// Fraunces, for Firn's few brand moments: soft corners on, wonky letters
    /// off, optical size following the size, as in the brand. `weight` is
    /// the font's own axis (360, then 600 for emphasis; never more).
    @MainActor static func fraunces(_ size: CGFloat, weight: CGFloat) -> Font {
        guard let base = frauncesDescriptor else { return .system(size: size) }
        // SwiftUI can't set a font's axes, so Core Text does.
        func axis(_ tag: String) -> NSNumber {
            NSNumber(value: tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        }
        let axes: [NSNumber: CGFloat] = [
            axis("wght"): weight, axis("SOFT"): 100, axis("WONK"): 0, axis("opsz"): min(max(size, 9), 144),
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            base, [kCTFontVariationAttribute: axes] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    /// The bundled file (SIL Open Font License, Fonts/Fraunces-OFL.txt next
    /// to it), read once; never downloaded. Nil if it's missing, and the
    /// system font stands in.
    @MainActor private static let frauncesDescriptor: CTFontDescriptor? = {
        let fonts = ["ttf", "otf", "woff2"].flatMap { kind in
            [nil, "Fonts"].flatMap { Bundle.main.urls(forResourcesWithExtension: kind, subdirectory: $0) ?? [] }
        }
        guard let file = fonts.first(where: {
            let name = $0.lastPathComponent.lowercased()
            return name.hasPrefix("fraunces") && !name.contains("italic")
        }) else { return nil }
        return (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])?.first
    }()

    // MARK: Motion

    /// About 200ms, easing out (cubic-bezier(0.33, 1, 0.68, 1)). Nil with
    /// Reduce Motion, so things change in place.
    /// A group letting go of its tabs (Ungroup): a touch slower than a
    /// glide, since it's a deliberate moment; no bounce.
    static let thaw = Animation.smooth(duration: 0.3)

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

/// Something dragged that wants to stay where it belongs (a Basecamp tile,
/// a tab row, a group's card): free between its limits, and past them it
/// gives only a little, more slowly the further it's pulled.
enum Tug {
    /// The most it gives past a limit.
    static let give: CGFloat = 10

    static func held(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat,
                     give lowGive: CGFloat = give, _ highGive: CGFloat = give) -> CGFloat {
        let high = max(low, high)
        if value < low { return low - lowGive * tanh((low - value) / 50) }
        if value > high { return high + highGive * tanh((value - high) / 50) }
        return value
    }
}
