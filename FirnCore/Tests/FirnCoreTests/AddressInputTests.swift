import Foundation
import Testing
@testable import FirnCore

struct AddressInputTests {
    private func open(_ text: String, _ engine: SearchEngine = .default) -> String? {
        AddressInput.url(for: text, searchEngine: engine)?.absoluteString
    }

    @Test func siteDropsWWWAndKeepsThePort() {
        #expect(WebAddress.site(of: URL(string: "https://www.example.com/a?b")) == "example.com")
        #expect(WebAddress.site(of: URL(string: "http://localhost:8080/")) == "localhost:8080")
        #expect(WebAddress.site(of: nil) == "")
    }

    @Test func domainGetsHTTPS() {
        #expect(open("example.com") == "https://example.com")
        #expect(open("  news.example.co.uk/a?b=1#top  ") == "https://news.example.co.uk/a?b=1#top")
    }

    @Test func typedAddressStaysAsTyped() {
        #expect(open("http://example.com/x") == "http://example.com/x")
        #expect(open("HTTPS://example.com") == "HTTPS://example.com")
    }

    @Test func localAddressesUseHTTP() {
        #expect(open("localhost:3000") == "http://localhost:3000")
        #expect(open("192.168.1.1") == "http://192.168.1.1")
        #expect(open("firn.localhost/page") == "http://firn.localhost/page")
        #expect(open("example.com:8080") == "https://example.com:8080")
    }

    @Test func wordsBecomeAGoogleSearch() {
        #expect(open("hello") == "https://www.google.com/search?q=hello")
        #expect(open("calm browser") == "https://www.google.com/search?q=calm%20browser")
        #expect(open("999.1.1.1") == "https://www.google.com/search?q=999.1.1.1")
    }

    @Test func searchKeepsSymbols() {
        #expect(open("c++ & tea?") == "https://www.google.com/search?q=c%2B%2B%20%26%20tea%3F")
    }

    @Test func otherEngines() {
        #expect(open("tea", .duckDuckGo) == "https://duckduckgo.com/?q=tea")
        #expect(open("tea", .bing) == "https://www.bing.com/search?q=tea")
        #expect(open("tea", .ecosia) == "https://www.ecosia.org/search?q=tea")
        #expect(open("tea", .yahoo) == "https://search.yahoo.com/search?p=tea")
    }

    @Test(arguments: [
        "javascript:alert(1)", "JavaScript:alert(1)", "file:///etc/passwd", "mailto:a@example.com",
        "data:text/html,hi", "about:blank", "ftp://example.com", "zoommtg://join", "http://", "",  "   ",
    ])
    func refusesEverythingButWebPages(_ text: String) {
        #expect(open(text) == nil)
    }
}

struct NavigationPolicyTests {
    private func allows(_ text: String, mainFrame: Bool = true) -> Bool {
        NavigationPolicy.allows(URL(string: text)!, isMainFrame: mainFrame)
    }

    @Test func webPagesAndBlankFrames() {
        #expect(allows("https://example.com"))
        #expect(allows("http://example.com"))
        #expect(allows("about:blank"))
        #expect(allows("blob:https://example.com/123"))
    }

    @Test func dataOnlyInsideFrames() {
        #expect(!allows("data:text/html,hi"))
        #expect(allows("data:text/html,hi", mainFrame: false))
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "mailto:a@example.com", "zoommtg://join", "about:config"])
    func refusesTheRest(_ text: String) {
        #expect(!allows(text))
        #expect(!allows(text, mainFrame: false))
    }
}
