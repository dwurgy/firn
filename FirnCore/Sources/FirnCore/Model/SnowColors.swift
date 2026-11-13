import Foundation

/// Sunrise's snow colors for each space (brand/BRAND.md, "Snow and ice";
/// docs/SUNRISE-PLAN.md, "Space colors").
///
/// Every space's snow is Glacier's snow with its hue turned a little in
/// OKLCH, keeping lightness and chroma, so it always reads as snow: the
/// site's rule is 30% of the way toward a cool space color (the short way
/// round) and 20% toward a warm one by way of rose (increasing hue, through
/// violet). The snow stays subtle (David, 2026-11-13): any later tweak only
/// makes the turns smaller, never larger.
public enum SnowColors {
    /// Glacier's five snow colors, surface first (`--s1` … `--s5`).
    public static let glacierLight: [UInt32] = [0xDCE5EB, 0xC3D3DE, 0xA6BFCF, 0x8AABC0, 0x6E98B2]
    public static let glacierDark: [UInt32] = [0x536777, 0x4A5B69, 0x42505C, 0x3B4350, 0x34353A]

    /// The five snow colors, surface first, for light and dark.
    public struct Layers: Equatable, Sendable {
        public let light: [UInt32]
        public let dark: [UInt32]
    }

    /// The space colors whose snow turns by way of rose; the rest turn the short way.
    static let warmSpaces: Set<String> = ["heather", "clay", "sand", "ochre"]

    /// A space's snow, from its color's name (`Space.color`) and hex.
    /// Glacier, and any color as hued as Glacier's snow, gets no turn.
    public static func layers(space: String, spaceHex: UInt32) -> Layers {
        let degrees = turn(spaceHex: spaceHex, byRose: warmSpaces.contains(space))
        return Layers(light: glacierLight.map { turned($0, by: degrees) },
                      dark: glacierDark.map { turned($0, by: degrees) })
    }

    /// The hue turn in degrees for a space's color.
    static func turn(spaceHex: UInt32, byRose: Bool) -> Double {
        let glacierHue = OKLCH(hex: glacierLight[0]).hue
        let hue = OKLCH(hex: spaceHex).hue
        if byRose {
            return 0.2 * positiveModulo(hue - glacierHue, 360)
        }
        return 0.3 * (positiveModulo(hue - glacierHue + 180, 360) - 180)
    }

    /// The color with its OKLCH hue turned, lightness and chroma kept.
    static func turned(_ hex: UInt32, by degrees: Double) -> UInt32 {
        guard degrees != 0 else { return hex }
        var color = OKLCH(hex: hex)
        color.hue = positiveModulo(color.hue + degrees, 360)
        return color.hex
    }

    private static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }
}

/// A color in OKLCH (Björn Ottosson's Oklab, in polar form), from and to
/// sRGB hex. The same math as `docs/sunrise-snow-colors.html`.
struct OKLCH: Equatable {
    var lightness: Double
    var chroma: Double
    /// Degrees, 0 ..< 360.
    var hue: Double

    init(hex: UInt32) {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(16), g = linear(8), b = linear(0)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        lightness = okL
        chroma = (okA * okA + okB * okB).squareRoot()
        let degrees = atan2(okB, okA) * 180 / .pi
        hue = degrees < 0 ? degrees + 360 : degrees
    }

    /// Back to sRGB hex, each channel clamped to the gamut.
    var hex: UInt32 {
        let a = chroma * cos(hue * .pi / 180), b = chroma * sin(hue * .pi / 180)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        return linear.reduce(UInt32(0)) { result, c in
            let gamma = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
            let byte = UInt32((min(1, max(0, gamma)) * 255).rounded())
            return result << 8 | byte
        }
    }
}
