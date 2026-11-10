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
                        shape.strokeBorder(
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
