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
        // Summarize's plain text: the article's blocks, one per line, no
        // markup and nothing the cleaner dropped.
        let text = article.text
        #expect(text.split(separator: "\n").count > 3)
        #expect(text.contains("more notes"))
        for banned in ["<", "steal", "Footer text", "evil.test"] {
            #expect(!text.contains(banned), "\(banned) got into the text")
        }
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

/// Reader, step 3, part 1: the page Reader shows.
struct ReaderDocumentTests {
    private let page = URL(string: "https://reader.test/story")!

    private func article(
        title: String = "A Calm Morning", byline: String? = "Jane Doe", site: String? = "Snow Notes",
        excerpt: String? = nil, html: String = "<p>The snow had settled.</p>"
    ) throws -> ReaderArticle {
        var fields: [String: Any] = ["title": title, "html": html, "words": 460, "lang": "en"]
        fields["byline"] = byline
        fields["siteName"] = site
        fields["excerpt"] = excerpt
        return try #require(ReaderArticle(scriptResult: fields, pageURL: page))
    }

    @Test func escapesEverythingFromThePage() throws {
        let hostile = "</title><script>steal()</script><img src=x onerror=steal()>\"'"
        let html = ReaderDocument.html(
            for: try article(title: hostile, byline: hostile, site: hostile, excerpt: hostile),
            look: ReaderLook(), accent: 0x7F9CB0, icon: nil)
        #expect(!html.contains("<script"))
        #expect(!html.contains("<img src=x"))
        #expect(!html.contains("</title><"))
        #expect(html.contains("&lt;/title&gt;&lt;script&gt;"))
        #expect(html.contains("&quot;&#39;"))
    }

    @Test func thePolicyComesFirst() throws {
        let html = ReaderDocument.html(for: try article(), look: ReaderLook(), accent: 0x7F9CB0, icon: nil)
        let policy = try #require(html.range(of: "Content-Security-Policy"))
        let body = try #require(html.range(of: "<body>"))
        #expect(policy.lowerBound < body.lowerBound)
        #expect(ReaderDocument.contentPolicy.hasPrefix("default-src 'none'"))
        #expect(!ReaderDocument.contentPolicy.contains("script-src"))
    }

    @Test func showsTheLookAndTheLine() throws {
        let html = ReaderDocument.html(
            for: try article(), look: ReaderLook(font: .sans, size: 3), accent: 0x8FAE8B, icon: Data([1, 2, 3]))
        #expect(html.contains("class=\"sans size-3\""))
        #expect(html.contains("--space: #8FAE8B"))
        #expect(html.contains("Jane Doe · 2 min read"))
        #expect(html.contains("src=\"data:image/png;base64,AQID\""))
        #expect(html.contains("<span>Snow Notes</span>"))
        #expect(html.contains("<p>The snow had settled.</p>"))
    }

    @Test func summarizesPillOnlyWhenOffered() throws {
        let plain = ReaderDocument.html(for: try article(), look: ReaderLook(), accent: 0x7F9CB0, icon: nil)
        #expect(!plain.contains("firn-summary"))
        let offered = ReaderDocument.html(
            for: try article(), look: ReaderLook(), accent: 0x7F9CB0, icon: nil, summarize: true)
        // Under the byline, inside the heading, above the article.
        let meta = try #require(offered.range(of: "<div class=\"meta\">"))
        let slot = try #require(offered.range(of: "<div class=\"sum-slot\" id=\"firn-summary\" lang=\"en\">"))
        let head = try #require(offered.range(of: "</header>"))
        #expect(meta.lowerBound < slot.lowerBound && slot.lowerBound < head.lowerBound)
        #expect(offered.contains("data-act=\"make\""))
        // VoiceOver hears when a summary arrives, from a line inside the heading.
        let news = try #require(offered.range(of: "id=\"firn-summary-news\" lang=\"en\" aria-live=\"polite\""))
        #expect(news.lowerBound < head.lowerBound)
        // The summary is set as text by Firn's world, never written as HTML.
        #expect(ReaderDocument.summaryScript.contains("node.textContent = words"))
        #expect(!ReaderDocument.summaryScript.contains("innerHTML"))
    }

    @Test func noExcerptWhenItRepeatsTheStart() throws {
        #expect(ReaderDocument.showsExcerpt(try article(excerpt: "The snow had settled.")) == nil)
        #expect(ReaderDocument.showsExcerpt(try article(excerpt: "Why snow goes quiet.")) == "Why snow goes quiet.")
    }

    @Test func lookStaysInRange() {
        var look = ReaderLook(size: 9)
        #expect(look.size == ReaderLook.sizes.count - 1)
        #expect(!look.canGrow)
        look.size = -2
        #expect(look.size == 0)
        #expect(!look.canShrink)
        #expect(look.points == 16)
    }
}

/// Reader's own view, against real WebKit.
@MainActor
struct ReaderViewTests {
    private func paragraphs(_ count: Int) -> String {
        (1...count).map { i in
            "<p>The snow had settled overnight into a firm, quiet layer, and the morning light came slowly over "
                + "the ridge. We walked out past the cabin with coffee in hand, listening to each step. Part \(i).</p>"
        }.joined()
    }

    private func load(_ html: String, into page: WebKitPageController? = nil) async throws -> WebKitPageController {
        let page = try #require(page ?? (BrowserEngine.makePage(dataStoreID: UUID()) as? WebKitPageController))
        page.webView.loadHTMLString(html, baseURL: URL(string: "https://reader.test/\(UUID().uuidString)")!)
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<100 where page.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))
        return page
    }

    private func waitForReader(_ reader: ReaderPage) async throws {
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<100 where reader.webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func ask(_ reader: ReaderPage, _ script: String) async throws -> Any? {
        try await reader.webView.callAsyncJavaScript(
            script, arguments: [:], in: nil, contentWorld: WebKitPageController.firnWorld)
    }

    @Test func opensAndClosesWithThePage() async throws {
        let page = try await load("<html><head><title>Snow</title></head><body><article><h1>Snow</h1>\(paragraphs(10))</article></body></html>")
        let id = try #require(page.webView.configuration.websiteDataStore.identifier)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        // The check runs as loading finishes; slower while other tests run.
        for _ in 0..<100 where !page.isArticle {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(page.isArticle)
        #expect(await page.openReader(look: ReaderLook(), accent: 0x7F9CB0))
        #expect(page.isReading)
        let reader = try #require(page.reader)
        // The same space's data store, never another.
        #expect(reader.webView.configuration.websiteDataStore.identifier == id)
        #expect(!reader.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        try await waitForReader(reader)
        let words = try await ask(reader, "return document.querySelector('article').textContent.length")
        #expect(((words as? NSNumber)?.intValue ?? 0) > 1000)
        // A new look, without reloading.
        page.setReaderLook(ReaderLook(font: .sans, size: 2))
        try await Task.sleep(for: .milliseconds(200))
        #expect(try await ask(reader, "return document.documentElement.className") as? String == "sans size-2")
        // A new page always opens with Reader off.
        _ = try await load("<html><body><p>Another page.</p></body></html>", into: page)
        #expect(!page.isReading)
        #expect(page.reader == nil)
    }

    @Test func runsNoScriptsAndLoadsNothingElse() async throws {
        let page = try #require(BrowserEngine.makePage(dataStoreID: UUID()) as? WebKitPageController)
        let id = try #require(page.webView.configuration.websiteDataStore.identifier)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        // Straight in, past the cleaner, as if it had missed something.
        let fields: [String: Any] = [
            "title": "Tricks", "words": 400,
            "html": """
                <p>Text</p><script>document.title = 'ran';</script>
                <img src="x" onerror="document.title = 'ran'">
                <iframe src="https://reader.test/frame"></iframe>
                """,
        ]
        let article = try #require(ReaderArticle(scriptResult: fields, pageURL: URL(string: "https://reader.test/a")!))
        let reader = ReaderPage(article: article, page: page, look: ReaderLook(), accent: 0x7F9CB0)
        try await waitForReader(reader)
        #expect(try await ask(reader, "return document.title") as? String == "Tricks")
        // The frame was refused by the content policy: it never loaded a page.
        let framed = try await ask(reader, "return document.querySelector('iframe').contentDocument?.URL ?? ''")
        #expect((framed as? String)?.contains("reader.test") != true)
    }

    @Test func tooShortWhenReadLosesTheBook() async throws {
        // Enough paragraphs for the quick check, too few words when read.
        let short = (1...6).map { _ in "<p>" + String(repeating: "Snowfall ", count: 20) + "</p>" }.joined()
        let page = try await load("<html><body><article>\(short)</article></body></html>")
        let id = try #require(page.webView.configuration.websiteDataStore.identifier)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        page.isArticle = true // As if the quick check had passed.
        #expect(await !page.openReader(look: ReaderLook(), accent: 0x7F9CB0))
        #expect(!page.isArticle)
        #expect(!page.isReading)
    }
}
