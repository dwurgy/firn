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

    @Test func tilesNeverGetSmall() {
        for width in stride(from: 170.0, through: 352.0, by: 2.0) {
            for count in 1...12 {
                let layout = BasecampLayout.make(count: count, width: width)
                #expect(layout.tileSize >= BasecampLayout.minimumTile, "\(count) in \(width)")
                #expect(layout.rows.reduce(0, +) == count)
                let widest = Double(layout.rows[0])
                #expect(widest * layout.tileSize + (widest - 1) * BasecampLayout.gap <= width)
                #expect((layout.rows.max()! - layout.rows.min()!) <= 1)
            }
        }
    }

    @Test func emptyHasNoRows() {
        #expect(rows(0, 244).isEmpty)
    }
}
