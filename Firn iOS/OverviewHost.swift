import SwiftUI
import UIKit
import os

/// The overview in a UIKit view of its own, so it can be drawn alone while
/// the page covers it (`OverviewCanvas`). SwiftUI can't draw one covered
/// part of a screen, and a picture of the whole screen is the page while
/// browsing, so a tab closing after the overview had changed behind the page
/// had no picture, and no focus pull (`FrozenOverview`; `docs/IOS-PLAN.md`,
/// step 1b). Tried first as a throwaway on David's iPhone (2026-11-19): the
/// picture came out whole, glass included, and landings glide as before.
///
/// What the overview reads from its surroundings doesn't cross into a
/// hosting controller by itself: `BrowserScreen` hands it on.
struct OverviewHost<Content: View>: UIViewControllerRepresentable {
    let canvas: OverviewCanvas
    @ViewBuilder var content: Content

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        // The overview stays where it is under the keyboard (typing from +).
        host.safeAreaRegions = .container
        canvas.view = host.view
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        host.rootView = content
    }
}

/// The overview's own view, to draw it alone, whatever is over it.
@MainActor final class OverviewCanvas {
    weak var view: UIView?
    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "overview picture")

    /// The overview as it's laid out now, at the screen's own scale. On the
    /// main thread; logs only how long it took.
    func take() -> UIImage? {
        guard let view, view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(for: view.traitCollection)
        format.opaque = true
        let start = CACurrentMediaTime()
        var drew = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            drew = view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let ms = (CACurrentMediaTime() - start) * 1000
        Self.log.notice("taken in \(ms, format: .fixed(precision: 1), privacy: .public)ms, drew \(drew, privacy: .public)")
        return drew ? image : nil
    }
}
