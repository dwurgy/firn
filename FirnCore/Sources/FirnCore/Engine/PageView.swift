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

    public func makeNSView(context: Context) -> WKWebView {
        let webView = webKitPage.webView
        webView.wantsLayer = true
        webView.layer?.masksToBounds = true
        webView.layer?.cornerCurve = .continuous
        webView.layer?.cornerRadius = cornerRadius
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        webView.layer?.cornerRadius = cornerRadius
    }

    private var webKitPage: WebKitPageController {
        guard let page = page as? WebKitPageController else {
            preconditionFailure("PageView shows pages made by BrowserEngine.makePage")
        }
        return page
    }
}
#endif
