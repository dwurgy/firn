import Foundation

/// How Firn notices text typed into a page and not yet sent (a half-written
/// email, a comment, a form), so that page never sleeps and loses it. A
/// script in Firn's own content world (the page can't see it or reach Firn
/// through it), in every frame, since editors often live in an embedded one.
///
/// It remembers the fields a person typed into and, when that might have
/// changed (typing, a form sent, the tab going out of sight), tells Firn
/// `{frame, draft}`: a random frame name and a yes or no. Never the text.
/// A field counts while it's still on the page and holds something other
/// than what the page put there; a sent email's editor goes away, and a
/// sent form's fields go back, so neither keeps the tab awake.
///
/// *Known:* a field the page empties on its own while the tab is out of
/// sight still counts until the tab is next shown, so that tab stays awake
/// a little longer than it needs to; the safe way round.
enum PageDraftScript {
    static let handlerName = "firnDraft"

    static let source = """
        (function () {
            var frame = Math.random().toString(36).slice(2, 14);
            var edited = new Set();
            var last = false;
            var timer = null;
            function post(draft) {
                if (draft === last) return;
                last = draft;
                window.webkit.messageHandlers.firnDraft.postMessage({ frame: frame, draft: draft });
            }
            function holdsText(el) {
                if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
                    return el.value.trim() !== '' && el.value !== el.defaultValue;
                }
                return el.isContentEditable && el.innerText.trim() !== '';
            }
            function hasDraft() {
                for (var el of edited) {
                    if (!el.isConnected) { edited.delete(el); continue; }
                    if (holdsText(el)) return true;
                }
                return false;
            }
            function check(wait) {
                clearTimeout(timer);
                timer = setTimeout(function () { post(hasDraft()); }, wait);
            }
            window.addEventListener('input', function (event) {
                // The field itself, even inside a shadow root.
                var el = event.composedPath()[0];
                if (!(el instanceof Element)) return;
                if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement)) {
                    el = el.closest('[contenteditable]') || el;
                    if (!el.isContentEditable) return;
                }
                edited.add(el);
                check(500);
            }, true);
            window.addEventListener('submit', function () { check(500); }, true);
            document.addEventListener('visibilitychange', function () {
                if (document.visibilityState === 'hidden') check(0);
            });
            window.addEventListener('pagehide', function () { clearTimeout(timer); post(false); });
        })();
        """

    /// One frame's report, checked field by field: exactly a short frame
    /// name of letters and digits, and a yes or no. Anything else is nil.
    struct Report: Equatable {
        let frame: String
        let draft: Bool
    }

    static func parse(_ body: Any) -> Report? {
        guard let dict = body as? [String: Any], dict.count == 2,
              let frame = dict["frame"] as? String, (1...16).contains(frame.count),
              frame.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let draft = dict["draft"] as? NSNumber,
              CFGetTypeID(draft) == CFBooleanGetTypeID() else { return nil }
        return Report(frame: frame, draft: draft.boolValue)
    }

    /// How many frames one page may report holding text; past this, new
    /// ones are ignored (the page stays awake either way).
    static let frameLimit = 32
}
