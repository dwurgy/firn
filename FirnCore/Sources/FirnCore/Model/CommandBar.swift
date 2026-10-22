import Foundation

/// Something Firn can do, found in the command bar by name. The app makes
/// the list; this only matches it.
public struct CommandAction: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Other words people might type for it ("preferences" for Settings).
    public let keywords: [String]
    /// The shortcut, shown faintly beside it ("⌘,"), if it has one.
    public let shortcut: String?

    public init(id: String, name: String, keywords: [String] = [], shortcut: String? = nil) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.shortcut = shortcut
    }
}

/// One row in the command bar.
public enum CommandRow: Identifiable {
    /// Go to the address typed.
    case go(URL)
    /// Search for the text typed, or for one of the engine's suggestions.
    case search(String, URL, isSuggestion: Bool)
    /// Show a tab or Basecamp tile already open in this space.
    case tab(Tab)
    /// Bring back a tidied-away tab.
    case tidied(Tab)
    /// Bring back something from Recently closed.
    case closed(ClosedEntry)
    case action(CommandAction)

    public var id: String {
        switch self {
        case let .go(url): "go \(url.absoluteString)"
        case let .search(text, _, isSuggestion): "\(isSuggestion ? "suggestion" : "search") \(text)"
        case let .tab(tab): "tab \(tab.id)"
        case let .tidied(tab): "tidied \(tab.id)"
        case let .closed(entry): "closed \(entry.id)"
        case let .action(action): "action \(action.id)"
        }
    }
}

/// How well typed words match a row's text. Every word typed must start a
/// word in the text ("cal bro" finds "A calm browser", "goo" finds
/// "mail.google.com"); case and accents don't matter.
public enum CommandMatch {
    /// A higher score is a better match; nil means no match.
    public static func score(_ query: String, in fields: [String]) -> Int? {
        let typed = words(in: query)
        guard !typed.isEmpty else { return nil }
        let fieldWords = fields.map(words)
        var score = 0
        for word in typed {
            var best: Int?
            for (index, field) in fieldWords.enumerated() {
                for (position, candidate) in field.enumerated() where candidate.hasPrefix(word) {
                    // Whole words, first words, and the first field count most.
                    let points = (candidate == word ? 3 : 2) + (position == 0 ? 2 : 0) + (index == 0 ? 1 : 0)
                    best = max(best ?? 0, points)
                }
            }
            guard let best else { return nil }
            score += best
        }
        // The whole text starting a field ("gmail.c" in "gmail.com") is best of all.
        let whole = fold(query.trimmingCharacters(in: .whitespaces))
        if fields.contains(where: { fold($0).hasPrefix(whole) }) { score += 10 }
        return score
    }

    static func words(in text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

extension BrowserStore {
    /// The most rows the bar shows.
    public static let commandRowLimit = 7

    /// The command bar's rows for what's typed, from the space on screen
    /// only: first the address or search, then this space's tabs, actions,
    /// its tidied-away and recently closed tabs, and the engine's
    /// suggestions (which keep up to three rows when there are some).
    /// Nothing typed, no rows.
    public func commandRows(
        for text: String,
        searchEngine: SearchEngine,
        suggestions: [String] = [],
        actions: [CommandAction] = []
    ) -> [CommandRow] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var top: [CommandRow] = []
        if let url = AddressInput.url(for: text, searchEngine: searchEngine) {
            top = AddressInput.isAddress(text) ? [.go(url)] : [.search(text, url, isSuggestion: false)]
        }

        func best<T>(_ items: [T], _ limit: Int, fields: (T) -> [String], recency: (T) -> Date = { _ in .distantPast }) -> [T] {
            items.compactMap { item in CommandMatch.score(text, in: fields(item)).map { (item, $0) } }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : recency($0.0) > recency($1.0) }
                .prefix(limit).map(\.0)
        }
        let tabFields = { (tab: Tab) in [tab.title, WebAddress.site(of: tab.url)] }

        let shown = (basecampTabs + openTabs).filter { $0.id != activeTabID }
        let tabRows = best(shown, 3, fields: tabFields, recency: \.lastActiveAt).map(CommandRow.tab)
        let actionRows = best(actions, 2, fields: { [$0.name] + $0.keywords }).map(CommandRow.action)
        let tidiedRows = best(driftedTabs, 2, fields: tabFields, recency: \.lastActiveAt).map(CommandRow.tidied)
        let closedRows = best(recentlyClosed, 2, fields: { [$0.title] }).map(CommandRow.closed)
        let pastRows = Array((tidiedRows + closedRows).prefix(2))

        let suggestionRows = suggestions.compactMap { line in
            searchEngine.searchURL(for: line).map { CommandRow.search(line, $0, isSuggestion: true) }
        }
        let room = Self.commandRowLimit - top.count
        let local = Array((tabRows + actionRows + pastRows).prefix(room - min(3, suggestionRows.count)))
        return top + local + suggestionRows.prefix(room - local.count)
    }
}
