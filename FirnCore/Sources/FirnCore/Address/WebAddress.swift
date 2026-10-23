import Foundation

/// Which addresses Firn will open. Only web pages (http and https) reach
/// navigation; everything else is refused (CLAUDE.md, Security).
public enum WebAddress {
    public static func isWebScheme(_ scheme: String) -> Bool {
        let scheme = scheme.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// An http or https address with a host.
    public static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme, isWebScheme(scheme),
              let host = url.host(), !host.isEmpty else { return false }
        return true
    }

    /// Just the site, as the address bar shows it at rest: "example.com",
    /// without "www.", with a port if there is one. Empty without a host.
    public static func site(of url: URL?) -> String {
        guard let url, let host = url.host(percentEncoded: false) else { return "" }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = url.port { return "\(site):\(port)" }
        return site
    }

    /// Whether two addresses belong to the same site: "mail.google.com" and
    /// "accounts.google.com" do; "google.com" and "youtube.com" don't. Firn
    /// has no list of public suffixes, so this takes the host's last two
    /// parts (three after a country pair like "co.uk"). A wrong guess only
    /// changes where a link opens, never which space's data it uses.
    public static func isSameSite(_ a: URL, _ b: URL) -> Bool {
        guard let first = siteKey(of: a), let second = siteKey(of: b) else { return false }
        return first == second
    }

    /// Second-level names that sit under a country, as in "co.uk" or "com.au".
    private static let countrySecondLevels: Set<String> = ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go"]

    private static func siteKey(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        // An IP address or a one-word host ("localhost") is a site on its own.
        if host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return host }
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        let isCountryPair = labels[labels.count - 1].count == 2
            && countrySecondLevels.contains(String(labels[labels.count - 2]))
        return labels.suffix(isCountryPair ? 3 : 2).joined(separator: ".")
    }
}

/// What a page may load into one of its frames. Pages are untrusted, so this
/// is the gate for every navigation they start, not only typed ones.
public enum NavigationPolicy {
    public static func allows(_ url: URL, isMainFrame: Bool) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https":
            return true
        case "about":
            // Blank and srcdoc frames are part of ordinary pages.
            return url.absoluteString == "about:blank" || url.absoluteString == "about:srcdoc"
        case "blob":
            // Content the page made itself, under the page's own origin.
            return true
        case "data":
            // Fine inside a frame; a whole page made of data: is a classic spoofing trick.
            return !isMainFrame
        default:
            // file:, javascript:, mailto:, other apps' schemes, and anything else.
            return false
        }
    }
}

/// Which addresses may be saved as a download: web addresses, and files a
/// page made itself (blob: and data:), which are saved but never shown.
public enum DownloadPolicy {
    public static func allows(_ url: URL) -> Bool {
        ["http", "https", "blob", "data"].contains(url.scheme?.lowercased() ?? "")
    }
}
