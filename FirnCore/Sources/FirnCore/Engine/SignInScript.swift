import Foundation

/// How Firn notices a sign-in, so it can offer to save the password. A
/// script in Firn's own content world (the page can't see it, change it, or
/// reach Firn through it), in the main frame only, acts on real clicks and
/// keys only (`isTrusted`; a page's own script can't fake one): a form sent,
/// Enter in a password field, or a click on a button near a filled one.
///
/// Then it reads the password, and the username field (one marked as a
/// username, even hidden, as on a site's password step; else the last text
/// field before the password), and tells Firn `{kind: "submitted",
/// username, password}`. It then watches the password field for 10 seconds:
/// if it leaves the page (a site that signs in without loading a new page),
/// it tells Firn `{kind: "gone"}`. A field still there after a wrong
/// password says nothing, so nothing is offered.
///
/// For a change of password (new and confirm), the new one is read; when
/// it can't tell which field holds the password, it sends nothing.
enum SignInScript {
    static let handlerName = "firnSignIn"
    /// How long a sign-in is held, in seconds, waiting to see if it worked.
    static let pendingLimit: TimeInterval = 60

    /// What the script tells Firn.
    enum Message: Equatable {
        case submitted(username: String, password: String)
        case gone
    }

    /// The message in its exact shape, within the store's limits, or nil.
    static func parse(_ body: Any) -> Message? {
        guard let message = body as? [String: Any], let kind = message["kind"] as? String else { return nil }
        switch kind {
        case "gone":
            return message.count == 1 ? .gone : nil
        case "submitted":
            guard message.count == 3, let username = message["username"] as? String,
                  let password = message["password"] as? String, !password.isEmpty,
                  username.count <= PasswordStore.usernameLimit, password.count <= PasswordStore.passwordLimit
            else { return nil }
            return .submitted(username: username, password: password)
        default:
            return nil
        }
    }

    static let source = """
        (function () {
            var lastPost = 0, lastSent = null;
            var watching = null;
            function visible(el) {
                return el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
            }
            function autocomplete(el) {
                return (el.getAttribute('autocomplete') || '').toLowerCase();
            }
            function pickPassword(root) {
                var filled = [];
                var fields = root.querySelectorAll('input[type="password"]');
                for (var i = 0; i < fields.length; i++) {
                    if (fields[i].value && visible(fields[i])) filled.push(fields[i]);
                }
                for (var i = 0; i < filled.length; i++) {
                    if (autocomplete(filled[i]).indexOf('new-password') >= 0) return filled[i];
                }
                for (var i = 0; i < filled.length; i++) {
                    if (autocomplete(filled[i]).indexOf('current-password') >= 0) return filled[i];
                }
                if (filled.length === 1) return filled[0];
                var n = filled.length;
                if (n >= 2 && filled[n - 1].value === filled[n - 2].value) return filled[n - 1];
                return null;
            }
            function pickUsername(root, password) {
                var marked = null, before = null, passed = false;
                var inputs = root.querySelectorAll('input');
                for (var i = 0; i < inputs.length; i++) {
                    var el = inputs[i];
                    if (el === password) { passed = true; continue; }
                    if (!el.value) continue;
                    var auto = autocomplete(el);
                    if (!marked && (auto.indexOf('username') >= 0 || auto.indexOf('email') >= 0)) marked = el;
                    var type = (el.type || 'text').toLowerCase();
                    if (!passed && (type === 'text' || type === 'email' || type === 'tel') && visible(el)) before = el;
                }
                var chosen = marked || before;
                return chosen ? chosen.value.trim() : '';
            }
            function watch(field) {
                clearInterval(watching);
                var checks = 0;
                watching = setInterval(function () {
                    checks++;
                    if (!field.isConnected || !visible(field)) {
                        clearInterval(watching);
                        window.webkit.messageHandlers.firnSignIn.postMessage({ kind: 'gone' });
                    } else if (checks >= 20) {
                        clearInterval(watching);
                    }
                }, 500);
            }
            function capture(root) {
                var password = pickPassword(root);
                if (!password) return;
                var username = pickUsername(root, password);
                if (!username && root !== document) username = pickUsername(document, password);
                if (password.value.length > 1024 || username.length > 512) return;
                // Enter fires the form's submit too: one message for both.
                var now = Date.now(), sent = username + '\\n' + password.value;
                if (now - lastPost < 1000 && sent === lastSent) return;
                lastPost = now;
                lastSent = sent;
                window.webkit.messageHandlers.firnSignIn.postMessage({
                    kind: 'submitted', username: username, password: password.value
                });
                watch(password);
            }
            document.addEventListener('submit', function (event) {
                if (event.isTrusted && event.target instanceof HTMLFormElement) capture(event.target);
            }, true);
            document.addEventListener('keydown', function (event) {
                var el = event.target;
                if (event.isTrusted && event.key === 'Enter' && el instanceof HTMLInputElement && el.type === 'password') {
                    capture(el.form || document);
                }
            }, true);
            document.addEventListener('click', function (event) {
                if (!event.isTrusted || !(event.target instanceof Element)) return;
                var button = event.target.closest('button, input[type="submit"], input[type="button"], [role="button"]');
                if (button) capture(button.form || button.closest('form') || document);
            }, true);
        })();
        """
}
