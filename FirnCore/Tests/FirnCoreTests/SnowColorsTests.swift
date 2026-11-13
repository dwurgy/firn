import Testing
@testable import FirnCore

struct SnowColorsTests {
    private func close(_ a: [UInt32], _ b: [UInt32]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { x, y in
            [16, 8, 0].allSatisfy { shift in
                abs(Int((x >> UInt32(shift)) & 0xFF) - Int((y >> UInt32(shift)) & 0xFF)) <= 1
            }
        }
    }

    @Test func glacierIsUnchanged() {
        let snow = SnowColors.layers(space: "glacier", spaceHex: 0x7F9CB0)
        #expect(snow.light == SnowColors.glacierLight)
        #expect(snow.dark == SnowColors.glacierDark)
    }

    /// The method is proven on BRAND.md's own rows before it makes new colors.
    @Test func sageMatchesBrand() {
        let snow = SnowColors.layers(space: "sage", spaceHex: 0x8FAE8B)
        #expect(close(snow.light, [0xDAE6E8, 0xC0D5D8, 0xA1C2C6, 0x83AFB5, 0x649DA4]))
        #expect(close(snow.dark, [0x4D6A70, 0x455E63, 0x3D5257, 0x35454D, 0x32363A]))
    }

    @Test func sandMatchesBrand() {
        let snow = SnowColors.layers(space: "sand", spaceHex: 0xC9A27E)
        #expect(close(snow.light, [0xE1E3EC, 0xCCD0E0, 0xB3BAD2, 0x9CA4C4, 0x8690B7]))
        #expect(close(snow.dark, [0x5F6379, 0x55576A, 0x4B4D5D, 0x44404E, 0x373439]))
    }

    /// docs/SUNRISE-PLAN.md's table of turns.
    @Test(arguments: [
        ("lagoon", UInt32(0x6FA3A0), -14.0), ("sage", 0x8FAE8B, -28), ("dusk", 0x8E8FB8, 14),
        ("heather", 0xB88A9E, 23), ("clay", 0xB07F6A, 34), ("sand", 0xC9A27E, 38), ("ochre", 0xC4A95B, 43),
    ])
    func turnsMatchThePlan(space: String, hex: UInt32, degrees: Double) {
        let turn = SnowColors.turn(spaceHex: hex, byRose: SnowColors.warmSpaces.contains(space))
        #expect(turn.rounded() == degrees)
    }

    @Test func roundTripKeepsTheColor() {
        for hex in SnowColors.glacierLight + SnowColors.glacierDark + [0x000000, 0xFFFFFF, 0x241F1B] {
            #expect(OKLCH(hex: hex).hex == hex)
        }
    }
}
