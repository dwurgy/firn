import Foundation
import Testing
@testable import FirnCore

struct PageSoundTests {
    @Test func acceptsAReport() {
        let report = PageSoundScript.parse(["frame": "abc123", "sounding": true])
        #expect(report == .init(frame: "abc123", sounding: true))
    }

    @Test func refusesAnythingElse() {
        #expect(PageSoundScript.parse("playing") == nil)
        #expect(PageSoundScript.parse(["frame": "abc", "sounding": 1]) == nil)
        #expect(PageSoundScript.parse(["frame": "abc", "sounding": "yes"]) == nil)
        #expect(PageSoundScript.parse(["frame": "", "sounding": true]) == nil)
        #expect(PageSoundScript.parse(["frame": String(repeating: "a", count: 17), "sounding": true]) == nil)
        #expect(PageSoundScript.parse(["frame": "a b", "sounding": true]) == nil)
        #expect(PageSoundScript.parse(["frame": "abc", "sounding": true, "extra": 1]) == nil)
    }
}
