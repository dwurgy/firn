#if os(macOS)
import Foundation
import Testing
import WebKit
@testable import FirnCore

@MainActor
struct WebExtensionMessagingTests {
    @available(macOS 15.4, *)
    private struct Fixture {
        let root: URL
        let archive: URL

        init(listener: String) throws {
            root = URL(fileURLWithPath: "/private/tmp/Firn-extension-messaging-tests", isDirectory: true)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let source = root.appending(path: "fixture", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let manifest: [String: Any] = [
                "manifest_version": 2,
                "name": "Firn Messaging Fixture",
                "description": "Synthetic local fixture for runtime messaging tests.",
                "version": "1.0",
                "background": ["scripts": ["background.js"], "persistent": true],
            ]
            try JSONSerialization.data(withJSONObject: manifest).write(to: source.appending(path: "manifest.json"))
            try Data(listener.utf8).write(to: source.appending(path: "background.js"))
            try Data("<!doctype html><html><body>Messaging fixture</body></html>".utf8)
                .write(to: source.appending(path: "page.html"))
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
    private func responseListener(alias: String, asynchronous: Bool) -> String {
        let registration: String
        if asynchronous {
            registration = """
                api.runtime.onMessage.addListener((message, sender, sendResponse) => {
                    if (message === 'configuration') sendResponse(payload);
                    return true;
                });
                """
        } else {
            registration = """
                api.runtime.onMessage.addListener(message =>
                    message === 'configuration' ? Promise.resolve(payload) : undefined
                );
                """
        }
        return """
            const payload = {ok: true, data: {accounts: [], vaults: [], marker: 'synthetic'}};
            const api = globalThis.\(alias);
            globalThis.__aliasesAreSame = browser === chrome;
            // An unrelated listener returning undefined must not mask the response.
            api.runtime.onMessage.addListener(() => undefined);
            \(registration)
            """
    }

    @available(macOS 15.4, *)
    private func exerciseMessaging(asynchronous: Bool, alias: String) async throws {
        let fixture = try Fixture(listener: responseListener(alias: alias, asynchronous: asynchronous))
        defer { fixture.cleanUp() }

        let storeID = UUID()
        let library = WebExtensionLibrary(rootURL: fixture.root.appending(path: "library", directoryHint: .isDirectory))
        let candidate = try await library.prepareImport(from: fixture.archive)
        let installed = try library.install(candidate, in: storeID)
        let manager = WebExtensionManager(library: library)
        let controller = try #require(manager.controller(for: storeID))
        let extensionURL = URL(string: "webkit-extension://\(installed.id.uuidString.lowercased())/")!

        var context: WKWebExtensionContext?
        for _ in 0..<100 {
            if let loaded = controller.extensionContext(for: extensionURL), loaded.isLoaded {
                context = loaded
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let loadedContext = try #require(context)
        let page = WKWebView(frame: .zero, configuration: try #require(loadedContext.webViewConfiguration))
        page.load(URLRequest(url: loadedContext.baseURL.appending(path: "page.html")))
        for _ in 0..<100 {
            if page.url?.scheme == "webkit-extension" && !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        let result = try await page.callAsyncJavaScript("""
            const timeout = new Promise((_, reject) =>
                setTimeout(() => reject(new Error('sendMessage timed out after 5 seconds')), 5000)
            );
            const response = await Promise.race([
                browser.runtime.sendMessage('configuration'), timeout
            ]);
            return { aliasesAreSame: browser === chrome, response };
            """, in: nil, contentWorld: .page) as? [String: Any]
        let value = try #require(result)
        #expect(value["aliasesAreSame"] as? Bool == true)
        let response = try #require(value["response"] as? [String: Any])
        #expect(response["ok"] as? Bool == true)
        let data = try #require(response["data"] as? [String: Any])
        #expect((data["accounts"] as? [Any])?.isEmpty == true)
        #expect((data["vaults"] as? [Any])?.isEmpty == true)
        #expect(data["marker"] as? String == "synthetic")
    }

    @Test @available(macOS 15.4, *)
    func firefoxPromiseResponsePreservesEntirePayload() async throws {
        try await exerciseMessaging(asynchronous: false, alias: "browser")
    }

    @Test @available(macOS 15.4, *)
    func chromeAsyncSendResponsePreservesEntirePayload() async throws {
        try await exerciseMessaging(asynchronous: true, alias: "chrome")
    }
}
#endif
