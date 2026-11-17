import SwiftUI

/// The bar in iOS's own glass, a TestFlight try-out (David, 2026-11-17;
/// `docs/IOS-PLAN.md`, "Try-out: the bar in iOS's own glass"): Liquid Glass
/// has no blur setting, so each recipe adds frost a different way. Kept on
/// the device only (`@AppStorage`); App Store builds keep Firn's frost.
enum BarGlass: String, CaseIterable {
    /// Firn's own frost, as before.
    case firn
    /// iOS's regular glass, the milkier one (never `.clear`, the bubbly one).
    case light
    /// Regular glass with a faint neutral tint.
    case medium
    /// The tinted glass over the system's thinnest blur in the same shape.
    case frosty

    static let key = "barGlass"

    var name: String {
        switch self {
        case .firn: "Firn"
        case .light: "Light"
        case .medium: "Medium"
        case .frosty: "Frosty"
        }
    }

    /// The tint: a faint white in light, a fainter warm white in dark,
    /// never the space's color (bars stay neutral, 2026-11-15).
    static let frostTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 245 / 255, green: 241 / 255, blue: 236 / 255, alpha: 0.16)
            : UIColor(white: 1, alpha: 0.30)
    })
}

/// A bar's glass in one of the native recipes (not `.firn`, which is
/// `FirnFrost`). Never `.interactive()`: its press is the bubbly kind.
struct NativeBarGlass<S: Shape>: View {
    let shape: S
    let glass: BarGlass

    var body: some View {
        switch glass {
        case .firn, .light:
            Color.clear.glassEffect(.regular, in: shape)
        case .medium:
            Color.clear.glassEffect(.regular.tint(BarGlass.frostTint), in: shape)
        case .frosty:
            // The blur first, so the glass above it sees soft color rather
            // than the page's shapes, and keeps its lit edge.
            shape.fill(.ultraThinMaterial)
                .overlay { Color.clear.glassEffect(.regular.tint(BarGlass.frostTint), in: shape) }
        }
    }
}
