import Testing
@testable import FirnCore

@Suite struct SidebarSizingTests {
    @Test func widthInRangeIsKept() {
        #expect(SidebarSizing.outcome(forProposedWidth: 300) == .width(300))
        #expect(SidebarSizing.outcome(forProposedWidth: 200) == .width(200))
        #expect(SidebarSizing.outcome(forProposedWidth: 360) == .width(360))
    }

    @Test func tooWideStopsAtMaximum() {
        #expect(SidebarSizing.outcome(forProposedWidth: 900) == .width(360))
    }

    @Test func narrowerHitsTheWallAtMinimum() {
        #expect(SidebarSizing.outcome(forProposedWidth: 199) == .width(200))
        #expect(SidebarSizing.outcome(forProposedWidth: 141) == .width(200))
    }

    @Test func pullingPastTheWallCollapses() {
        #expect(SidebarSizing.outcome(forProposedWidth: 139) == .collapse)
        #expect(SidebarSizing.outcome(forProposedWidth: -50) == .collapse)
    }
}
