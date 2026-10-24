import CoreGraphics
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
///
/// For filling, a real click (or Tab) into an empty field of a sign-in form
/// (a password field, or a username field with one after it or marked as a
/// username) tells Firn only where that field is on screen,
/// `{kind: "fillable", x, y, width, height}`, never what's in the page. It
/// remembers that field and its partner; `fillSource` fills them later, once
/// someone picks a saved login. Sign-up and change-password forms (a
/// `new-password` field, or two password fields) aren't offered.
enum SignInScript {
    static let handlerName = "firnSignIn"
    /// How long a sign-in is held, in seconds, waiting to see if it worked.
    static let pendingLimit: TimeInterval = 60

    /// What the script tells Firn.
    enum Message: Equatable {
        case submitted(username: String, password: String)
        case gone
        /// A sign-in field was clicked; where it sits, in CSS pixels from
        /// the top left of the page's visible area.
        case fillable(CGRect)
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
        case "fillable":
            guard message.count == 5, let x = number(message["x"]), let y = number(message["y"]),
                  let width = number(message["width"]), let height = number(message["height"]),
                  width > 0, height > 0
            else { return nil }
            return .fillable(CGRect(x: x, y: y, width: width, height: height))
        default:
            return nil
        }
    }

    /// A finite number of a sane size, or nil. (A JavaScript number arrives
    /// as NSNumber, and so would a boolean, which isn't wanted.)
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite && abs(double) <= 100_000 ? double : nil
    }

    /// Fills the fields last offered, run with `callAsyncJavaScript` in
    /// Firn's world, main frame, with `username`, `password`, and `origin`
    /// as arguments (never pasted into the source). Only on the very origin
    /// expected. Returns whether anything was filled.
    static let fillSource = """
        if (window.location.origin !== origin || typeof window.firnFill !== 'function') return false;
        return window.firnFill(username, password);
        """

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
            // Filling. Only Firn's world can see `firnFill`; the page can't.
            var fillTarget = null;
            function textLike(el) {
                var type = (el.type || 'text').toLowerCase();
                return type === 'text' || type === 'email' || type === 'tel';
            }
            function usable(el) {
                return el && el.isConnected && !el.disabled && !el.readOnly && visible(el);
            }
            function fillFields(el) {
                if (!(el instanceof HTMLInputElement) || !usable(el) || el.value) return null;
                var root = el.form || document;
                var inputs = root.querySelectorAll('input');
                var passwords = [], marked = null, before = null, after = null, passed = false;
                for (var i = 0; i < inputs.length; i++) {
                    var field = inputs[i];
                    if (field === el) { passed = true; }
                    if (!usable(field)) continue;
                    if (field.type === 'password') {
                        if (autocomplete(field).indexOf('new-password') >= 0) return null;
                        passwords.push(field);
                        if (passed && !after && field !== el) after = field;
                    } else if (textLike(field) && field !== el) {
                        var auto = autocomplete(field);
                        if (!marked && (auto.indexOf('username') >= 0 || auto.indexOf('email') >= 0)) marked = field;
                        if (!passed) before = field;
                    }
                }
                if (passwords.length > 1) return null;
                if (el.type === 'password') return { user: marked || before, pass: el };
                if (!textLike(el)) return null;
                if (!after && autocomplete(el).indexOf('username') < 0) return null;
                return { user: el, pass: after };
            }
            function offerFill(el) {
                fillTarget = fillFields(el);
                if (!fillTarget) return;
                var r = el.getBoundingClientRect();
                window.webkit.messageHandlers.firnSignIn.postMessage({
                    kind: 'fillable', x: r.left, y: r.top, width: r.width, height: r.height
                });
            }
            function setValue(el, value) {
                // The element's own setter, so sites that watch typing
                // (React and the like) see the change, then the usual events.
                var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                el.focus();
                setter.call(el, value);
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
            }
            window.firnFill = function (username, password) {
                var target = fillTarget;
                if (!target) return false;
                var filled = false;
                if (username && usable(target.user) && textLike(target.user)) { setValue(target.user, username); filled = true; }
                if (usable(target.pass) && target.pass.type === 'password') { setValue(target.pass, password); filled = true; }
                return filled;
            };
            document.addEventListener('click', function (event) {
                if (event.isTrusted && event.target instanceof HTMLInputElement) offerFill(event.target);
            }, true);
            document.addEventListener('keyup', function (event) {
                if (event.isTrusted && event.key === 'Tab') offerFill(document.activeElement);
            }, true);
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
