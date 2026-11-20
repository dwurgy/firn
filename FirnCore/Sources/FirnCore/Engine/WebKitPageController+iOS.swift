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
        let webView = frontView
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        // The page below the status bar only: the strip behind the clock
        // (its covered top) stays out of the picture, as the glide expects.
        let bounds = webView.bounds
        let top = min(webView.obscuredContentInsets.top, bounds.height)
        if top > 0 {
            configuration.rect = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
        }
        let image = try? await webView.takeSnapshot(configuration: configuration)
        return image?.cgImage
    }

    /// The strip behind the status bar as the page shows it now, small: only
    /// its color is wanted (`PagePictures`).
    func topStripSnapshot() async -> CGImage? {
        guard url != nil, loadError == nil else { return nil }
        let webView = frontView
        let bounds = webView.bounds
        let top = min(webView.obscuredContentInsets.top, bounds.height)
        guard top > 0, bounds.width > 0 else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: 32)
        configuration.rect = CGRect(x: 0, y: 0, width: bounds.width, height: top)
        let image = try? await webView.takeSnapshot(configuration: configuration)
        return image?.cgImage
    }

    /// Where the header ends, measured in Firn's own world (the page never
    /// sees it): from the top of the screen down, each band that's pinned
    /// there (fixed or sticky) or is the site's banner (a header, a nav, or
    /// something named for one), at least half the screen wide, each
    /// starting where the last ended; or, if lower, where the page's
    /// `<main>` starts. What the page says is only a number:
    /// anything but one between 0 and a third of the shown page is 0.
    func headerDepth() async -> CGFloat {
        guard url != nil, loadError == nil, !isReading else { return 0 }
        let webView = frontView
        let shown = webView.bounds.height - min(webView.obscuredContentInsets.top, webView.bounds.height)
        guard shown > 0, webView.bounds.width > 0,
              let result = try? await webView.callAsyncJavaScript(
                  Self.headerScript, arguments: [:], in: nil, contentWorld: WebKitPageController.firnWorld),
              let numbers = result as? [Any], numbers.count == 2,
              let depth = (numbers[0] as? NSNumber)?.doubleValue, let width = (numbers[1] as? NSNumber)?.doubleValue,
              depth.isFinite, width.isFinite, depth > 0, width > 0 else { return 0 }
        // CSS pixels to points: the shown width is the screen's.
        let points = CGFloat(depth) * webView.bounds.width / CGFloat(width)
        return points <= shown / 3 ? points : 0
    }

    /// Returns [the header's bottom below the top of the screen, the
    /// screen's width], both in CSS pixels.
    private static let headerScript = """
        const view = window.visualViewport;
        if (!view || !document.body) return [0, 1];
        const width = view.width, height = view.height, top = view.offsetTop;
        const named = /(^|[-_ ])(header|masthead|banner|navbar|nav|topbar|top-bar)([-_ ]|$)/i;
        const isBand = (el, y) => {
            if (el === document.body || el === document.documentElement) return null;
            const box = el.getBoundingClientRect();
            if (box.top > y + 1 || box.bottom <= y + 1 || box.width < width * 0.5 || box.height > height / 3) return null;
            const style = getComputedStyle(el);
            const pinned = style.position === 'fixed' || style.position === 'sticky';
            const banner = el.matches('header, nav, [role=banner], [role=navigation]')
                || named.test(el.id || '') || named.test(typeof el.className === 'string' ? el.className : '');
            return pinned || banner ? box : null;
        };
        let bottom = top;
        for (let step = 0; step < 4; step++) {
            const y = bottom + 1;
            let found = null;
            for (const x of [width * 0.25, width * 0.5, width * 0.75]) {
                for (let el = document.elementFromPoint(x, y); el; el = el.parentElement) {
                    const box = isBand(el, y);
                    if (box && (!found || box.bottom > found.bottom)) found = box;
                }
            }
            if (!found || found.bottom <= bottom) break;
            bottom = found.bottom;
        }
        // Where the page's main part starts, if that's lower: a header
        // with no telling name (made-up class names) still ends there.
        const main = document.querySelector('main, [role=main]');
        if (main) {
            const box = main.getBoundingClientRect();
            if (box.top > bottom && box.top - top <= height / 3 && box.width >= width * 0.5) bottom = box.top;
        }
        return [bottom - top, width];
        """

    var topColor: CGColor? {
        let webView = frontView
        return (webView.themeColor ?? webView.underPageBackgroundColor)?.cgColor
    }

    /// iOS prints from the share sheet, which comes in a later phase.
    func printPage() {}

    /// Opens iOS's find bar on what's on screen: Reader's article while
    /// it's on, else the page. Nothing without a loaded page.
    func showFind() {
        guard url != nil, loadError == nil else { return }
        frontView.findInteraction?.presentFindNavigator(showingReplace: false)
        (frontView as? FirnWebView)?.findWatcher?.check()
    }

    func endFind() {
        guard isFinding else { return }
        frontView.findInteraction?.dismissFindNavigator()
        isFinding = false
    }
}

/// Tells the page when iOS's find bar opens and closes, so Firn's address
/// bar can step aside. iOS gives the bar's delegate to WebKit for good, so
/// this asks the bar itself whether it's showing each time the keyboard
/// (which carries it) comes, goes, or changes. What's typed in the bar
/// stays between iOS and WebKit; the page never sees it (CLAUDE.md, Security).
@MainActor
final class FindWatcher: NSObject {
    private weak var view: FirnWebView?

    init(view: FirnWebView) {
        self.view = view
        super.init()
        // Selector observers go away with the watcher on their own.
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification,
                     UIResponder.keyboardDidChangeFrameNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardMoved), name: name, object: nil)
        }
    }

    @objc private func keyboardMoved() { check() }

    /// Whether the bar shows now, passed on to the page if it changed.
    func check() {
        guard let view, let page = view.page, page.frontView === view else { return }
        let shown = view.findInteraction?.isFindNavigatorVisible ?? false
        if page.isFinding != shown { page.isFinding = shown }
    }
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
