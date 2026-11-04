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

/// Holds a page's web view. The page starts below the status bar (see
/// `PageFrame`) and runs down to the screen's bottom edge, and WebKit keeps
/// it clear of Firn's bar through the safe area, its own way: an ordinary
/// page scrolls its end clear, and a page that asks to fill the screen
/// (`viewport-fit=cover`) gets the room as `env(safe-area-inset-bottom)`
/// and makes it itself.
///
/// Not `obscuredContentInsets`: setting it switches WebKit's own safe-area
/// handling off, and a page that fills the screen, saved while Firn was in
/// the background, then came back 62pt down with its top row under the
/// status bar, out of reach (David's recording on firnbrowser.com,
/// 2026-11-04; the hunt is in `docs/IOS-PLAN.md`).
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

    /// The bar's room beyond what the screen already keeps safe at the
    /// bottom (the home indicator's); adding it changes the safe area
    /// again, so it's set only when the number changes. Measured against
    /// the screen here: SwiftUI reported the page's bottom edge at the home
    /// indicator rather than the screen's edge, so a long page's end rested
    /// 34pt behind the bar (phase 2, step 1's Known).
    private func updateBarInset() {
        guard let screen = view.window?.bounds else { return }
        let covered = barTop > 0 ? max(screen.maxY - barTop, 0) : 0
        let screenBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
        let extra = max(covered - screenBottom, 0)
        if additionalSafeAreaInsets.bottom != extra {
            additionalSafeAreaInsets.bottom = extra
        }
    }
}

/// Passes on only real sizes, as on the Mac: SwiftUI sizes a newly shown
/// view at 0×0 first, and every size change makes WebKit lay the whole page
/// out again.
///
/// The page starts just below the status bar, as in Safari before iOS 26,
/// and runs down under Firn's bar. Under the status bar, a page's bar
/// pinned to its top (apple.com's, firnbrowser.com's menu) slid up behind
/// the clock (David's recordings, 2026-11-04): WebKit pins such bars to the
/// top of the web view, not below the safe area. The strip behind the
/// status bar takes the page's own color (its theme color, else its
/// background), so the page still seems to reach the top.
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let top = min(safeAreaInsets.top, bounds.height)
        let frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
        // Only on a real change: each new frame lays the page out again.
        if webView.frame != frame { webView.frame = frame }
    }
}
#endif
