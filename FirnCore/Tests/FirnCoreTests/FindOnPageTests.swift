import Testing
@testable import FirnCore

struct FindOnPageTests {
    @Test func labels() {
        #expect(FindOnPage.label(count: 0) == "No matches")
        #expect(FindOnPage.label(count: 1) == "1 match")
        #expect(FindOnPage.label(count: 12) == "12 matches")
        #expect(FindOnPage.label(count: FindOnPage.countLimit) == "\(FindOnPage.countLimit.formatted())+ matches")
    }

    @Test func queryIsOneShortLine() {
        #expect(FindOnPage.query("calm\nbrowser") == "calm browser")
        #expect(FindOnPage.query(String(repeating: "a", count: 500)).count == FindOnPage.maxLength)
    }
}
