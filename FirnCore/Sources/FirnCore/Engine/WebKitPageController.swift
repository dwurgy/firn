import Foundation
import Observation
import WebKit

/// A page backed by WKWebView. Everything WebKit-specific stays in this file
/// and PageView.
@MainActor
@Observable
final class WebKitPageController: NSObject, PageController {
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var isProvisional = false

    init(dataStoreID: UUID) {
        let configuration = WKWebViewConfiguration()
        // Every page uses its space's own store, never .default().
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        // Without a Safari-style version, some sites (Google sign-in among them)
        // treat WKWebView as an embedded app view and serve a lesser page.
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true // The Web Inspector is Firn's only developer tool.
        observeWebView()
    }

    func load(_ url: URL) {
        guard WebAddress.isWebURL(url) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    // MARK: - Keeping state in step with WebKit

    private func observeWebView() {
        let sync: @Sendable (WKWebView, Any) -> Void = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncState() }
        }
        observations = [
            webView.observe(\.title, changeHandler: sync),
            webView.observe(\.canGoBack, changeHandler: sync),
            webView.observe(\.canGoForward, changeHandler: sync),
            webView.observe(\.isLoading, changeHandler: sync),
            webView.observe(\.url) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.sameDocumentURLChanged() }
            },
        ]
    }

    private func syncState() {
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    /// WKWebView's `url` can change before a navigation commits, so the address
    /// bar would show a page that isn't there yet (a spoofing risk). Cross-origin
    /// changes are only taken at commit; here we accept changes within the same
    /// origin, which is all a page can do without navigating (pushState, #links).
    private func sameDocumentURLChanged() {
        guard !isProvisional, let newURL = webView.url, let current = url,
              Self.sameOrigin(newURL, current) else { return }
        url = newURL
    }

    private static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host()?.lowercased() == b.host()?.lowercased()
            && a.port == b.port
    }

    private static var safariUserAgentSuffix: String {
        // Safari's version follows macOS from 26 on; before that it was macOS + 3.
        let macOS = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let safari = macOS >= 26 ? macOS : macOS + 3
        return "Version/\(safari).0 Safari/605.1.15"
    }
}

// MARK: - Navigation

extension WebKitPageController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        decisionHandler(NavigationPolicy.allows(url, isMainFrame: isMainFrame) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isProvisional = true
        syncState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isProvisional = false
        url = webView.url
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        // The old page stays, and so does its address.
        isProvisional = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        syncState()
    }
}

// MARK: - New windows

extension WebKitPageController: WKUIDelegate {
    /// Phase 1 has a single page, so links meant for a new window open here.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, WebAddress.isWebURL(url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
