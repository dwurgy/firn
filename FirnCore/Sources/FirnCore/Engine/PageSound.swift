import Foundation

/// Whether a page is making sound, as its tab's speaker shows it.
public enum PageSound: Sendable {
    case silent
    case playing
    /// Playing, but muted by Firn.
    case muted
}

/// How Firn hears and mutes a page's sound. WebKit has no public way to be
/// told when a page starts playing, or to mute one, so a script in Firn's
/// own content world (the page can't see it or reach Firn through it) does
/// both, in every frame, since sound often plays in an embedded frame.
///
/// It watches the page's audio and video elements and, whenever whether any
/// of them is audible changes, tells Firn: `{frame, sounding}`. `frame` is a
/// random name the script picks once, so Firn can tell frames apart and mute
/// each. Muted elements count as sounding only if Firn muted them, so a
/// silent background video never shows a speaker.
///
/// *Known:* sound from an element the page never adds to the document, or
/// one inside a shadow root, or from Web Audio alone, isn't heard or muted.
enum PageSoundScript {
    static let handlerName = "firnSound"

    static let source = """
        (function () {
            var frame = Math.random().toString(36).slice(2, 14);
            var seen = new Set();
            var mutedByFirn = new Set();
            var pausedByFirn = new Set();
            var muted = false;
            var last = false;
            var timer = null;
            function post(sounding) {
                if (sounding === last) return;
                last = sounding;
                window.webkit.messageHandlers.firnSound.postMessage({ frame: frame, sounding: sounding });
            }
            function sounding() {
                for (var el of seen) {
                    if (!el.isConnected) { seen.delete(el); continue; }
                    if (el.paused || el.ended) continue;
                    if (mutedByFirn.has(el) || (!el.muted && el.volume > 0)) return true;
                }
                return false;
            }
            function check() {
                clearTimeout(timer);
                timer = setTimeout(function () { post(sounding()); }, 150);
            }
            function quiet(el) {
                if (!el.muted) { el.muted = true; mutedByFirn.add(el); }
            }
            function heard(event) {
                var el = event.target;
                if (!(el instanceof HTMLMediaElement)) return;
                seen.add(el);
                if (muted && !el.paused) quiet(el);
                check();
            }
            ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange'].forEach(function (name) {
                window.addEventListener(name, heard, true);
            });
            window.addEventListener('pagehide', function () { clearTimeout(timer); post(false); });
            document.querySelectorAll('audio, video').forEach(function (el) { seen.add(el); });
            window.__firnSetMuted = function (on) {
                muted = on;
                for (var el of seen) {
                    if (on && !el.paused) quiet(el);
                }
                if (!on) {
                    for (var el of mutedByFirn) el.muted = false;
                    mutedByFirn.clear();
                }
                check();
            };
            window.__firnSetPaused = function (on) {
                if (on) {
                    pausedByFirn.clear();
                    for (var el of seen) {
                        if (el.isConnected && !el.paused && !el.ended) { pausedByFirn.add(el); el.pause(); }
                    }
                } else {
                    for (var el of pausedByFirn) {
                        if (el.isConnected) { var p = el.play(); if (p) p.catch(function () {}); }
                    }
                    pausedByFirn.clear();
                }
            };
            check();
        })();
        """

    static func setMutedScript(_ muted: Bool) -> String {
        "window.__firnSetMuted && window.__firnSetMuted(\(muted))"
    }

    /// Pauses what's playing in a frame, remembering it, or plays just
    /// that again. For the mini player; the page's own media, nothing else.
    static func setPausedScript(_ paused: Bool) -> String {
        "window.__firnSetPaused && window.__firnSetPaused(\(paused))"
    }

    /// One frame's report, checked field by field: exactly a short frame
    /// name of letters and digits, and a yes or no. Anything else is nil.
    struct Report: Equatable {
        let frame: String
        let sounding: Bool
    }

    static func parse(_ body: Any) -> Report? {
        guard let dict = body as? [String: Any], dict.count == 2,
              let frame = dict["frame"] as? String, (1...16).contains(frame.count),
              frame.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let sounding = dict["sounding"] as? NSNumber,
              CFGetTypeID(sounding) == CFBooleanGetTypeID() else { return nil }
        return Report(frame: frame, sounding: sounding.boolValue)
    }

    /// How many frames one page may report; past this, new ones are ignored.
    static let frameLimit = 32
}
