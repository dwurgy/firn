import Foundation

/// Where typed words go when they aren't an address. Google is the default;
/// the welcome and Settings will let people pick another one later.
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
        // Encode by hand: URLComponents leaves "+" alone, and search engines
        // read a bare "+" as a space ("c++" would become "c  ").
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?/")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(base)?\(parameter)=\(encoded)")
    }
}
