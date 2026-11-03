import Testing
@testable import FirnCore

@Suite struct BasecampLayoutTests {
    private func rows(_ count: Int, _ width: Double) -> [Int] {
        BasecampLayout.make(count: count, width: width).rows
    }

    @Test func roomyBalancesRows() {
        #expect(rows(1, 244) == [1])
        #expect(rows(4, 244) == [4])
        #expect(rows(5, 244) == [3, 2])
        #expect(rows(6, 244) == [3, 3])
        #expect(rows(7, 244) == [4, 3])
        #expect(rows(8, 244) == [4, 4])
        #expect(rows(9, 244) == [3, 3, 3])
        #expect(rows(10, 244) == [4, 3, 3])
        #expect(rows(12, 244) == [4, 4, 4])
    }

    @Test func narrowSidebarDropsToThreeColumns() {
        #expect(rows(4, 192) == [2, 2])
        #expect(rows(5, 192) == [3, 2])
        #expect(rows(12, 192) == [3, 3, 3, 3])
    }

    @Test func theLongestRowFillsTheWidth() {
        let layout = BasecampLayout.make(count: 3, width: 252)
        #expect(layout.tileWidth * 3 + BasecampLayout.gap * 2 == 252)
        #expect(BasecampLayout.make(count: 6, width: 252).height == 40 * 2 + 6)
    }

    @Test func tilesNeverGetNarrow() {
        for width in stride(from: 170.0, through: 352.0, by: 2.0) {
            for count in 1...12 {
                let layout = BasecampLayout.make(count: count, width: width)
                #expect(layout.tileWidth >= BasecampLayout.minimumWidth, "\(count) in \(width)")
                #expect(layout.rows.reduce(0, +) == count)
                let widest = Double(layout.rows[0])
                #expect(widest * layout.tileWidth + (widest - 1) * BasecampLayout.gap <= width + 0.001)
                #expect((layout.rows.max()! - layout.rows.min()!) <= 1)
            }
        }
    }

    @Test func emptyHasNoRows() {
        #expect(rows(0, 244).isEmpty)
    }

    /// The iOS brief's table (docs/IOS-BRIEF.md): iPhone up to 4 across, a
    /// narrow iPad sidebar 3 (its width allows no more), and a two-column
    /// iPad up to 6, all with iOS's 56pt minimum tile width.
    @Test func iOSMatchesTheBriefsTable() {
        func iOS(_ count: Int, _ width: Double, upTo columns: Int) -> [Int] {
            BasecampLayout.make(count: count, width: width, maximumColumns: columns, minimumWidth: 56).rows
        }
        let iPhone: [Int: [Int]] = [
            4: [4], 5: [3, 2], 6: [3, 3], 7: [4, 3], 8: [4, 4],
            9: [3, 3, 3], 10: [4, 3, 3], 11: [4, 4, 3], 12: [4, 4, 4],
        ]
        let narrowIPad: [Int: [Int]] = [
            4: [2, 2], 5: [3, 2], 6: [3, 3], 7: [3, 2, 2], 8: [3, 3, 2],
            9: [3, 3, 3], 10: [3, 3, 2, 2], 11: [3, 3, 3, 2], 12: [3, 3, 3, 3],
        ]
        let twoColumnIPad: [Int: [Int]] = [
            4: [4], 5: [5], 6: [6], 7: [4, 3], 8: [4, 4],
            9: [5, 4], 10: [5, 5], 11: [6, 5], 12: [6, 6],
        ]
        for count in 4...12 {
            #expect(iOS(count, 370, upTo: 4) == iPhone[count], "iPhone, \(count) tiles")
            #expect(iOS(count, 220, upTo: 6) == narrowIPad[count], "narrow iPad, \(count) tiles")
            #expect(iOS(count, 700, upTo: 6) == twoColumnIPad[count], "two-column iPad, \(count) tiles")
        }
    }
}
