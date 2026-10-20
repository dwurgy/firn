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

    /// The set David approved on 2026-10-19 (viewBox 0 0 24 24, stroke 1.6,
    /// round caps and joins), with one pass to even out their sizes: the
    /// mountains, leaf, paw, and star made larger, the briefcase, camera,
    /// bag, and palette a touch smaller, the pine a little wider. Also
    /// kept as a picture in docs/space-icons.svg. Change these only with
    /// David's OK, and update that file to match.
    private static func source(_ icon: SpaceIcon) -> [Part] {
        switch icon {
        case .home:
            [.path("M4.5 10.5 12 4.5l7.5 6"), .path("M6.5 9v9.5a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1V9"), .path("M10 19.5V15h4v4.5")]
        case .work:
            [.rect(4, 7.5, 16, 12, radius: 2.5), .path("M9 7.5V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v1.5"), .path("M4 12.5h16")]
        case .reading:
            [.path("M12 6.8C10 5.2 7 5 4 5.6v12.8c3-.6 6-.4 8 1.2 2-1.6 5-1.8 8-1.2V5.6c-3-.6-6-.4-8 1.2Z"), .path("M12 6.8v12.8")]
        case .family:
            [.path("M12 19C5.5 14.8 3.8 11.6 3.8 9.1c0-2.4 1.9-4.2 4.1-4.2 1.7 0 3.2 1 4.1 2.5.9-1.5 2.4-2.5 4.1-2.5 2.2 0 4.1 1.8 4.1 4.2 0 2.5-1.7 5.7-8.2 9.9Z")]
        case .shopping:
            [.path("M5.5 8.5h13l-.95 10.1a1.5 1.5 0 0 1-1.5 1.4H7.95a1.5 1.5 0 0 1-1.5-1.4Z"), .path("M9 10.5v-3a3 3 0 0 1 6 0v3")]
        case .pets:
            [.circle(6.3, 10.6, 1.75), .circle(9.6, 6.2, 1.85), .circle(14.4, 6.2, 1.85), .circle(17.7, 10.6, 1.75),
             .path("M12 12.2c-2.64 0-5.28 3.08-5.28 5.39 0 1.65 1.32 2.42 2.75 2.09 1.1-.22 1.65-.66 2.53-.66s1.43.44 2.53.66c1.43.33 2.75-.44 2.75-2.09 0-2.31-2.64-5.39-5.28-5.39Z")]
        case .coffee:
            [.path("M5 9.5h11v5a4.5 4.5 0 0 1-4.5 4.5h-2A4.5 4.5 0 0 1 5 14.5Z"), .path("M16 11h1.2a2.2 2.2 0 0 1 0 4.4H16"),
             .path("M9 4c-.7.9.7 1.5 0 2.6M12.5 4c-.7.9.7 1.5 0 2.6")]
        case .music:
            [.path("M9 17.5V6.2l10-2v11.3"), .path("M9 9.2l10-2"), .circle(6.8, 17.5, 2.2), .circle(16.8, 15.5, 2.2)]
        case .creative:
            [.path("M12 4.3a7.7 7.7 0 0 0 0 15.4c1.03 0 1.69-.66 1.69-1.5 0-.56-.28-.94-.56-1.32-.28-.38-.47-.75-.47-1.22 0-.94.75-1.69 1.69-1.69h1.88a3.76 3.76 0 0 0 3.76-3.76c0-3.29-3.57-5.92-7.99-5.92Z"),
             .circle(8.05, 11.25, 0.85), .circle(9.95, 7.85, 0.85), .circle(14.05, 7.65, 0.85)]
        case .photos:
            [.rect(4, 7, 16, 12.5, radius: 2.5), .path("M8.5 7l1.3-2.2h4.4L15.5 7"), .circle(12, 13.2, 3.3)]
        case .travel:
            [.path("M12 3.8c.8 0 1.4.8 1.4 1.9v3.9l6.4 3.9v1.7l-6.4-2v3.5l1.9 1.5v1.3l-3.3-.9-3.3.9v-1.3l1.9-1.5v-3.5l-6.4 2v-1.7l6.4-3.9V5.7c0-1.1.6-1.9 1.4-1.9Z")]
        case .outdoors:
            [.path("M3.5 19 9.5 6l3.5 7.5 2.5-3.5 5 9Z"), .path("M7.7 10l1.8 1.2 1.8-1.2")]
        case .leaf:
            [.path("M4.8 19.2C4.8 10.4 9.8 4.8 19.2 4.8c0 9.4-5 14.4-14.4 14.4Z"), .path("M4.8 19.2 13.1 10.9")]
        case .forest:
            [.path("M12 4 7 10.3h2.6l-4.3 5.5h13.4l-4.3-5.5H17Z"), .path("M12 15.8V20")]
        case .sun:
            [.circle(12, 12, 3.6),
             .path("M12 4v1.6M12 18.4V20M4 12h1.6M18.4 12H20M6.3 6.3l1.1 1.1M16.6 16.6l1.1 1.1M6.3 17.7l1.1-1.1M16.6 7.4l1.1-1.1")]
        case .star:
            [.path("M12 4c.53 4.05 3.63 7.36 8 8-4.37.64-7.47 3.95-8 8-.53-4.05-3.63-7.36-8-8 4.37-.64 7.47-3.95 8-8Z")]
        }
    }
}
