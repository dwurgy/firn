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
    /// the overview with that card's place empty; nil if no card is found
    /// there. The card stays as it is on screen: its place in the picture is
    /// painted over with the backdrop beside it, a thin strip from the
    /// screen's nearer edge stretched across. The picture is only ever seen
    /// blurred, behind a held page. Hidden for the drawing instead, the card
    /// was gone from the screen for one frame at the tap, and the drawing,
    /// which then had to wait for the screen, held the opening's first
    /// frames still (David's recording, 2026-11-22, in three opens of four).
    /// In a group's glass card the patch is the backdrop, not the glass.
    func take(without point: CGPoint? = nil) -> UIImage? {
        guard let view, view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        var hole: CGRect?
        if let point {
            guard let cell = Self.cell(at: point, in: view) else { return nil }
            // Its shadow too.
            hole = cell.convert(cell.bounds, to: view).insetBy(dx: -8, dy: -8).intersection(view.bounds)
        }
        let format = UIGraphicsImageRendererFormat(for: view.traitCollection)
        format.opaque = true
        let start = CACurrentMediaTime()
        var drew = false
        let bounds = view.bounds
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            drew = view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            guard drew, let hole, hole.width > 0, hole.height > 0,
                  let whole = context.cgContext.makeImage() else { return }
            let scale = CGFloat(whole.width) / bounds.width
            // Two points of backdrop at the nearer edge, clear of every card.
            let x = hole.midX < bounds.midX ? 1 : bounds.maxX - 3
            let strip = CGRect(x: x * scale, y: hole.minY * scale, width: 2 * scale, height: hole.height * scale)
            guard let patch = whole.cropping(to: strip.integral) else { return }
            UIImage(cgImage: patch, scale: scale, orientation: .up).draw(in: hole)
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
