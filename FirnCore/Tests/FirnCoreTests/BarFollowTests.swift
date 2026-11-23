import CoreGraphics
import Testing
@testable import FirnCore

struct BarFollowTests {
    @Test func aWobbleNeverMovesTheBar() {
        var bar = BarFollow()
        #expect(bar.scrolled(by: 10) == nil)
        #expect(bar.scrolled(by: -6) == nil)
        #expect(bar.scrolled(by: 10) == nil)
    }

    @Test func scrollingDownFollowsAThirdOfTheWayThenShrinks() {
        var bar = BarFollow()
        #expect(bar.scrolled(by: 15) == nil)
        #expect(bar.scrolled(by: 15) == .follow(shrink: true, lead: 0.5 / 3))
        #expect(bar.scrolled(by: 9) == .follow(shrink: true, lead: 0.8 / 3))
        #expect(bar.scrolled(by: 6) == .shrink)
        #expect(bar.small)
        #expect(!bar.following)
    }

    @Test func aFastFlickShrinksAtOnce() {
        var bar = BarFollow()
        #expect(bar.scrolled(by: 80) == .shrink)
    }

    @Test func turningBackWhileFollowingPutsTheBarBack() {
        var bar = BarFollow()
        _ = bar.scrolled(by: 30)
        #expect(bar.scrolled(by: -6) == .follow(shrink: true, lead: 0.3 / 3))
        #expect(bar.scrolled(by: -12) == .back)
        #expect(!bar.small)
        // Already back: no second word.
        #expect(bar.scrolled(by: -12) == nil)
    }

    @Test func lettingGoWhileFollowingPutsTheBarBack() {
        var bar = BarFollow()
        _ = bar.scrolled(by: 30)
        #expect(bar.stopped() == .back)
        #expect(bar.stopped() == nil)
        // The next scroll starts from nothing.
        #expect(bar.scrolled(by: 10) == nil)
    }

    @Test func scrollingUpTakesLongerToStartAndLetsGoSooner() {
        var bar = BarFollow(small: true)
        #expect(bar.scrolled(by: -50) == nil)
        guard case let .follow(shrink, lead)? = bar.scrolled(by: -17.5) else {
            Issue.record("the bar should be following")
            return
        }
        #expect(!shrink)
        #expect(abs(lead - 0.5 / 6) < 0.0001)
        #expect(bar.scrolled(by: -20) == .grow)
        #expect(!bar.small)
    }

    @Test func theTopOfThePageAlwaysGrowsTheBar() {
        var small = BarFollow(small: true)
        #expect(small.reachedTop() == .grow)
        #expect(small.reachedTop() == nil)

        var shrinking = BarFollow()
        _ = shrinking.scrolled(by: 30)
        #expect(shrinking.reachedTop() == .back)

        var growing = BarFollow(small: true)
        _ = growing.scrolled(by: -70)
        #expect(growing.reachedTop() == .grow)
    }

    @Test func aChangeFromElsewhereIsTakenAtRestOnly() {
        var bar = BarFollow(small: true)
        bar.rests(small: false)
        #expect(!bar.small)
        _ = bar.scrolled(by: 30)
        bar.rests(small: true)
        #expect(!bar.small)
        #expect(bar.following)
    }
}
