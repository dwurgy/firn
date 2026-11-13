import Foundation

/// Reader: a calm, text-only view of an article (CLAUDE.md, "Reader";
/// plan in `docs/HISTORY.md`). This part finds the article; showing it is
/// the apps' job.
///
/// The finding is Mozilla's Readability.js, version 0.6.0, the heart of
/// Firefox's Reader View, bundled in `Reader/Readability/` with its license
/// (Apache 2.0) and never downloaded. From npm's `@mozilla/readability`
/// 0.6.0, sha512 `juG5VWh4qAivzTAeMzvY9xs9HY5rAcr2E4I7tiSSCokRFi7XIZCAu92ZkSTsIj1OPceCifL3cpfteP3pDT9/QQ==`.
/// To update it: replace both files from the new package, check its
/// checksum against the registry, and change the version here.
///
/// Both scripts run in Firn's own content world, so the page can't see them
/// or tamper with them, and Readability works on a copy of the page's
/// document, so nothing it does reaches the page.
public enum Reader {
    /// An article this short isn't worth a reader (a teaser, a stub, a
    /// page Readability guessed wrong about).
    public static let minimumWords = 150

    /// About how fast people read on a screen, for "minutes to read".
    static let wordsPerMinute = 230

    /// The cleaned article's largest size. Real articles are well under it;
    /// a page past it is treated as no article rather than slowing Firn.
    static let maxHTMLBytes = 3_000_000

    /// Only web pages: never Firn's own pages, files, or error pages.
    public static func canRead(_ url: URL?) -> Bool {
        guard let url else { return false }
        return WebAddress.isWebURL(url)
    }

    // MARK: Scripts

    /// Firefox's own check, the one that shows its reader icon: enough
    /// paragraphs of real text that aren't comments, sidebars, or footers.
    /// Cheap and read-only, so it runs as every page finishes loading.
    static let readerableScript: String? = bundled("Readability-readerable").map {
        $0 + "\nreturn isProbablyReaderable(document);"
    }

    /// Reads the article from a copy of the page and rebuilds its HTML from
    /// an allowlist (see `cleanerSource`). Returns the fields
    /// `ReaderArticle(scriptResult:pageURL:)` expects, or null.
    static let articleScript: String? = bundled("Readability").map {
        $0 + "\n" + cleanerSource + """

            let article;
            try {
                const copy = document.cloneNode(true);
                article = new Readability(copy, { serializer: firnClean }).parse();
            } catch (e) {
                return null;
            }
            if (!article || typeof article.content !== 'string') return null;
            const text = String(article.textContent || '').slice(0, 2000000);
            let words = 0;
            if (typeof Intl.Segmenter === 'function') {
                for (const part of new Intl.Segmenter(article.lang || undefined, { granularity: 'word' }).segment(text)) {
                    if (part.isWordLike) words += 1;
                }
            } else {
                words = text.split(/\\s+/).filter(Boolean).length;
            }
            return {
                title: article.title, byline: article.byline, siteName: article.siteName,
                excerpt: article.excerpt, lang: article.lang, dir: article.dir,
                html: article.content, words: words
            };
            """
    }

    /// Rebuilds the article in a fresh, inert document, keeping only what a
    /// reader shows: text, headings, paragraphs, lists, quotes, code, tables,
    /// pictures, and links. Scripts, styles, frames, forms, media, and
    /// anything unknown are dropped (unknown tags keep their text); every
    /// attribute is dropped except a link's address, a picture's address,
    /// size, and description, and a table cell's span. Addresses must be
    /// http or https, made absolute against the page. The reader that shows
    /// this still runs no scripts and allows nothing else (step 3).
    private static let cleanerSource = """
        const firnDrop = new Set(['script', 'style', 'noscript', 'template', 'iframe', 'frame', 'frameset',
            'object', 'embed', 'applet', 'form', 'input', 'button', 'select', 'option', 'textarea', 'label',
            'canvas', 'video', 'audio', 'source', 'track', 'link', 'meta', 'base', 'title', 'head', 'dialog',
            'svg', 'math', 'portal', 'slot']);
        const firnKeep = new Set(['p', 'br', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre',
            'code', 'em', 'i', 'strong', 'b', 'u', 's', 'del', 'ins', 'sub', 'sup', 'small', 'mark', 'q',
            'cite', 'abbr', 'kbd', 'samp', 'var', 'time', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'figure',
            'figcaption', 'img', 'a', 'table', 'caption', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td',
            'div', 'section', 'article', 'span']);
        const firnHTML = 'http://www.w3.org/1999/xhtml';
        const firnMaxDepth = 60;

        function firnWebURL(value) {
            if (typeof value !== 'string' || value.trim() === '') return null;
            try {
                const url = new URL(value.trim(), document.baseURI);
                return (url.protocol === 'http:' || url.protocol === 'https:') ? url.href : null;
            } catch (e) {
                return null;
            }
        }

        function firnNumber(value, max) {
            const number = parseInt(value, 10);
            return (number > 0 && number <= max) ? String(number) : null;
        }

        function firnImageURL(image) {
            const src = firnWebURL(image.getAttribute('src'));
            if (src) return src;
            const set = image.getAttribute('srcset') || '';
            const last = set.split(',').map((part) => part.trim().split(/\\s+/)[0]).filter(Boolean).pop();
            return firnWebURL(last);
        }

        function firnCopy(from, into, out, depth) {
            for (const child of from.childNodes) {
                if (child.nodeType === Node.TEXT_NODE) {
                    into.appendChild(out.createTextNode(child.data));
                    continue;
                }
                if (child.nodeType !== Node.ELEMENT_NODE || child.namespaceURI !== firnHTML) continue;
                const tag = child.localName;
                if (firnDrop.has(tag)) continue;
                if (depth >= firnMaxDepth) {
                    into.appendChild(out.createTextNode(child.textContent || ''));
                    continue;
                }
                if (!firnKeep.has(tag)) {
                    firnCopy(child, into, out, depth + 1);
                    continue;
                }
                const made = out.createElement(tag);
                if (tag === 'a') {
                    const href = firnWebURL(child.getAttribute('href'));
                    if (!href) {
                        firnCopy(child, into, out, depth + 1);
                        continue;
                    }
                    made.setAttribute('href', href);
                } else if (tag === 'img') {
                    const src = firnImageURL(child);
                    if (!src) continue;
                    made.setAttribute('src', src);
                    const alt = child.getAttribute('alt');
                    if (alt) made.setAttribute('alt', alt.slice(0, 500));
                    for (const name of ['width', 'height']) {
                        const size = firnNumber(child.getAttribute(name), 10000);
                        if (size) made.setAttribute(name, size);
                    }
                } else if (tag === 'td' || tag === 'th') {
                    for (const name of ['colspan', 'rowspan']) {
                        const span = firnNumber(child.getAttribute(name), 100);
                        if (span) made.setAttribute(name, span);
                    }
                } else if (tag === 'ol') {
                    const start = firnNumber(child.getAttribute('start'), 100000);
                    if (start) made.setAttribute('start', start);
                }
                into.appendChild(made);
                firnCopy(child, made, out, depth + 1);
            }
        }

        function firnClean(element) {
            const out = document.implementation.createHTMLDocument('');
            const root = out.createElement('div');
            firnCopy(element, root, out, 0);
            return root.innerHTML;
        }
        """

    private static func bundled(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Readability")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// An article as Reader shows it. Everything here came from a web page, so
/// it's checked, trimmed, and capped; the HTML is the cleaned copy (see
/// `Reader.articleScript`) and must still be shown with scripts off.
public struct ReaderArticle: Equatable, Sendable {
    public let title: String
    /// The author, as the page gives it ("By Jane Doe").
    public let byline: String?
    public let siteName: String?
    /// A sentence or two from the start, or the page's own description.
    public let excerpt: String?
    /// The article's body: cleaned HTML, links and pictures http and https.
    public let html: String
    /// The article's language, as a language tag ("en", "pt-BR").
    public let language: String?
    public let isRightToLeft: Bool
    public let wordCount: Int
    /// The page it came from, for its site and for links.
    public let pageURL: URL

    /// Rounded, and never less than one.
    public var minutesToRead: Int {
        max(1, Int((Double(wordCount) / Double(Reader.wordsPerMinute)).rounded()))
    }

    /// Reads `Reader.articleScript`'s result, or nil if it isn't exactly the
    /// shape expected, or isn't long enough to be an article.
    init?(scriptResult: Any?, pageURL: URL) {
        guard let fields = scriptResult as? [String: Any],
              let html = fields["html"] as? String,
              !html.isEmpty, html.utf8.count <= Reader.maxHTMLBytes,
              let words = (fields["words"] as? NSNumber)?.intValue,
              words >= Reader.minimumWords
        else { return nil }
        self.html = html
        wordCount = words
        self.pageURL = pageURL
        title = Self.line(fields["title"], limit: 300) ?? pageURL.host() ?? ""
        byline = Self.line(fields["byline"], limit: 200)
        siteName = Self.line(fields["siteName"], limit: 100)
        excerpt = Self.line(fields["excerpt"], limit: 500)
        language = Self.line(fields["lang"], limit: 35).flatMap {
            $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } ? $0 : nil
        }
        isRightToLeft = (fields["dir"] as? String)?.lowercased() == "rtl"
    }

    /// One plain line: whitespace and line breaks collapsed, control
    /// characters dropped, cut at `limit` characters; nil if nothing's left.
    static func line(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String else { return nil }
        let visible = value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined()
        let words = visible.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        var joined = words.joined(separator: " ")
        if joined.count > limit { joined = String(joined.prefix(limit - 1)) + "…" }
        return joined
    }
}
