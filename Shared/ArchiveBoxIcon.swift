import FirnCore
import SwiftUI

/// The box tidied tabs are kept in (the Mac's overflow button, the
/// iPhone's Tidied Away row): a plain archive box, its lid a band a little
/// wider than the box. Drawn in the
/// style and size of the space icons Firn once had (24pt grid, 1.6 stroke,
/// round caps and joins; docs/space-icons.svg); also
/// kept as docs/overflow-icon.svg. Change it only with David's OK, and
/// update that file to match. (The snow-drift lid it replaces read as a
/// toupee; David, 2026-10-21.)
///
/// While tidied tabs fall in, or brought-back ones rise out, the lid lifts
/// on its right corner and then lands softly, never overshooting: the
/// timing approved as "B" on 2026-10-21 (docs/overflow-lid-animation.html
/// still shows it with the old snow lid).
struct ArchiveBoxIcon: View {
    var size: CGFloat = 18
    /// Lifted while tabs go in or come out.
    var lidOpen = false
    @State private var lidAngle = 0.0

    private static let lift = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.22)
    /// Eases in so the lid lands softly and never overshoots.
    private static let land = Animation.timingCurve(0.45, 0, 0.25, 1, duration: 0.26)

    var body: some View {
        let style = StrokeStyle(lineWidth: size * 1.6 / 24, lineCap: .round, lineJoin: .round)
        ZStack {
            BoxShape().stroke(style: style)
            LidShape()
                .stroke(style: style)
                .rotationEffect(.degrees(lidAngle), anchor: LidShape.hinge)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: lidOpen) { _, open in
            withAnimation(open ? Self.lift : Self.land) { lidAngle = open ? 20 : 0 }
        }
    }
}

/// Fits drawing in the 24pt grid to `rect`, centered.
private func fitGrid(_ rect: CGRect) -> CGAffineTransform {
    let scale = min(rect.width, rect.height) / 24
    return CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        .scaledBy(x: scale, y: scale)
}

/// The box without its lid.
private struct BoxShape: Shape {
    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    /// Built once from the path data in docs/overflow-icon.svg (viewBox 0 0 24 24).
    private static let path: Path = {
        var path = Path()
        for data in [
            "M5.5 9.5v8a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-8",
            "M10 13.5h4",
        ] {
            path.addPath(Path(SVGPath.cgPath(data)))
        }
        return path
    }()
}

/// The lid.
private struct LidShape: Shape {
    /// The lid's bottom right corner, where it lifts from.
    static let hinge = UnitPoint(x: 20 / 24, y: 9.5 / 24)

    func path(in rect: CGRect) -> Path {
        Self.path.applying(fitGrid(rect))
    }

    /// Built once from the path data in docs/overflow-icon.svg (viewBox 0 0 24 24).
    private static let path = Path(SVGPath.cgPath("M5.5 4.5h13a1.5 1.5 0 0 1 1.5 1.5v3.5H4V6a1.5 1.5 0 0 1 1.5-1.5Z"))
}
