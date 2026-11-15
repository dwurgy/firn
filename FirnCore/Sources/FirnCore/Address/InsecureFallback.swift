import Foundation

/// The addresses Firn put `https://` on itself, because someone typed one
/// without a scheme ("example.com"). If such an address then fails because
/// no secure connection could be made, the error page may offer the same
/// address over http, as Safari does. Only an offer: Firn never falls back
/// on its own, so a network can't quietly push a site onto http.
///
/// Typed `https://` addresses are never remembered: whoever typed the scheme
/// asked for a secure connection. Kept in memory only (never saved), and
/// only the last few.
@MainActor
public enum InsecureFallback {
    static let limit = 20
    private static var guesses: [(key: String, http: URL)] = []

    /// Call when typed text is opened (Go, or a Go row picked), before the
    /// load starts. Does nothing unless Firn guessed https for the text.
    public static func remember(typed text: String) {
        guard let https = AddressInput.guessedHTTPS(text),
              let key = key(for: https), let http = httpURL(for: https) else { return }
        guesses.removeAll { $0.key == key }
        guesses.append((key, http))
        if guesses.count > limit { guesses.removeFirst(guesses.count - limit) }
    }

    /// The http address to offer when `url` failed as not secure, or nil if
    /// Firn didn't guess https for it.
    public static func fallback(for url: URL) -> URL? {
        guard let key = key(for: url) else { return nil }
        return guesses.last { $0.key == key }?.http
    }

    static func forgetAll() { guesses = [] }

    /// https only; "example.com" and "example.com/" are the same address.
    private static func key(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: true)?.lowercased(), !host.isEmpty else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path(percentEncoded: true)
        let query = url.query(percentEncoded: true).map { "?\($0)" } ?? ""
        return host + port + (path.isEmpty ? "/" : path) + query
    }

    /// The same address over http. A port typed with it stays, so
    /// "example.com:8443" stays on 8443.
    private static func httpURL(for https: URL) -> URL? {
        guard var parts = URLComponents(url: https, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "http"
        guard let url = parts.url, WebAddress.isWebURL(url) else { return nil }
        return url
    }
}
