import Foundation

/// Search suggestions from the person's own search engine, as they type in
/// the command bar. This is the one place Firn sends typing over the network,
/// so it sends as little as it can: only to the chosen engine, with no
/// cookies, sign-in, or cache (so the engine can't tie it to an account),
/// never for an address, and the reply is read as hostile input.
public enum SearchSuggestions {
    /// The most suggestions kept from one reply.
    public static let limit = 8
    /// Longer text isn't sent: it's more likely pasted than typed, and
    /// suggestions stop helping long before this.
    static let longestQuery = 100
    static let longestSuggestion = 150
    static let largestReply = 64 * 1024

    /// Whether typed text may be sent for suggestions: words, not an
    /// address, not empty, not long.
    public static func mayAsk(about text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= longestQuery && !AddressInput.isAddress(text)
    }

    /// The engine's suggestions for the text, or none if anything is off.
    /// Cancelling the task cancels the request.
    public static func fetch(_ text: String, from engine: SearchEngine) async -> [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mayAsk(about: query), let url = engine.suggestionsURL(for: query) else { return [] }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https"
        else { return [] }
        return parse(data, for: query)
    }

    /// Reads a reply shaped `["query", ["one", "two", …], …]`. Anything
    /// else, or a reply for different text, gives no suggestions. Keeps
    /// plain, short, distinct lines, minus the text itself (the bar's first
    /// row already searches for that).
    static func parse(_ data: Data, for query: String) -> [String] {
        guard data.count <= largestReply,
              let reply = try? JSONSerialization.jsonObject(with: data) as? [Any], reply.count >= 2,
              let echoed = reply[0] as? String, fold(echoed) == fold(query),
              let lines = reply[1] as? [Any]
        else { return [] }

        var seen: Set<String> = [fold(query)]
        var suggestions: [String] = []
        for case let line as String in lines {
            let clean = String(String.UnicodeScalarView(line.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            })).trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, clean.count <= longestSuggestion,
                  seen.insert(fold(clean)).inserted else { continue }
            suggestions.append(clean)
            if suggestions.count == limit { break }
        }
        return suggestions
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// No cookies, cache, or saved credentials: each request stands alone.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 3
        return URLSession(configuration: configuration)
    }()
}
