import Foundation
import Testing
import WebKit
@testable import FirnCore

struct BlockListTests {
    private typealias Parser = BlockListConverter.Parser

    private func rules(_ list: String) throws -> [[String: Any]] {
        let json = BlockListConverter.convert(list).json
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    private func trigger(_ rule: [String: Any]) -> [String: Any] { rule["trigger"] as? [String: Any] ?? [:] }
    private func action(_ rule: [String: Any]) -> [String: Any] { rule["action"] as? [String: Any] ?? [:] }

    @Test func addressPatterns() {
        #expect(Parser.urlFilter("||ads.example.com^") == "^[^:]+://+([^:/]+\\.)?ads\\.example\\.com[/:]")
        #expect(Parser.urlFilter("/banner/*/ad.") == "/banner/.*/ad\\.")
        #expect(Parser.urlFilter("|https://x.com/a.js|") == "^https://x\\.com/a\\.js$")
        #expect(Parser.urlFilter("-ad.js^") == "-ad\\.js([^a-zA-Z0-9_.%-].*)?$")
        #expect(Parser.urlFilter("&ad_id=") == "&ad_id=")
        #expect(Parser.urlFilter("?ad=") == "\\?ad=")
        #expect(Parser.urlFilter("a|b") == nil)
        #expect(Parser.urlFilter("*") == ".*")
        #expect(Parser.urlFilter("ad\u{e9}s") == nil)
    }

    @Test func commentsAndHeadersAreNotRules() {
        let output = BlockListConverter.convert("[Adblock Plus 2.0]\n! Title: EasyList\n\n")
        #expect(output.ruleCount == 0)
        #expect(output.skipped == 0)
    }

    @Test func blockRuleOptions() throws {
        let list = "||tracker.test^$script,third-party,domain=news.test|blog.test\n||frames.test^$subdocument,image"
        let converted = try rules(list)
        #expect(converted.count == 3)
        let script = trigger(converted[0])
        #expect(script["resource-type"] as? [String] == ["script"])
        #expect(script["load-type"] as? [String] == ["third-party"])
        #expect(script["if-domain"] as? [String] == ["*blog.test", "*news.test"])
        #expect(action(converted[0])["type"] as? String == "block")
        // Frames get their own rule, so the child-frame context doesn't narrow images.
        #expect(trigger(converted[1])["resource-type"] as? [String] == ["image"])
        #expect(trigger(converted[1])["load-context"] == nil)
        #expect(trigger(converted[2])["resource-type"] as? [String] == ["document"])
        #expect(trigger(converted[2])["load-context"] as? [String] == ["child-frame"])
    }

    @Test func negatedTypesMeanEverythingElse() throws {
        let converted = try rules("||cdn.test/ad^$~script")
        let types = try #require(trigger(converted[0])["resource-type"] as? [String])
        #expect(!types.contains("script"))
        #expect(types.contains("image"))
    }

    @Test func unknownOrUnsayableRulesAreSkipped() {
        let list = """
        /banner[0-9]+/
        ||ads.test^$csp=script-src 'none'
        ||ads.test^$redirect=noop.js
        ||ads.test^$domain=a.test|~b.a.test
        example.com#?#div:-abp-has(.ad)
        example.*##.ad
        ##div:has-text(Sponsored)
        """
        let output = BlockListConverter.convert(list)
        #expect(output.ruleCount == 0)
        #expect(output.skipped == 7)
    }

    @Test func hidingRules() throws {
        let list = """
        ##.ad-box
        ##.sponsor
        news.test,blog.test##.promo
        ~shop.test##.banner
        shop.test#@#.sponsor
        """
        let converted = try rules(list)
        let selectors = converted.compactMap { action($0)["selector"] as? String }
        // A selector with an exception gets its own rule, so the exception is exact.
        let sponsor = try #require(converted.first { action($0)["selector"] as? String == ".sponsor" })
        #expect(trigger(sponsor)["unless-domain"] as? [String] == ["*shop.test"])
        #expect(selectors.contains(".ad-box"))
        let promo = try #require(converted.first { action($0)["selector"] as? String == ".promo" })
        #expect(trigger(promo)["if-domain"] as? [String] == ["*blog.test", "*news.test"])
        let banner = try #require(converted.first { action($0)["selector"] as? String == ".banner" })
        #expect(trigger(banner)["unless-domain"] as? [String] == ["*shop.test"])
    }

    @Test func anExceptionEverywhereRemovesTheSelector() throws {
        let converted = try rules("##.ad\n#@#.ad\nnews.test#@#.ad")
        #expect(converted.isEmpty)
    }

    @Test func manySelectorsShareARule() throws {
        let list = (0..<120).map { "##.ad-\($0)" }.joined(separator: "\n")
        let converted = try rules(list)
        #expect(converted.count == 3)
        #expect((action(converted[0])["selector"] as? String)?.hasPrefix(".ad-0, .ad-1, ") == true)
    }

    /// Exceptions come after what they cancel: WebKit only ignores rules above.
    @Test func exceptionsComeAfterBlocks() throws {
        let list = """
        @@||site.test^$document
        @@||cdn.test/ok.js
        ||cdn.test^
        @@||site.test^$elemhide
        ##.ad
        """
        let types = try rules(list).map { "\(action($0)["type"] ?? "")" }
        #expect(types == ["css-display-none", "ignore-previous-rules", "block", "ignore-previous-rules", "ignore-previous-rules"])
        let page = try rules(list).last.map(trigger)
        #expect(page?["url-filter"] as? String == ".*")
        #expect((page?["if-top-url"] as? [String])?.count == 1)
    }

    /// The shipped lists fit WebKit's limit, most of them converts, and WebKit
    /// compiles them. Run this after refreshing the lists.
    @MainActor @Test(arguments: BlockList.allCases)
    func shippedListsCompile(_ list: BlockList) async throws {
        let text = try #require(list.text())
        let started = Date.now
        let output = BlockListConverter.convert(text)
        let converted = Date.now.timeIntervalSince(started)
        print("\(list.rawValue): \(output.ruleCount) rules, \(output.skipped) skipped, converted in \(converted)s")
        #expect(output.ruleCount > 1_000)
        #expect(output.ruleCount <= BlockListConverter.maxRules)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FirnBlockListTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(WKContentRuleListStore(url: folder))
        let compiled = try await store.compileContentRuleList(forIdentifier: list.rawValue, encodedContentRuleList: output.json)
        print("\(list.rawValue): compiled in \(Date.now.timeIntervalSince(started) - converted)s")
        #expect(compiled != nil)
    }

    /// The real check: WebKit itself accepts everything the converter writes.
    @MainActor @Test func webKitCompilesTheRules() async throws {
        let list = """
        ||ads.example.test^
        ||tracker.test^$script,third-party,domain=news.test
        ||frames.test^$subdocument,image,~third-party
        /banner/*/ad.$image
        -ad.js^
        |https://x.test/a.js|
        ?ad_id=
        @@||cdn.test/ok.js$script
        @@||site.test^$document
        @@||site.test^$generichide
        ##.ad-box
        ##div[id^="ad-"] > a
        news.test##.promo
        ~shop.test##.banner
        """
        let output = BlockListConverter.convert(list)
        #expect(output.skipped == 0)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FirnBlockListTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try #require(WKContentRuleListStore(url: folder))
        let compiled = try await store.compileContentRuleList(forIdentifier: "test", encodedContentRuleList: output.json)
        #expect(compiled != nil)
    }
}
