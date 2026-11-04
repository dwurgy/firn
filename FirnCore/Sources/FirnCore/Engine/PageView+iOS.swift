#if os(iOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI on iPhone and iPad. The only place a view and
/// WKWebView meet on iOS; the Mac's is PageView.swift. UIKit wrapper because
/// SwiftUI's own WebView would be its own step (see CLAUDE.md, Engine).
public struct PageView: UIViewRepresentable {
    private let page: any PageController
    private let obscuredBottom: CGFloat

    /// `obscuredBottom` is how much of the page's bottom edge Firn's own bar
    /// covers, so WebKit can scroll the page's end clear of it and keep
    /// fixed footers above it.
    public init(page: any PageController, obscuredBottom: CGFloat = 0) {
        self.page = page
        self.obscuredBottom = obscuredBottom
    }

    public func makeUIView(context: Context) -> PageHolder {
        PageHolder(webView: webKitPage.webView)
    }

    public func updateUIView(_ holder: PageHolder, context: Context) {
        holder.obscuredBottom = max(obscuredBottom, 0)
    }

    private var webKitPage: WebKitPageController {
        guard let page = page as? WebKitPageController else {
            preconditionFailure("PageView shows pages made by BrowserEngine.makePage")
        }
        return page
    }
}

/// Holds a page's web view and passes on only real sizes, as on the Mac:
/// SwiftUI sizes a newly shown view at 0×0 first, and every size change
/// makes WebKit lay the whole page out again.
public final class PageHolder: UIView {
    let webView: WKWebView

    /// How much of the page's bottom edge Firn's bar covers.
    var obscuredBottom: CGFloat = 0 {
        didSet {
            guard obscuredBottom != oldValue else { return }
            updateObscuredInsets()
        }
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateObscuredInsets()
    }

    /// WebKit also hears about the status bar: it scrolls a new page to its
    /// own idea of the top, and without this that was under the status bar,
    /// while a page shown again or restored sat below it, where UIKit puts
    /// the top. The same page sat in two places (2026-11-03).
    private func updateObscuredInsets() {
        let insets = UIEdgeInsets(top: safeAreaInsets.top, left: 0, bottom: obscuredBottom, right: 0)
        if webView.obscuredContentInsets != insets { webView.obscuredContentInsets = insets }
    }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        if webView.frame.isEmpty { webView.frame = bounds }
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        webView.frame = bounds
    }
}
#endif
