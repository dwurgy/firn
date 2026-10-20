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

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
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

    public var headline: String { "Firn couldn’t reach \(site)" }

    public var explanation: String {
        switch reason {
        case .offline: "This Mac seems to be offline. Check your Wi‑Fi, then try again."
        case .noSuchSite: "There’s no site at this address. Check the spelling."
        case .notAnswering: "The site isn’t answering. It may be busy or down for a moment."
        case .notSecure: "Firn couldn’t make a secure connection, so it didn’t open the page."
        case .other: "Something went wrong on the way there."
        }
    }
}
