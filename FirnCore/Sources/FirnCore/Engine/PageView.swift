#if os(macOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI. The only place a view and WKWebView meet.
/// AppKit wrapper because SwiftUI's own WebView needs macOS 26.
public struct PageView: NSViewRepresentable {
    private let page: any PageController
    private let cornerRadius: CGFloat

    public init(page: any PageController, cornerRadius: CGFloat) {
        self.page = page
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> PageHolder {
        let webView = webKitPage.webView
        webView.wantsLayer = true
        webView.layer?.masksToBounds = true
        webView.layer?.cornerCurve = .continuous
        webView.layer?.cornerRadius = cornerRadius
        return PageHolder(webView: webView)
    }

    public func updateNSView(_ holder: PageHolder, context: Context) {
        holder.webView.layer?.cornerRadius = cornerRadius
    }

    private var webKitPage: WebKitPageController {
        guard let page = page as? WebKitPageController else {
            preconditionFailure("PageView shows pages made by BrowserEngine.makePage")
        }
        return page
    }
}
/// Holds a page's web view and passes on only real sizes. SwiftUI sizes a
/// newly shown view at 0×0 before its real size, and each size change makes
/// WebKit lay the whole page out again: on a long article (Wikipedia) that
/// took long enough to freeze the window for a third of a second on every
/// tab switch. With the holder, the page keeps its size while off screen.
public final class PageHolder: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        if webView.frame.isEmpty { webView.frame = bounds }
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        webView.frame = bounds
    }
}
#endif
