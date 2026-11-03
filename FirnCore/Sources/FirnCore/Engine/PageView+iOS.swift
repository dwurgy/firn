#if os(iOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI on iPhone and iPad. The only place a view and
/// WKWebView meet on iOS; the Mac's is PageView.swift. UIKit wrapper because
/// SwiftUI's own WebView would be its own step (see CLAUDE.md, Engine).
public struct PageView: UIViewRepresentable {
    private let page: any PageController

    public init(page: any PageController) {
        self.page = page
    }

    public func makeUIView(context: Context) -> PageHolder {
        PageHolder(webView: webKitPage.webView)
    }

    public func updateUIView(_ holder: PageHolder, context: Context) {}

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
