import SwiftUI

/// The iPhone's one glass (David, 2026-11-17, `docs/IOS-PLAN.md`, "Plan:
/// iOS's own glass buttons on the iPhone"): iOS's own Liquid Glass, made
/// frosty ("Frosty, no tint"): the system's thinnest blur in the glass's
/// shape, so the page behind turns to soft color, under regular glass (the
/// milkier one, never `.clear`), which keeps its lit edge. No tint of
/// Firn's. Liquid Glass has no blur setting of its own, so the blur is a
/// layer under it.
///
/// Two forms, one recipe:
/// - `FirnGlass`, a surface that isn't a button (the bars' fields, pills).
///   `interactive` gives it iOS's glass press, for a surface that is tapped.
/// - `.firnGlassButton(...)`, a `Button` drawn by iOS's glass button style,
///   so iOS knows it's a button: its press (the small glassy swell) and its
///   morphing come with it.
///
/// Reduce Transparency: Firn's solid frost and its warm-wash press, as the
/// Mac's (iOS's glass would turn solid by itself, but grey, not Firn's).
struct FirnGlass<S: InsettableShape>: View {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            FirnFrost(shape: shape, fill: Theme.barFrost, solid: true)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay { Color.clear.glassEffect(.regular.interactive(interactive), in: shape) }
                // An interactive glass has to feel the finger to swell; a
                // plain one is only light.
                .allowsHitTesting(interactive)
                .accessibilityHidden(true)
        }
    }
}

enum GlassButton {
    /// iOS's glass button style puts this much glass around its label on
    /// every side (measured in the Simulator, iOS 27).
    static let padding: CGFloat = 7

    /// The label's size for a glass button `whole` points across.
    static func label(_ whole: CGFloat) -> CGFloat { whole - 2 * padding }
}

/// The shapes a glass button comes in.
enum FirnGlassShape {
    case circle, capsule
}

extension View {
    /// A `Button` in iOS's own glass over the thinnest blur (`FirnGlass`).
    /// `tint` makes it the solid, colored kind (`.glassProminent`), as the
    /// overview's check in the space's vivid color; it needs no blur.
    func firnGlassButton(_ shape: FirnGlassShape = .circle, tint: Color? = nil) -> some View {
        modifier(FirnGlassButton(shape: shape, tint: tint))
    }
}

private struct FirnGlassButton: ViewModifier {
    let shape: FirnGlassShape
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        switch shape {
        case .circle: styled(content, Circle(), border: .circle)
        case .capsule: styled(content, Capsule(), border: .capsule)
        }
    }

    @ViewBuilder
    private func styled<S: InsettableShape>(_ content: Content, _ shape: S, border: ButtonBorderShape) -> some View {
        if reduceTransparency {
            content
                .buttonStyle(FrostPress(shape: shape))
                .background {
                    if let tint {
                        FirnFrost(shape: shape, fill: tint, solid: false)
                    } else {
                        FirnFrost(shape: shape, fill: Theme.barFrost, solid: true)
                    }
                }
        } else if let tint {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(border)
                .tint(tint)
        } else {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(border)
                .background { shape.fill(.ultraThinMaterial).allowsHitTesting(false) }
        }
    }
}

extension View {
    /// Glass that holds buttons of its own (Back and Forward's pill): iOS's
    /// glass drawn on this view itself, not beside it, so a finger on any
    /// button inside reaches the glass too and it takes iOS's press. Beside
    /// it, as `FirnGlass` in a background, the buttons took the touch and
    /// the glass never felt it (the overview's name pill, 2026-11-17).
    ///
    /// `enabled` false draws nothing (iOS's `.identity` glass), keeping the
    /// view the same, so a bar can hand its glass to a separate piece for a
    /// glide (the address field growing into its menu, the space name's
    /// pills sliding) and take it back at rest, with no state lost.
    func firnGlassSurface<S: InsettableShape>(_ shape: S, interactive: Bool = false, enabled: Bool = true) -> some View {
        modifier(FirnGlassSurface(shape: shape, interactive: interactive, enabled: enabled))
    }
}

private struct FirnGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                FirnFrost(shape: shape, fill: Theme.barFrost, solid: true).opacity(enabled ? 1 : 0)
            }
        } else {
            content
                .glassEffect(enabled ? .regular.interactive(interactive) : .identity, in: shape)
                // Under the glass (a background added after it), as the
                // glass buttons' blur is.
                .background {
                    shape.fill(.ultraThinMaterial).opacity(enabled ? 1 : 0).allowsHitTesting(false)
                }
        }
    }
}

extension View {
    /// Glass shapes inside are drawn together by iOS, and melt into one
    /// another when they come within `spacing`.
    func glassContainer(spacing: CGFloat) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}
