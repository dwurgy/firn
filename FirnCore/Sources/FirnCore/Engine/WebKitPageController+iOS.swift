#if os(iOS)
import UIKit
import WebKit

/// The iOS twins of WebKitPageController's Mac-only parts (focus, the page's
/// picture, and print). The Mac versions stay in WebKitPageController.swift.
extension WebKitPageController {
    func focus() {
        webView.becomeFirstResponder()
    }

    func snapshot(width: CGFloat) async -> CGImage? {
        guard url != nil, loadError == nil else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        let image = try? await webView.takeSnapshot(configuration: configuration)
        return image?.cgImage
    }

    /// iOS prints from the share sheet, which comes in a later phase.
    func printPage() {}
}

/// The Mac's pinch zoom, as iOS sees it: 1 until the page is pinched past
/// where it started, so the password fill list's check reads the same.
extension WKWebView {
    var magnification: CGFloat {
        let start = scrollView.minimumZoomScale
        return start > 0 ? scrollView.zoomScale / start : 1
    }
}
#endif
