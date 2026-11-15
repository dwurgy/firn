import Foundation
import Testing
@testable import FirnCore

/// One shared memory of guesses, so these run one at a time.
@MainActor
@Suite(.serialized)
struct InsecureFallbackTests {
    init() { InsecureFallback.forgetAll() }

    private func notSecure(_ url: URL) -> LoadError? {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted,
                            userInfo: [NSURLErrorFailingURLErrorKey: url])
        return LoadError(error, fallbackURL: nil)?.offeringInsecureFallback()
    }

    @Test func onlyHTTPSFirnAddedItselfIsAGuess() {
        #expect(AddressInput.guessedHTTPS("ipv4.download.thinkbroadband.com/5MB.zip")
            == URL(string: "https://ipv4.download.thinkbroadband.com/5MB.zip"))
        #expect(AddressInput.guessedHTTPS("  example.com  ") == URL(string: "https://example.com"))
        #expect(AddressInput.guessedHTTPS("https://example.com") == nil)
        #expect(AddressInput.guessedHTTPS("http://example.com") == nil)
        #expect(AddressInput.guessedHTTPS("localhost:3000") == nil)
        #expect(AddressInput.guessedHTTPS("192.168.1.1") == nil)
        #expect(AddressInput.guessedHTTPS("calm browser") == nil)
        #expect(AddressInput.guessedHTTPS("firn") == nil)
        #expect(AddressInput.guessedHTTPS("javascript:alert(1)") == nil)
    }

    @Test func aGuessedAddressThatFailsAsNotSecureOffersHTTP() {
        InsecureFallback.remember(typed: "ipv4.download.thinkbroadband.com/5MB.zip")
        let failed = URL(string: "https://ipv4.download.thinkbroadband.com/5MB.zip")!
        #expect(notSecure(failed)?.insecureFallback == URL(string: "http://ipv4.download.thinkbroadband.com/5MB.zip"))
    }

    @Test func aTrailingSlashAndCaseAreTheSameAddress() {
        InsecureFallback.remember(typed: "Example.com")
        #expect(notSecure(URL(string: "https://example.com/")!)?.insecureFallback == URL(string: "http://Example.com"))
    }

    @Test func typedHTTPSGetsNoFallback() {
        InsecureFallback.remember(typed: "https://example.com")
        #expect(notSecure(URL(string: "https://example.com")!)?.insecureFallback == nil)
    }

    @Test func anotherAddressGetsNoFallback() {
        InsecureFallback.remember(typed: "example.com")
        // A redirect to www, or any other page on the site.
        #expect(notSecure(URL(string: "https://www.example.com/")!)?.insecureFallback == nil)
        #expect(notSecure(URL(string: "https://example.com/other")!)?.insecureFallback == nil)
    }

    @Test func otherFailuresGetNoFallback() {
        InsecureFallback.remember(typed: "example.com")
        let failed = URL(string: "https://example.com")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                            userInfo: [NSURLErrorFailingURLErrorKey: failed])
        #expect(LoadError(error, fallbackURL: nil)?.offeringInsecureFallback().insecureFallback == nil)
        #expect(LoadError(url: failed, reason: .notAnswering, insecureFallback: failed).insecureFallback == nil)
    }

    @Test func aTypedPortStays() {
        InsecureFallback.remember(typed: "example.com:8443/a?b=1")
        #expect(notSecure(URL(string: "https://example.com:8443/a?b=1")!)?.insecureFallback
            == URL(string: "http://example.com:8443/a?b=1"))
    }

    @Test func onlyTheLastFewAreKept() {
        InsecureFallback.remember(typed: "first.com")
        for n in 0..<InsecureFallback.limit { InsecureFallback.remember(typed: "site\(n).com") }
        #expect(notSecure(URL(string: "https://first.com")!)?.insecureFallback == nil)
        #expect(notSecure(URL(string: "https://site0.com")!)?.insecureFallback == URL(string: "http://site0.com"))
    }
}
