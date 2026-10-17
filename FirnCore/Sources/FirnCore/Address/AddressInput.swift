import Foundation

/// Turns what someone typed into the address bar into the address to open.
public enum AddressInput {
    /// The address to open, or nil when there's nothing to open or the text
    /// asks for something other than a web page (javascript:, file:, mailto:,
    /// and so on), which Firn refuses.
    public static func url(for text: String, searchEngine: SearchEngine = .default) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Anything with a space in it is a search.
        if text.contains(where: \.isWhitespace) {
            return searchEngine.searchURL(for: text)
        }

        if let scheme = explicitScheme(in: text) {
            guard WebAddress.isWebScheme(scheme),
                  let url = URL(string: text), WebAddress.isWebURL(url) else { return nil }
            return url
        }

        return addressWithoutScheme(text) ?? searchEngine.searchURL(for: text)
    }

    /// The scheme the text starts with ("https" in "https://…", "javascript"
    /// in "javascript:…"), or nil. "localhost:3000" is a host and port, not a scheme.
    private static func explicitScheme(in text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) })
        else { return nil }

        let rest = text[text.index(after: colon)...]
        if rest.hasPrefix("//") { return String(scheme) }
        let port = rest.prefix { !"/?#".contains($0) }
        if !port.isEmpty, port.allSatisfy(\.isASCII), port.allSatisfy(\.isNumber) { return nil }
        return String(scheme)
    }

    /// "example.com/page" → https, "localhost:3000" or "192.168.1.1" → http,
    /// anything that doesn't look like a host → nil (it's a search).
    private static func addressWithoutScheme(_ text: String) -> URL? {
        let hostAndPort = text.prefix { !"/?#".contains($0) }
        let scheme: String
        if hostAndPort.hasPrefix("[") {
            scheme = "http" // IPv6 literal, like [::1]
        } else {
            let host = hostAndPort.prefix { $0 != ":" }.lowercased()
            if host == "localhost" || host.hasSuffix(".localhost") || isIPv4(host) {
                scheme = "http"
            } else if looksLikeDomain(host) {
                scheme = "https"
            } else {
                return nil
            }
        }
        guard let url = URL(string: "\(scheme)://\(text)"), WebAddress.isWebURL(url) else { return nil }
        return url
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCII) && (UInt8(part) != nil)
        }
    }

    private static func looksLikeDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last, last.count >= 2,
              last.allSatisfy(\.isLetter) else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
