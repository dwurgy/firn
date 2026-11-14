import Foundation
import WebKit
#if os(iOS)
import UIKit
#endif

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

    // MARK: Summarize's state, kept only while Reader is open

    private enum Summary: Equatable {
        case offered, making, made(String), failed
        var word: String {
            switch self {
            case .offered: "offered"
            case .making: "making"
            case .made: "made"
            case .failed: "failed"
            }
        }
    }

    /// The on-device model, when Summarize is offered as Reader opens.
    private let summarizer: ArticleSummarizer?
    private var summary = Summary.offered
    /// Whether the card is open (the ✕ folds it back to the pill).
    private var showsCard = false
    /// Whether the sentences have settled in once already.
    private var settled = false
    private var summaryTask: Task<Void, Never>?
    /// Whether the reader's page has loaded, so its slot can be drawn.
    private var loaded = false

    init(article: ReaderArticle, page: WebKitPageController, look: ReaderLook, accent: UInt32) {
        self.article = article
        self.page = page
        let summarizer = ArticleSummarizer.onDevice.flatMap { $0.isAvailable ? $0 : nil }
        self.summarizer = summarizer
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
        // Firn's own view, as the page's: its right-click menu and its keys
        // (⌃Tab) work the same while reading.
        // Summarize's pill and ✕ reach Firn only from Firn's own world
        // (`SummaryMessages`); the reader's page runs no scripts of its own.
        let messages = SummaryMessages()
        if summarizer != nil {
            let world = WebKitPageController.firnWorld
            configuration.userContentController.add(messages, contentWorld: world, name: SummaryMessages.name)
            configuration.userContentController.addUserScript(WKUserScript(
                source: ReaderDocument.summaryListenerScript, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true, in: world))
        }
        let view = FirnWebView(frame: page.webView.frame, configuration: configuration)
        view.page = page
        view.isReader = true
        webView = view
        super.init()
        messages.reader = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        #if os(macOS)
        webView.allowsMagnification = true
        #endif
        let html = ReaderDocument.html(
            for: article, look: look, accent: accent, icon: page.icon, summarize: summarizer != nil)
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

    // MARK: Summarize

    /// The pill, View › Summarize Article, or the command bar: opens the
    /// card, and makes the summary if it isn't made yet. Once made (or
    /// failed), it's shown again at once, never made twice.
    func summarize() {
        guard let summarizer else { return }
        let grow = !showsCard
        showsCard = true
        if summary == .offered {
            summary = .making
            let article = article
            summaryTask = Task { [weak self] in
                let text = await summarizer.summary(of: article)
                guard let self, !Task.isCancelled else { return }
                self.summary = text.map { .made($0) } ?? .failed
                self.drawSummary(grow: false)
            }
        }
        drawSummary(grow: grow)
    }

    /// The card's ✕: back to the pill. A summary still being made goes on,
    /// and shows when the card opens again.
    func hideSummary() {
        guard showsCard else { return }
        showsCard = false
        drawSummary(grow: false)
    }

    /// Reader is closing: the summary goes with it, never saved.
    func stopSummary() {
        summaryTask?.cancel()
        summaryTask = nil
    }

    fileprivate func heard(_ word: String) {
        switch word {
        case "make": summarize()
        case "hide": hideSummary()
        default: break
        }
    }

    private func drawSummary(grow: Bool) {
        guard loaded, summarizer != nil else { return }
        let state = showsCard ? summary : .offered
        var text = ""
        if case let .made(made) = state { text = made }
        let settle = !text.isEmpty && !settled
        if settle { settled = true }
        let arguments: [String: Any] = [
            "state": state.word, "text": text, "device": Self.deviceName, "grow": grow, "settle": settle,
        ]
        Task {
            _ = try? await webView.callAsyncJavaScript(
                ReaderDocument.summaryScript, arguments: arguments,
                in: nil, contentWorld: WebKitPageController.firnWorld)
        }
    }

    /// The foot's "Made on this Mac", as the device is called.
    private static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// The reader's own page has loaded: a summary asked for before it did
    /// (View › Summarize Article opens Reader first) can now be drawn.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if showsCard { drawSummary(grow: true) }
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

extension ReaderPage: WKUIDelegate {
    /// A new window from the reader: a Firn menu item (Open in New Tab, Save
    /// Link As…) does what it does on the page; anything else that asks
    /// (the iPhone's Open in New Tab, say) becomes a fresh tab of its own.
    /// Never a page made from the reader's setup, which has scripts off.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let page, !page.runMenuChoice(for: navigationAction),
              let url = navigationAction.request.url, WebAddress.isWebURL(url),
              let onRequest = page.onRequest else { return nil }
        onRequest(.openURL(url, inBackground: false))
        return nil
    }
}

/// Hears Summarize's pill and the card's ✕ (`ReaderDocument.summaryListenerScript`).
/// Its own object, holding the reader weakly, since WebKit holds its
/// handlers strongly. A message counts only from Firn's world, the reader's
/// own main frame, and as one of the two exact words.
@MainActor
private final class SummaryMessages: NSObject, WKScriptMessageHandler {
    static let name = "firnSummary"
    weak var reader: ReaderPage?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.world.name == WebKitPageController.firnWorld.name,
              let word = message.body as? String, word == "make" || word == "hide",
              let reader, message.webView === reader.webView else { return }
        reader.heard(word)
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
        reader.stopSummary()
        reader.webView.configuration.userContentController.removeAllScriptMessageHandlers()
        reader.webView.stopLoading()
        reader.webView.navigationDelegate = nil
        reader.webView.uiDelegate = nil
        self.reader = nil
    }

    func setReaderLook(_ look: ReaderLook) {
        reader?.setLook(look)
    }

    func summarizeArticle() {
        reader?.summarize()
    }
}
