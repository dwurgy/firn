import Foundation
import WebKit

// Firn's own page scripts and the handlers that hear them, one per kind.
// Each lives only in Firn's content world and checks every message's world,
// shape, and (where it matters) frame and real origin before it reaches the
// page's controller (WebKitPageController.swift).

/// Tells pages when their icon links change. Its script and message channel
/// live only in Firn's content world, so the page can't post to it; even so,
/// a message counts only from the main frame, from the page's real origin
/// (WebKit's, not anything claimed), and only as the exact word "changed".
/// One watcher serves every page: popups share their opener's content
/// controller, and a handler can't be added to it twice.
@MainActor
final class IconChangeWatcher: NSObject, WKScriptMessageHandler {
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

/// Hears pages' sound (see `PageSoundScript`). Like `IconChangeWatcher`,
/// its script and handler live only in Firn's content world, so a page
/// can't post to it; a message counts only in its exact shape. It runs in
/// every frame, since sound often plays in an embedded one.
@MainActor
final class SoundWatcher: NSObject, WKScriptMessageHandler {
    static let shared = SoundWatcher()

    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let pages = NSMapTable<WKWebView, WebKitPageController>.weakToWeakObjects()

    func watch(_ webView: WKWebView, for page: WebKitPageController) {
        pages.setObject(page, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        let world = WebKitPageController.firnWorld
        controller.add(self, contentWorld: world, name: PageSoundScript.handlerName)
        controller.addUserScript(WKUserScript(
            source: PageSoundScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world
        ))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.world.name == WebKitPageController.firnWorld.name,
              let report = PageSoundScript.parse(message.body),
              let webView = message.webView, let page = pages.object(forKey: webView) else { return }
        page.heard(report, in: message.frameInfo)
    }
}

/// Notices text typed into pages and not yet sent (see `PageDraftScript`).
/// Like `SoundWatcher`, its script and handler live only in Firn's content
/// world, so a page can't post to it; a message counts only in its exact
/// shape. It runs in every frame, since editors often live in an embedded one.
@MainActor
final class DraftWatcher: NSObject, WKScriptMessageHandler {
    static let shared = DraftWatcher()

    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let pages = NSMapTable<WKWebView, WebKitPageController>.weakToWeakObjects()

    func watch(_ webView: WKWebView, for page: WebKitPageController) {
        pages.setObject(page, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        let world = WebKitPageController.firnWorld
        controller.add(self, contentWorld: world, name: PageDraftScript.handlerName)
        controller.addUserScript(WKUserScript(
            source: PageDraftScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world
        ))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.world.name == WebKitPageController.firnWorld.name,
              let report = PageDraftScript.parse(message.body),
              let webView = message.webView, let page = pages.object(forKey: webView) else { return }
        page.noticed(report)
    }
}

/// Hears sign-ins (see `SignInScript`). Like the watchers above, its script
/// and handler live only in Firn's content world, so a page can't post to
/// it; even so, a message counts only from the main frame, in its exact
/// shape, and the page checks the frame's real origin.
@MainActor
final class SignInWatcher: NSObject, WKScriptMessageHandler {
    static let shared = SignInWatcher()

    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let pages = NSMapTable<WKWebView, WebKitPageController>.weakToWeakObjects()

    func watch(_ webView: WKWebView, for page: WebKitPageController) {
        pages.setObject(page, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        let world = WebKitPageController.firnWorld
        controller.add(self, contentWorld: world, name: SignInScript.handlerName)
        controller.addUserScript(WKUserScript(
            source: SignInScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world
        ))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.world.name == WebKitPageController.firnWorld.name,
              let heard = SignInScript.parse(message.body),
              let webView = message.webView, let page = pages.object(forKey: webView) else { return }
        page.heard(heard, from: message.frameInfo.securityOrigin)
    }
}
