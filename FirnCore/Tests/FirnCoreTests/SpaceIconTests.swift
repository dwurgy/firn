import Testing
@testable import FirnCore

struct SpaceIconTests {
    @Test func sixteenIconsAndTheLeafByDefault() {
        #expect(SpaceIcon.allCases.count == 16)
        #expect(SpaceIcon.default == .leaf)
    }

    @Test func unknownNamesFallBackToTheLeaf() {
        #expect(SpaceIcon(stored: "coffee") == .coffee)
        #expect(SpaceIcon(stored: "") == .leaf)
        #expect(SpaceIcon(stored: "🍂") == .leaf)
        #expect(SpaceIcon(stored: "Coffee") == .leaf)
    }

    @Test func everyIconHasItsOwnSpokenName() {
        let names = SpaceIcon.allCases.map(\.spokenName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        // The leaf is stored as "leaf" (older sessions) but spoken as Nature.
        #expect(SpaceIcon.leaf.spokenName == "Nature")
    }
}
