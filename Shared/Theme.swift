#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
    /// A group card's name: ink in dark; in light, a step softer than ink,
    /// since dark semibold on a pale card reads heavier (David, 2026-10-26).
    static let groupName = Color(light: 0x3B342E, dark: 0xF5F1EC)
    static let faint = Color(light: 0x9D9389, dark: 0x958D85)
    static let frost = Color(light: 0x82A8BE, dark: 0xA0C4D6, opacity: 0.45)
    /// The system accent (radio buttons, switches, focus): a slightly more
    /// saturated Glacier, from the asset catalog. Set on controls in sheets
    /// by hand, where macOS otherwise draws them in its own blue.
    #if os(macOS)
    static let accent = Color("AccentColor")
    #else
    /// The iPhone's catalog has no accent: the same values, here.
    static let accent = Color(light: 0x689ABB, dark: 0x5F98BB)
    #endif

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
    /// The page behind the command bar. Light is a warm near-black, not the
    /// brown wash, so white pages dim instead of turning tan (David,
    /// 2026-11-05: wanted a plain dim, as on iOS).
    static let commandDim = Color(light: 0x14100C, lightOpacity: 0.18, dark: 0x000000, darkOpacity: 0.45)
    /// iOS: the page or overview behind the address field while typing.
    /// Deeper than the Mac's, so the field and its results read clearly
    /// over a busy page (David, 2026-11-05: 16% was too light). Light is a
    /// warm near-black, not the brown wash: brown this deep turned white
    /// pages tan (David, 2026-11-05: wanted a plain dim).
    static let typingDim = Color(light: 0x14100C, lightOpacity: 0.35, dark: 0x000000, darkOpacity: 0.60)
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
    /// Under anything lifted on the iPhone (a tab, a group, a Basecamp
    /// tile), held or dragged: the solid tile, see-through, one level the
    /// whole way (David, 2026-11-09: 85% read too dark; 60%).
    static let heldRowBase = Color(light: 0xF4F0EA, lightOpacity: 0.6, dark: 0x45413D, darkOpacity: 0.6)
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
    /// The iPhone's group cards: the same recipe, stronger. The Mac's card
    /// sits on an even sidebar; the iPhone's sits on a haze that can be any
    /// mid tone of the page, where the Mac's numbers vanished (David's
    /// screenshots, 2026-11-08). Fixed levels, never adapting.
    static let groupCardFill = Color(light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xF5F1EC, darkOpacity: 0.11)
    static let groupCardShadow = Color(light: 0x3C2814, lightOpacity: 0.14, dark: 0x000000, darkOpacity: 0.35)
    /// The iPhone's slim tab rows: flat, like paper rather than frost (no
    /// blur, rim, or tint), a step lighter than the haze and the group
    /// cards so each row reads as something to tap (David, 2026-11-08).
    /// One recipe for both modes; only the wash differs (page white in
    /// light, warm white in dark). With a hairline and `shadowSoft`.
    static let slimRowFill = Color(light: 0xFBFAF8, lightOpacity: 0.72, dark: 0xF5F1EC, darkOpacity: 0.10)
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

    /// A new space's color, given `spaces`: the first no space has yet
    /// (or, with all taken, the next in turn). An import asks once per
    /// space, so each one it adds takes the next.
    static func freeSpaceColor(among spaces: [Space]) -> String {
        let taken = Set(spaces.map(\.color))
        return spaceColorNames.first { !taken.contains($0) } ?? spaceColorNames[spaces.count % spaceColorNames.count]
    }

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

    /// A livelier version of a space's color, for a filled button with a
    /// white symbol on it (the overview's check, in place of Safari's blue).
    /// More saturated than the space color, deepened just enough for the
    /// white to read (about 3.5:1 or better); the same in light and dark.
    static func spaceVivid(_ name: String) -> Color {
        let hex: UInt32 = switch name {
        case "sand": 0xAA8253
        case "sage": 0x64955F
        case "heather": 0xB16C8A
        case "ochre": 0xA1873D
        case "dusk": 0x7978B7
        case "clay": 0xB86846
        case "lagoon": 0x3C9994
        default: 0x5690B8
        }
        return Color(light: hex, dark: hex)
    }

    /// The tab overview's haze (iOS): the frame's color washed over the
    /// blurred picture of the page you came from, at one level for every
    /// page (like the Mac's window, it shows whatever is behind it).
    static let overviewWash = Color(light: 0xE9E3DA, lightOpacity: 0.6, dark: 0x3A3734, darkOpacity: 0.7)

    /// The fill of a tall card's title pill and X (iOS), over a real blur of
    /// the page's picture: the group cards' frost, stronger, so the title
    /// reads over any page, at one level for every page. Dark is a lighter
    /// warm gray than the frame, so the pill lifts off a dark page. Light
    /// always bleeds through, like a frosted cabin window (David,
    /// 2026-11-08): the blur erases shapes, so the fill can stay light;
    /// one level in both modes (David, 2026-11-08).
    static let cardPillVeil = Color(light: 0xE9E3DA, lightOpacity: 0.42, dark: 0x67635F, darkOpacity: 0.42)
    /// The iPhone's bars (the address bar, and the overview's bar): Firn's
    /// frost over iOS's thinnest material, which already blurs and veils,
    /// so the fill is far lighter than the pills': 42%, then 24%, still
    /// read milky next to Safari's bar (David's screenshots, 2026-11-09),
    /// so the material does the work and the frost is mostly its rim,
    /// hairline, and tint. The card pills' colors, one level for both modes.
    static let barFrost = Color(light: 0xE9E3DA, lightOpacity: 0.10, dark: 0x67635F, darkOpacity: 0.10)

    /// Firn's hold menu (iOS, docs/hold-menu-design.html): the dim over the
    /// overview while it's open, and the card's veil over a real blur of
    /// what's behind it (the pills' recipe: one fixed level, page white in
    /// light, the pills' warm gray in dark), its frosted edge, and its shadow.
    static let holdDim = Color(light: 0x14100C, lightOpacity: 0.18, dark: 0x000000, darkOpacity: 0.40)
    /// Thicker than the mockup's 44% (David, 2026-11-09: words got hard to
    /// read over a bright page), still one level for every screen.
    static let holdMenuVeil = Color(light: 0xFBFAF8, lightOpacity: 0.58, dark: 0x4A4642, darkOpacity: 0.62)
    static let holdMenuEdge = Color(light: 0xFFFFFF, lightOpacity: 0.60, dark: 0xC8DCE6, darkOpacity: 0.16)
    static let holdMenuShadow = Color(light: 0x3C2814, lightOpacity: 0.24, dark: 0x000000, darkOpacity: 0.50)
    static let holdMenuHairline = Color(light: 0x3C2814, lightOpacity: 0.07, dark: 0xF5F1EC, darkOpacity: 0.10)
    /// Muted terracotta for closing things, never alarm red (Danger).
    static let danger = Color(light: 0xB0503A, dark: 0xE3907A)
    /// The iPhone hold menu's Close rows: the same terracotta, a step deeper
    /// in light and brighter in dark, since the menu's see-through frost is
    /// mid-toned and `danger` read faint on it (David, 2026-11-09).
    static let menuDanger = Color(light: 0xA2442F, dark: 0xF2A68C)

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

    // MARK: Sunrise

    /// The welcome's and the empty page's scene, "Sunrise" (BRAND.md;
    /// docs/SUNRISE-PLAN.md). Dark is "blue hour". The sky and sun are
    /// always Firn's own; only the snow takes the space's color.
    enum Sunrise {
        /// The paper grain (`PaperGrain`, now only the iPhone overview's haze):
        /// multiplied in light, soft light in dark.
        static func grainOpacity(dark: Bool) -> Double { dark ? 0.5 : 0.13 }

        /// Sunrise's snow for a space in one look (docs/SUNRISE-PLAN.md, "The
        /// snow"; the site's `.lay` in firn-site's home.css). Glacier's snow
        /// with its hue turned a little toward the space's color (`SnowColors`).
        /// Plain colors, not light-and-dark pairs: the snow's `Canvas` draws
        /// once per look and picks its own.
        static func snow(_ space: String, dark: Bool) -> Snow {
            let layers = SnowColors.layers(space: space, spaceHex: spaceHex(space))
            let colors = dark ? layers.dark : layers.light
            return Snow(
                // Each layer's color pushed a little darker, so the texture's
                // white crystals bring it back up.
                bases: colors.enumerated().map { index, hex in
                    let amount = dark ? (index == 1 ? 0.16 : 0.10) : 0.20
                    return plain(mix(hex, dark ? 0x0B121B : 0x26394B, amount))
                },
                veils: colors.map { plain($0, dark ? 0.42 : 0) },
                deeps: dark
                    ? [0.20, 0.20, 0.24, 0.24, 0.24].map { plain(0x04080E, $0) }
                    : [0.13, 0.13, 0.16, 0.18, 0.20].map { plain(0x0E2032, $0) },
                lift: plain(0xFFFFFF, dark ? 0.07 : 0.2),
                wash: dark ? plain(0xF2AA78, 0.14) : plain(0xFFCEA0, 0.42),
                washHeight: dark ? 380 : 420,
                lip: dark ? plain(0xDCEAF6, 0.04) : plain(0xFFFFFF, 0.06),
                surfaceLip: dark ? plain(0xFFD6B4, 0.05) : plain(0xFFECD6, 0.1),
                rim: dark ? plain(0xD6E6F4, 0.38) : plain(0xFFFFFF, 0.85),
                surfaceRim: dark ? plain(0xFFDEC4, 0.5) : plain(0xFFF0DE, 0.95),
                shadow: dark ? plain(0x02060C, 0.06) : plain(0x102234, 0.032)
            )
        }

        /// The colors of the five snow layers, surface first, and their light.
        struct Snow {
            /// The layer's own color, a little darker, under the texture.
            let bases: [Color]
            /// The layer's color again over the texture, softening its grain
            /// (clear in light).
            let veils: [Color]
            /// The darkening at each layer's bottom.
            let deeps: [Color]
            /// The brightening at each layer's top.
            let lift: Color
            /// The warm light on the surface where the sun is, and how tall it reaches.
            let wash: Color
            let washHeight: CGFloat
            /// The soft bands just under each edge.
            let lip: Color
            let surfaceLip: Color
            /// The bright line along each edge (3pt, 4pt on the surface).
            let rim: Color
            let surfaceRim: Color
            /// Each edge's faint shadow on the layer above it.
            let shadow: Color
        }

        /// Sunrise's sky and sun in one look (docs/SUNRISE-PLAN.md, step 4;
        /// BRAND.md, "Blue-hour sky" and "The sun"). Plain colors: the sky's
        /// `Canvas` draws once per look and picks its own.
        static func sky(dark: Bool) -> Sky {
            // BRAND.md's blue hour, compressed for one screen: the warm stops
            // packed into the stretch just above the snow (light), or blue
            // hour all the way down (dark). Locations run from the window's
            // top (0) to the middle of the surface's ridge (1).
            let stops: [(UInt32, CGFloat)] = dark
                ? [(0x1A1F2D, 0), (0x212839, 0.22), (0x283043, 0.42), (0x2E3548, 0.60),
                   (0x34394B, 0.76), (0x373A48, 0.88), (0x383733, 1)]
                // Light: the site's lightened sky (2026-11-13), lighter at
                // the top and warm sooner; the warm stops are unchanged.
                : [(0x36415D, 0), (0x3E4966, 0.22), (0x4C5774, 0.42), (0x69728E, 0.60),
                   (0x9894A6, 0.76), (0xCDB8B4, 0.87), (0xEAD3C5, 1)]
            return Sky(
                stops: stops.map { Gradient.Stop(color: plain($0.0), location: $0.1) },
                apricot: dark ? plain(0xF2C4A0, 0.16) : plain(0xF2C4A0, 0.55),
                peach: dark ? plain(0xECCEBA, 0.12) : plain(0xECCEBA, 0.45),
                band: dark ? plain(0xF2BE96, 0.2) : plain(0xF0AA80, 0.5),
                halo: dark ? plain(0xF4B88C, 0.2) : plain(0xF4B88C, 0.55),
                glow: dark
                    ? [.init(color: plain(0xF2AA78, 0.3), location: 0), .init(color: plain(0xF2AA78, 0.1), location: 0.45),
                       .init(color: plain(0xF2AA78, 0), location: 1)]
                    : [.init(color: plain(0xF4A068, 0.7), location: 0), .init(color: plain(0xF6B488, 0.32), location: 0.4),
                       .init(color: plain(0xF6B488, 0), location: 1)],
                disc: [.init(color: plain(0xFFF0DA), location: 0), .init(color: plain(0xFAC690), location: 0.36),
                       .init(color: plain(0xF29A5C), location: 0.8), .init(color: plain(0xEA8A50), location: 1)],
                // Dark is blue hour: the sun never clears the snow.
                sunDrop: dark ? 78 : 0
            )
        }

        /// The sky's gradient, its two soft glows, and the sun's colors.
        struct Sky {
            let stops: [Gradient.Stop]
            /// The soft apricot and peach glows low on the sky.
            let apricot: Color
            let peach: Color
            /// The warm band on the sky above the snow, at its strongest.
            let band: Color
            /// The wide halo around the sun.
            let halo: Color
            /// The glow around the disc.
            let glow: [Gradient.Stop]
            /// The disc, lit a little above its middle.
            let disc: [Gradient.Stop]
            /// How much lower the disc and glow sit (at full size), so only a cap shows.
            let sunDrop: CGFloat
        }

        /// The flakes on the dark sky: Glow's glacier, faint, in both looks.
        #if os(macOS)
        static let flake = NSColor(hex: 0x9DB7C8, opacity: 1)
        #else
        static let flake = UIColor(hex: 0x9DB7C8, opacity: 1)
        #endif
        static let flakeOpacity: Float = 0.3

        /// One color, the same in both looks.
        private static func plain(_ hex: UInt32, _ opacity: Double = 1) -> Color {
            Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
        }
    }

    /// The welcome's own colors over Sunrise; its card is the command
    /// bar's glass (`CommandBarGlass`).
    enum Welcome {
        /// The little window drawings' bars.
        static let pill = Color(light: 0xFFFFFF, lightOpacity: 0.6, dark: 0xFFFAF5, darkOpacity: 0.12)
        /// The Hello screen's mark: the on-dark lockup's sand (BRAND.md,
        /// "Logo"), a touch lighter at the top.
        static let markTop = Color(light: 0xF5F1EC, dark: 0xF5F1EC)
        static let markBottom = Color(light: 0xE9E3DA, dark: 0xE9E3DA)
        static let markShadow = Color(light: 0x0B0F18, lightOpacity: 0.35, dark: 0x000000, darkOpacity: 0.35)

        // Words and buttons on the blue-hour sky: light in both looks
        // (BRAND.md, "Text on the dark sky" and "Buttons, links and focus").
        /// Headlines and words on the sky: 15:1 at the top, at least 4.5:1
        /// where the welcome's words sit. No muted grey: low on the
        /// light-mode sky it fails 4.5:1.
        static let skyInk = Color(light: 0xF5F1EC, dark: 0xF5F1EC)
        /// The main button on the sky: a light pill, dark words.
        static let skyButton = Color(light: 0xF5F1EC, dark: 0xF5F1EC)
        static let skyButtonText = Color(light: 0x2B2826, dark: 0x2B2826)
        /// The small pill on the sky (the site's eyebrow): a faint light
        /// fill, a slightly stronger edge, light words.
        static let skyPill = Color(light: 0xF5F1EC, lightOpacity: 0.1, dark: 0xF5F1EC, darkOpacity: 0.1)
        static let skyPillHover = Color(light: 0xF5F1EC, lightOpacity: 0.16, dark: 0xF5F1EC, darkOpacity: 0.16)
        static let skyPillPress = Color(light: 0xF5F1EC, lightOpacity: 0.22, dark: 0xF5F1EC, darkOpacity: 0.22)
        static let skyPillEdge = Color(light: 0xF5F1EC, lightOpacity: 0.18, dark: 0xF5F1EC, darkOpacity: 0.18)
        /// The keyboard focus ring on the sky (3pt).
        static let skyFocus = Color(light: 0xCFE3EF, dark: 0xCFE3EF)
        /// Paper under the steps' card, so its glass reads as paper over the
        /// dark sky instead of taking the navy in (the glass alone lets about
        /// 40% through).
        static let cardBase = Color(light: 0xFBFAF8, lightOpacity: 0.55, dark: 0x2B2826, darkOpacity: 0.5)
    }

    // MARK: Sizes

    /// The page floats this far inside the window frame.
    static let pageInset: CGFloat = 8

    /// On macOS 26 and later, the window's own corners less the inset, so the
    /// two nest (window corners differ between 26 and 27); 8pt until the
    /// window is measured. 12pt before 26.
    @MainActor static var pageCornerRadius: CGFloat {
        if #available(macOS 26, *) {
            guard let window = WindowCorners.shared.radius else { return 8 }
            return min(max(window - pageInset, 6), 24)
        } else {
            return 12
        }
    }

    static let rowHeight: CGFloat = 36
    /// The traffic lights' share of the sidebar's top row: the three lights
    /// (11pt in, 14pt each, 23pt apart) and 16pt of air before the next button.
    static let trafficLightsWidth: CGFloat = 85
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
    @MainActor static var peekCornerRadius: CGFloat { pageCornerRadius + pageInset - peekInset }
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
    /// A group card's name: the tabs' size, a step heavier, in ink, so it
    /// reads as the card's title (as Dia's does).
    static let groupHeaderFont = Font.system(size: 13, weight: .semibold)
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
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, opacity: darkOpacity) : NSColor(hex: light, opacity: lightOpacity)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return isDark ? UIColor(hex: dark, opacity: darkOpacity) : UIColor(hex: light, opacity: lightOpacity)
        })
        #endif
    }
}

#if os(macOS)
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
#else
private extension UIColor {
    convenience init(hex: UInt32, opacity: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
#endif

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

/// The window's corner radius, measured once it's set up (`WindowSetup`).
/// Observable, so the page's corners redraw when it arrives.
@MainActor @Observable
final class WindowCorners {
    static let shared = WindowCorners()
    var radius: CGFloat?
}
