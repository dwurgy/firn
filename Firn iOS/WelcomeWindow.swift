import FirnCore
import SwiftUI
import UIKit

/// The welcome's window, and its finish (docs/HISTORY.md, "Plan: Frost").
///
/// A window of its own, over Firn's: at the finish it goes behind Firn's,
/// which waits just below the screen, then rises over "Welcome in." as one
/// card. Only Firn's layer moves, and only as it's drawn (Core Animation),
/// so nothing in Firn lays out again while it rises.
@MainActor @Observable final class WelcomePresenter {
    /// Set as a new iPhone or iPad starts with no saved session, gone once
    /// the welcome is done: quitting halfway through it doesn't lose it.
    private static let pendingKey = "welcomePending"

    private(set) var finish: Finish?
    /// The welcome is coming: Firn's window shows only the sky until the
    /// finish, so it's never seen for a frame before the welcome is over it.
    private(set) var covers = false
    /// Grows each time the finish lands in the overview (`BrowserScreen`).
    private(set) var overviewRequests = 0
    /// How much of the screen's bottom Hello's words take.
    var footer: CGFloat = 256

    enum Finish {
        /// The step fades, the logo behind it, out of focus.
        case begun
        /// The logo comes into focus, "Welcome in."
        case clearing
        /// Firn rises over the words into its place.
        case rising
    }

    @ObservationIgnored private let store: BrowserStore
    @ObservationIgnored private var window: UIWindow?
    /// Firn's own window, once it's on screen.
    @ObservationIgnored private weak var firn: UIWindow?
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    init(store: BrowserStore, firstRun: Bool) {
        self.store = store
        if firstRun { UserDefaults.standard.set(true, forKey: Self.pendingKey) }
        covers = UserDefaults.standard.bool(forKey: Self.pendingKey)
    }

    /// Firn's window is on screen: the welcome goes over it, if it's waiting.
    func firnAppeared(in firn: UIWindow) {
        self.firn = firn
        if UserDefaults.standard.bool(forKey: Self.pendingKey) { show(fading: false) }
    }

    /// Settings › Show Welcome.
    func showAgain() { show(fading: true) }

    private func show(fading: Bool) {
        guard window == nil, let firn, let scene = firn.windowScene else { return }
        finish = nil
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: Welcome(presenter: self, store: store))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // VoiceOver stays in it.
        window.accessibilityViewIsModal = true
        window.makeKeyAndVisible()
        self.window = window
        if fading {
            window.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) { window.alpha = 1 }
        }
    }

    // MARK: The finish

    /// "Start Browsing" or "Skip setup": "Welcome in.", and Firn rises over
    /// the scene, at the Mac's speeds (`WindowModel.finishWelcome`). With
    /// Reduce Motion, the welcome simply fades (300ms).
    func finish(reduceMotion: Bool) {
        guard finish == nil, let window, let firn else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        covers = false
        window.endEditing(true)
        // Nothing open, but sites were picked: they're in the overview.
        if store.activeTab == nil, !store.basecampTabs.isEmpty { overviewRequests += 1 }
        guard !reduceMotion else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) { window.alpha = 0 } completion: { _ in
                MainActor.assumeIsolated { self.close() }
            }
            return
        }
        finish = .begun
        AccessibilityNotification.Announcement("Welcome in.").post()
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            finish = .clearing
            try? await Task.sleep(for: .milliseconds(1050))
            rise(firn, over: window)
        }
    }

    /// The rise: 1.7s with a soft start, from just below the screen at 86%
    /// of its size.
    private func rise(_ firn: UIWindow, over window: UIWindow) {
        finish = .rising
        firn.isUserInteractionEnabled = false
        let size = firn.bounds.size
        // On its side, an iPhone's inset is at the sides.
        let insets = firn.safeAreaInsets
        let radius = Hold.screenRadius(topInset: max(insets.top, insets.left, insets.right))
        let scale: CGFloat = 0.86
        // Past the edge by 30pt, so the card's shadow is too.
        let low = CATransform3DConcat(
            CATransform3DMakeScale(scale, scale, 1),
            CATransform3DMakeTranslation(0, size.height + 30 - size.height * (1 - scale) / 2, 0))

        // The card's shadow on the scene. Firn's own layer clips its
        // corners, so its shadow is a layer behind it, moving with it.
        let shadow = CALayer()
        shadow.frame = CGRect(origin: .zero, size: size)
        shadow.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: radius).cgPath
        shadow.shadowColor = UIColor(Theme.shadowPeek).resolvedColor(with: firn.traitCollection).withAlphaComponent(1).cgColor
        shadow.shadowOpacity = firn.traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.22
        shadow.shadowRadius = 24
        shadow.shadowOffset = CGSize(width: 0, height: 18)

        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = low
        move.toValue = CATransform3DIdentity
        move.duration = 1.7
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.15, 0.2, 1)
        move.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                shadow.removeFromSuperlayer()
                firn.layer.cornerRadius = 0
                firn.layer.masksToBounds = false
                firn.isUserInteractionEnabled = true
                self.close()
            }
        }
        window.layer.addSublayer(shadow)
        firn.layer.cornerRadius = radius
        firn.layer.cornerCurve = .continuous
        firn.layer.masksToBounds = true
        firn.layer.add(move, forKey: "welcomeRise")
        shadow.add(move, forKey: "welcomeRise")
        // Behind Firn's window, in the same frame Firn's goes below the screen.
        window.windowLevel = .normal - 1
        CATransaction.commit()
    }

    private func close() {
        finishTask = nil
        firn?.makeKey()
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let firn {
            UIAccessibility.post(notification: .screenChanged, argument: firn)
        }
    }
}

/// Tells the presenter once Firn's window is there.
struct WelcomeAnchor: UIViewRepresentable {
    let presenter: WelcomePresenter

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.presenter = presenter
        anchor.isUserInteractionEnabled = false
        anchor.isAccessibilityElement = false
        return anchor
    }

    func updateUIView(_ view: Anchor, context: Context) {}

    final class Anchor: UIView {
        weak var presenter: WelcomePresenter?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { presenter?.firnAppeared(in: window) }
        }
    }
}

extension EnvironmentValues {
    /// Shows the welcome again (Settings).
    @Entry var showWelcome: SheetAction? = nil
}
