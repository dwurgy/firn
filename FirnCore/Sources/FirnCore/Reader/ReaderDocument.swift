import Foundation

/// How Reader's text looks: the only two choices, Serif or Sans and a text
/// size. One setting for the whole app, kept on this device only (never
/// synced, never per site).
public struct ReaderLook: Equatable, Sendable {
    public enum Font: String, Sendable, CaseIterable {
        /// New York.
        case serif
        /// SF.
        case sans
    }

    /// The text sizes, in points (the approved design's S, M, L, and XL).
    public static let sizes = [16, 19, 22, 26]

    public var font: Font
    /// An index into `sizes`.
    public var size: Int {
        didSet { size = Self.clamped(size) }
    }

    public init(font: Font = .serif, size: Int = 1) {
        self.font = font
        self.size = Self.clamped(size)
    }

    public var points: Int { Self.sizes[size] }
    public var canGrow: Bool { size < Self.sizes.count - 1 }
    public var canShrink: Bool { size > 0 }

    /// The classes on the reader's root element that pick this look.
    var rootClasses: String { "\(font.rawValue) size-\(size)" }

    private static func clamped(_ size: Int) -> Int {
        min(max(size, 0), sizes.count - 1)
    }

    // MARK: Saved

    private static let fontKey = "readerFont"
    private static let sizeKey = "readerSize"

    /// The look last picked, or the default (Serif, M).
    public static var saved: ReaderLook {
        get {
            let defaults = UserDefaults.standard
            let font = defaults.string(forKey: fontKey).flatMap(Font.init(rawValue:)) ?? .serif
            let size = defaults.object(forKey: sizeKey) as? Int ?? 1
            return ReaderLook(font: font, size: size)
        }
        set {
            UserDefaults.standard.set(newValue.font.rawValue, forKey: fontKey)
            UserDefaults.standard.set(newValue.size, forKey: sizeKey)
        }
    }
}

/// The page Reader shows: the article on warm paper, in one narrow column
/// (the approved design, `docs/reader-design.html`). Everything from the
/// web page is escaped here, except the article's body, which
/// `Reader.articleScript` already rebuilt from an allowlist. The page is
/// then shown with scripts off, and its content policy lets nothing load
/// but pictures.
enum ReaderDocument {
    /// What the reader may load: http and https pictures (the article's),
    /// and the site's icon, which Firn hands over as data. No scripts,
    /// styles from elsewhere, frames, fonts, forms, or anything else.
    static let contentPolicy =
        "default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'; "
        + "base-uri 'none'; form-action 'none'; frame-src 'none'"

    /// - Parameters:
    ///   - accent: the space's color (0xRRGGBB), for link underlines and a
    ///     quote's line.
    ///   - icon: the site's icon as PNG (Firn's own, at most 64px), or nil.
    ///   - summarize: whether Summarize's pill sits under the byline
    ///     (`ArticleSummarizer.isOffered`).
    static func html(
        for article: ReaderArticle, look: ReaderLook, accent: UInt32, icon: Data?, summarize: Bool = false
    ) -> String {
        let site = article.siteName ?? article.pageURL.host() ?? ""
        let language = article.language.map { " lang=\"\(escape($0))\"" } ?? ""
        let direction = article.isRightToLeft ? "rtl" : "ltr"
        let iconTag = icon.map { "<img class=\"fav\" alt=\"\" src=\"data:image/png;base64,\($0.base64EncodedString())\">" } ?? ""
        let dek = showsExcerpt(article).map { "<p class=\"dek\">\(escape($0))</p>\n" } ?? ""
        let minutes = article.minutesToRead == 1 ? "1 min read" : "\(article.minutesToRead) min read"
        let meta = [article.byline, minutes].compactMap { $0 }.map(escape).joined(separator: " · ")
        let color = String(format: "#%06X", accent & 0xFFFFFF)
        let slot = summarize ? "\n<div class=\"sum-slot\" id=\"firn-summary\">\(pill)</div>" : ""
        return """
            <!doctype html>
            <html\(language) dir="\(direction)" class="\(look.rootClasses)">
            <head>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="\(contentPolicy)">
            <meta name="referrer" content="no-referrer">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(escape(article.title))</title>
            <style>:root { --space: \(color); }
            \(style)</style>
            </head>
            <body>
            <main class="column">
            <div class="site">\(iconTag)<span>\(escape(site))</span></div>
            <header class="head">
            <h1>\(escape(article.title))</h1>
            \(dek)<div class="meta">\(meta)</div>\(slot)
            </header>
            <article>
            \(article.html)
            </article>
            </main>
            </body>
            </html>
            """
    }

    /// The excerpt, unless it's only the article's first lines again
    /// (Readability falls back to the first paragraph when a page has no
    /// description of its own).
    static func showsExcerpt(_ article: ReaderArticle) -> String? {
        guard let excerpt = article.excerpt else { return nil }
        let start = String(excerpt.prefix(60))
        let body = article.html.prefix(4000)
        if body.contains(escape(start)) || body.contains(start) { return nil }
        return excerpt
    }

    /// Text from a web page, safe inside HTML text and quoted attributes.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Changes the look of a reader already showing; run in Firn's world
    /// with `classes` passed as an argument, never written into the code.
    static let setLookScript = "document.documentElement.className = classes;"

    // MARK: Summarize

    /// SF Symbols' "text.append", drawn for the web page (the approved
    /// design's stand-in: three lines, the last one short, with a plus).
    private static let glyph = """
        <svg class="glyph" aria-hidden="true" viewBox="0 0 16 16" fill="none" stroke="currentColor" \
        stroke-width="1.4" stroke-linecap="round"><path d="M2.5 4h11M2.5 8h11M2.5 12h5.5M11.5 10.5v3M10 12h3"/></svg>
        """

    /// The suggestion, as the reader first shows it.
    private static let pill =
        "<button class=\"suggest\" type=\"button\" data-act=\"make\">\(glyph)Summarize</button>"

    /// Hears the pill and the card's ✕. Runs in Firn's world (the reader's
    /// page runs no scripts of its own), only on people's own clicks inside
    /// the slot, and posts only the button's fixed word, "make" or "hide".
    static let summaryListenerScript = """
        (function () {
            var slot = document.getElementById('firn-summary');
            if (!slot) return;
            slot.addEventListener('click', function (event) {
                if (!event.isTrusted || !(event.target instanceof Element)) return;
                var button = event.target.closest('button[data-act]');
                if (!button || !slot.contains(button)) return;
                window.webkit.messageHandlers.firnSummary.postMessage(button.dataset.act);
            });
        })();
        """

    /// Shows the slot's state: `state` is "offered", "making", "made", or
    /// "failed"; `text` the summary, set as plain text, never as HTML;
    /// `device` "Mac", "iPhone", or "iPad"; `grow` whether the card grows
    /// out of the pill (not when it only changes state); `settle` whether
    /// the sentences settle in (only the first time). Run in Firn's world
    /// with these as arguments, never written into the code.
    static let summaryScript = """
        var slot = document.getElementById('firn-summary');
        if (!slot) return;
        var glyph = \(jsString(glyph));
        var hadFocus = slot.contains(document.activeElement);
        slot.textContent = '';
        function el(tag, cls, words) {
            var node = document.createElement(tag);
            if (cls) node.className = cls;
            if (words) node.textContent = words;
            return node;
        }
        function top(label) {
            var row = el('div', 'card-top');
            row.insertAdjacentHTML('beforeend', glyph);
            row.appendChild(el('span', null, label));
            var x = el('button', 'x');
            x.type = 'button';
            x.dataset.act = 'hide';
            x.setAttribute('aria-label', 'Hide Summary');
            x.insertAdjacentHTML('beforeend', \(jsString(xmark)));
            row.appendChild(x);
            return row;
        }
        var focus = null;
        if (state === 'offered') {
            var pill = el('button', 'suggest');
            pill.type = 'button';
            pill.dataset.act = 'make';
            pill.insertAdjacentHTML('beforeend', glyph);
            pill.appendChild(document.createTextNode('Summarize'));
            slot.appendChild(pill);
            focus = pill;
        } else {
            var card = el('div', grow ? 'card' : 'card still');
            if (state === 'making') {
                card.setAttribute('role', 'status');
                card.setAttribute('aria-label', 'Summarizing');
                card.appendChild(top('Summarizing…'));
                var lines = el('div', 'making');
                lines.setAttribute('aria-hidden', 'true');
                lines.appendChild(el('i')); lines.appendChild(el('i')); lines.appendChild(el('i'));
                card.appendChild(lines);
            } else if (state === 'failed') {
                card.setAttribute('role', 'status');
                card.appendChild(top('Summary'));
                card.appendChild(el('p', 'fail', 'Couldn’t summarize this article.'));
            } else {
                card.appendChild(top('Summary'));
                card.appendChild(el('p', settle ? 'prose settle' : 'prose', text));
                card.appendChild(el('div', 'foot', 'Made on this ' + device + ' by Apple Intelligence. It can make mistakes.'));
            }
            slot.appendChild(card);
            focus = card.querySelector('.x');
        }
        if (hadFocus && focus) focus.focus();
        """

    private static let xmark = """
        <svg aria-hidden="true" viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1.5" \
        stroke-linecap="round"><path d="M1.5 1.5l7 7M8.5 1.5l-7 7"/></svg>
        """

    /// Firn's own fixed markup as a JavaScript string literal.
    private static func jsString(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ") + "'"
    }

    /// The approved design's pill and card (`docs/summarize-design.html`).
    private static let summaryStyle = """
        .sum-slot { margin-top: 14px; }
        .suggest {
          display: inline-flex; align-items: center; gap: 7px; height: 30px; padding: 0 13px 0 11px;
          border: 0; border-radius: 15px; background: var(--wash); color: var(--muted);
          font: 500 13px/1 -apple-system, system-ui, sans-serif; cursor: pointer;
          transition: background .15s ease-out, color .15s ease-out;
        }
        .suggest:hover { background: var(--press); color: var(--ink); }
        .suggest:focus-visible, .card-top .x:focus-visible { outline: 3px solid var(--frost); outline-offset: 2px; }
        .glyph { width: 15px; height: 15px; flex: none; }
        .card {
          border-radius: 14px; background: var(--card); box-shadow: inset 0 0 0 .5px var(--hair);
          padding: 14px 18px; overflow: hidden;
          animation: grow .26s cubic-bezier(.2,.8,.2,1) both;
        }
        .card.still { animation: none; }
        @keyframes grow {
          from { clip-path: inset(0 calc(100% - 128px) calc(100% - 30px) 0 round 15px); opacity: .6; }
          to { clip-path: inset(0 0 0 0 round 14px); opacity: 1; }
        }
        .card-top {
          display: flex; align-items: center; gap: 7px; height: 22px; color: var(--muted);
          font: 600 12px/1 -apple-system, system-ui, sans-serif; letter-spacing: .01em;
        }
        .card-top .x {
          margin-inline-start: auto; width: 24px; height: 24px; border-radius: 12px; border: 0;
          background: transparent; color: var(--faint); display: grid; place-items: center; cursor: pointer; padding: 0;
        }
        .card-top .x:hover { background: var(--wash); color: var(--ink); }
        .card-top .x svg { width: 10px; height: 10px; }
        .prose { margin: 10px 0 0; font-size: .92em; line-height: 1.5; text-wrap: pretty; hyphens: manual; }
        .prose.settle {
          -webkit-mask-image: linear-gradient(to bottom, #000 0%, #000 45%, transparent 55%);
          -webkit-mask-size: 100% 220%; -webkit-mask-repeat: no-repeat;
          animation: settle .9s ease-out both;
        }
        @keyframes settle { from { -webkit-mask-position: 0 100%; } to { -webkit-mask-position: 0 0; } }
        .foot { margin-top: 6px; font: 11px/1.4 -apple-system, system-ui, sans-serif; color: var(--faint); }
        .making { margin: 12px 0 4px; }
        .making i { display: block; height: 10px; border-radius: 5px; margin-bottom: 11px; background: var(--wash); position: relative; overflow: hidden; }
        .making i:nth-child(1) { width: 92%; } .making i:nth-child(2) { width: 78%; }
        .making i:nth-child(3) { width: 58%; margin-bottom: 4px; }
        .making i::after {
          content: ""; position: absolute; inset: 0; transform: translateX(-100%);
          background: linear-gradient(90deg, transparent, color-mix(in srgb, var(--page) 70%, transparent), transparent);
          animation: sheen 1.6s ease-in-out infinite;
        }
        @keyframes sheen { to { transform: translateX(100%); } }
        .fail { margin: 8px 0 2px; font: 13px/1.45 -apple-system, system-ui, sans-serif; color: var(--muted); }
        @media (prefers-reduced-motion: reduce) {
          .suggest { transition: none; }
          .card { animation: fade .3s ease-out both; }
          .prose.settle { -webkit-mask-image: none; animation: fade .3s ease-out both; }
          .making i::after { display: none; }
          @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
        }
        """

    /// The approved design's reader, as one page. Colors are Firn's tokens
    /// (CLAUDE.md); the system's light and dark decide which.
    private static let style = """
        :root {
          --page: #FBFAF8; --ink: #241F1B; --muted: #5E564E; --faint: #9D9389;
          --hair: rgba(70,55,40,.12); --wash: rgba(70,55,40,.07); --press: rgba(70,55,40,.13);
          --frost: rgba(130,168,190,.45);
          --card: color-mix(in srgb, var(--ink) 4%, var(--page));
          color-scheme: light dark;
          --size: 19px;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --page: #2B2826; --ink: #F5F1EC; --muted: #D4CDC5; --faint: #958D85;
            --hair: rgba(255,248,240,.10); --wash: rgba(255,248,240,.07); --press: rgba(255,248,240,.13);
            --frost: rgba(160,196,214,.45);
            --card: color-mix(in srgb, var(--ink) 5%, var(--page));
          }
          img { filter: brightness(.92); }
        }
        .size-0 { --size: 16px; } .size-1 { --size: 19px; } .size-2 { --size: 22px; } .size-3 { --size: 26px; }
        * { box-sizing: border-box; }
        html { background: var(--page); -webkit-text-size-adjust: 100%; }
        body {
          margin: 0; padding: 64px 48px 80px;
          background: var(--page); color: var(--ink);
          font-family: ui-serif, "New York", Georgia, serif;
          font-size: var(--size); line-height: 1.6;
          overflow-wrap: break-word;
        }
        .sans body { font-family: -apple-system, system-ui, sans-serif; font-size: calc(var(--size) - 1px); line-height: 1.55; }
        @media (max-width: 600px) { body { padding: 28px 20px 64px; } }
        ::selection { background: var(--frost); }
        .column { max-width: 34em; margin: 0 auto; }
        .site {
          font: 500 12px/1.4 -apple-system, system-ui, sans-serif; color: var(--muted);
          display: flex; align-items: center; gap: 8px; margin-bottom: 14px;
        }
        .site .fav { width: 16px; height: 16px; border-radius: 4px; margin: 0; filter: none; }
        h1 {
          font-weight: 600; font-size: 1.75em; line-height: 1.18; letter-spacing: -0.01em;
          margin: 0 0 12px; text-wrap: balance;
        }
        .sans h1 { letter-spacing: -0.02em; }
        .dek { color: var(--muted); font-size: 1.05em; line-height: 1.45; margin: 0 0 16px; }
        .meta { font: 12px/1.4 -apple-system, system-ui, sans-serif; color: var(--faint); }
        .head { padding-bottom: 22px; margin-bottom: 26px; border-bottom: 1px solid var(--hair); }
        \(summaryStyle)
        p { margin: 0 0 1.05em; hyphens: auto; }
        a {
          color: inherit; text-decoration: underline;
          text-decoration-color: color-mix(in srgb, var(--space) 70%, transparent);
          text-decoration-thickness: 1.5px; text-underline-offset: 3px;
        }
        article h1, h2 { font-weight: 600; font-size: 1.2em; line-height: 1.3; margin: 1.6em 0 .5em; letter-spacing: 0; }
        h3, h4, h5, h6 { font-weight: 600; font-size: 1.05em; line-height: 1.35; margin: 1.4em 0 .4em; }
        blockquote {
          margin: 1.4em 0; padding: 0; padding-inline-start: 1em;
          border-inline-start: 2px solid color-mix(in srgb, var(--space) 60%, transparent);
          color: var(--muted); font-style: italic;
        }
        .sans blockquote { font-style: normal; }
        ul, ol { margin: 0 0 1.05em; padding-inline-start: 1.4em; }
        li { margin: 0 0 .35em; }
        figure { margin: 1.6em 0; }
        img { max-width: 100%; height: auto; border-radius: 10px; display: block; margin: 1.2em auto; }
        figure img { margin: 0 auto; }
        figcaption { font: 13px/1.45 -apple-system, system-ui, sans-serif; color: var(--muted); margin-top: 8px; }
        hr { border: 0; border-top: 1px solid var(--hair); margin: 2em 0; }
        pre, code, kbd, samp { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .85em; }
        pre { background: var(--wash); border-radius: 8px; padding: 12px 14px; overflow-x: auto; line-height: 1.45; }
        :not(pre) > code { background: var(--wash); border-radius: 4px; padding: .1em .3em; }
        table {
          display: block; overflow-x: auto; border-collapse: collapse; margin: 1.4em 0;
          font: 14px/1.45 -apple-system, system-ui, sans-serif;
        }
        th, td { border-bottom: 1px solid var(--hair); padding: 6px 10px; text-align: start; vertical-align: top; }
        th { font-weight: 600; }
        caption { color: var(--muted); padding-bottom: 6px; text-align: start; }
        mark { background: var(--frost); color: inherit; }
        """
}
