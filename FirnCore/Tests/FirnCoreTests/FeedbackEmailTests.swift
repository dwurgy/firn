import Foundation
import Testing
@testable import FirnCore

struct FeedbackEmailTests {
    @Test func theDraftGoesToFirnsAddressWithTheDetailsAtTheBottom() throws {
        let url = FeedbackEmail.url(details: "Firn 1.0.0 (3), iOS 26.1, iPhone17,1")
        let link = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(link.scheme == "mailto")
        #expect(link.path == "hello@firnbrowser.com")
        let items = Dictionary(uniqueKeysWithValues: (link.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == "Firn feedback")
        #expect(items["body"] == "\r\n\r\n---\r\nFirn 1.0.0 (3), iOS 26.1, iPhone17,1")
        // Spaces and line breaks are escaped, so every mail app reads it whole.
        #expect(!url.absoluteString.contains(" "))
        #expect(url.absoluteString.contains("%0D%0A"))
    }

    @Test func theDetailsNameOnlyVersionsAndTheModel() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "7"]
        let line = FeedbackEmail.details(
            info: info,
            system: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0),
            model: "iPhone17,1"
        )
        #expect(line.hasPrefix("Firn 1.2.0 (7), "))
        #expect(line.hasSuffix(" 26.1, iPhone17,1"))
    }

    @Test func aPatchVersionShowsAndAMissingModelLeavesNoComma() {
        let line = FeedbackEmail.details(
            info: nil,
            system: OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 1),
            model: ""
        )
        #expect(line.hasPrefix("Firn ? (?), "))
        #expect(line.hasSuffix(" 15.6.1"))
    }

    @Test func thisDeviceHasAModel() {
        #expect(!FeedbackEmail.model.isEmpty)
    }
}
