import CoreGraphics
import Testing
@testable import FirnCore

struct SpaceIconTests {
    @Test func sixteenIconsAndHomeFirstAndByDefault() {
        #expect(SpaceIcon.allCases.count == 16)
        #expect(SpaceIcon.allCases.first == .home)
        #expect(SpaceIcon.default == .home)
    }

    @Test func unknownNamesFallBackToHome() {
        #expect(SpaceIcon(stored: "coffee") == .coffee)
        #expect(SpaceIcon(stored: "leaf") == .leaf)
        #expect(SpaceIcon(stored: "") == .home)
        #expect(SpaceIcon(stored: "🍂") == .home)
        #expect(SpaceIcon(stored: "Coffee") == .home)
    }

    @Test func aNewSpaceStartsOnTheNextIconNotInUse() {
        #expect(SpaceIcon.next(after: []) == .home)
        #expect(SpaceIcon.next(after: ["home"]) == .work)
        #expect(SpaceIcon.next(after: ["home", "work"]) == .reading)
        // Someone picked coffee for their second space: the gap comes first.
        #expect(SpaceIcon.next(after: ["home", "coffee"]) == .work)
        // All sixteen in use: round again.
        let all = SpaceIcon.allCases.map(\.rawValue)
        #expect(SpaceIcon.next(after: all) == .home)
        #expect(SpaceIcon.next(after: all + ["home"]) == .work)
    }

    @Test func everyIconHasItsOwnSpokenName() {
        let names = SpaceIcon.allCases.map(\.spokenName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        // The leaf is stored as "leaf" (older sessions) but spoken as Nature.
        #expect(SpaceIcon.leaf.spokenName == "Nature")
    }
}

struct SVGPathTests {
    @Test func readsCompactNumbersAndRelativeCommands() {
        // ".7.9.7" is three numbers; "l7.5 6" is relative to the last point.
        let box = SVGPath.cgPath("M9 4c-.7.9.7 1.5 0 2.6").boundingBoxOfPath
        #expect(abs(box.minY - 4) < 0.01 && abs(box.maxY - 6.6) < 0.01)
        let roof = SVGPath.cgPath("M4.5 10.5 12 4.5l7.5 6").boundingBox
        #expect(roof == CGRect(x: 4.5, y: 4.5, width: 15, height: 6))
    }

    @Test func drawsArcsOnTheirCircle() {
        // A half circle of radius 3 from (3, 6) to (9, 6), sweeping over the top.
        let box = SVGPath.cgPath("M3 6a3 3 0 0 1 6 0").boundingBoxOfPath
        #expect(abs(box.minX - 3) < 0.01 && abs(box.maxX - 9) < 0.01)
        #expect(abs(box.minY - 3) < 0.05 && abs(box.maxY - 6) < 0.01)
    }

    @Test func stopsQuietlyOnBadData() {
        #expect(SVGPath.cgPath("M1 2 L").boundingBoxOfPath.width == 0)
        #expect(SVGPath.cgPath("").isEmpty)
    }
}
