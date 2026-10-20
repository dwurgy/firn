import FirnCore
import SwiftUI

/// A space's icon: one of Firn's own line drawings, stroked in the space's
/// color. Vector paths, so it's crisp at any size and costs nothing to draw.
struct SpaceIconView: View {
    let icon: SpaceIcon
    let size: CGFloat
    let color: Color

    var body: some View {
        SpaceIconShape(icon: icon)
            // The drawings are on a 24pt grid with 2pt lines; thinner and
            // they'd fade at the row's 16pt.
            .stroke(color, style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The drawings, on a 24 × 24 grid, scaled to fit. Soft corners and round
/// ends, about 3pt of air on every side, nothing fussy enough to blur at 16pt.
struct SpaceIconShape: Shape {
    let icon: SpaceIcon

    func path(in rect: CGRect) -> Path {
        var p = Path()
        Self.draw(icon, into: &p)
        let scale = min(rect.width, rect.height) / 24
        return p.applying(
            CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
                .scaledBy(x: scale, y: scale)
        )
    }

    private static func draw(_ icon: SpaceIcon, into p: inout Path) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }

        switch icon {
        case .home:
            // A roof, the walls under it, and an arched door.
            p.move(to: pt(4, 11.5)); p.addLine(to: pt(12, 4.5)); p.addLine(to: pt(20, 11.5))
            p.move(to: pt(6.5, 9.8)); p.addLine(to: pt(6.5, 19.5)); p.addLine(to: pt(17.5, 19.5)); p.addLine(to: pt(17.5, 9.8))
            p.move(to: pt(10, 19.5)); p.addLine(to: pt(10, 16))
            p.addCurve(to: pt(14, 16), control1: pt(10, 13.3), control2: pt(14, 13.3))
            p.addLine(to: pt(14, 19.5))

        case .work:
            // A briefcase with its handle and a seam.
            p.addRoundedRect(in: CGRect(x: 4, y: 8, width: 16, height: 11.5), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: pt(9, 8)); p.addLine(to: pt(9, 6.3))
            p.addQuadCurve(to: pt(10.3, 5), control: pt(9, 5))
            p.addLine(to: pt(13.7, 5))
            p.addQuadCurve(to: pt(15, 6.3), control: pt(15, 5))
            p.addLine(to: pt(15, 8))
            p.move(to: pt(4, 13)); p.addLine(to: pt(20, 13))

        case .reading:
            // An open book.
            p.move(to: pt(12, 7.2))
            p.addQuadCurve(to: pt(4, 5.5), control: pt(8.5, 5))
            p.addLine(to: pt(4, 17.8))
            p.addQuadCurve(to: pt(12, 19.5), control: pt(8.5, 17.4))
            p.addQuadCurve(to: pt(20, 17.8), control: pt(15.5, 17.4))
            p.addLine(to: pt(20, 5.5))
            p.addQuadCurve(to: pt(12, 7.2), control: pt(15.5, 5))
            p.addLine(to: pt(12, 19.5))

        case .family:
            // A grown-up and a child, side by side.
            circle(8.5, 8, 2.7)
            p.move(to: pt(4, 19.5))
            p.addCurve(to: pt(8.5, 13.2), control1: pt(4, 15.6), control2: pt(6.2, 13.2))
            p.addCurve(to: pt(13, 19.5), control1: pt(10.8, 13.2), control2: pt(13, 15.6))
            circle(17.3, 11.6, 2)
            p.move(to: pt(14.8, 19.5))
            p.addCurve(to: pt(17.3, 15.6), control1: pt(14.8, 17.1), control2: pt(15.9, 15.6))
            p.addCurve(to: pt(19.8, 19.5), control1: pt(18.7, 15.6), control2: pt(19.8, 17.1))

        case .shopping:
            // A shopping bag, its handle dipping inside.
            p.move(to: pt(6, 8.5)); p.addLine(to: pt(18, 8.5))
            p.addLine(to: pt(19, 18.6))
            p.addQuadCurve(to: pt(17.8, 20), control: pt(19.1, 20))
            p.addLine(to: pt(6.2, 20))
            p.addQuadCurve(to: pt(5, 18.6), control: pt(4.9, 20))
            p.closeSubpath()
            p.move(to: pt(9, 11)); p.addLine(to: pt(9, 7.5))
            p.addCurve(to: pt(12, 4.5), control1: pt(9, 5.6), control2: pt(10.3, 4.5))
            p.addCurve(to: pt(15, 7.5), control1: pt(13.7, 4.5), control2: pt(15, 5.6))
            p.addLine(to: pt(15, 11))

        case .pets:
            // A paw: one soft pad and four toes.
            p.move(to: pt(12, 12.5))
            p.addCurve(to: pt(7, 17.4), control1: pt(9.6, 12.5), control2: pt(7, 15.3))
            p.addCurve(to: pt(9.6, 19.6), control1: pt(7, 19), control2: pt(8.3, 19.8))
            p.addCurve(to: pt(12, 19), control1: pt(10.7, 19.4), control2: pt(11.2, 19))
            p.addCurve(to: pt(14.4, 19.6), control1: pt(12.8, 19), control2: pt(13.3, 19.4))
            p.addCurve(to: pt(17, 17.4), control1: pt(15.7, 19.8), control2: pt(17, 19))
            p.addCurve(to: pt(12, 12.5), control1: pt(17, 15.3), control2: pt(14.4, 12.5))
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 3.6, y: 8.6, width: 3.2, height: 4))
            p.addEllipse(in: CGRect(x: 7.7, y: 4.2, width: 3.4, height: 4.3))
            p.addEllipse(in: CGRect(x: 12.9, y: 4.2, width: 3.4, height: 4.3))
            p.addEllipse(in: CGRect(x: 17.2, y: 8.6, width: 3.2, height: 4))

        case .coffee:
            // A mug, its handle, and two curls of steam.
            p.move(to: pt(5, 10.5)); p.addLine(to: pt(16, 10.5)); p.addLine(to: pt(16, 15.5))
            p.addCurve(to: pt(11.5, 20), control1: pt(16, 18), control2: pt(14, 20))
            p.addLine(to: pt(9.5, 20))
            p.addCurve(to: pt(5, 15.5), control1: pt(7, 20), control2: pt(5, 18))
            p.closeSubpath()
            p.move(to: pt(16, 12)); p.addLine(to: pt(17.3, 12))
            p.addCurve(to: pt(19.8, 14.4), control1: pt(18.7, 12), control2: pt(19.8, 13))
            p.addCurve(to: pt(17.3, 16.8), control1: pt(19.8, 15.8), control2: pt(18.7, 16.8))
            p.addLine(to: pt(15.7, 16.8))
            for x in [8.5, 12.5] as [CGFloat] {
                p.move(to: pt(x, 7.8))
                p.addQuadCurve(to: pt(x, 6.2), control: pt(x - 1, 7))
                p.addQuadCurve(to: pt(x, 4.6), control: pt(x + 1, 5.4))
            }

        case .music:
            // Two notes joined by a beam.
            p.addEllipse(in: CGRect(x: 4.5, y: 15.4, width: 4.5, height: 3.6))
            p.addEllipse(in: CGRect(x: 13.5, y: 13.4, width: 4.5, height: 3.6))
            p.move(to: pt(9, 17.2)); p.addLine(to: pt(9, 6.6)); p.addLine(to: pt(18, 4.6)); p.addLine(to: pt(18, 15.2))

        case .creative:
            // A pencil, tip down to the left.
            p.move(to: pt(4.5, 19.5)); p.addLine(to: pt(5.6, 15.4)); p.addLine(to: pt(15.4, 5.6))
            p.addCurve(to: pt(18.4, 5.6), control1: pt(16.2, 4.8), control2: pt(17.6, 4.8))
            p.addCurve(to: pt(18.4, 8.6), control1: pt(19.2, 6.4), control2: pt(19.2, 7.8))
            p.addLine(to: pt(8.6, 18.4))
            p.closeSubpath()
            p.move(to: pt(5.6, 15.4)); p.addLine(to: pt(8.6, 18.4))
            p.move(to: pt(13.4, 7.6)); p.addLine(to: pt(16.4, 10.6))

        case .photos:
            // A camera: body, the bump on top, and the lens.
            p.addRoundedRect(in: CGRect(x: 3.5, y: 7.5, width: 17, height: 12), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: pt(8.6, 7.5)); p.addLine(to: pt(9.8, 5.2)); p.addLine(to: pt(14.2, 5.2)); p.addLine(to: pt(15.4, 7.5))
            circle(12, 13.5, 3.2)

        case .travel:
            // A paper plane.
            p.move(to: pt(20, 4)); p.addLine(to: pt(3.5, 10.6)); p.addLine(to: pt(10, 13.8)); p.addLine(to: pt(13.2, 20.3))
            p.closeSubpath()
            p.move(to: pt(20, 4)); p.addLine(to: pt(10, 13.8))

        case .outdoors:
            // Two peaks, the tall one capped with snow.
            p.move(to: pt(2.5, 19.5)); p.addLine(to: pt(9, 6)); p.addLine(to: pt(13, 13))
            p.addLine(to: pt(15.8, 9.5)); p.addLine(to: pt(21.5, 19.5))
            p.closeSubpath()
            p.move(to: pt(7.1, 10)); p.addLine(to: pt(8.1, 11.2)); p.addLine(to: pt(9.2, 10.1))
            p.addLine(to: pt(10.2, 11.1)); p.addLine(to: pt(11.3, 10))

        case .leaf:
            // A leaf with its stem and vein in one line.
            p.move(to: pt(5.6, 18.4))
            p.addCurve(to: pt(19, 5), control1: pt(4.6, 11), control2: pt(9, 5))
            p.addCurve(to: pt(5.6, 18.4), control1: pt(19, 15), control2: pt(13, 19.4))
            p.closeSubpath()
            p.move(to: pt(4, 20)); p.addLine(to: pt(13.5, 10.5))

        case .forest:
            // A pine in two tiers on its trunk.
            p.move(to: pt(12, 3.5)); p.addLine(to: pt(7, 10)); p.addLine(to: pt(9.5, 10))
            p.addLine(to: pt(5.5, 15.5)); p.addLine(to: pt(18.5, 15.5)); p.addLine(to: pt(14.5, 10))
            p.addLine(to: pt(17, 10))
            p.closeSubpath()
            p.move(to: pt(12, 15.5)); p.addLine(to: pt(12, 20.5))

        case .sun:
            // A round sun and eight short rays.
            circle(12, 12, 4)
            for step in 0..<8 {
                let angle = CGFloat(step) * .pi / 4
                p.move(to: pt(12 + 6.8 * cos(angle), 12 + 6.8 * sin(angle)))
                p.addLine(to: pt(12 + 8.8 * cos(angle), 12 + 8.8 * sin(angle)))
            }

        case .star:
            // Five soft points (round joins take the sharpness off).
            for step in 0..<10 {
                let angle = -CGFloat.pi / 2 + CGFloat(step) * .pi / 5
                let radius: CGFloat = step.isMultiple(of: 2) ? 8.6 : 4
                let point = pt(12 + radius * cos(angle), 12.7 + radius * sin(angle))
                if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
        }
    }
}
