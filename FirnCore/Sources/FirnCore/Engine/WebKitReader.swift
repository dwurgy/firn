import Foundation
import WebKit

/// Reader's own view: the article, drawn by Firn (`ReaderDocument`) in a
/// separate web view beside the page's. It uses the same space's data store
/// (so pictures load as the space would load them) but runs no scripts at
/// all, keeps no history, opens nothing by itself, and loads only what its
/// content policy lets through: pictures. A link closes Reader and opens in
/// the tab, as the page's own links do.
@MainActor
final class ReaderPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let article: ReaderArticle
    private weak var page: WebKitPageController?

    init(article: ReaderArticle, page: WebKitPageController, look: ReaderLook, accent: UInt32) {
        self.article = article
        self.page = page
        let configuration = WKWebViewConfiguration()
        // The page's own store: never .default(), never another space's.
        configuration.websiteDataStore = page.webView.configuration.websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.applicationNameForUserAgent = WebKitPageController.safariUserAgentSuffix
        // Trackers hidden among an article's pictures stay blocked, unless
        // this space stopped blocking on the article's site.
        ContentBlocker.shared.attach(configuration.userContentController)
        ContentBlocker.shared.setBlocks(
            page.blocksContent?(article.pageURL) ?? true, for: configuration.userContentController)
        webView = WKWebView(frame: page.webView.frame, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isInspectable = true
        #if os(macOS)
        webView.allowsMagnification = true
        #endif
        let html = ReaderDocument.html(for: article, look: look, accent: accent, icon: page.icon)
        // No base address: the reader belongs to no site, and every link
        // and picture in it is already absolute.
        webView.loadHTMLString(html, baseURL: nil)
    }

    func setLook(_ look: ReaderLook) {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                ReaderDocument.setLookScript, arguments: ["classes": look.rootClasses],
                in: nil, contentWorld: WebKitPageController.firnWorld)
        }
    }

    /// Only Firn's own load of the reader, and links a person clicks.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, url.absoluteString == "about:blank", navigationAction.navigationType == .other {
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
        guard navigationAction.navigationType == .linkActivated, WebAddress.isWebURL(url),
              let page else { return }
        if let click = page.specialClick(for: navigationAction, in: webView), let onRequest = page.onRequest {
            switch click {
            case let .newTab(inBackground): onRequest(.openURL(url, inBackground: inBackground))
            case .lookout: onRequest(.openInLookout(url))
            }
            return
        }
        page.load(url)
    }
}

// MARK: - Reader, as the rest of Firn sees it

extension WebKitPageController {
    func openReader(look: ReaderLook, accent: UInt32) async -> Bool {
        if reader != nil { return true }
        let pageURL = url
        guard let article = await readArticle() else {
            // Passed the quick check, but too short or empty when read:
            // the book quietly goes away for this page.
            if url == pageURL { isArticle = false }
            return false
        }
        // The page moved on, or Reader opened another way, while reading.
        guard url == pageURL, reader == nil else { return reader != nil }
        reader = ReaderPage(article: article, page: self, look: look, accent: accent)
        return true
    }

    func closeReader() {
        guard let reader else { return }
        reader.webView.stopLoading()
        reader.webView.navigationDelegate = nil
        self.reader = nil
    }

    func setReaderLook(_ look: ReaderLook) {
        reader?.setLook(look)
    }
}
