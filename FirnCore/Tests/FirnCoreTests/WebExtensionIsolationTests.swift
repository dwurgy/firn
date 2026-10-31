#if os(macOS)
import AppKit
import Foundation
import Testing
import WebKit
@testable import FirnCore

@MainActor
struct WebExtensionIsolationTests {
    @available(macOS 15.4, *)
    private struct Fixture {
        let root: URL
        let archive: URL

        init() throws {
            root = URL(fileURLWithPath: "/private/tmp/Firn-extension-isolation-tests", isDirectory: true)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let source = root.appending(path: "fixture", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "manifest_version": 2,
                "name": "Firn Isolation Fixture",
                "description": "Synthetic local fixture for Firn runtime isolation tests.",
                "version": "1.0",
                "permissions": ["storage", "nativeMessaging", "http://example.test/*"],
                "background": ["scripts": ["background.js"], "persistent": true],
                "options_ui": ["page": "options.html", "open_in_tab": true],
                "web_accessible_resources": ["public.html"],
                "content_scripts": [[
                    "matches": ["http://example.test/*"],
                    "js": ["content.js"],
                    "run_at": "document_start",
                ]],
            ]
            try JSONSerialization.data(withJSONObject: manifest).write(to: source.appending(path: "manifest.json"))
            try Data("document.documentElement.dataset.firnExtensionMarker = 'enabled';".utf8)
                .write(to: source.appending(path: "content.js"))
            try Data("browser.storage.local.set({restartMarker: 'persisted'});".utf8)
                .write(to: source.appending(path: "background.js"))
            try Data("<!doctype html><html><body>Extension options fixture</body></html>".utf8)
                .write(to: source.appending(path: "options.html"))
            let frame = Data("<!doctype html><html><body><script src='frame.js'></script></body></html>".utf8)
            try frame.write(to: source.appending(path: "public.html"))
            try frame.write(to: source.appending(path: "private.html"))
            try Data("parent.postMessage(location.pathname, '*');".utf8).write(to: source.appending(path: "frame.js"))
            archive = root.appending(path: "fixture.zip")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zip.arguments = ["-c", "-k", source.path, archive.path]
            try zip.run()
            zip.waitUntilExit()
            #expect(zip.terminationStatus == 0)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @available(macOS 15.4, *)
    private func install(_ fixture: Fixture, library: WebExtensionLibrary, in storeID: UUID) async throws -> InstalledWebExtension {
        let candidate = try await library.prepareImport(from: fixture.archive)
        return try library.install(candidate, in: storeID)
    }

    @available(macOS 15.4, *)
    private func makePage(dataStoreID: UUID, manager: WebExtensionManager) -> WebKitPageController {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        configuration.webExtensionController = manager.controller(for: dataStoreID)
        return WebKitPageController(configuration: configuration, isPopup: false)
    }

    @available(macOS 15.4, *)
    private func waitForContext(_ controller: WKWebExtensionController, id: UUID) async -> WKWebExtensionContext? {
        let url = URL(string: "webkit-extension://\(id.uuidString.lowercased())/")!
        for _ in 0..<100 {
            if let context = controller.extensionContext(for: url), context.isLoaded { return context }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    @available(macOS 15.4, *)
    private func waitForMarker(in page: WebKitPageController) async -> Bool {
        for _ in 0..<100 {
            if (try? await page.webView.evaluateJavaScript("document.documentElement.dataset.firnExtensionMarker || ''") as? String) == "enabled" {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    @available(macOS 15.4, *)
    private func waitForNoContext(_ controller: WKWebExtensionController, id: UUID) async -> Bool {
        let url = URL(string: "webkit-extension://\(id.uuidString.lowercased())/")!
        for _ in 0..<100 {
            if controller.extensionContext(for: url) == nil { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    @Test func runtimeIsScopedToItsWebsiteStoreAndOnlyInjectsWhenEnabled() async throws {
        guard #available(macOS 15.4, *) else { return }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let storeA = UUID(), storeB = UUID()
        let library = WebExtensionLibrary(rootURL: fixture.root.appending(path: "library", directoryHint: .isDirectory))
        let installed = try await install(fixture, library: library, in: storeA)
        let manager = WebExtensionManager(library: library)
        let spaceA = Space(name: "A", color: "glacier", order: 0, dataStoreID: storeA)
        let spaceB = Space(name: "B", color: "sand", order: 1, dataStoreID: storeB)
        let store = BrowserStore(spaces: [spaceA, spaceB], makePage: { [manager] id in
            self.makePage(dataStoreID: id, manager: manager)
        })
        manager.connect(to: store)

        let controllerA = try #require(manager.controller(for: storeA))
        let controllerAAgain = try #require(manager.controller(for: storeA))
        let controllerB = try #require(manager.controller(for: storeB))
        #expect(controllerA === controllerAAgain)
        #expect(controllerA !== controllerB)
        #expect(controllerA.configuration.defaultWebsiteDataStore.identifier == storeA)
        #expect(controllerB.configuration.defaultWebsiteDataStore.identifier == storeB)

        let pageA = try #require(store.openTab(URL(string: "about:blank")!).page as? WebKitPageController)
        let tabA = try #require(store.tabs.first)
        #expect(store.addToBasecamp(tabA))
        store.selectSpace(spaceB)
        let pageB = try #require(store.openTab(URL(string: "about:blank")!).page as? WebKitPageController)
        pageA.webView.loadHTMLString("<html><head></head><body>A</body></html>", baseURL: URL(string: "http://example.test/a"))
        pageB.webView.loadHTMLString("<html><head></head><body>B</body></html>", baseURL: URL(string: "http://example.test/b"))

        let contextA = await waitForContext(controllerA, id: installed.id)
        #expect(contextA != nil)
        #expect(controllerB.extensionContext(for: URL(string: "webkit-extension://\(installed.id.uuidString.lowercased())/")!) == nil)
        #expect(await waitForMarker(in: pageA))
        #expect(!(await waitForMarker(in: pageB)))
        let context = try #require(contextA)
        let windowA = try #require(manager.webExtensionController(controllerA, openWindowsFor: context).first)
        let tabsA = windowA.tabs?(for: context) ?? []
        #expect(tabsA.count == 1)
        #expect(tabsA.first?.url?(for: context)?.host == "example.test")

        let selectedSpace = store.activeSpaceID
        let selectedTab = store.activeTabID
        var openedOptions = false
        manager.webExtensionController(controllerA, openOptionsPageFor: context) { error in
            #expect(error == nil)
            openedOptions = error == nil
        }
        #expect(openedOptions)
        #expect(store.activeSpaceID == selectedSpace)
        #expect(store.activeTabID == selectedTab)
        #expect(store.tabs.filter { $0.spaceID == spaceA.id }.count == 2)
        let optionsPage = try #require(store.tabs.first { $0.spaceID == spaceA.id && $0.id != tabA.id }?.page as? WebKitPageController)
        for _ in 0..<100 where optionsPage.webView.isLoading || optionsPage.webView.url == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(optionsPage.webView.url?.scheme == "webkit-extension")
        let optionsText = try await optionsPage.webView.evaluateJavaScript("document.body.innerText") as? String
        #expect(optionsText?.contains("Extension options fixture") == true)

        // Inline extension UI is allowed, while WebKit still enforces the
        // manifest's resource boundary against the embedding website.
        let publicURL = context.baseURL.appending(path: "public.html").absoluteString
        let privateURL = context.baseURL.appending(path: "private.html").absoluteString
        pageA.webView.loadHTMLString("""
            <script>window.seenFrames = []; addEventListener('message', e => seenFrames.push(e.data));</script>
            <iframe src="\(publicURL)"></iframe><iframe src="\(privateURL)"></iframe>
            """, baseURL: URL(string: "http://example.test/frames"))
        var frames: [String] = []
        for _ in 0..<100 {
            frames = (try? await pageA.webView.evaluateJavaScript("window.seenFrames || []") as? [String]) ?? []
            if frames.contains("/public.html") && !pageA.webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(frames.contains("/public.html"))
        #expect(!frames.contains("/private.html"))

        // Calling the manager with a context created by another store must
        // never expose that context's windows through this controller.
        let otherID = UUID()
        try library.setEnabled(true, id: installed.id, in: otherID)
        let controllerOther = try #require(manager.controller(for: otherID))
        guard let contextOther = await waitForContext(controllerOther, id: installed.id) else {
            Issue.record("Extension did not load in the explicitly enabled second store")
            return
        }
        #expect(manager.webExtensionController(controllerA, openWindowsFor: contextOther).isEmpty)
        #expect(manager.webExtensionController(controllerOther, openWindowsFor: contextA!).count == 0)
    }

    @Test func disableWinsAgainstAnInFlightLoadAndReenableRestoresContext() async throws {
        guard #available(macOS 15.4, *) else { return }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let storeID = UUID()
        let library = WebExtensionLibrary(rootURL: fixture.root.appending(path: "library", directoryHint: .isDirectory))
        let installed = try await install(fixture, library: library, in: storeID)
        let manager = WebExtensionManager(library: library)
        let space = Space(name: "Only", color: "glacier", order: 0, dataStoreID: storeID)
        let store = BrowserStore(spaces: [space], makePage: { _ in
            WebKitPageController(configuration: WKWebViewConfiguration(), isPopup: false)
        })
        manager.connect(to: store)
        let controller = try #require(manager.controller(for: storeID))

        // Start WebKit's asynchronous package/context load, then immediately
        // revoke membership. A stale task must not publish a loaded context.
        try library.setEnabled(false, id: installed.id, in: storeID)
        #expect(await waitForNoContext(controller, id: installed.id))
        #expect(await waitForContext(controller, id: installed.id) == nil)

        try library.setEnabled(true, id: installed.id, in: storeID)
        #expect(await waitForContext(controller, id: installed.id) != nil)
        try library.setEnabled(false, id: installed.id, in: storeID)
        #expect(await waitForNoContext(controller, id: installed.id))
    }

    @Test func extensionIdentitySurvivesManagerAndLibraryRestart() async throws {
        guard #available(macOS 15.4, *) else { return }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let storeID = UUID()
        let libraryRoot = fixture.root.appending(path: "library", directoryHint: .isDirectory)
        let library = WebExtensionLibrary(rootURL: libraryRoot)
        let installed = try await install(fixture, library: library, in: storeID)
        let firstManager = WebExtensionManager(library: library)
        let firstController = try #require(firstManager.controller(for: storeID))
        guard let firstContext = await waitForContext(firstController, id: installed.id) else {
            Issue.record("Extension did not load before manager restart")
            return
        }
        let identifier = firstContext.uniqueIdentifier
        let baseURL = firstContext.baseURL
        #expect(identifier == installed.id.uuidString)
        #expect(baseURL == URL(string: "webkit-extension://\(installed.id.uuidString.lowercased())/"))
        let token = UUID().uuidString
        let firstView = WKWebView(frame: .zero, configuration: try #require(firstContext.webViewConfiguration))
        firstView.load(URLRequest(url: baseURL.appending(path: "options.html")))
        for _ in 0..<100 where firstView.isLoading || firstView.url == nil { try await Task.sleep(for: .milliseconds(25)) }
        _ = try await firstView.callAsyncJavaScript("await browser.storage.local.set({isolationTestToken: token}); return true;", arguments: ["token": token], in: nil, contentWorld: .page)
        firstManager.disable()

        let restartedLibrary = WebExtensionLibrary(rootURL: libraryRoot)
        let restartedManager = WebExtensionManager(library: restartedLibrary)
        let restartedController = try #require(restartedManager.controller(for: storeID))
        guard let restartedContext = await waitForContext(restartedController, id: installed.id) else {
            Issue.record("Extension did not load after library and manager restart")
            return
        }
        #expect(restartedContext.uniqueIdentifier == identifier)
        #expect(restartedContext.baseURL == baseURL)
        let secondView = WKWebView(frame: .zero, configuration: try #require(restartedContext.webViewConfiguration))
        secondView.load(URLRequest(url: baseURL.appending(path: "options.html")))
        for _ in 0..<100 where secondView.isLoading || secondView.url == nil { try await Task.sleep(for: .milliseconds(25)) }
        let restored = try await secondView.callAsyncJavaScript("return (await browser.storage.local.get('isolationTestToken')).isolationTestToken;", in: nil, contentWorld: .page)
        #expect(restored as? String == token)
    }

    @Test func nativeMessagingCallbacksAreDeniedAndOldContextsCannotOpenWindows() async throws {
        guard #available(macOS 15.4, *) else { return }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let storeID = UUID()
        let library = WebExtensionLibrary(rootURL: fixture.root.appending(path: "library", directoryHint: .isDirectory))
        let installed = try await install(fixture, library: library, in: storeID)
        let manager = WebExtensionManager(library: library)
        let controller = try #require(manager.controller(for: storeID))
        guard let context = await waitForContext(controller, id: installed.id) else {
            Issue.record("Extension did not load for native messaging test")
            return
        }

        var replied = false
        manager.webExtensionController(controller, sendMessage: ["probe": true], toApplicationWithIdentifier: "test.host", for: context) { response, error in
            replied = true
            #expect(response == nil)
            #expect(error != nil)
        }
        #expect(replied)
        #expect(installed.permissions.contains("nativeMessaging"))
        let view = WKWebView(frame: .zero, configuration: try #require(context.webViewConfiguration))
        view.load(URLRequest(url: context.baseURL.appending(path: "options.html")))
        for _ in 0..<100 where view.isLoading || view.url == nil { try await Task.sleep(for: .milliseconds(25)) }
        let nativeAPIs = try await view.evaluateJavaScript("typeof browser.runtime.connectNative + ':' + typeof browser.runtime.sendNativeMessage") as? String
        #expect(nativeAPIs == "undefined:undefined")
        manager.disable()
        #expect(manager.webExtensionController(controller, openWindowsFor: context).isEmpty)
    }

    @Test func uninstallAcknowledgesOnlySuccessfulCleanupAndPreservesWebsite() async throws {
        guard #available(macOS 15.4, *) else { return }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let storeID = UUID()
        let library = WebExtensionLibrary(rootURL: fixture.root.appending(path: "library", directoryHint: .isDirectory))
        let installed = try await install(fixture, library: library, in: storeID)
        let manager = WebExtensionManager(library: library)
        let space = Space(name: "Cleanup", color: "glacier", order: 0, dataStoreID: storeID)
        let store = BrowserStore(spaces: [space], makePage: { _ in
            WebKitPageController(configuration: WKWebViewConfiguration(), isPopup: false)
        })
        manager.connect(to: store)
        let controller = try #require(manager.controller(for: storeID))
        let context = try #require(await waitForContext(controller, id: installed.id))
        let websiteStore = WKWebsiteDataStore(forIdentifier: storeID)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()

        let ownView = WKWebView(frame: .zero, configuration: try #require(context.webViewConfiguration))
        ownView.load(URLRequest(url: context.baseURL.appending(path: "options.html")))
        for _ in 0..<100 where ownView.isLoading || ownView.url == nil { try await Task.sleep(for: .milliseconds(25)) }
        let token = UUID().uuidString
        let wrote = try await ownView.callAsyncJavaScript("""
            localStorage.setItem('cleanupToken', token);
            await new Promise((resolve, reject) => {
                const open = indexedDB.open('firn-cleanup-fixture', 1);
                open.onupgradeneeded = () => open.result.createObjectStore('tokens');
                open.onerror = () => reject(open.error);
                open.onsuccess = () => {
                    const db = open.result;
                    const transaction = db.transaction('tokens', 'readwrite');
                    transaction.objectStore('tokens').put(token, 'value');
                    transaction.oncomplete = () => { db.close(); resolve(true); };
                    transaction.onerror = () => reject(transaction.error);
                };
            });
            return localStorage.getItem('cleanupToken') === token;
            """, arguments: ["token": token], in: nil, contentWorld: .page) as? Bool
        #expect(wrote == true)

        let unrelatedConfiguration = WKWebViewConfiguration()
        unrelatedConfiguration.websiteDataStore = websiteStore
        let unrelatedView = WKWebView(frame: .zero, configuration: unrelatedConfiguration)
        unrelatedView.loadHTMLString("<html><body>Unrelated website</body></html>", baseURL: URL(string: "http://example.test/")!)
        for _ in 0..<100 where unrelatedView.isLoading || unrelatedView.url == nil { try await Task.sleep(for: .milliseconds(25)) }
        _ = try await unrelatedView.evaluateJavaScript("localStorage.setItem('unrelatedToken', '\(token)')")
        var before = await websiteStore.dataRecords(ofTypes: types)
        let ownHost = installed.id.uuidString.lowercased()
        for _ in 0..<100 where !before.contains(where: { $0.displayName.lowercased().contains(ownHost) }) {
            try await Task.sleep(for: .milliseconds(25))
            before = await websiteStore.dataRecords(ofTypes: types)
        }
        // Some SDK versions omit extension DOM storage from public records.
        // Cleanup below must preserve unrelated data whether it is exposed or not;
        // this test cannot prove DOM erasure when WebKit omits those records.
        #expect(before.contains { $0.displayName == "example.test" })

        ownView.load(URLRequest(url: URL(string: "about:blank")!))
        try library.remove(id: installed.id)
        #expect(library.pendingRemovals[installed.id] != nil)
        for _ in 0..<200 where manager.errors[installed.id] == nil && library.pendingRemovals[installed.id] != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        let sdkRecords = await controller.dataRecords(ofTypes: WKWebExtensionController.allExtensionDataTypes)
        if sdkRecords.contains(where: { $0.uniqueIdentifier == installed.id.uuidString && !$0.errors.isEmpty }) {
            #expect(manager.errors[installed.id] != nil)
            #expect(library.pendingRemovals[installed.id] != nil)
        } else {
            #expect(library.pendingRemovals[installed.id] == nil)
        }
        let after = await websiteStore.dataRecords(ofTypes: types)
        #expect(!after.contains { $0.displayName.lowercased().contains(ownHost) })
        #expect(after.contains { $0.displayName == "example.test" })
        #expect(try await unrelatedView.evaluateJavaScript("localStorage.getItem('unrelatedToken')") as? String == token)
    }
}
#endif
