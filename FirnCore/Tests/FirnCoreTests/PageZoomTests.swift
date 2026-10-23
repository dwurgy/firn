import Testing
@testable import FirnCore

struct PageZoomTests {
    @Test func stepsUpAndDown() {
        #expect(PageZoom.larger(than: 1) == 1.15)
        #expect(PageZoom.smaller(than: 1) == 0.85)
        #expect(PageZoom.larger(than: 3) == nil)
        #expect(PageZoom.smaller(than: 0.5) == nil)
    }

    @Test func offStepZoomGoesToTheNearestStepThatWay() {
        #expect(PageZoom.larger(than: 1.1) == 1.15)
        #expect(PageZoom.smaller(than: 1.1) == 1)
    }

    @Test func percentAndActualSize() {
        #expect(PageZoom.percent(1.25) == "125%")
        #expect(PageZoom.percent(0.85) == "85%")
        #expect(PageZoom.isActualSize(1))
        #expect(!PageZoom.isActualSize(1.15))
    }
}
