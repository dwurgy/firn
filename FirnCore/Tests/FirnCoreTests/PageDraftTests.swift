import Foundation
import Testing
import WebKit
@testable import FirnCore

struct PageDraftTests {
    @Test func acceptsAReport() {
        let report = PageDraftScript.parse(["frame": "abc123", "draft": true])
        #expect(report == .init(frame: "abc123", draft: true))
    }

    @Test func refusesAnythingElse() {
        #expect(PageDraftScript.parse("typing") == nil)
        #expect(PageDraftScript.parse(["frame": "abc", "draft": 1]) == nil)
        #expect(PageDraftScript.parse(["frame": "abc", "draft": "yes"]) == nil)
        #expect(PageDraftScript.parse(["frame": "", "draft": true]) == nil)
        #expect(PageDraftScript.parse(["frame": String(repeating: "a", count: 17), "draft": true]) == nil)
        #expect(PageDraftScript.parse(["frame": "a b", "draft": true]) == nil)
        #expect(PageDraftScript.parse(["frame": "abc", "draft": "hello", "text": "secret"]) == nil)
        #expect(PageDraftScript.parse(["frame": "abc", "draft": true, "extra": 1]) == nil)
    }
}

/// Runs the real page script in a real web view, typing as the page would
/// see it (an `input` event), and listens to what it tells Firn.
@MainActor
struct PageDraftScriptTests {
    final class Listener: NSObject, WKScriptMessageHandler {
        var reports: [PageDraftScript.Report] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let report = PageDraftScript.parse(message.body) { reports.append(report) }
        }
    }

    func page(_ html: String) async throws -> (WKWebView, Listener) {
        let listener = Listener()
        let world = WKContentWorld.world(name: "Firn")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(listener, contentWorld: world, name: PageDraftScript.handlerName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: PageDraftScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world
        ))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: "https://site.example/")!)
        for _ in 0..<100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return (webView, listener)
    }

    func run(_ script: String, in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(script)
        try await Task.sleep(for: .milliseconds(800))
    }

    func type(_ text: String, into selector: String) -> String {
        """
        (function () {
            var el = document.querySelector('\(selector)');
            if ('value' in el) el.value = '\(text)'; else el.textContent = '\(text)';
            el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        })()
        """
    }

    @Test func typedTextCountsUntilItsFieldGoes() async throws {
        let (webView, listener) = try await page("<form><textarea id='t'></textarea></form>")
        try await run(type("Dear Ann", into: "#t"), in: webView)
        #expect(listener.reports.last?.draft == true)
        try await run("document.getElementById('t').remove(); document.forms[0].dispatchEvent(new Event('submit'))", in: webView)
        #expect(listener.reports.last?.draft == false)
    }

    @Test func clearingTheFieldOrLeavingWhatThePageWroteDoesNotCount() async throws {
        let (webView, listener) = try await page("<input id='i' value='Search'><input id='j'>")
        try await run(type("Search", into: "#i"), in: webView)
        #expect(listener.reports.isEmpty)
        try await run(type("hello", into: "#j"), in: webView)
        try await run(type("", into: "#j"), in: webView)
        #expect(listener.reports.map(\.draft) == [true, false])
    }

    @Test func editorsCountEvenInsideAShadowRoot() async throws {
        let (webView, listener) = try await page("""
            <div id='host'></div>
            <script>
            document.getElementById('host').attachShadow({ mode: 'open' }).innerHTML = '<div contenteditable><p></p></div>';
            </script>
            """)
        try await run("""
            (function () {
                var p = document.getElementById('host').shadowRoot.querySelector('p');
                p.textContent = 'Notes';
                p.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
            })()
            """, in: webView)
        #expect(listener.reports.last?.draft == true)
    }
}
