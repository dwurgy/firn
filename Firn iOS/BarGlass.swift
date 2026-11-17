import SwiftUI

/// The bar in iOS's own glass, a TestFlight try-out (David, 2026-11-17;
/// `docs/IOS-PLAN.md`, "Try-out: the bar in iOS's own glass"): Liquid Glass
/// has no blur setting, so each recipe adds frost a different way. Kept on
/// the device only (`@AppStorage`); App Store builds keep Firn's frost.
enum BarGlass: String, CaseIterable {
    /// Firn's own frost, as before.
    case firn
    /// iOS's regular glass, the milkier one (never `.clear`, the bubbly one).
    case light
    /// Regular glass with a faint neutral tint.
    case medium
    /// Plain glass over a weaker blur with less milk: about half of the
    /// system's thinnest (`PartialBlur`). Between Medium and Frosty.
    case soft
    /// Frosty without Firn's tint.
    case frostyUntinted
    /// The tinted glass over the system's thinnest blur in the same shape.
    case frosty

    static let key = "barGlass"

    var name: String {
        switch self {
        case .firn: "Firn"
        case .light: "Light"
        case .medium: "Medium"
        case .soft: "Soft"
        case .frostyUntinted: "Frosty, no tint"
        case .frosty: "Frosty"
        }
    }

    /// The tint: a faint white in light, a fainter warm white in dark,
    /// never the space's color (bars stay neutral, 2026-11-15).
    static let frostTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 245 / 255, green: 241 / 255, blue: 236 / 255, alpha: 0.16)
            : UIColor(white: 1, alpha: 0.30)
    })
}

/// A bar's glass in one of the native recipes (not `.firn`, which is
/// `FirnFrost`). Never `.interactive()`: its press is the bubbly kind.
struct NativeBarGlass<S: Shape>: View {
    let shape: S
    let glass: BarGlass

    var body: some View {
        switch glass {
        case .firn, .light:
            Color.clear.glassEffect(.regular, in: shape)
        case .medium:
            Color.clear.glassEffect(.regular.tint(BarGlass.frostTint), in: shape)
        case .soft:
            PartialBlur(fraction: PartialBlur.softFraction)
                .clipShape(shape)
                .overlay { Color.clear.glassEffect(.regular, in: shape) }
        case .frostyUntinted:
            shape.fill(.ultraThinMaterial)
                .overlay { Color.clear.glassEffect(.regular, in: shape) }
        case .frosty:
            // The blur first, so the glass above it sees soft color rather
            // than the page's shapes, and keeps its lit edge.
            shape.fill(.ultraThinMaterial)
                .overlay { Color.clear.glassEffect(.regular.tint(BarGlass.frostTint), in: shape) }
        }
    }
}

/// A blur weaker than any of iOS's materials, with less of their milk: the
/// thinnest material's blur, stopped part of the way in. UIKit has no blur
/// radius setting; a paused animator from no effect to the material is the
/// public way to get one in between (it scales the blur and its tint
/// together). UIKit, since SwiftUI's materials come only in fixed strengths.
struct PartialBlur: UIViewRepresentable {
    let fraction: CGFloat
    /// Soft's strength: about half.
    static let softFraction: CGFloat = 0.5

    func makeUIView(context: Context) -> PartialBlurView { PartialBlurView(fraction: fraction) }
    func updateUIView(_ view: PartialBlurView, context: Context) { view.fraction = fraction }
}

final class PartialBlurView: UIVisualEffectView {
    var fraction: CGFloat { didSet { animator?.fractionComplete = fraction } }
    private var animator: UIViewPropertyAnimator?
    private var foreground: (any NSObjectProtocol)?

    init(fraction: CGFloat) {
        self.fraction = fraction
        super.init(effect: nil)
        isUserInteractionEnabled = false
        // iOS finishes paused animators when the app leaves the screen, so
        // the blur would come back at full strength: set it up again.
        foreground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.start() } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else if animator == nil { start() }
    }

    private func start() {
        stop()
        effect = nil
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = fraction
        self.animator = animator
    }

    /// A paused animator must be stopped before it's let go, or UIKit stops
    /// the app.
    private func stop() {
        guard let animator else { return }
        animator.stopAnimation(true)
        self.animator = nil
    }

    isolated deinit {
        animator?.stopAnimation(true)
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
    }
}
