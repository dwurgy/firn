import Foundation
import Testing
import WebKit
@testable import FirnCore

/// Reader, step 2: finding the article (see `Reader`).
struct ReaderArticleTests {
    private let page = URL(string: "https://reader.test/story")!

    private func fields(words: Int = 400, html: String = "<p>Text</p>") -> [String: Any] {
        ["title": "  A  Calm\nMorning ", "byline": "By Jane Doe", "siteName": NSNull(),
         "excerpt": "", "lang": "en-US", "dir": "rtl", "html": html, "words": words]
    }

    @Test func readsTheFields() throws {
        let article = try #require(ReaderArticle(scriptResult: fields(), pageURL: page))
        #expect(article.title == "A Calm Morning")
        #expect(article.byline == "By Jane Doe")
        #expect(article.siteName == nil)
        #expect(article.excerpt == nil)
        #expect(article.language == "en-US")
        #expect(article.isRightToLeft)
        #expect(article.minutesToRead == 2)
    }

    @Test func refusesAnythingElse() {
        #expect(ReaderArticle(scriptResult: nil, pageURL: page) == nil)
        #expect(ReaderArticle(scriptResult: "<p>hi</p>", pageURL: page) == nil)
        #expect(ReaderArticle(scriptResult: fields(words: Reader.minimumWords - 1), pageURL: page) == nil)
        #expect(ReaderArticle(scriptResult: fields(html: ""), pageURL: page) == nil)
        let huge = String(repeating: "a", count: Reader.maxHTMLBytes + 1)
        #expect(ReaderArticle(scriptResult: fields(html: huge), pageURL: page) == nil)
        var wrongType = fields()
        wrongType["words"] = "400"
        #expect(ReaderArticle(scriptResult: wrongType, pageURL: page) == nil)
    }

    @Test func cleansLinesFromThePage() {
        // Control characters, and direction overrides (a spoofing trick), go.
        #expect(ReaderArticle.line("a\u{0}b\u{202E}c", limit: 50) == "a b c")
        #expect(ReaderArticle.line(" \n\t ", limit: 50) == nil)
        #expect(ReaderArticle.line(String(repeating: "x", count: 20), limit: 10)?.count == 10)
        var odd = fields()
        odd["lang"] = "en\"><script>"
        odd["title"] = NSNull()
        let article = ReaderArticle(scriptResult: odd, pageURL: page)
        #expect(article?.language == nil)
        #expect(article?.title == "reader.test")
    }

    @Test func minutesNeverZero() throws {
        let article = try #require(ReaderArticle(scriptResult: fields(words: Reader.minimumWords), pageURL: page))
        #expect(article.minutesToRead == 1)
    }

    @Test func onlyWebPages() {
        #expect(Reader.canRead(URL(string: "https://example.com/a")))
        #expect(Reader.canRead(URL(string: "http://example.com/a")))
        #expect(!Reader.canRead(URL(string: "file:///Users/me/a.html")))
        #expect(!Reader.canRead(URL(string: "about:blank")))
        #expect(!Reader.canRead(nil))
    }

    @Test func scriptsAreBundled() {
        #expect(Reader.readerableScript?.contains("function isProbablyReaderable") == true)
        #expect(Reader.articleScript?.contains("function Readability") == true)
    }
}

/// The same, against real WebKit: the page's own tricks never reach the
/// article.
@MainActor
struct ReaderPageTests {
    private static let paragraph = """
        The snow had settled overnight into a firm, quiet layer, and the morning light came slowly \
        over the ridge. We walked out past the cabin with coffee in hand, listening to the soft \
        creak of each step, and talked about nothing much at all, which was exactly the point.
        """

    private static let article = """
        <!doctype html><html lang="en"><head><title>A Calm Morning | Snow Notes</title>
        <meta name="author" content="Jane Doe">
        <script>window.ranPageScript = true;</script></head>
        <body><nav><a href="/">Home</a> <a href="/about">About</a></nav>
        <article><h1>A Calm Morning</h1>
        \((1...8).map { i in "<p onclick=\"steal()\" style=\"color:red\" class=\"x\">\(paragraph) Part \(i).</p>" }.joined())
        <p>See <a href="/more" onmouseover="steal()">more notes</a>, \
        <a href="javascript:steal()">a trick</a>, and <a href="data:text/html,hi">another</a>.</p>
        <img src="/snow.jpg" alt="Snow" width="800" onerror="steal()">
        <img src="javascript:steal()" alt="Bad">
        <iframe src="https://evil.test/"></iframe>
        <script>steal()</script>
        <svg><script>steal()</script></svg>
        <form action="https://evil.test/"><input name="q"></form>
        </article><footer>Footer text</footer></body></html>
        """

    private func load(_ html: String) async throws -> (WebKitPageController, UUID) {
        let id = UUID()
        let page = try #require(BrowserEngine.makePage(dataStoreID: id) as? WebKitPageController)
        page.webView.loadHTMLString(html, baseURL: URL(string: "https://reader.test/story")!)
        // Loaded, and checked (the check runs as loading finishes).
        for _ in 0..<100 where page.url == nil || page.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))
        return (page, id)
    }

    @Test func findsTheArticleAndOnlyTheArticle() async throws {
        let (page, id) = try await load(Self.article)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        #expect(page.isArticle)
        let article = try #require(await page.readArticle())
        #expect(article.title.contains("A Calm Morning"))
        #expect(article.byline == "Jane Doe")
        #expect(article.language == "en")
        #expect(article.wordCount > 300)
        let html = article.html
        for banned in ["script", "onclick", "onmouseover", "onerror", "style=", "class=", "javascript:",
                       "data:", "iframe", "evil.test", "<form", "<input", "<svg", "steal", "Footer text"] {
            #expect(!html.contains(banned), "\(banned) got through")
        }
        #expect(html.contains("<a href=\"https://reader.test/more\">more notes</a>"))
        #expect(html.contains("a trick"))
        #expect(html.contains("src=\"https://reader.test/snow.jpg\""))
        #expect(html.contains("alt=\"Snow\""))
        #expect(!html.contains("Bad"))
        // Readability read a copy: the page itself is untouched (its nav,
        // footer, iframe, and three scripts are all still there).
        let left = try await page.webView.callAsyncJavaScript(
            "return document.querySelectorAll('nav, footer, iframe, script').length", contentWorld: .page)
        #expect((left as? NSNumber)?.intValue == 6)
    }

    @Test func aShortPageIsNoArticle() async throws {
        let (page, id) = try await load("<html><body><h1>Hi</h1><p>Just a line.</p></body></html>")
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        #expect(!page.isArticle)
        #expect(await page.readArticle() == nil)
    }
}
