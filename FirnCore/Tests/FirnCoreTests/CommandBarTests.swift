import Foundation
import Testing
@testable import FirnCore

@MainActor
struct CommandBarTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())
    private let work = Space(name: "Work", icon: "work", color: "sand", order: 1, dataStoreID: UUID())

    private func makeStore() -> BrowserStore {
        BrowserStore(spaces: [space, work], makePage: { FakePage(dataStoreID: $0) })
    }

    @discardableResult
    private func open(_ store: BrowserStore, _ host: String, title: String) -> Tab {
        let tab = store.openTab(URL(string: "https://\(host)/")!)
        (tab.page as? FakePage)?.title = title
        return tab
    }

    private func rows(_ store: BrowserStore, _ text: String, suggestions: [String] = [], actions: [CommandAction] = []) -> [CommandRow] {
        store.commandRows(for: text, searchEngine: .google, suggestions: suggestions, actions: actions)
    }

    // MARK: Matching

    @Test func everyTypedWordMustStartAWord() {
        #expect(CommandMatch.score("cal bro", in: ["A calm browser"]) != nil)
        #expect(CommandMatch.score("goo", in: ["Inbox", "mail.google.com"]) != nil)
        #expect(CommandMatch.score("alm", in: ["A calm browser"]) == nil)
        #expect(CommandMatch.score("calm tea", in: ["A calm browser"]) == nil)
        #expect(CommandMatch.score("  ", in: ["Anything"]) == nil)
    }

    @Test func caseAndAccentsDontMatter() {
        #expect(CommandMatch.score("CAFE", in: ["Café Firn"]) != nil)
    }

    @Test func theStartOfAFieldScoresHighest() throws {
        let start = try #require(CommandMatch.score("gmail", in: ["Gmail", "mail.google.com"]))
        let later = try #require(CommandMatch.score("mail", in: ["Gmail", "mail.google.com"]))
        #expect(start > later)
    }

    // MARK: Rows

    @Test func nothingTypedShowsNothing() {
        let store = makeStore()
        open(store, "a.example", title: "Anything")
        #expect(rows(store, "  ").isEmpty)
    }

    @Test func anAddressGoesAndWordsSearch() {
        let store = makeStore()
        guard case let .go(url) = rows(store, "example.com").first else { Issue.record("no go row"); return }
        #expect(url.absoluteString == "https://example.com")
        guard case let .search(text, url2, isSuggestion) = rows(store, "calm tea").first else { Issue.record("no search row"); return }
        #expect(text == "calm tea" && !isSuggestion)
        #expect(url2.absoluteString == "https://www.google.com/search?q=calm%20tea")
    }

    @Test func refusedAddressesGetNoTopRow() {
        let store = makeStore()
        #expect(rows(store, "javascript:alert(1)").isEmpty)
    }

    @Test func findsOpenTabsButNotTheOneOnScreen() {
        let store = makeStore()
        let mail = open(store, "mail.example", title: "Inbox")
        open(store, "news.example", title: "Calm news")
        let found = rows(store, "inbox").compactMap { if case let .tab(tab) = $0 { tab.id } else { nil } }
        #expect(found == [mail.id])
        let onScreen = rows(store, "calm").contains { if case .tab = $0 { true } else { false } }
        #expect(!onScreen)
    }

    @Test func neverShowsAnotherSpacesTabs() throws {
        let store = makeStore()
        open(store, "personal.example", title: "Secret plans")
        let closed = open(store, "closed.example", title: "Secret closed")
        open(store, "other.example", title: "Other")
        store.close(closed)
        let workSpace = try #require(store.spaces.first { $0.id == work.id })
        store.selectSpace(workSpace)
        open(store, "work.example", title: "Work things")
        #expect(rows(store, "secret").count == 1) // only the search row
    }

    @Test func findsActionsByNameOrKeyword() {
        let store = makeStore()
        let settings = CommandAction(id: "settings", name: "Settings", keywords: ["preferences"], shortcut: "⌘,")
        let found = rows(store, "prefer", actions: [settings]).contains { $0.id == "action settings" }
        #expect(found)
    }

    @Test func findsTidiedAndClosedTabs() {
        let store = makeStore()
        let old = open(store, "old.example", title: "Old recipe")
        let gone = open(store, "gone.example", title: "Gone recipe")
        open(store, "now.example", title: "Now")
        store.drift(old)
        store.close(gone)
        let ids = rows(store, "recipe").map(\.id)
        #expect(ids.contains("tidied \(old.id)"))
        #expect(ids.contains("closed \(gone.id)"))
    }

    @Test func suggestionsKeepThreeRowsAndTheLimitHolds() {
        let store = makeStore()
        for n in 0..<6 { open(store, "t\(n).example", title: "Tea \(n)") }
        let actions = (0..<3).map { CommandAction(id: "a\($0)", name: "Tea action \($0)") }
        let result = rows(store, "tea", suggestions: ["tea one", "tea two", "tea three", "tea four"], actions: actions)
        #expect(result.count == BrowserStore.commandRowLimit)
        let suggested = result.filter { if case .search(_, _, true) = $0 { true } else { false } }
        #expect(suggested.count == 3)
    }

    @Test func historyComesAfterTabsAndSkipsOpenPages() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FirnCommandHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = HistoryStore(directory: folder)
        let store = BrowserStore(spaces: [space, work], makePage: { FakePage(dataStoreID: $0) }, history: history)
        await history.record(URL(string: "https://open.example/")!, title: "Tea open", in: space.dataStoreID)
        await history.record(URL(string: "https://past.example/")!, title: "Tea past", in: space.dataStoreID)
        await history.record(URL(string: "https://work.example/")!, title: "Tea at work", in: work.dataStoreID)
        let tab = open(store, "open.example", title: "Tea open")
        open(store, "other.example", title: "Other")
        let pages = await store.historyPages(for: "tea")
        #expect(pages.map(\.title).sorted() == ["Tea open", "Tea past"])
        let ids = store.commandRows(for: "tea", searchEngine: .google, history: pages).map(\.id)
        #expect(ids == ["search tea", "tab \(tab.id)", "history https://past.example/"])
    }

    // MARK: Suggestions

    @Test func onlyWordsAreSentForSuggestions() {
        #expect(SearchSuggestions.mayAsk(about: "calm tea"))
        #expect(!SearchSuggestions.mayAsk(about: ""))
        #expect(!SearchSuggestions.mayAsk(about: "example.com"))
        #expect(!SearchSuggestions.mayAsk(about: "localhost:3000"))
        #expect(!SearchSuggestions.mayAsk(about: "https://bank.example/account?id=1"))
        #expect(!SearchSuggestions.mayAsk(about: "javascript:alert(1)"))
        #expect(!SearchSuggestions.mayAsk(about: String(repeating: "a", count: 101)))
    }

    @Test func suggestionAddressesUseTheChosenEngine() {
        #expect(SearchEngine.google.suggestionsURL(for: "c++ tea")?.host() == "suggestqueries.google.com")
        #expect(SearchEngine.duckDuckGo.suggestionsURL(for: "c++ tea")?.absoluteString
            == "https://duckduckgo.com/ac/?type=list&q=c%2B%2B%20tea")
        for engine in SearchEngine.allCases {
            #expect(engine.suggestionsURL(for: "tea")?.scheme == "https")
        }
    }

    @Test func readsAPlainReply() {
        let reply = Data(#"["calm",["calm","calm app","Calm App","calming\u0007 music",42],[],{"x":1}]"#.utf8)
        #expect(SearchSuggestions.parse(reply, for: "calm") == ["calm app", "calming music"])
    }

    @Test func refusesOddReplies() {
        #expect(SearchSuggestions.parse(Data(#"["other",["x"]]"#.utf8), for: "calm").isEmpty)
        #expect(SearchSuggestions.parse(Data(#"{"q":"calm"}"#.utf8), for: "calm").isEmpty)
        #expect(SearchSuggestions.parse(Data("<html>".utf8), for: "calm").isEmpty)
        let long = String(repeating: "x", count: 200)
        #expect(SearchSuggestions.parse(Data(#"["calm",["\#(long)"]]"#.utf8), for: "calm").isEmpty)
        let huge = Data(#"["calm",["\#(String(repeating: "y", count: 70_000))"]]"#.utf8)
        #expect(SearchSuggestions.parse(huge, for: "calm").isEmpty)
    }

    @Test func keepsAtMostTheLimit() {
        let lines = (0..<20).map { "\"calm \($0)\"" }.joined(separator: ",")
        let reply = Data(#"["calm",[\#(lines)]]"#.utf8)
        #expect(SearchSuggestions.parse(reply, for: "calm").count == SearchSuggestions.limit)
    }
}
