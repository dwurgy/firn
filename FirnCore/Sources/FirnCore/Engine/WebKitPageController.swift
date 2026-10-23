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
    private(set) var icon: Data?
    private(set) var loadError: LoadError?
    @ObservationIgnored var onRequest: (@MainActor (PageRequest) -> Void)?
    @ObservationIgnored var sendsOtherSitesToLookout = false

    @ObservationIgnored let webView: WKWebView
    /// Only pages a site opened as popups may close themselves.
    @ObservationIgnored private let isPopup: Bool
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var isProvisional = false
    /// Where the load in progress is headed, in case its error doesn't say.
    @ObservationIgnored private var provisionalURL: URL?
    /// The icon addresses last tried, so a page that finishes loading again
    /// (or changes nothing) doesn't fetch its icon again.
    @ObservationIgnored private var iconCandidates: [URL] = []
    @ObservationIgnored private var iconTask: Task<Void, Never>?
    @ObservationIgnored private var iconRecheckPending = false
    /// When "Open in Lookout" was chosen from a link's menu, so the new
    /// window WebKit then asks for becomes a Lookout instead.
    @ObservationIgnored private var lookoutChosenAt: TimeInterval?
    /// Alerts, confirms, and prompts shown since this page last changed, so
    /// one that keeps asking can be told to stop.
    @ObservationIgnored private var dialogsShown = 0
    @ObservationIgnored private var dialogsBlocked = false
    @ObservationIgnored private var isShowingPanel = false

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
        // A real starting size, not zero: a page that loads before it's ever
        // on screen (a split's new half, say) laid out at 0×0 sat blank for
        // seconds once shown. Its holder gives it the true size when shown.
        let webView = FirnWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        self.webView = webView
        super.init()
        webView.page = self

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true // The Web Inspector is Firn's only developer tool.
        observeWebView()
        IconChangeWatcher.shared.watch(webView, for: self)
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
    func reload() {
        // After a failed load, the web view still holds the page before it,
        // so trying again means loading the address that failed.
        if let loadError {
            webView.load(URLRequest(url: loadError.url))
        } else {
            webView.reload()
        }
    }
    func stopLoading() { webView.stopLoading() }

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    func snapshot(width: CGFloat) async -> CGImage? {
        guard url != nil, loadError == nil else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        let image = try? await webView.takeSnapshot(configuration: configuration)
        return image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
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
        if let onRequest, navigationAction.navigationType == .linkActivated, WebAddress.isWebURL(url) {
            if let click = specialClick(for: navigationAction) {
                decisionHandler(.cancel)
                switch click {
                case let .newTab(inBackground): onRequest(.openURL(url, inBackground: inBackground))
                case .lookout: onRequest(.openInLookout(url))
                }
                return
            }
            if sendsOtherSitesToLookout, leavesTile(for: navigationAction, to: url) {
                decisionHandler(.cancel)
                onRequest(.openInLookout(url))
                return
            }
        }
        decisionHandler(NavigationPolicy.allows(url, isMainFrame: isMainFrame) ? .allow : .cancel)
    }

    /// A tile's link that would take it to another site, or open a new
    /// window (no target frame). Same-site links stay in the tile, as with
    /// Arc's Peek. Not a real click is needed: a link chosen from the
    /// keyboard counts too, and a page faking one only gets a Lookout.
    private func leavesTile(for action: WKNavigationAction, to url: URL) -> Bool {
        guard let frame = action.targetFrame else { return true }
        guard frame.isMainFrame, let current = self.url else { return false }
        return !WebAddress.isSameSite(current, url)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isProvisional = true
        provisionalURL = webView.url
        syncState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isProvisional = false
        provisionalURL = nil
        loadError = nil
        // A new page starts with a clean slate for alerts.
        dialogsShown = 0
        dialogsBlocked = false
        let previous = url
        url = webView.url
        // A different site: its old icon must not linger beside the new title.
        if previous?.host()?.lowercased() != url?.host()?.lowercased() {
            iconTask?.cancel()
            iconTask = nil
            iconCandidates = []
            icon = nil
        }
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState()
        findIcon()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        // Nothing new committed, so `url` stays the old page's. The error
        // page covers it, and the tab shows the address that failed instead.
        isProvisional = false
        if let failure = LoadError(error, fallbackURL: provisionalURL) { loadError = failure }
        provisionalURL = nil
        syncState()
    }

    /// The page had started arriving, then the connection gave out.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if let failure = LoadError(error, fallbackURL: url) { loadError = failure }
        syncState()
    }
}

// MARK: - Site icon

extension WebKitPageController {
    /// Firn's own scripts run here, never in the page's world, so the page
    /// can't see them, change them, or reach Firn through them.
    static let firnWorld = WKContentWorld.world(name: "Firn")

    /// Reads the page's icon links in Firn's world, then fetches the best one
    /// (see `SiteIcon`). Results arriving after the page moved to another
    /// site are dropped.
    private func findIcon() {
        guard let pageURL = url, WebAddress.isWebURL(pageURL) else { return }
        webView.evaluateJavaScript(SiteIcon.script, in: nil, in: Self.firnWorld) { [weak self] result in
            guard let self, let current = self.url, Self.sameOrigin(current, pageURL) else { return }
            let found = SiteIcon.parse(scriptResult: try? result.get())
            let candidates = SiteIcon.candidates(from: found.links, pageURL: pageURL)
            guard !candidates.isEmpty, candidates != self.iconCandidates else { return }
            self.iconCandidates = candidates
            self.iconTask?.cancel()
            self.iconTask = Task { [weak self] in
                let png = await SiteIcon.fetch(candidates, userAgent: found.userAgent)
                guard !Task.isCancelled, let png, let self,
                      let current = self.url, Self.sameOrigin(current, pageURL) else { return }
                self.icon = png
            }
        }
    }

    /// The page changed its icon links, or light and dark mode flipped (GitHub
    /// swaps in its dark icon by script after loading). Looks again a second
    /// later, so a busy page can't make Firn fetch over and over; `findIcon`
    /// only fetches if the list really changed.
    fileprivate func iconLinksMayHaveChanged(from origin: WKSecurityOrigin) {
        guard let url, origin.protocol == url.scheme?.lowercased(),
              origin.host.lowercased() == url.host()?.lowercased(), !iconRecheckPending else { return }
        iconRecheckPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.iconRecheckPending = false
            self.findIcon()
        }
    }
}

/// WKWebView sends keys to the page first, and when the page doesn't use
/// ⌃Tab, AppKit takes it as "next field" and focuses the address bar, so the
/// menu's Show Next Tab only worked every other press. Tab switching goes
/// to the menu first instead, as in other browsers; everything else still
/// goes to the page.
private final class FirnWebView: WKWebView {
    weak var page: WebKitPageController?

    #if os(macOS)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift)
        if event.type == .keyDown, event.charactersIgnoringModifiers == "\t" || event.charactersIgnoringModifiers == "\u{19}",
           modifiers == .control, NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Adds "Open in Lookout" above WebKit's "Open Link in New Window". WebKit
    /// doesn't say which link the menu is for, so the item runs WebKit's own
    /// and marks the new window it asks for as a Lookout (see `lookoutChosen`).
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard page?.onRequest != nil, let index = menu.items.firstIndex(where: {
            $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow"
        }) else { return }
        let item = NSMenuItem(title: "Open in Lookout", action: #selector(openInLookout(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = menu.items[index]
        menu.insertItem(item, at: index)
    }

    @objc private func openInLookout(_ sender: NSMenuItem) {
        guard let original = sender.representedObject as? NSMenuItem, let action = original.action else { return }
        page?.lookoutChosen()
        NSApp.sendAction(action, to: original.target, from: original)
    }
    #endif
}

/// Tells pages when their icon links change. Its script and message channel
/// live only in Firn's content world, so the page can't post to it; even so,
/// a message counts only from the main frame, from the page's real origin
/// (WebKit's, not anything claimed), and only as the exact word "changed".
/// One watcher serves every page: popups share their opener's content
/// controller, and a handler can't be added to it twice.
@MainActor
private final class IconChangeWatcher: NSObject, WKScriptMessageHandler {
    static let shared = IconChangeWatcher()
    private static let name = "firnIconsChanged"
    private static let script = """
        (function () {
            var timer = null;
            function changed() {
                clearTimeout(timer);
                timer = setTimeout(function () {
                    window.webkit.messageHandlers.firnIconsChanged.postMessage('changed');
                }, 300);
            }
            if (document.head) {
                new MutationObserver(changed).observe(document.head, {
                    childList: true, subtree: true,
                    attributes: true, attributeFilter: ['href', 'rel', 'media', 'sizes', 'type']
                });
            }
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', changed);
        })();
        """

    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let pages = NSMapTable<WKWebView, WebKitPageController>.weakToWeakObjects()

    func watch(_ webView: WKWebView, for page: WebKitPageController) {
        pages.setObject(page, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        let world = WebKitPageController.firnWorld
        controller.add(self, contentWorld: world, name: Self.name)
        controller.addUserScript(WKUserScript(
            source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world
        ))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.world.name == WebKitPageController.firnWorld.name,
              message.body as? String == "changed",
              let webView = message.webView, let page = pages.object(forKey: webView) else { return }
        page.iconLinksMayHaveChanged(from: message.frameInfo.securityOrigin)
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
        // Taken on every new window, so a stale choice can't be used later.
        if let chosen = lookoutChosenAt {
            lookoutChosenAt = nil
            if ProcessInfo.processInfo.systemUptime - chosen < 1, let onRequest,
               let url = navigationAction.request.url, WebAddress.isWebURL(url) {
                // A fresh page in the Lookout, not WebKit's: it needn't stay tied to this one.
                onRequest(.openInLookout(url))
                return nil
            }
        }
        guard let onRequest, Self.mayOpenInNewTab(navigationAction.request.url) else { return nil }
        // The popup must use its opener's store, so it stays in the same space.
        // WebKit's copy does; anything else is refused rather than risk a leak.
        guard let store = configuration.websiteDataStore.identifier,
              store == webView.configuration.websiteDataStore.identifier else { return nil }
        let page = WebKitPageController(configuration: configuration, isPopup: true)
        onRequest(.openPage(page, inBackground: false))
        // Only a page a tab took in gets listened to. One nobody took (its
        // opener was closing, say) is refused, so it never loads unseen.
        guard page.onRequest != nil else { return nil }
        return page.webView
    }

    /// "Open in Lookout" was chosen; WebKit asks for the new window next.
    fileprivate func lookoutChosen() {
        lookoutChosenAt = ProcessInfo.processInfo.systemUptime
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

// MARK: - Alerts and choosing files

#if os(macOS)
extension WebKitPageController {
    /// `alert()`.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        showDialog(message, from: frame, buttons: ["OK"]) { _ in completionHandler() }
    }

    /// `confirm()`: true only if OK was clicked.
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        showDialog(message, from: frame, buttons: ["OK", "Cancel"]) { answer in
            completionHandler(answer != nil)
        }
    }

    /// `prompt()`: the typed text, or nil for Cancel.
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let field = NSTextField(string: Self.clipped(defaultText ?? ""))
        field.frame = CGRect(x: 0, y: 0, width: 260, height: 24)
        showDialog(prompt, from: frame, buttons: ["OK", "Cancel"], field: field) { answer in
            completionHandler(answer)
        }
    }

    /// A file input's panel. WebKit only asks after a real click on one.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        guard let window = webView.window, !isShowingPanel else { return completionHandler(nil) }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        isShowingPanel = true
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.isShowingPanel = false
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    /// One alert at a time, attached to the window, headed by the site that
    /// asked (the frame's real origin, so an embedded frame can't pass itself
    /// off as the page). `done` gets nil for Cancel, otherwise the field's
    /// text (empty without a field). A page that isn't on screen, or one told
    /// to stop, is answered Cancel without asking, so nothing jumps out.
    private func showDialog(
        _ message: String,
        from frame: WKFrameInfo,
        buttons: [String],
        field: NSTextField? = nil,
        done: @escaping @MainActor (String?) -> Void
    ) {
        guard let window = webView.window, !dialogsBlocked, !isShowingPanel else { return done(nil) }
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? "This page says" : "\(host) says"
        alert.informativeText = Self.clipped(message)
        for title in buttons { alert.addButton(withTitle: title) }
        alert.accessoryView = field
        dialogsShown += 1
        // From the second one on, a way out of a page that keeps asking.
        if dialogsShown > 1 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t let this page show more"
        }
        if let field { alert.window.initialFirstResponder = field }
        isShowingPanel = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return done(nil) }
            self.isShowingPanel = false
            if alert.suppressionButton?.state == .on { self.dialogsBlocked = true }
            done(response == .alertFirstButtonReturn ? (field?.stringValue ?? "") : nil)
        }
    }

    /// Pages decide what these say; a few screens' worth is plenty.
    private static func clipped(_ text: String) -> String {
        text.count > 2000 ? String(text.prefix(2000)) + "…" : text
    }
}
#endif

// MARK: - ⌘-click, middle-click, and Shift-click

extension WebKitPageController {
    private enum SpecialClick {
        /// ⌘-click or middle-click; in the background unless Shift is held.
        case newTab(inBackground: Bool)
        /// Shift-click, as in Arc.
        case lookout
    }

    /// Whether a link click should open somewhere else. A page can fake a
    /// modified click in script, so the modifiers WebKit reports only count if
    /// a real click on this page just happened. Nil for an ordinary click.
    private func specialClick(for action: WKNavigationAction) -> SpecialClick? {
        #if os(macOS)
        // Taken on every link click, so a stale click can't be used later.
        guard let click = ClickRecorder.shared.takeRecentClick(in: webView) else { return nil }
        // WebKit and AppKit number the middle button differently (a mask, 4,
        // or an index, 2); either counts, as long as the real click agrees.
        let isMiddleClick = click.type == .otherMouseUp && click.buttonNumber == 2
            && (action.buttonNumber == 2 || action.buttonNumber == 4)
        let isCommandClick = click.type == .leftMouseUp && click.modifierFlags.contains(.command)
            && action.modifierFlags.contains(.command)
        let modifiers = click.modifierFlags.intersection([.shift, .command, .option, .control])
        if click.type == .leftMouseUp, modifiers == .shift, action.modifierFlags.contains(.shift) {
            return .lookout
        }
        guard isMiddleClick || isCommandClick else { return nil }
        // Background unless Shift is held, as in Safari, Arc, and Dia.
        return .newTab(inBackground: !click.modifierFlags.contains(.shift))
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
