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
    static let frame = Color(light: 0xE9E3DA, dark: 0x28241F)
    /// The frame over the window's glass: mostly frame, a little desktop showing through.
    static let frameWash = Color(light: 0xE9E3DA, lightOpacity: 0.45, dark: 0x28241F, darkOpacity: 0.55)
    static let page = Color(light: 0xFBFAF8, dark: 0x1C1916)
    static let ink = Color(light: 0x241F1B, dark: 0xF5F1EC)
    static let muted = Color(light: 0x5E564E, dark: 0xD4CDC5)
    /// A group card's name: ink in dark; in light, a step softer than ink,
    /// since dark semibold on a pale card reads heavier (David, 2026-10-26).
    static let groupName = Color(light: 0x3B342E, dark: 0xF5F1EC)
    static let faint = Color(light: 0x9D9389, dark: 0x958D85)
    static let frost = Color(light: 0x82A8BE, dark: 0xA0C4D6, opacity: 0.45)
    /// The system accent (radio buttons, switches, focus, text selection): a
    /// deeper, more saturated Glacier, #458CBA, the same in light and dark
    /// (David, 2026-11-27: the device's mode picks it, not the page's, so a
    /// white page in dark mode needs it as strong), from the asset catalog. Set on controls in sheets
    /// by hand, where macOS otherwise draws them in its own blue.
    #if os(macOS)
    static let accent = Color("AccentColor")
    #else
    /// The iPhone's catalog has no accent: the same values, here.
    static let accent = Color(light: 0x458CBA, dark: 0x458CBA)
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
    static let liftBacking = Color(light: 0xE9E3DA, lightOpacity: 0.88, dark: 0x28241F, darkOpacity: 0.88)
    /// The other tabs' titles rest a step back, so the tab on screen leads.
    static let tabRest = Color(light: 0x5E564E, dark: 0xBDB5AC)

    /// Shadows are warm brown in light, never grey.
    static let shadowSoft = Color(light: 0x3C2814, lightOpacity: 0.08, dark: 0x000000, darkOpacity: 0.15)
    /// The tab on screen's wider, fainter shadow, under its contact shadow.
    static let shadowLift = Color(light: 0x3C2814, lightOpacity: 0.07, dark: 0x000000, darkOpacity: 0.20)
    /// Under each card in the iPhone's grid: soft and clearly there, a
    /// little below, as Safari's, so the grid has depth (docs/IOS-PLAN.md,
    /// the swipe's idea 4). 
    /// A wide halo under it read as far too much (David, 2026-11-18), and
    /// dark softened to match Safari's, barely there.
    static let gridCardShadow = Color(light: 0x3C2814, lightOpacity: 0.14, dark: 0x000000, darkOpacity: 0.22)
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
    static let commandVeil = Color(light: 0xFFFFFF, lightOpacity: 0.62, dark: 0x1C1C1E, darkOpacity: 0.62)

    /// Basecamp tiles: frosted pebbles that sit a little lighter than the frame.
    static let tileFill = Color(light: 0xFFFFFF, lightOpacity: 0.42, dark: 0xFFFFFF, darkOpacity: 0.08)
    static let tileFillHover = Color(light: 0xFFFFFF, lightOpacity: 0.62, dark: 0xFFFFFF, darkOpacity: 0.13)
    /// With Reduce Transparency: the same tile, solid. Neutral, not warm
    /// (David, 2026-11-15: cards read brown in dark).
    static let tileSolid = Color(light: 0xF5F5F5, dark: 0x2E2E30)
    /// A folded group's card as iOS carries it when an open group is moved
    /// by its name line (`GroupFolder.flat`): solid, in the grey its glass
    /// reads as over the overview. `tileSolid` was all but invisible there
    /// in dark (David's recording, 2026-11-24).
    static let folderCarried = Color(light: 0xF2F2F2, dark: 0x4A4A4C)
    /// A tile's edge: lit along the top, a warm hairline around.
    static let tileRimTop = Color(light: 0xFFFFFF, lightOpacity: 0.85, dark: 0xFFFFFF, darkOpacity: 0.16)
    static let tileRimBottom = Color(light: 0xFFFFFF, lightOpacity: 0.15, dark: 0xFFFFFF, darkOpacity: 0.03)
    static let tileHairline = Color(light: 0x000000, lightOpacity: 0.07, dark: 0x000000, darkOpacity: 0.30)
    /// The crisp, frosty edge on Liquid Glass (the command bar).
    static let tileFrostEdge = Color(light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xFFFFFF, darkOpacity: 0.14)
    /// Tiles are a touch crisper than tab rows (10pt), so the glass reads as ice.
    static let tileRadius: CGFloat = 9

    /// Group cards: frosted like the tiles, a touch more see-through, and
    /// washed with the space's color.
    static let groupFill = Color(light: 0xFFFFFF, lightOpacity: 0.34, dark: 0xFFFFFF, darkOpacity: 0.05)
    static let groupTint = 0.10
    /// The Mac's native glass on tiles and group cards, in light: a faint warm
    /// shade in the glass, so it sits nearer the frame instead of reading
    /// white (David, 2026-11-28: light stuck out beside dark). Dark keeps the
    /// plain glass.
    static let glassWash = Color(light: 0x463728, lightOpacity: 0.08, dark: 0x463728, darkOpacity: 0)
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
    /// third in dark). Its dot uses it; the name is ink (David, 2026-11-25).
    static func spaceInk(_ name: String) -> Color {
        let hex = spaceHex(name)
        return Color(light: mix(hex, 0x241F1B, 0.5), dark: mix(hex, 0xF5F1EC, 0.35))
    }

    /// A livelier version of a space's color, for a filled button with a
    /// white symbol on it (the overview's check, in place of Safari's blue).
    /// More saturated than the space color, deepened just enough for the
    /// white to read (about 3.5:1 or better); the same in light and dark.
    /// A hair calmer since (David, 2026-11-15: read too saturated): about a
    /// fifth less saturation at the same lightness, so the white reads the same.
    static func spaceVivid(_ name: String) -> Color {
        let hex = vividHex(name)
        return Color(light: hex, dark: hex)
    }

    private static func vividHex(_ name: String) -> UInt32 {
        switch name {
        case "sand": 0xA38460
        case "sage": 0x6C9368
        case "heather": 0xA87189
        case "ochre": 0x9D884B
        case "dusk": 0x7A79AD
        case "clay": 0xAC6E53
        case "lagoon": 0x4A9793
        default: 0x628FAE
        }
    }

    /// A space's color for a small symbol that's on (Reader's book while
    /// reading, the translate mark once tapped), livelier so it reads on the
    /// bar's glass (David, 2026-11-27). Light: the check's vivid color
    /// (about 3:1 on the pale glass). Dark: the same hue, as lively but
    /// lighter, since the vivid one sinks into the dark grey (about 3:1 there).
    static func spaceSymbol(_ name: String) -> Color {
        let dark: UInt32 = switch name {
        case "sand": 0xD3B592
        case "sage": 0xA1C79E
        case "heather": 0xD9AABF
        case "ochre": 0xDEC887
        case "dusk": 0xAFAEDB
        case "clay": 0xDFA890
        case "lagoon": 0x89DCD8
        default: 0x8BBADA
        }
        return Color(light: vividHex(name), dark: dark)
    }

    #if os(iOS)
    /// The space's color frosted over the iPhone's pill, and gathering over
    /// a card, as tabs are tidied away into it (`Tidying`): the color over
    /// a veil of the mode's own white or black.
    static func tidyFrost(_ name: String) -> Color {
        spaceColor(name).mix(with: Color(light: 0xFFFFFF, dark: 0x1E2023), by: 0.5).opacity(0.82)
    }
    static let tidyRim = Color(light: 0xFFFFFF, lightOpacity: 0.55, dark: 0xFFFFFF, darkOpacity: 0.2)
    #endif

    /// The iPhone's bars (the address bar, and the overview's bar): Firn's
    /// frost over iOS's thinnest material, which already blurs and veils,
    /// so the fill is far lighter than the pills': 42%, then 24%, still
    /// read milky next to Safari's bar (David's screenshots, 2026-11-09),
    /// so the material does the work and the frost is mostly its rim,
    /// hairline, and tint. In dark, the frame at 40%, so the bar sits as dark
    /// as the darker frame (David, 2026-11-15: the material alone read pale).
    static let barFrost = Color(light: 0xFFFFFF, lightOpacity: 0.10, dark: 0x1C1C1E, darkOpacity: 0.40)

    /// Menus, cards, and the bars are neutral, never warm or tinted by the
    /// space, so they sit beside Apple's own (David, 2026-11-15). The space's
    /// color stays on the overview's tint, the ring, the check, the loading
    /// frost, and the Mac's sidebar.
    /// A hairline in Firn's own menus (the bar's, the space's name).
    static let holdMenuHairline = Color(light: 0x000000, lightOpacity: 0.07, dark: 0xFFFFFF, darkOpacity: 0.10)
    /// Muted terracotta for closing things, never alarm red (Danger).
    static let danger = Color(light: 0xB0503A, dark: 0xE3907A)
    /// The iPhone hold menu's Close rows: the same terracotta, a step deeper
    /// in light and brighter in dark, since the menu's see-through frost is
    /// mid-toned and `danger` read faint on it (David, 2026-11-09).
    static let menuDanger = Color(light: 0xA2442F, dark: 0xF2A68C)
    /// The system's own destructive red, for a Close row in a menu that
    /// sits beside iOS's menus (the iPhone bar's menu), so they match
    /// (David, 2026-11-23). Terracotta stays for scam warnings.
    static let systemDestructive = Color.red

    /// `a` blended toward `b` by `amount` (0 is all `a`, 1 is all `b`).
    private static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// A space's color as 0xRRGGBB (Reader's accent takes it this way).
    static func spaceHex(_ name: String) -> UInt32 {
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

    // MARK: Frost

    /// Frost, Firn's look for the welcome and the "no tabs" screen: a frosted
    /// window on a snowy morning, blue hour in dark (docs/design/frost,
    /// BRAND.md; every value is the drawings').
    enum Frost {
        static let skyTop = Color(light: 0xD3DBDF, dark: 0x151A27)
        static let skyLow = Color(light: 0xE9ECEA, dark: 0x232B3F)
        /// The warm band along the bottom, from the bottom up. Light only.
        static let horizonLow = Color(light: 0xF2C4A0, lightOpacity: 0.20, dark: 0xF2C4A0, darkOpacity: 0)
        static let horizonMid = Color(light: 0xECCEBA, lightOpacity: 0.11, dark: 0xECCEBA, darkOpacity: 0)
        static let horizonClear = Color(light: 0xECCEBA, lightOpacity: 0, dark: 0xECCEBA, darkOpacity: 0)
        static let ink = Color(light: 0x241F1B, dark: 0xE9E3DA)
        static let muted = Color(light: 0x5E564E, dark: 0xB9B2AA)
        /// The small mark: its own Glacier by day, cream on blue hour.
        static let mark = Color(light: 0x6E98B2, dark: 0xE9E3DA)
        /// The other steps' dots.
        static let dot = Color(light: 0x241F1B, lightOpacity: 0.24, dark: 0xE9E3DA, darkOpacity: 0.28)
        static let field = Color(light: 0xFFFFFF, lightOpacity: 0.62, dark: 0x141926, darkOpacity: 0.5)
        static let fieldLine = Color(light: 0x241F1B, lightOpacity: 0.28, dark: 0xE9E3DA, darkOpacity: 0.32)

        // The pill before macOS 26: a hairline, a line outside it, and its shadow.
        static let rimLine = Color(light: 0xFFFFFF, lightOpacity: 0.35, dark: 0xE9E3DA, darkOpacity: 0.16)
        static let rimOuter = Color(light: 0x241F1B, lightOpacity: 0.09, dark: 0x000000, darkOpacity: 0.3)
        static let shadow = Color(light: 0x241F1B, lightOpacity: 0.16, dark: 0x000000, darkOpacity: 0.4)
        /// Glass before macOS 26, and solid with Reduce Transparency.
        static let glass = Color(light: 0xFFFFFF, lightOpacity: 0.5, dark: 0x2C354C, darkOpacity: 0.5)
        static let glassSolid = Color(light: 0xF6F7F6, dark: 0x2C354C)

        static let logoOpacity = 0.85
        /// The "no tabs" flake's, in the space's color.
        static func flakeOpacity(dark: Bool) -> Double { dark ? 0.5 : 0.62 }
    }

    /// The paper grain (`PaperGrain`) on the iPhone overview's haze:
    /// multiplied in light, soft light in dark.
    static func grainOpacity(dark: Bool) -> Double { dark ? 0.5 : 0.13 }

    /// The welcome's little window drawings.
    enum Welcome {
        static let pill = Color(light: 0xFFFFFF, lightOpacity: 0.6, dark: 0xFFFAF5, darkOpacity: 0.12)
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
    /// SF semibold at 22pt, as the iPhone's (David, 2026-11-13: Fraunces is
    /// no more; Gooper Deck is for brand moments only).
    static let panelTitleFont = Font.system(size: 22, weight: .semibold)

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
