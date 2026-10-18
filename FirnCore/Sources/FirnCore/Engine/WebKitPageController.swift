import Foundation
import Observation
import WebKit
#if os(macOS)
import AppKit
#endif

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
    @ObservationIgnored var onRequest: (@MainActor (PageRequest) -> Void)?

    @ObservationIgnored let webView: WKWebView
    /// Only pages a site opened as popups may close themselves.
    @ObservationIgnored private let isPopup: Bool
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var isProvisional = false

    convenience init(dataStoreID: UUID) {
        let configuration = WKWebViewConfiguration()
        // Every page uses its space's own store, never .default().
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        // Without a Safari-style version, some sites (Google sign-in among them)
        // treat WKWebView as an embedded app view and serve a lesser page.
        configuration.applicationNameForUserAgent = Self.safariUserAgentSuffix
        // On the Mac, WebKit lets scripts open windows without a click unless
        // told not to. Popups a site opens need a click; WebKit enforces it.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.init(configuration: configuration, isPopup: false)
    }

    /// `configuration` is either Firn's own (above) or the one WebKit hands
    /// over for a popup, which is a copy of the opener's.
    private init(configuration: WKWebViewConfiguration, isPopup: Bool) {
        self.isPopup = isPopup
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true // The Web Inspector is Firn's only developer tool.
        observeWebView()
        #if os(macOS)
        ClickRecorder.start() // Before the first click, or it would be missed.
        #endif
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
        if let onRequest, navigationAction.navigationType == .linkActivated, WebAddress.isWebURL(url),
           let inBackground = newTabClick(for: navigationAction) {
            decisionHandler(.cancel)
            onRequest(.openURL(url, inBackground: inBackground))
            return
        }
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
    /// A link meant for a new window, or `window.open` after a click, becomes
    /// a new tab. The new page is made from WebKit's configuration and handed
    /// back, so it stays connected to its opener (sign-in popups report back
    /// through `window.opener`), and WebKit loads it through the new page's
    /// own navigation checks.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let onRequest, Self.mayOpenInNewTab(navigationAction.request.url) else { return nil }
        // The popup must use its opener's store, so it stays in the same space.
        // WebKit's copy does; anything else is refused rather than risk a leak.
        guard let store = configuration.websiteDataStore.identifier,
              store == webView.configuration.websiteDataStore.identifier else { return nil }
        let page = WebKitPageController(configuration: configuration, isPopup: true)
        onRequest(.openPage(page, inBackground: false))
        return page.webView
    }

    /// `window.close()`. Honored only for popups, so an ordinary tab can't
    /// close itself out from under someone.
    func webViewDidClose(_ webView: WKWebView) {
        guard isPopup else { return }
        onRequest?(.close)
    }

    /// A web address, or a blank page the opener is about to fill in.
    private static func mayOpenInNewTab(_ url: URL?) -> Bool {
        guard let url, !url.absoluteString.isEmpty else { return true }
        return url.absoluteString == "about:blank" || WebAddress.isWebURL(url)
    }
}

// MARK: - ⌘-click and middle-click

extension WebKitPageController {
    /// Whether a link click should open a new tab instead, and whether in the
    /// background. A page can fake a ⌘-click in script, so the modifiers WebKit
    /// reports only count if a real click on this page just happened.
    /// Returns nil for an ordinary click, otherwise whether to stay put.
    private func newTabClick(for action: WKNavigationAction) -> Bool? {
        #if os(macOS)
        // Taken on every link click, so a stale click can't be used later.
        guard let click = ClickRecorder.shared.takeRecentClick(in: webView) else { return nil }
        // WebKit and AppKit number the middle button differently (a mask, 4,
        // or an index, 2); either counts, as long as the real click agrees.
        let isMiddleClick = click.type == .otherMouseUp && click.buttonNumber == 2
            && (action.buttonNumber == 2 || action.buttonNumber == 4)
        let isCommandClick = click.type == .leftMouseUp && click.modifierFlags.contains(.command)
            && action.modifierFlags.contains(.command)
        guard isMiddleClick || isCommandClick else { return nil }
        // Background unless Shift is held, as in Safari, Arc, and Dia.
        return !click.modifierFlags.contains(.shift)
        #else
        return nil
        #endif
    }
}

#if os(macOS)
/// Remembers the last real mouse click the app received, so ⌘-click and
/// middle-click can be told apart from clicks a page fakes in script.
@MainActor
private final class ClickRecorder {
    static let shared = ClickRecorder()
    private var lastClick: NSEvent?

    static func start() { _ = shared }

    private init() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .otherMouseUp]) { event in
            MainActor.assumeIsolated { ClickRecorder.shared.lastClick = event }
            return event
        }
    }

    /// The click, if it landed on `view` within the last second. Each click
    /// is used once, so one click opens at most one tab.
    func takeRecentClick(in view: NSView) -> NSEvent? {
        guard let click = lastClick else { return nil }
        lastClick = nil
        guard click.window === view.window,
              ProcessInfo.processInfo.systemUptime - click.timestamp < 1,
              view.bounds.contains(view.convert(click.locationInWindow, from: nil)) else { return nil }
        return click
    }
}
#endif
