import SwiftUI

/// The overview's backdrop: a space wash (David, 2026-11-16), the iPhone's
/// match to the Mac's space-tinted frame. The frame color, deepening toward
/// the bottom with the space's color, a soft glow of that color low on the
/// screen, and the paper grain on top. It replaced a baked, blurred Sunrise:
/// Sunrise is for moments (the welcome and the empty page), and the space's
/// color barely showed through it.
///
/// Plain gradients drawn directly: nothing to bake or keep, and nothing
/// redraws while the overview sits still or scrolls. A space change
/// cross-fades over 600ms, easing out (at once with Reduce Motion). Opaque,
/// so Reduce Transparency keeps it as it is.
struct SpaceWash: View {
    let space: String

    /// Every number worth tuning, in one place. A stop's `mix` is how much
    /// of the space's color goes into its base (0.12 = 12% space color).
    enum Tuning {
        struct Stop {
            let location: CGFloat
            let base: UInt32
            let mix: CGFloat
        }

        static let light: [Stop] = [
            Stop(location: 0, base: 0xF2EDE6, mix: 0.12),
            Stop(location: 0.35, base: 0xE9E3DA, mix: 0.16),
            Stop(location: 0.70, base: 0xE9E3DA, mix: 0.26),
            Stop(location: 1, base: 0xE9E3DA, mix: 0.34),
        ]
        static let dark: [Stop] = [
            Stop(location: 0, base: 0x2A2724, mix: 0.10),
            Stop(location: 0.40, base: 0x2A2724, mix: 0.14),
            Stop(location: 0.75, base: 0x24211F, mix: 0.22),
            Stop(location: 1, base: 0x24211F, mix: 0.18),
        ]

        /// The glow's middle, as a share of the screen (0.6 across, 0.82 down).
        static let glowCenter = UnitPoint(x: 0.60, y: 0.82)
        /// The glow's ellipse, as a share of the screen's width and height.
        static let glowSize = CGSize(width: 0.75, height: 0.30)
        /// Light: the space's color with this share of white in it…
        static let lightGlowWhite: CGFloat = 0.45
        /// …at this opacity in the glow's middle, fading to clear at its edge.
        static let lightGlowOpacity: Double = 0.55
        /// Dark: the space's color itself at this opacity.
        static let darkGlowOpacity: Double = 0.20

        /// How long a space change cross-fades.
        static let fade: Double = 0.6
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The space faded from, held under the new one until it's fully in.
    @State private var under: String?
    /// The new space's wash, fading in from 0 to 1 over `Tuning.fade`.
    @State private var over: Double = 1

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // The old space's wash stays fully there while the new one fades
            // in over it, so the screen never dips (a plain opacity
            // transition let both go half see-through, or dropped the old one
            // at once, in the Simulator's recordings).
            if let under, under != space { wash(for: under) }
            wash(for: space)
                .opacity(over)
            Image("PaperGrain")
                .resizable(resizingMode: .tile)
                .opacity(Theme.Sunrise.grainOpacity(dark: dark))
                .blendMode(dark ? .softLight : .multiply)
        }
        .onChange(of: space) { old, new in
            guard !reduceMotion else { return under = new }
            under = old
            over = 0
            withAnimation(.easeOut(duration: Tuning.fade)) { over = 1 } completion: {
                if space == new { under = new }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wash(for space: String) -> some View {
        let tint = Theme.spaceHex(space)
        let stops = (dark ? Tuning.dark : Tuning.light).map {
            Gradient.Stop(color: Self.color(Self.mix($0.base, tint, $0.mix)), location: $0.location)
        }
        let glow = dark
            ? Self.color(tint).opacity(Tuning.darkGlowOpacity)
            : Self.color(Self.mix(tint, 0xFFFFFF, Tuning.lightGlowWhite)).opacity(Tuning.lightGlowOpacity)
        return ZStack {
            LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            GeometryReader { proxy in
                let size = proxy.size
                Rectangle()
                    .fill(EllipticalGradient(colors: [glow, glow.opacity(0)],
                                             center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                    .frame(width: size.width * Tuning.glowSize.width,
                           height: size.height * Tuning.glowSize.height)
                    .position(x: size.width * Tuning.glowCenter.x, y: size.height * Tuning.glowCenter.y)
            }
        }
    }

    /// `share` of `other` mixed into `base`, channel by channel in sRGB.
    private static func mix(_ base: UInt32, _ other: UInt32, _ share: CGFloat) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = CGFloat((base >> shift) & 0xFF), b = CGFloat((other >> shift) & 0xFF)
            return UInt32((a + (b - a) * share).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}
