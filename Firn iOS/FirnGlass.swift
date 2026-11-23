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
    func firnGlassSurface<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(FirnGlassSurface(shape: shape, interactive: interactive))
    }
}

private struct FirnGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background { FirnFrost(shape: shape, fill: Theme.barFrost, solid: true) }
        } else {
            content
                .glassEffect(.regular.interactive(interactive), in: shape)
                // Under the glass (a background added after it), as the
                // glass buttons' blur is.
                .background { shape.fill(.ultraThinMaterial).allowsHitTesting(false) }
        }
    }
}

/// One glass that changes shape (David, 2026-11-18: one native glass per
/// button, never a second glass taking over mid-move): a rounded rectangle
/// at `frame`, in the view's own space, which may reach outside the view
/// (the page menu grows above the field, the small pill hangs below it).
/// Animatable, so iOS's glass glides from one frame to the next. An empty
/// frame means the view's own bounds, a capsule.
struct GlassFrame: InsettableShape {
    var frame: CGRect
    var radius: CGFloat
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(frame.minX, frame.minY),
                           AnimatablePair(AnimatablePair(frame.width, frame.height), radius))
        }
        set {
            frame = CGRect(x: newValue.first.first, y: newValue.first.second,
                           width: newValue.second.first.first, height: newValue.second.first.second)
            radius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let box = (frame.isEmpty ? rect : frame).insetBy(dx: inset, dy: inset)
        let corner = min(frame.isEmpty ? box.height / 2 : radius, box.height / 2, box.width / 2)
        return RoundedRectangle(cornerRadius: max(corner, 0), style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> GlassFrame {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// A `GlassFrame` that grows upward into a menu (the overview's space
/// name, David, 2026-11-22): at `open` 0 it is `base`; at 1, a rounded
/// rectangle `grown` in size, centered on the view, its bottom edge on the
/// view's. In between, each edge and the corners glide, so iOS's one glass
/// becomes the menu and comes back. Measured from the view's own bounds, so
/// it keeps up with a view whose width is gliding too.
struct GrowingGlass: InsettableShape {
    var base: GlassFrame
    var grown: CGSize
    var radius: CGFloat
    var open: CGFloat
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<GlassFrame.AnimatableData, CGFloat> {
        get { AnimatablePair(base.animatableData, open) }
        set {
            base.animatableData = newValue.first
            open = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let from = base.frame.isEmpty ? rect : base.frame
        let fromRadius = base.frame.isEmpty ? from.height / 2 : min(base.radius, from.height / 2)
        let to = CGRect(x: rect.midX - grown.width / 2, y: rect.maxY - grown.height,
                        width: grown.width, height: grown.height)
        let t = open
        let box = CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t,
                         width: from.width + (to.width - from.width) * t,
                         height: from.height + (to.height - from.height) * t)
            .insetBy(dx: inset, dy: inset)
        let corner = min(fromRadius + (radius - fromRadius) * t, box.height / 2, box.width / 2)
        return RoundedRectangle(cornerRadius: max(corner, 0), style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> GrowingGlass {
        var copy = self
        copy.inset += amount
        return copy
    }
}

extension View {
    /// Glass shapes inside are drawn together by iOS, and melt into one
    /// another when they come within `spacing`.
    func glassContainer(spacing: CGFloat) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}
