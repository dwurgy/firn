import SwiftUI

/// Firn's own frost, the one glass on both the Mac and the iPhone (David,
/// 2026-11-09, "Firn's own frost, everywhere" in `docs/IOS-PLAN.md`): a
/// frosted fill, the space's color washed over it, a 1pt rim lit along the
/// top, a warm hairline, and a small soft shadow. Flat and icy, never
/// bubbly: no lens, no bend at the edges, no wobble when pressed. One fixed
/// level, never adapting to what's behind it.
///
/// It has no blur of its own. Where it sits on something already soft (the
/// Mac's sidebar, the iPhone overview's haze, iOS's edge blur under the
/// bars) that's enough; where it floats over sharp shapes, the caller puts
/// a blur under it.
///
/// With Reduce Transparency (`solid`): the solid tile color, tinted, with
/// its hairline.
struct FirnFrost<S: InsettableShape, Under: View>: View {
    let shape: S
    var fill: Color = Theme.tileFill
    /// The space's color, already at its strength (usually `groupTint`).
    var tint: Color = .clear
    var solid = false
    var shadow: Color = Theme.shadowSoft
    var shadowRadius: CGFloat = 1
    var shadowY: CGFloat = 0.5
    /// How far the hairline sits outside the rim (the Mac's tiles: 0.5).
    var hairlineOutset: CGFloat = 0
    /// Under the fill, and inside its shadow (the Mac's `LiftBacking`).
    @ViewBuilder var under: Under

    var body: some View {
        Group {
            if solid {
                shape.fill(Theme.tileSolid)
                    .overlay { shape.fill(tint) }
                    .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
            } else {
                shape.fill(fill)
                    .background { under }
                    .overlay { shape.fill(tint) }
                    .overlay {
                        shape.gradientBorder(
                            LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    }
                    .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5).padding(-hairlineOutset) }
                    .shadow(color: shadow, radius: shadowRadius, y: shadowY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension FirnFrost where Under == EmptyView {
    init(shape: S, fill: Color = Theme.tileFill, tint: Color = .clear, solid: Bool = false,
         shadow: Color = Theme.shadowSoft, shadowRadius: CGFloat = 1, shadowY: CGFloat = 0.5,
         hairlineOutset: CGFloat = 0) {
        self.init(shape: shape, fill: fill, tint: tint, solid: solid, shadow: shadow,
                  shadowRadius: shadowRadius, shadowY: shadowY, hairlineOutset: hairlineOutset,
                  under: { EmptyView() })
    }
}

extension InsettableShape {
    /// An outline colored by a gradient, drawn by the GPU. Firn's lit rims
    /// were `strokeBorder(LinearGradient(...))`, which iOS paints on the
    /// CPU, the shape's whole box, again whenever its size changes: on
    /// David's iPhone the main thread's largest single cost, every frame of
    /// a gesture (Instruments, 2026-11-13, `docs/IOS-PLAN.md`). The same
    /// gradient as its own layer, masked to the ring, looks the same.
    func gradientBorder<G: ShapeStyle & View>(_ gradient: G, lineWidth: CGFloat) -> some View {
        // Only light, never a touch: masking hides the gradient but not its
        // hit area, so it covered whatever it rimmed and swallowed every tap
        // on the hold menu's rows (2026-11-15).
        gradient.mask { strokeBorder(.black, lineWidth: lineWidth) }
            .allowsHitTesting(false)
    }

    /// A shape filled with a gradient, drawn by the GPU (see `gradientBorder`).
    func gradientFill<G: ShapeStyle & View>(_ gradient: G) -> some View {
        gradient.clipShape(self)
    }
}

/// A button on Firn's frost, pressed: the warm wash in its shape, never a
/// bounce or a bulge (Liquid Glass's `.interactive()` is the bubbly kind).
struct FrostPress<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay { shape.fill(Theme.press).opacity(configuration.isPressed ? 1 : 0).allowsHitTesting(false) }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The frost for a pill or button floating over a live page (the iPhone's
/// bars, and the Mac reader's Aa pill), neutral, never tinted by the space
/// (David, 2026-11-15).
///
/// On the iPhone, iOS's own glass made frosty: "Frosty, no tint" (David,
/// 2026-11-17, `docs/IOS-PLAN.md`, "Try-out: the bar in iOS's own glass"):
/// the system's thinnest blur in the bar's shape, so the page behind turns
/// to soft color, under regular Liquid Glass (the milkier one, never
/// `.clear`), which keeps its lit edge. Never `.interactive()`, the bubbly
/// press. On the Mac, Firn's own frost. Reduce Transparency: solid, both.
struct BarFrost<S: InsettableShape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        #if os(iOS)
        if reduceTransparency {
            firnFrost
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay { Color.clear.glassEffect(.regular, in: shape) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #else
        firnFrost
        #endif
    }

    private var firnFrost: some View {
        FirnFrost(shape: shape, fill: Theme.barFrost, solid: reduceTransparency) {
            shape.fill(.ultraThinMaterial)
        }
    }
}
