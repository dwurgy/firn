#if os(macOS)
import AppKit
#else
import UIKit
#endif
import FirnCore
import SwiftUI

/// "First light": sunrise in a snowy cabin. Cool glacier sky high, warm
/// sunrise low, Sunrise's textured snow at the bottom (docs/SUNRISE-PLAN.md,
/// step 3; the sky and sun follow in step 4), and a few drifting flakes. Shown on the empty page now, and behind the welcome later.
/// Ported from the Electron app (docs/electron-welcome: FirstLight.tsx and
/// styles.css, "First light"), never redrawn from a description.
///
/// Performance (CLAUDE.md): gradients and shapes, no filters; the snow's
/// texture is a static image; the sky and snow draw once per size and look; the flakes drift in
/// Core Animation, so nothing in Firn redraws while the scene sits idle.
struct FirstLightScene: View {
    /// The space's color name (`Space.color`); only the snow takes it.
    let spaceColor: String
    /// The whole scene, or one half of it: the welcome's finish lifts the
    /// real window between the sky (back) and the snow (front).
    var part = Part.whole
    /// The welcome's finish: the sun brightens and rises (the old sky only).
    var sunRises = false
    /// First light's pale sky and sun instead of Sunrise's: the Mac welcome
    /// only, whose dark words don't read on the blue-hour sky until it moves
    /// over (docs/SUNRISE-PLAN.md, step 5, which deletes this).
    var oldSky = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Part { case whole, back, front }

    /// How much of the scene's height the snow takes (a first guess, judged
    /// on screen: docs/SUNRISE-PLAN.md, question 1).
    static let snowShare: CGFloat = 0.3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if part != .front {
                    if oldSky {
                        FirstLightSky()
                        FirstLightSun(rises: sunRises)
                    } else {
                        SunriseSky()
                    }
                    // Never on small screens (BRAND.md).
                    if oldSky || proxy.size.width >= 600 {
                        FirstLightFlakes(reduceMotion: reduceMotion, onDarkSky: !oldSky)
                    }
                }
                if part != .back {
                    FirstLightSnow(spaceColor: spaceColor, reduceMotion: reduceMotion)
                        .frame(height: proxy.size.height * Self.snowShare)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(part == .front ? .clear : Theme.page)
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
    fileprivate static func ellipse(_ context: GraphicsContext, _ size: CGSize, _ gradient: Gradient,
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

/// Sunrise's sky and sun (docs/SUNRISE-PLAN.md, "What changes"; the site's
/// `.sunrise` in home.css), drawn once per size and look: the blue-hour
/// gradient, two soft apricot glows low on it, and the sun at 62% across,
/// in the lowest dip of the surface's edge, so the snow (drawn over it)
/// hides the disc's lower part. Always risen, as the site with Reduce Motion.
private struct SunriseSky: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let sky = Theme.FirstLight.sky(dark: colorScheme == .dark)
        Canvas { context, size in
            Self.draw(in: context, size: size, sky: sky)
        }
    }

    static func draw(in context: GraphicsContext, size: CGSize, sky: Theme.FirstLight.Sky) {
        let (w, h) = (size.width, size.height)
        guard w > 0, h > 0 else { return }
        // Where the snow's surface sits: its highest point, and the dip.
        let snowHeight = h * FirstLightScene.snowShare
        let ridge = SnowLayers.layout(width: w, height: snowHeight).edges[0]
        let top = h - snowHeight
        let dip = top + ridge
        // The sky ends mid-ridge; its last color carries on behind the snow.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: sky.stops), startPoint: .zero, endPoint: CGPoint(x: 0, y: top + 0.5 * ridge)))
        // The two soft glows on the sky, around the sun and to its left.
        FirstLightSky.ellipse(context, size, Gradient(colors: [sky.peach, sky.peach.opacity(0)]),
                              center: CGPoint(x: 0.2 * w, y: dip), radii: CGSize(width: 0.45 * w, height: 0.3 * top))
        FirstLightSky.ellipse(context, size, Gradient(colors: [sky.apricot, sky.apricot.opacity(0)]),
                              center: CGPoint(x: 0.62 * w, y: dip), radii: CGSize(width: 0.55 * w, height: 0.42 * top))

        // The sun, the site's sizes scaled down a little on smaller windows
        // (a first guess, judged on screen).
        let scale = w < 600 ? 0.5 : min(1, max(0.75, h / 900))
        let x = 0.62 * w
        let drop = sky.sunDrop * scale
        // The warm band: a 300pt strip on the sky, ending at the dip.
        let strip = 300 * scale
        context.fill(Path(CGRect(x: 0, y: dip - strip, width: w, height: strip)), with: .linearGradient(
            Gradient(colors: [sky.band.opacity(0), sky.band]),
            startPoint: CGPoint(x: 0, y: dip - strip), endPoint: CGPoint(x: 0, y: dip)))
        // The halo, wide and soft.
        FirstLightSky.ellipse(context, size, Gradient(colors: [sky.halo, sky.halo.opacity(0)]),
                              center: CGPoint(x: x, y: dip), radii: CGSize(width: 0.45 * w, height: 360 * scale))
        // The glow (550pt) and the disc (150pt): their bottoms 244pt and
        // 44pt below the dip, so they share a middle.
        let center = CGPoint(x: x, y: dip + 44 * scale - 75 * scale + drop)
        let glow = 275 * scale
        context.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: 2 * glow, height: 2 * glow)),
                     with: .radialGradient(Gradient(stops: sky.glow), center: center, startRadius: 0, endRadius: glow))
        let disc = 75 * scale
        // Lit at 50% 40%, out to the square's farthest corner, as CSS does.
        let lit = CGPoint(x: center.x, y: center.y - 0.2 * disc)
        context.fill(Path(ellipseIn: CGRect(x: center.x - disc, y: center.y - disc, width: 2 * disc, height: 2 * disc)),
                     with: .radialGradient(Gradient(stops: sky.disc), center: lit,
                                           startRadius: 0, endRadius: disc * (1 + 1.2 * 1.2).squareRoot()))
    }
}

/// The sun: a glow just behind the snowline, in a box 94% wide (at most
/// 1200pt) and 52% tall whose bottom sits 7.5% below the window. Its own
/// layer, so the welcome's finish can lift it (6% of the height, 12% larger,
/// over 1.2s) while a brighter sun fades in on top, transforms and opacity only.
private struct FirstLightSun: View {
    let rises: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Read so a change of look redraws the sun.
        let _ = colorScheme
        GeometryReader { proxy in
            let (w, h) = (proxy.size.width, proxy.size.height)
            let box = CGSize(width: min(1200, 0.94 * w), height: 0.52 * h)
            ZStack {
                Self.glow([.init(color: Theme.FirstLight.sun, location: 0),
                           .init(color: Theme.FirstLight.sunMid, location: 0.5),
                           .init(color: Theme.FirstLight.sunMid.opacity(0), location: 1)])
                Self.glow([.init(color: Theme.FirstLight.sun, location: 0),
                           .init(color: Theme.FirstLight.sun.opacity(0), location: 0.72)])
                    .opacity(rises ? 1 : 0)
            }
            .frame(width: box.width, height: box.height)
            .scaleEffect(rises ? 1.12 : 1)
            .offset(y: rises ? -0.06 * h : 0)
            .position(x: w / 2, y: 1.075 * h - box.height / 2)
            .animation(.easeOut(duration: 1.2), value: rises)
        }
    }

    /// An elliptical gradient filling the box, as CSS's `closest-side`.
    private static func glow(_ stops: [Gradient.Stop]) -> some View {
        Canvas { context, size in
            FirstLightSky.ellipse(context, size, Gradient(stops: stops),
                                  center: CGPoint(x: size.width / 2, y: size.height / 2),
                                  radii: CGSize(width: size.width / 2, height: size.height / 2))
        }
    }
}

/// Sunrise's snow: five layers, surface first, each cut along one of the
/// site's hand-cut edges (`SnowEdges`) and drawn as the site's `.lay` is.
/// A new space's snow fades in over the old one over 600ms, as the site's
/// does (instantly with Reduce Motion).
private struct FirstLightSnow: View {
    let spaceColor: String
    let reduceMotion: Bool
    /// The snow underneath, and the one fading in over it.
    @State private var shown: String
    @State private var incoming: String?

    init(spaceColor: String, reduceMotion: Bool) {
        self.spaceColor = spaceColor
        self.reduceMotion = reduceMotion
        _shown = State(initialValue: spaceColor)
    }

    var body: some View {
        ZStack {
            SnowLayers(space: shown)
            if let incoming {
                SnowLayers(space: incoming)
                    .id(incoming)
                    .transition(.opacity)
            }
        }
        .onChange(of: spaceColor) { _, new in
            var still = Transaction()
            still.disablesAnimations = true
            // A fade already running finishes at once.
            withTransaction(still) {
                if let incoming { shown = incoming }
                incoming = nil
            }
            guard new != shown else { return }
            if reduceMotion {
                withTransaction(still) { shown = new }
                return
            }
            withAnimation(.easeOut(duration: 0.6)) {
                incoming = new
            } completion: {
                guard incoming == new else { return }
                withTransaction(still) {
                    shown = new
                    incoming = nil
                }
            }
        }
    }
}

/// The five layers in one `Canvas`, drawn once per size, look, and space.
private struct SnowLayers: View {
    let space: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snow = Theme.FirstLight.snow(space, dark: colorScheme == .dark)
        let textures = [SnowTexture.fresh, SnowTexture.fresh, SnowTexture.packed,
                        SnowTexture.packed, SnowTexture.packed]
        Canvas { context, size in
            Self.draw(in: &context, size: size, snow: snow, textures: textures)
        }
    }

    /// Where each layer's edge starts and how tall its ridge is.
    struct Layout {
        var tops: [CGFloat]
        var edges: [CGFloat]
    }

    /// The site's edge heights (64pt, the surface 96pt; 36pt and 56pt under
    /// 600pt wide). Each layer shows a little more than its ridge and the
    /// deepest at least 0.6 of one; room left over is shared out evenly, and
    /// if there isn't enough, the ridges shrink with the layers.
    static func layout(width: CGFloat, height: CGFloat) -> Layout {
        var edges: [CGFloat] = width < 600 ? [56, 36, 36, 36, 36] : [96, 64, 64, 64, 64]
        var gaps = edges.prefix(4).map { $0 * 1.15 } + [edges[4] * 0.6]
        let needed = gaps.reduce(0, +)
        if needed > height {
            let shrink = height / needed
            edges = edges.map { $0 * shrink }
            gaps = gaps.map { $0 * shrink }
        } else {
            let extra = (height - needed) / CGFloat(gaps.count)
            gaps = gaps.map { $0 + extra }
        }
        var tops: [CGFloat] = [0]
        for gap in gaps.dropLast() { tops.append(tops.last! + gap) }
        return Layout(tops: tops, edges: edges)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize,
                     snow: Theme.FirstLight.Snow, textures: [Image?]) {
        let w = size.width, height = size.height
        guard w > 0, height > 0 else { return }
        let layout = layout(width: w, height: height)
        // How much the ridges shrank, for the surface's warm light.
        let shrink = layout.edges[1] / (w < 600 ? 36 : 64)

        func edge(_ index: Int, shift: CGFloat = 0) -> [CGPoint] {
            let top = layout.tops[index], rise = layout.edges[index]
            return SnowEdges.layers[index].map { CGPoint(x: $0.x * w, y: top + $0.y * rise + shift) }
        }
        /// The edge, closed straight down (or up) to `y`.
        func closed(_ points: [CGPoint], to y: CGFloat) -> Path {
            var path = Path()
            path.addLines(points)
            path.addLine(to: CGPoint(x: w, y: y))
            path.addLine(to: CGPoint(x: 0, y: y))
            path.closeSubpath()
            return path
        }

        for index in 0..<5 {
            let top = layout.tops[index], rise = layout.edges[index]
            let surface = index == 0
            // Down to the lowest point of the next layer's edge, which covers the rest.
            let bottom = index < 4 ? min(height, layout.tops[index + 1] + layout.edges[index + 1]) : height
            let tall = bottom - top
            let points = edge(index)
            let shape = closed(points, to: bottom)
            let box = Path(CGRect(x: 0, y: top, width: w, height: tall))

            var layer = context
            layer.clip(to: shape)
            // 1. The base color, 2. the texture (white, only its alpha
            // changing), 3. the veil.
            layer.fill(box, with: .color(snow.bases[index]))
            if let texture = textures[index] {
                let tile = layer.resolve(texture)
                if tile.size.width > 0 {
                    layer.fill(box, with: .tiledImage(texture, scale: 256 / tile.size.width))
                }
            }
            layer.fill(box, with: .color(snow.veils[index]))
            // 4. Deeper toward the bottom, 5. brighter at the top.
            layer.fill(box, with: .linearGradient(
                Gradient(colors: [snow.deeps[index].opacity(0), snow.deeps[index]]),
                startPoint: CGPoint(x: 0, y: top + 0.3 * tall), endPoint: CGPoint(x: 0, y: bottom)))
            layer.fill(box, with: .linearGradient(
                Gradient(colors: [snow.lift, snow.lift.opacity(0)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + min(280, tall))))
            // 6. The surface's warm light where the sun is.
            if surface {
                FirstLightSky.ellipse(layer, size, Gradient(colors: [snow.wash, snow.wash.opacity(0)]),
                                      center: CGPoint(x: 0.62 * w, y: top),
                                      radii: CGSize(width: 0.7 * w, height: snow.washHeight * shrink))
            }
            // 7. The crest: five soft lip bands under the edge, then the rim
            // (stroked twice as wide, half of it clipped away outside the snow).
            for depth in [0.05, 0.11, 0.19, 0.30, 0.45] as [CGFloat] {
                layer.fill(closed(edge(index, shift: depth * rise), to: top - 1),
                           with: .color(surface ? snow.surfaceLip : snow.lip))
            }
            var rim = Path()
            rim.addLines(points)
            layer.stroke(rim, with: .color(surface ? snow.surfaceRim : snow.rim),
                         style: StrokeStyle(lineWidth: surface ? 8 : 6, lineJoin: .round))
            // 8. The shadow the next edge casts on this layer: ten copies of
            // it, each a little higher and fainter in sum, so it fades smoothly.
            if index < 4 {
                let next = layout.edges[index + 1]
                for step in 1...10 {
                    let lift = 0.6 * pow(CGFloat(step) / 10, 1.6) * next
                    layer.fill(closed(edge(index + 1, shift: -lift), to: bottom), with: .color(snow.shadow))
                }
            }
        }
    }
}

/// The two snow textures (512px tiles shown at 256pt), bundled from
/// firn-site's (`Shared/Sunrise/`), loaded once.
@MainActor private enum SnowTexture {
    static let fresh = load("snow-fresh")
    static let packed = load("snow-packed")

    private static func load(_ name: String) -> Image? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "webp") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }
}

#if os(macOS)
/// Four small Firn marks drifting very slowly in the sky, away from where
/// words will sit. AppKit, not SwiftUI: the drift is a Core Animation
/// animation that the system runs on its own, so Firn doesn't redraw every
/// frame (a repeating SwiftUI animation would).
private struct FirstLightFlakes: NSViewRepresentable {
    let reduceMotion: Bool
    /// Sunrise's blue-hour sky: the flakes in a lighter glacier.
    var onDarkSky = false

    func makeNSView(context: Context) -> FlakesView { FlakesView() }

    func updateNSView(_ view: FlakesView, context: Context) {
        view.drifts = !reduceMotion
        view.onDarkSky = onDarkSky
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

    var onDarkSky = false {
        didSet {
            guard onDarkSky != oldValue else { return }
            typealias FL = Theme.FirstLight
            for layer in layers {
                layer.backgroundColor = (onDarkSky ? FL.skyFlake : FL.flake).cgColor
                layer.opacity = onDarkSky ? FL.skyFlakeOpacity : FL.flakeOpacity
            }
        }
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
#else
/// iOS's twin of the Mac's flakes, above: the same four marks and the same
/// Core Animation drift, placed in UIKit's coordinates (y points down).
private struct FirstLightFlakes: UIViewRepresentable {
    let reduceMotion: Bool
    /// Sunrise's blue-hour sky: the flakes in a lighter glacier.
    var onDarkSky = false

    func makeUIView(context: Context) -> FlakesView { FlakesView() }

    func updateUIView(_ view: FlakesView, context: Context) {
        view.drifts = !reduceMotion
        view.onDarkSky = onDarkSky
    }
}

private final class FlakesView: UIView {
    private static let flakes: [(left: CGFloat, top: CGFloat, size: CGFloat, turn: CGFloat, start: Double)] = [
        (0.117, 0.175, 30, -12, 0),
        (0.859, 0.138, 22, 18, 6),
        (0.813, 0.413, 14, 0, 12),
        (0.172, 0.525, 14, 40, 3),
    ]
    private static let drift: (seconds: Double, distance: CGFloat) = (20, 6)

    private var flakeLayers: [CALayer] = []

    var drifts = false {
        didSet { if drifts != oldValue { updateDrift() } }
    }

    var onDarkSky = false {
        didSet {
            guard onDarkSky != oldValue else { return }
            typealias FL = Theme.FirstLight
            for layer in flakeLayers {
                layer.backgroundColor = (onDarkSky ? FL.skyFlake : FL.flake).cgColor
                layer.opacity = onDarkSky ? FL.skyFlakeOpacity : FL.flakeOpacity
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let mark = UIImage(named: "FirnMarkSmall")?.cgImage
        for flake in Self.flakes {
            let layer = CALayer()
            layer.backgroundColor = Theme.FirstLight.flake.cgColor
            layer.opacity = Theme.FirstLight.flakeOpacity
            layer.mask = CALayer()
            layer.mask?.contentsGravity = .resizeAspect
            layer.mask?.contents = mark
            layer.bounds = CGRect(x: 0, y: 0, width: flake.size, height: flake.size)
            layer.mask?.frame = layer.bounds
            layer.transform = Self.turn(flake.turn)
            self.layer.addSublayer(layer)
            flakeLayers.append(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, flake) in zip(flakeLayers, Self.flakes) {
            layer.position = CGPoint(x: flake.left * bounds.width + flake.size / 2,
                                     y: flake.top * bounds.height + flake.size / 2)
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let scale = window?.screen.scale ?? 3
        for layer in flakeLayers { layer.mask?.contentsScale = scale }
    }

    /// A turn as CSS draws it (clockwise); UIKit's y points down, as CSS's does.
    private static func turn(_ degrees: CGFloat) -> CATransform3D {
        CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1)
    }

    private func updateDrift() {
        for (layer, flake) in zip(flakeLayers, Self.flakes) {
            layer.removeAnimation(forKey: "drift")
            guard drifts else { continue }
            let rest = Self.turn(flake.turn)
            let drift = CABasicAnimation(keyPath: "transform")
            drift.fromValue = rest
            drift.toValue = CATransform3DTranslate(rest, 0, Self.drift.distance, 0)
            drift.duration = Self.drift.seconds
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.timeOffset = flake.start
            layer.add(drift, forKey: "drift")
        }
    }
}
#endif
