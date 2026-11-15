import Foundation

/// Why an address couldn't load, in plain words. Engine-neutral: the engine
/// turns its own error into this, and views only ever see this.
public struct LoadError: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case offline, noSuchSite, notAnswering, notSecure, other
    }

    /// The address that failed (always http or https).
    public let url: URL
    public let reason: Reason
    /// For a not-secure failure of an address Firn put `https://` on itself:
    /// the same address over http, to offer (never to open on its own).
    /// See `InsecureFallback`.
    public let insecureFallback: URL?

    public init(url: URL, reason: Reason, insecureFallback: URL? = nil) {
        self.url = url
        self.reason = reason
        self.insecureFallback = reason == .notSecure ? insecureFallback : nil
    }

    /// This error, with the http address to offer if Firn guessed https.
    @MainActor
    func offeringInsecureFallback() -> LoadError {
        guard reason == .notSecure, let http = InsecureFallback.fallback(for: url) else { return self }
        return LoadError(url: url, reason: reason, insecureFallback: http)
    }

    /// The error a load failed with, or nil if it isn't worth showing:
    /// a load that was cancelled or replaced isn't a failure, and an address
    /// that isn't a web address is never shown. `fallbackURL` is used when
    /// the error doesn't say which address failed.
    public init?(_ error: any Error, fallbackURL: URL?) {
        let error = error as NSError
        guard let reason = Self.reason(domain: error.domain, code: error.code) else { return nil }
        let failed = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? fallbackURL
        guard let failed, WebAddress.isWebURL(failed) else { return nil }
        self.init(url: failed, reason: reason)
    }

    /// nil for errors that mean "nothing went wrong, the load just stopped".
    static func reason(domain: String, code: Int) -> Reason? {
        switch domain {
        case NSURLErrorDomain:
            switch code {
            case NSURLErrorCancelled:
                return nil
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorCallIsActive:
                return .offline
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return .noSuchSite
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost:
                return .notAnswering
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired, NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return .notSecure
            default:
                return .other
            }
        case "WebKitErrorDomain":
            // 102: the frame load was interrupted (Firn or the page chose not
            // to load it, or another load replaced it). 204: a plug-in took over.
            return code == 102 || code == 204 ? nil : .other
        default:
            return .other
        }
    }

    /// The site as the address bar shows it at rest: no "www.", port kept.
    public var site: String {
        guard let host = url.host(percentEncoded: false) else { return url.absoluteString }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = url.port { return "\(site):\(port)" }
        return site
    }

    /// The offline line names the device; a phone may be on Wi‑Fi or
    /// cellular data. The iPad gets its own words when Firn runs there.
    #if os(iOS)
    static let offlineLine = "This iPhone seems to be offline. Check Wi‑Fi or cellular data, then try again."
    #else
    static let offlineLine = "This Mac seems to be offline. Check your Wi‑Fi, then try again."
    #endif

    public var headline: String { "Firn couldn’t reach \(site)" }

    /// The quieter way through when Firn guessed https and the site may
    /// only answer over http. Only ever a button the person presses.
    public static let continueInsecurelyTitle = "Continue Without a Secure Connection"
    public static let continueInsecurelyNote =
        "The site may not offer one. If you continue, the connection won’t be private: others on the network could see the page and anything you type into it."

    public var explanation: String {
        switch reason {
        case .offline: Self.offlineLine
        case .noSuchSite: "There’s no site at this address. Check the spelling."
        case .notAnswering: "The site isn’t answering. It may be busy or down for a moment."
        case .notSecure: "Firn couldn’t make a secure connection, so it didn’t open the page."
        case .other: "Something went wrong on the way there."
        }
    }
}
