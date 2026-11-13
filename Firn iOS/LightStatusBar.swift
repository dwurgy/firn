import SwiftUI
import UIKit

/// Turns the status bar's clock and icons light while `on`: over Sunrise's
/// blue-hour sky on the empty page (docs/SUNRISE-PLAN.md, step 4).
///
/// UIKit, not SwiftUI: SwiftUI has no way to set the status bar's style for
/// one screen, and the app's root view controller is SwiftUI's own. So while
/// it's on, a see-through window sits just above Firn's, holding nothing and
/// taking no touches (they go straight to Firn's window below); iOS takes the
/// status bar's style from it. Hidden again as soon as it's off.
struct LightStatusBar: UIViewRepresentable {
    let on: Bool

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ view: Anchor, context: Context) {
        view.on = on
    }

    final class Anchor: UIView {
        var on = false {
            didSet { if on != oldValue { update() } }
        }
        private var overlay: UIWindow?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            update()
        }

        private func update() {
            guard on, let scene = window?.windowScene else {
                overlay?.isHidden = true
                overlay = nil
                return
            }
            guard overlay == nil else { return }
            let overlay = PassThroughWindow(windowScene: scene)
            overlay.windowLevel = .normal + 1
            overlay.backgroundColor = .clear
            overlay.rootViewController = LightController()
            overlay.isHidden = false
            self.overlay = overlay
        }
    }

    /// A window that never takes a touch, so every one reaches Firn's.
    private final class PassThroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    private final class LightController: UIViewController {
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
        }
    }
}
