import Foundation

/// Where typed words go when they aren't an address. Google is the default;
/// people pick another in the welcome or Settings.
public enum SearchEngine: String, CaseIterable, Codable, Sendable, Identifiable {
    case google
    case bing
    case duckDuckGo
    case ecosia
    case yahoo

    public static let `default`: SearchEngine = .google

    public var id: String { rawValue }

    /// The name people see.
    public var name: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckDuckGo: "DuckDuckGo"
        case .ecosia: "Ecosia"
        case .yahoo: "Yahoo"
        }
    }

    public func searchURL(for query: String) -> URL? {
        let (base, parameter) = switch self {
        case .google: ("https://www.google.com/search", "q")
        case .bing: ("https://www.bing.com/search", "q")
        case .duckDuckGo: ("https://duckduckgo.com/", "q")
        case .ecosia: ("https://www.ecosia.org/search", "q")
        case .yahoo: ("https://search.yahoo.com/search", "p")
        }
        guard let encoded = Self.encode(query) else { return nil }
        return URL(string: "\(base)?\(parameter)=\(encoded)")
    }

    /// Where to ask for search suggestions. Every engine answers in the same
    /// plain format (`["query", ["one", "two", …]]`).
    public func suggestionsURL(for query: String) -> URL? {
        let base = switch self {
        case .google: "https://suggestqueries.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q="
        case .bing: "https://api.bing.com/osjson.aspx?query="
        case .duckDuckGo: "https://duckduckgo.com/ac/?type=list&q="
        case .ecosia: "https://ac.ecosia.org/autocomplete?type=list&q="
        case .yahoo: "https://search.yahoo.com/sugg/ff?output=fxjson&command="
        }
        guard let encoded = Self.encode(query) else { return nil }
        return URL(string: base + encoded)
    }

    /// Encode by hand: URLComponents leaves "+" alone, and search engines
    /// read a bare "+" as a space ("c++" would become "c  ").
    private static func encode(_ query: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?/")
        return query.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
