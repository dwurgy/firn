#if os(iOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI on iPhone and iPad. The only place a view and
/// WKWebView meet on iOS; the Mac's is PageView.swift. UIKit wrapper because
/// SwiftUI's own WebView would be its own step (see CLAUDE.md, Engine). A
/// view controller rather than a plain view, because only a view controller
/// can add Firn's bar to the safe area (below).
public struct PageView: UIViewControllerRepresentable {
    private let page: any PageController
    private let barTop: CGFloat

    /// `barTop` is where Firn's own bar starts, from the screen's top (0
    /// for no bar), so WebKit can scroll the page's end clear of it and keep
    /// fixed footers above it.
    public init(page: any PageController, barTop: CGFloat = 0) {
        self.page = page
        self.barTop = barTop
    }

    public func makeUIViewController(context: Context) -> PageHolder {
        PageHolder(webView: webKitPage.webView)
    }

    public func updateUIViewController(_ holder: PageHolder, context: Context) {
        holder.barTop = barTop
    }

    private var webKitPage: WebKitPageController {
        guard let page = page as? WebKitPageController else {
            preconditionFailure("PageView shows pages made by BrowserEngine.makePage")
        }
        return page
    }
}

/// Holds a page's web view, which fills the whole screen, as Safari's does:
/// under the status bar (where iOS's soft blur shows once it's scrolled) and
/// under Firn's bar. `PageFrame` tells WebKit which edges are covered.
public final class PageHolder: UIViewController {
    let webView: WKWebView

    /// Where Firn's bar starts, from the screen's top; 0 for no bar.
    var barTop: CGFloat = 0 {
        didSet {
            guard barTop != oldValue else { return }
            updateBarInset()
        }
    }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func loadView() {
        view = PageFrame(webView: webView)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateBarInset()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBarInset()
    }

    /// The bar's room, from the screen's bottom edge up to the bar's top.
    /// Measured against the screen: SwiftUI reported the page's bottom edge
    /// at the home indicator rather than the screen's edge, so a long page's
    /// end rested 34pt behind the bar (phase 2, step 1's Known).
    private func updateBarInset() {
        guard let screen = view.window?.bounds, let frame = view as? PageFrame else { return }
        frame.barRoom = barTop > 0 ? max(screen.maxY - barTop, 0) : 0
    }
}

/// Passes on only real sizes, as on the Mac: SwiftUI sizes a newly shown
/// view at 0×0 first, and every size change makes WebKit lay the whole page
/// out again.
///
/// The page runs under the status bar and Firn's bar, as in Safari on iOS
/// 26, and WebKit is told both are covered in two places, which must agree:
/// `obscuredContentInsets` (so a bar a site pins to its top, like
/// apple.com's, sits below the clock, and fixed footers sit above Firn's
/// bar) and the scroll view's own `contentInset` (so the page's top and end
/// can be scrolled clear of them). With only the first, a new page opened
/// 62pt down but a restored one, or one pulled back to the top, stopped at 0
/// with its top row under the clock (firnbrowser.com's menu, 2026-11-04;
/// measured in `docs/IOS-PLAN.md`, step 3c.3). Under the clock the page
/// slides beneath iOS's own soft edge blur. Behind the page, the frame takes
/// the page's own color (its theme color, else its background) for the
/// moment before it draws.
private final class PageFrame: UIView {
    let webView: WKWebView
    private var colorWatchers: [NSKeyValueObservation] = []

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        if webView.frame.isEmpty { webView.frame = bounds }
        addSubview(webView)
        updateStripColor()
        // KVO hands changes over on the main thread here: WebKit sets both
        // colors from the main thread.
        colorWatchers = [
            webView.observe(\.themeColor) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateStripColor() }
            },
            webView.observe(\.underPageBackgroundColor) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateStripColor() }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateStripColor() {
        // The same color the page reports as `topColor`, for the glide.
        backgroundColor = webView.themeColor ?? webView.underPageBackgroundColor
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// Firn's bar's room from the screen's bottom edge; 0 for no bar.
    var barRoom: CGFloat = 0 {
        didSet { if barRoom != oldValue { setNeedsLayout() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Only on a real change: each new frame lays the page out again.
        if webView.frame != bounds { webView.frame = bounds }
        let top = min(safeAreaInsets.top, bounds.height)
        let covered = UIEdgeInsets(top: top, left: 0, bottom: barRoom, right: 0)
        if webView.obscuredContentInsets != covered {
            webView.obscuredContentInsets = covered
        }
        let scroller = webView.scrollView
        if scroller.contentInset != covered {
            scroller.contentInset = covered
            scroller.verticalScrollIndicatorInsets = covered
        }
        scroller.topEdgeEffect.style = .soft
    }
}
#endif
