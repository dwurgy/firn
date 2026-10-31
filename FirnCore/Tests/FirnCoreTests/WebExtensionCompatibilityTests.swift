#if os(macOS)
import Foundation
import Testing
import WebKit
@testable import FirnCore

@MainActor
struct WebExtensionCompatibilityTests {
    @available(macOS 15.4, *)
    private func extensionPage(prelude: String? = nil) async throws -> WKWebView {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"manifest_version":2,"name":"Compatibility Fixture","version":"1.0","permissions":["notifications"]}"#.utf8)
            .write(to: root.appending(path: "manifest.json"))
        try Data("<!doctype html><title>Extension fixture</title>".utf8)
            .write(to: root.appending(path: "page.html"))
        let ext = try await WKWebExtension(resourceBaseURL: root)
        let config = WKWebExtensionController.Configuration.nonPersistent()
        config.defaultWebsiteDataStore = .nonPersistent()
        config.webViewConfiguration.websiteDataStore = config.defaultWebsiteDataStore
        if let prelude {
            config.webViewConfiguration.userContentController.addUserScript(WKUserScript(
                source: prelude, injectionTime: .atDocumentStart,
                forMainFrameOnly: true, in: .page
            ))
        }
        config.webViewConfiguration.userContentController.addUserScript(WKUserScript(
            source: WebExtensionCompatibility.source, injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: .page
        ))
        let controller = WKWebExtensionController(configuration: config)
        let context = WKWebExtensionContext(for: ext)
        try controller.load(context)
        let page = WKWebView(frame: .zero, configuration: try #require(context.webViewConfiguration))
        page.load(URLRequest(url: context.baseURL.appending(path: "page.html")))
        for _ in 0..<100 {
            if page.url?.scheme == "webkit-extension" && !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        return page
    }

    @Test @available(macOS 15.4, *) func navigationTargetForwardsOnlyNativeTabsWithOpeners() async throws {
        let page = try await extensionPage(prelude: """
            globalThis.__created = new Set();
            globalThis.__nativeTabs = {onCreated: {
                addListener(fn) { __created.add(fn); },
                removeListener(fn) { __created.delete(fn); }
            }};
            globalThis.__navigationPermission = true;
            globalThis.browser = {
                runtime: {id: 'fixture', getManifest: () => ({permissions: ['webNavigation']})},
                permissions: {contains: async () => __navigationPermission}, tabs: __nativeTabs
            };
            """)
        let value = try await page.callAsyncJavaScript("""
            const event = browser.webNavigation?.onCreatedNavigationTarget;
            if (!event) return {missing: true};
            const received = [];
            const listener = details => received.push(details);
            let rejectedFilter = false;
            try { event.addListener(listener, {url: [{hostContains: 'example'}]}); }
            catch (error) { rejectedFilter = error instanceof TypeError; }
            const before = __created.size;
            event.addListener(listener);
            event.addListener(listener);
            const subscribed = __created.size;
            for (const tab of [
                {id: 4, url: 'https://example.test/no-opener'},
                {id: 5, openerTabId: '4', url: 'https://example.test/string-id'},
                {id: 6, openerTabId: 4, url: 'https://example.test/created'}
            ]) for (const callback of __created) callback(tab);
            await new Promise(resolve => setTimeout(resolve, 0));
            const wasRegistered = event.hasListener(listener) && event.hasListeners();
            __navigationPermission = false;
            for (const callback of __created) callback({id: 8, openerTabId: 4, url: 'https://example.test/revoked'});
            await new Promise(resolve => setTimeout(resolve, 0));
            event.removeListener(listener);
            const unsubscribed = __created.size === 0 && !event.hasListeners() && !event.hasListener(listener);
            for (const callback of __created) callback({id: 7, openerTabId: 4, url: 'https://example.test/later'});
            return {before, subscribed, rejectedFilter, wasRegistered, unsubscribed, received};
            """, in: nil, contentWorld: .page) as? [String: Any]
        let result = try #require(value)
        #expect(result["missing"] == nil)
        #expect(result["before"] as? Int == 0)
        #expect(result["subscribed"] as? Int == 1)
        #expect(result["rejectedFilter"] as? Bool == true)
        #expect(result["wasRegistered"] as? Bool == true)
        #expect(result["unsubscribed"] as? Bool == true)
        let received = try #require(result["received"] as? [[String: Any]])
        #expect(received.count == 1)
        #expect(received.first?["tabId"] as? Int == 6)
        #expect(received.first?["sourceTabId"] as? Int == 4)
        #expect(received.first?["url"] as? String == "https://example.test/created")
        #expect(received.first?["timeStamp"] as? Double != nil)
        #expect(Set(received.first?.keys ?? Dictionary<String, Any>().keys) == ["tabId", "sourceTabId", "url", "timeStamp"])
    }

    @Test @available(macOS 15.4, *) func freshNamespaceWrapperIsRetainedWithNativeReceivers() async throws {
        let page = try await extensionPage(prelude: """
            globalThis.__nativeEvent = {addListener() {}, removeListener() {}};
            globalThis.browser = {
                runtime: {id: 'fixture', getManifest: () => ({permissions: ['webNavigation']})},
                permissions: {contains: async () => true}, tabs: {onCreated: __nativeEvent},
                get webNavigation() {
                    const native = {onCommitted: __nativeEvent};
                    native.getAllFrames = function() { return this === native; };
                    return native;
                }
            };
            """)
        let value = try await page.evaluateJavaScript("""
            (() => {
                const first = browser.webNavigation;
                return first === browser.webNavigation &&
                    typeof first.onCreatedNavigationTarget.addListener === 'function' &&
                    first.onCommitted === __nativeEvent && first.getAllFrames() &&
                    Object.getOwnPropertyDescriptor(browser, 'webNavigation').get !== undefined;
            })()
            """) as? Bool
        #expect(value == true)
    }

    @Test @available(macOS 15.4, *) func deniedNotificationsAndEventRegistration() async throws {
        let page = try await extensionPage()
        let value = try await page.callAsyncJavaScript("""
            const api = globalThis.chrome.notifications;
            const click = () => {};
            api.onClicked.addListener(click);
            const registered = api.onClicked.hasListener(click) && api.onClicked.hasListeners();
            api.onClicked.removeListener(click);
            const callbackPermission = await new Promise(resolve => api.getPermissionLevel(resolve));
            const callbackAll = await new Promise(resolve => api.getAll(resolve));
            const callbackClear = await new Promise(resolve => api.clear('missing', resolve));
            let rejected = false;
            try { await api.create('id', {type:'basic', title:'x', message:'y'}); }
            catch (error) { rejected = /unsupported.*denied/i.test(error.message); }
            let callbackRejected = false;
            try { api.create('id', {type:'basic', title:'x', message:'y'}, () => {}); }
            catch (error) { callbackRejected = /unsupported.*denied/i.test(error.message); }
            return { registered, removed: !api.onClicked.hasListeners(),
                     permission: await api.getPermissionLevel(), all: await api.getAll(),
                     updated: await api.update('id', {}), cleared: await api.clear('id'),
                     callbackPermission, callbackAll, callbackClear, rejected, callbackRejected };
            """, in: nil, contentWorld: .page) as? [String: Any]
        let result = try #require(value)
        #expect(result["registered"] as? Bool == true)
        #expect(result["removed"] as? Bool == true)
        #expect(result["permission"] as? String == "denied")
        #expect((result["all"] as? [String: Any])?.isEmpty == true)
        #expect(result["updated"] as? Bool == false)
        #expect(result["cleared"] as? Bool == false)
        #expect(result["rejected"] as? Bool == true)
        #expect(result["callbackPermission"] as? String == "denied")
        #expect((result["callbackAll"] as? [String: Any])?.isEmpty == true)
        #expect(result["callbackClear"] as? Bool == false)
        #expect(result["callbackRejected"] as? Bool == true)
    }

    @Test @available(macOS 15.4, *) func navigationTargetRequiresDeclaredPermission() async throws {
        let page = try await extensionPage(prelude: """
            globalThis.browser = {
                runtime: {id: 'fixture', getManifest: () => ({permissions: ['notifications']})},
                permissions: {contains: async () => false},
                tabs: {onCreated: {addListener() {}, removeListener() {}}}
            };
            """)
        let result = try await page.evaluateJavaScript("typeof browser.webNavigation?.onCreatedNavigationTarget") as? String
        #expect(result == "undefined")
    }

    @Test func ordinaryPageGetsNoNotifications() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(
            source: WebExtensionCompatibility.source, injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: .page
        ))
        let page = WKWebView(frame: .zero, configuration: config)
        page.loadHTMLString("<html><body>Ordinary page</body></html>", baseURL: URL(string: "https://example.test")!)
        for _ in 0..<100 where page.isLoading || page.url == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        let value = try await page.evaluateJavaScript("typeof globalThis.chrome + ':' + typeof globalThis.browser") as? String
        #expect(value == "undefined:undefined")
    }
}
#endif
