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
    ///
    /// `without`: a point on screen inside one of the grid's cards, to draw
    /// the overview with that card's place empty. The card is hidden only
    /// for this drawing, within one turn of the run loop, so the screen
    /// never shows it gone; nil if no card is found there.
    func take(without point: CGPoint? = nil) -> UIImage? {
        guard let view, view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        var hidden: UIView?
        if let point {
            guard let cell = Self.cell(at: point, in: view) else { return nil }
            hidden = cell
        }
        let alpha = hidden?.alpha ?? 1
        hidden?.alpha = 0
        defer { hidden?.alpha = alpha }
        let pending = hidden != nil
        let format = UIGraphicsImageRendererFormat(for: view.traitCollection)
        format.opaque = true
        let start = CACurrentMediaTime()
        var drew = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            drew = view.drawHierarchy(in: view.bounds, afterScreenUpdates: pending)
        }
        let ms = (CACurrentMediaTime() - start) * 1000
        Self.log.notice("taken in \(ms, format: .fixed(precision: 1), privacy: .public)ms, drew \(drew, privacy: .public)")
        return drew ? image : nil
    }

    /// The smallest collection view cell under a point on screen.
    private static func cell(at point: CGPoint, in root: UIView) -> UIView? {
        var best: UIView?
        var bestArea = CGFloat.infinity
        func search(_ view: UIView) {
            guard !view.isHidden else { return }
            if view is UICollectionViewCell {
                let frame = view.convert(view.bounds, to: nil)
                let area = frame.width * frame.height
                if frame.contains(point), area < bestArea {
                    best = view
                    bestArea = area
                }
            }
            for child in view.subviews { search(child) }
        }
        search(root)
        return best
    }
}
