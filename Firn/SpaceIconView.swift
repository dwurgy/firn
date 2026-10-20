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
            // 1.6 on the 24pt grid, as approved.
            .stroke(color, style: StrokeStyle(lineWidth: size * 1.6 / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The drawings, on a 24 × 24 grid, scaled to fit.
struct SpaceIconShape: Shape {
    let icon: SpaceIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
            .scaledBy(x: scale, y: scale)
        return Self.paths[icon, default: Path()].applying(transform)
    }

    /// Built once from the source below.
    private static let paths: [SpaceIcon: Path] = Dictionary(
        uniqueKeysWithValues: SpaceIcon.allCases.map { icon in
            var path = Path()
            for part in source(icon) {
                switch part {
                case let .path(data): path.addPath(Path(SVGPath.cgPath(data)))
                case let .circle(x, y, r): path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                case let .rect(x, y, w, h, r):
                    path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
                }
            }
            return (icon, path)
        }
    )

    private enum Part {
        case path(String)
        case circle(CGFloat, CGFloat, CGFloat)
        case rect(CGFloat, CGFloat, CGFloat, CGFloat, radius: CGFloat)
    }

    /// The set David approved on 2026-10-19, copied exactly from the SVG
    /// draft (viewBox 0 0 24 24, stroke 1.6, round caps and joins). Also
    /// kept as a picture in docs/space-icons.svg. Change these only with
    /// David's OK, and update that file to match.
    private static func source(_ icon: SpaceIcon) -> [Part] {
        switch icon {
        case .home:
            [.path("M4.5 10.5 12 4.5l7.5 6"), .path("M6.5 9v9.5a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1V9"), .path("M10 19.5V15h4v4.5")]
        case .work:
            [.rect(3.5, 7.5, 17, 12, radius: 2.5), .path("M9 7.5V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v1.5"), .path("M3.5 12.5h17")]
        case .reading:
            [.path("M12 6.8C10 5.2 7 5 4 5.6v12.8c3-.6 6-.4 8 1.2 2-1.6 5-1.8 8-1.2V5.6c-3-.6-6-.4-8 1.2Z"), .path("M12 6.8v12.8")]
        case .family:
            [.path("M12 19C5.5 14.8 3.8 11.6 3.8 9.1c0-2.4 1.9-4.2 4.1-4.2 1.7 0 3.2 1 4.1 2.5.9-1.5 2.4-2.5 4.1-2.5 2.2 0 4.1 1.8 4.1 4.2 0 2.5-1.7 5.7-8.2 9.9Z")]
        case .shopping:
            [.path("M5.5 8.5h13l-1 10.6a1.5 1.5 0 0 1-1.5 1.4H8a1.5 1.5 0 0 1-1.5-1.4Z"), .path("M9 10.5V7a3 3 0 0 1 6 0v3.5")]
        case .pets:
            [.circle(6.8, 11, 1.6), .circle(9.8, 7, 1.7), .circle(14.2, 7, 1.7), .circle(17.2, 11, 1.6),
             .path("M12 12.5c-2.4 0-4.8 2.8-4.8 4.9 0 1.5 1.2 2.2 2.5 1.9 1-.2 1.5-.6 2.3-.6s1.3.4 2.3.6c1.3.3 2.5-.4 2.5-1.9 0-2.1-2.4-4.9-4.8-4.9Z")]
        case .coffee:
            [.path("M5 9.5h11v5a4.5 4.5 0 0 1-4.5 4.5h-2A4.5 4.5 0 0 1 5 14.5Z"), .path("M16 11h1.2a2.2 2.2 0 0 1 0 4.4H16"),
             .path("M9 4c-.7.9.7 1.5 0 2.6M12.5 4c-.7.9.7 1.5 0 2.6")]
        case .music:
            [.path("M9 17.5V6.2l10-2v11.3"), .path("M9 9.2l10-2"), .circle(6.8, 17.5, 2.2), .circle(16.8, 15.5, 2.2)]
        case .creative:
            [.path("M12 3.8a8.2 8.2 0 0 0 0 16.4c1.1 0 1.8-.7 1.8-1.6 0-.6-.3-1-.6-1.4-.3-.4-.5-.8-.5-1.3 0-1 .8-1.8 1.8-1.8h2a4 4 0 0 0 4-4c0-3.5-3.8-6.3-8.5-6.3Z"),
             .circle(7.8, 11.2, 0.9), .circle(9.8, 7.6, 0.9), .circle(14.2, 7.4, 0.9)]
        case .photos:
            [.rect(3.5, 7, 17, 12.5, radius: 2.5), .path("M8.5 7l1.3-2.2h4.4L15.5 7"), .circle(12, 13.2, 3.3)]
        case .travel:
            [.path("M12 3.8c.8 0 1.4.8 1.4 1.9v3.9l6.4 3.9v1.7l-6.4-2v3.5l1.9 1.5v1.3l-3.3-.9-3.3.9v-1.3l1.9-1.5v-3.5l-6.4 2v-1.7l6.4-3.9V5.7c0-1.1.6-1.9 1.4-1.9Z")]
        case .outdoors:
            [.path("M3.5 19 9.5 9l3.4 5.3 2.3-3.1 5.3 7.8Z"), .path("m7.7 12 1.8 1.1 1.8-1.1")]
        case .leaf:
            [.path("M5.5 18.5C5.5 10.5 10 5.5 18.5 5.5c0 8.5-5 13-13 13Z"), .path("M5.5 18.5 13 11")]
        case .forest:
            [.path("M12 4 7.2 10.2h2.5L5.8 15.5h12.4l-3.9-5.3h2.5Z"), .path("M12 15.5v4.5")]
        case .sun:
            [.circle(12, 12, 3.6),
             .path("M12 4v1.6M12 18.4V20M4 12h1.6M18.4 12H20M6.3 6.3l1.1 1.1M16.6 16.6l1.1 1.1M6.3 17.7l1.1-1.1M16.6 7.4l1.1-1.1")]
        case .star:
            [.path("M12 4.5c.5 3.8 3.4 6.9 7.5 7.5-4.1.6-7 3.7-7.5 7.5-.5-3.8-3.4-6.9-7.5-7.5 4.1-.6 7-3.7 7.5-7.5Z")]
        }
    }
}
