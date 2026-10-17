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
