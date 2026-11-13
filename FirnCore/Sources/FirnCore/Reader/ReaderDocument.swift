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
    static func html(for article: ReaderArticle, look: ReaderLook, accent: UInt32, icon: Data?) -> String {
        let site = article.siteName ?? article.pageURL.host() ?? ""
        let language = article.language.map { " lang=\"\(escape($0))\"" } ?? ""
        let direction = article.isRightToLeft ? "rtl" : "ltr"
        let iconTag = icon.map { "<img class=\"fav\" alt=\"\" src=\"data:image/png;base64,\($0.base64EncodedString())\">" } ?? ""
        let dek = showsExcerpt(article).map { "<p class=\"dek\">\(escape($0))</p>\n" } ?? ""
        let minutes = article.minutesToRead == 1 ? "1 min read" : "\(article.minutesToRead) min read"
        let meta = [article.byline, minutes].compactMap { $0 }.map(escape).joined(separator: " · ")
        let color = String(format: "#%06X", accent & 0xFFFFFF)
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
            <h1>\(escape(article.title))</h1>
            \(dek)<div class="meta">\(meta)</div>
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

    /// The approved design's reader, as one page. Colors are Firn's tokens
    /// (CLAUDE.md); the system's light and dark decide which.
    private static let style = """
        :root {
          --page: #FBFAF8; --ink: #241F1B; --muted: #5E564E; --faint: #9D9389;
          --hair: rgba(70,55,40,.12); --wash: rgba(70,55,40,.07);
          --frost: rgba(130,168,190,.45);
          color-scheme: light dark;
          --size: 19px;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --page: #2B2826; --ink: #F5F1EC; --muted: #D4CDC5; --faint: #958D85;
            --hair: rgba(255,248,240,.10); --wash: rgba(255,248,240,.07);
            --frost: rgba(160,196,214,.45);
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
        .meta {
          font: 12px/1.4 -apple-system, system-ui, sans-serif; color: var(--faint);
          padding-bottom: 22px; margin-bottom: 26px; border-bottom: 1px solid var(--hair);
        }
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
