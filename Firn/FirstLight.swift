import AppKit
import FirnCore
import SwiftUI

/// "First light": sunrise in a snowy cabin. Cool glacier sky high, warm
/// sunrise low, snow at the bottom, a faint paper grain, and a few drifting
/// flakes. Shown on the empty page now, and behind the welcome later.
/// Ported from the Electron app (docs/electron-welcome: FirstLight.tsx and
/// styles.css, "First light"), never redrawn from a description.
///
/// Performance (CLAUDE.md): gradients and shapes, no filters; the grain is a
/// static image; the sky draws once per size and look; the flakes drift in
/// Core Animation, so nothing in Firn redraws while the scene sits idle.
struct FirstLightScene: View {
    /// The space's color name (`Space.color`); only the snow takes it.
    let spaceColor: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                FirstLightSky()
                FirstLightFlakes(reduceMotion: reduceMotion)
                FirstLightSnow(colors: Theme.FirstLight.snow(spaceColor))
                    .frame(height: proxy.size.height * 0.25)
                    // A new space's snow fades in over about 400ms.
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: spaceColor)
                Image("FirstLightGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(Theme.FirstLight.grainOpacity(dark: colorScheme == .dark))
                    .blendMode(colorScheme == .dark ? .softLight : .multiply)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.page)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The sky and the sun: plain gradients, drawn once for each size and look.
private struct FirstLightSky: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Read so a change of look redraws the sky.
        let _ = colorScheme
        Canvas { context, size in
            typealias FL = Theme.FirstLight
            let (w, h) = (size.width, size.height)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(stops: [.init(color: FL.skyTop, location: 0), .init(color: Theme.page, location: 0.7)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // The three hazes, back to front (CSS lists them front to back).
            Self.glow(context, size, color: FL.warm2, center: CGPoint(x: 0.10 * w, y: 0.56 * h),
                      radii: CGSize(width: 0.44 * w, height: 0.50 * h), fade: 0.70)
            Self.glow(context, size, color: FL.warm, center: CGPoint(x: 0.86 * w, y: 0.62 * h),
                      radii: CGSize(width: 0.56 * w, height: 0.60 * h), fade: 0.68)
            Self.glow(context, size, color: FL.cool, center: CGPoint(x: 0.50 * w, y: -0.12 * h),
                      radii: CGSize(width: 0.70 * w, height: 0.58 * h), fade: 0.70)
            // The sun: a glow just behind the snowline, in a box 94% wide (at
            // most 1200pt) and 52% tall whose bottom sits 7.5% below the window.
            let sun = CGSize(width: min(1200, 0.94 * w), height: 0.52 * h)
            Self.ellipse(context, size, Gradient(stops: [
                .init(color: FL.sun, location: 0),
                .init(color: FL.sunMid, location: 0.5),
                .init(color: FL.sunMid.opacity(0), location: 1),
            ]), center: CGPoint(x: w / 2, y: 1.075 * h - sun.height / 2),
               radii: CGSize(width: sun.width / 2, height: sun.height / 2))
        }
    }

    /// A haze: `color` at the center, fading out `fade` of the way to the ellipse's edge.
    private static func glow(_ context: GraphicsContext, _ size: CGSize, color: Color,
                             center: CGPoint, radii: CGSize, fade: CGFloat) {
        ellipse(context, size, Gradient(stops: [
            .init(color: color, location: 0), .init(color: color.opacity(0), location: fade),
        ]), center: center, radii: radii)
    }

    /// An elliptical gradient, as CSS draws one: a unit circle stretched to `radii`.
    private static func ellipse(_ context: GraphicsContext, _ size: CGSize, _ gradient: Gradient,
                                center: CGPoint, radii: CGSize) {
        guard radii.width > 0, radii.height > 0 else { return }
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.scaleBy(x: radii.width, y: radii.height)
        let whole = CGRect(x: -center.x / radii.width, y: -center.y / radii.height,
                           width: size.width / radii.width, height: size.height / radii.height)
        layer.fill(Path(whole), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
    }
}

/// The five snow bands, stretched to the width.
private struct FirstLightSnow: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            ForEach(SnowBand.paths.indices, id: \.self) { index in
                SnowBand(index: index).fill(colors[index])
            }
        }
    }
}

private struct SnowBand: Shape {
    let index: Int

    /// Drawn in a 1280 × 200 box (FirstLight.tsx, `SNOW_BANDS`).
    static let paths: [Path] = [
        "M0,200 L0,26.6 C106.7,26.6 106.7,42.3 213.3,42.3 C320,42.3 320,33.3 426.7,33.3 C533.3,33.3 533.3,45.3 640,45.3 C746.7,45.3 746.7,46.4 853.3,46.4 C960,46.4 960,17.8 1066.7,17.8 C1173.3,17.8 1173.3,15.1 1280,15.1 L1280,200 Z",
        "M0,200 L0,76.2 C106.7,76.2 106.7,81.2 213.3,81.2 C320,81.2 320,97.9 426.7,97.9 C533.3,97.9 533.3,76.8 640,76.8 C746.7,76.8 746.7,78.8 853.3,78.8 C960,78.8 960,82.4 1066.7,82.4 C1173.3,82.4 1173.3,63.9 1280,63.9 L1280,200 Z",
        "M0,200 L0,121.8 C106.7,121.8 106.7,126.7 213.3,126.7 C320,126.7 320,128.9 426.7,128.9 C533.3,128.9 533.3,134.9 640,134.9 C746.7,134.9 746.7,126.6 853.3,126.6 C960,126.6 960,134.1 1066.7,134.1 C1173.3,134.1 1173.3,97.5 1280,97.5 L1280,200 Z",
        "M0,200 L0,152.8 C106.7,152.8 106.7,163 213.3,163 C320,163 320,168.5 426.7,168.5 C533.3,168.5 533.3,144.5 640,144.5 C746.7,144.5 746.7,161.5 853.3,161.5 C960,161.5 960,159.3 1066.7,159.3 C1173.3,159.3 1173.3,157.8 1280,157.8 L1280,200 Z",
        "M0,200 L0,191.7 C106.7,191.7 106.7,192.3 213.3,192.3 C320,192.3 320,190.8 426.7,190.8 C533.3,190.8 533.3,170.1 640,170.1 C746.7,170.1 746.7,183.2 853.3,183.2 C960,183.2 960,178.8 1066.7,178.8 C1173.3,178.8 1173.3,181.6 1280,181.6 L1280,200 Z",
    ].map { Path(SVGPath.cgPath($0)) }

    func path(in rect: CGRect) -> Path {
        Self.paths[index].applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 1280, y: rect.height / 200))
    }
}

/// Four small Firn marks drifting very slowly in the sky, away from where
/// words will sit. AppKit, not SwiftUI: the drift is a Core Animation
/// animation that the system runs on its own, so Firn doesn't redraw every
/// frame (a repeating SwiftUI animation would).
private struct FirstLightFlakes: NSViewRepresentable {
    let reduceMotion: Bool

    func makeNSView(context: Context) -> FlakesView { FlakesView() }

    func updateNSView(_ view: FlakesView, context: Context) {
        view.drifts = !reduceMotion
    }
}

private final class FlakesView: NSView {
    /// Where each sits, as parts of the window (left and top), its size in
    /// points, its turn in degrees, and how far into the drift it starts
    /// (FirstLight.tsx, `FLAKES`).
    private static let flakes: [(left: CGFloat, top: CGFloat, size: CGFloat, turn: CGFloat, start: Double)] = [
        (0.117, 0.175, 30, -12, 0),
        (0.859, 0.138, 22, 18, 6),
        (0.813, 0.413, 14, 0, 12),
        (0.172, 0.525, 14, 40, 3),
    ]
    /// 20 seconds down 6pt, then 20 back up.
    private static let drift: (seconds: Double, distance: CGFloat) = (20, 6)

    private var layers: [CALayer] = []

    var drifts = false {
        didSet { if drifts != oldValue { updateDrift() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for flake in Self.flakes {
            let layer = CALayer()
            layer.backgroundColor = Theme.FirstLight.flake.cgColor
            layer.opacity = Theme.FirstLight.flakeOpacity
            layer.mask = CALayer()
            layer.mask?.contentsGravity = .resizeAspect
            layer.bounds = CGRect(x: 0, y: 0, width: flake.size, height: flake.size)
            layer.mask?.frame = layer.bounds
            layer.transform = Self.turn(flake.turn)
            self.layer?.addSublayer(layer)
            layers.append(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, flake) in zip(layers, Self.flakes) {
            // The CSS places the flake's top-left corner; the layer is placed by its center.
            layer.position = CGPoint(x: flake.left * bounds.width + flake.size / 2,
                                     y: bounds.height - flake.top * bounds.height - flake.size / 2)
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        let mark = NSImage(named: "FirnMarkSmall")
        for layer in layers {
            layer.mask?.contentsScale = scale
            layer.mask?.contents = mark?.layerContents(forContentsScale: scale)
        }
    }

    /// A turn as CSS draws it (clockwise), in a layer whose y points up.
    private static func turn(_ degrees: CGFloat) -> CATransform3D {
        CATransform3DMakeRotation(-degrees * .pi / 180, 0, 0, 1)
    }

    private func updateDrift() {
        for (layer, flake) in zip(layers, Self.flakes) {
            layer.removeAnimation(forKey: "drift")
            guard drifts else { continue }
            let rest = Self.turn(flake.turn)
            let drift = CABasicAnimation(keyPath: "transform")
            drift.fromValue = rest
            // Down along the flake's own turned axis, as CSS's `rotate() translateY()`.
            drift.toValue = CATransform3DTranslate(rest, 0, -Self.drift.distance, 0)
            drift.duration = Self.drift.seconds
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.timeOffset = flake.start
            layer.add(drift, forKey: "drift")
        }
    }
}
