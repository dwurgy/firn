import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FirnCore

struct IconColorTests {
    /// Premultiplied RGBA pixels: `count` of each (red, green, blue, alpha).
    private func pixels(_ runs: [(Int, UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        runs.flatMap { run in Array(repeating: [run.1, run.2, run.3, run.4], count: run.0).flatMap { $0 } }
    }

    private func hue(_ color: IconColor.RGB) -> Double {
        IconColor.HSB(red: color.red, green: color.green, blue: color.blue).hue
    }

    @Test func seeThroughIconsHaveNoColor() {
        #expect(IconColor.pick(rgba: pixels([(100, 0, 0, 0, 0)])) == nil)
        #expect(IconColor.pick(rgba: []) == nil)
    }

    @Test func blackWhiteAndGreyIconsHaveNoColor() {
        let octocat = pixels([(60, 0, 0, 0, 255), (30, 255, 255, 255, 255), (10, 128, 128, 128, 255)])
        #expect(IconColor.pick(rgba: octocat) == nil)
    }

    @Test func aSpeckOfColorIsNotEnough() {
        #expect(IconColor.pick(rgba: pixels([(97, 255, 255, 255, 255), (3, 0, 0, 255, 255)])) == nil)
    }

    @Test func brightRedIsCalmedNotNeon() throws {
        let youtube = try #require(IconColor.pick(rgba: pixels([(60, 255, 0, 0, 255), (40, 255, 255, 255, 255)])))
        let hsb = IconColor.HSB(red: youtube.red, green: youtube.green, blue: youtube.blue)
        #expect(hue(youtube) < 0.02 || hue(youtube) > 0.98)
        #expect(hsb.saturation <= 0.5 + 1e-9)
        #expect(hsb.brightness <= 0.8 + 1e-9)
    }

    @Test func theMainHueWins() throws {
        let color = try #require(IconColor.pick(rgba: pixels([(60, 240, 140, 30, 255), (25, 30, 90, 220, 255)])))
        #expect(abs(hue(color) - 26.0 / 360) < 0.03)  // orange, not blue
    }

    @Test func halfSeeThroughPixelsKeepTheirColor() throws {
        // Premultiplied: (128, 0, 0, 128) is full red at half strength.
        let color = try #require(IconColor.pick(rgba: pixels([(50, 0, 128, 0, 128)])))
        #expect(abs(hue(color) - 1.0 / 3) < 0.02)
    }

    @Test func readsAPNG() throws {
        let png = try #require(Self.png(red: 0.1, green: 0.6, blue: 0.3))
        let colors = try #require(IconColor.from(png: png))
        #expect(abs(hue(colors.main) - 0.4) < 0.03)
        #expect(colors.ring.count == 8)
        #expect(colors.ring.allSatisfy { abs(hue($0) - 0.4) < 0.03 })
        #expect(IconColor.from(png: Data("not an image".utf8)) == nil)
    }

    /// A 32 × 32 grid colored by `paint(x, y)`, top row first.
    private func grid(_ paint: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        (0..<32).flatMap { y in (0..<32).flatMap { x in
            let p = paint(x, y)
            return [p.0, p.1, p.2, p.3]
        } }
    }

    @Test func theRingFollowsWhereEachColorSits() throws {
        // Red on the left, blue on the right.
        let colors = try #require(IconColor.colors(rgba: grid { x, _ in x < 16 ? (230, 40, 40, 255) : (40, 80, 230, 255) }))
        #expect(hue(colors.ring[4]) < 0.03 || hue(colors.ring[4]) > 0.97)  // left: red
        #expect(abs(hue(colors.ring[0]) - 0.63) < 0.05)  // right: blue
    }

    @Test func emptySlicesBorrowFromTheirNeighbors() throws {
        // Yellow on top, nothing below: the bottom of the ring is yellow too.
        let colors = try #require(IconColor.colors(rgba: grid { _, y in y < 12 ? (240, 200, 40, 255) : (0, 0, 0, 0) }))
        #expect(colors.ring.allSatisfy { abs(hue($0) - 0.135) < 0.03 })
    }

    @Test func greyIconsHaveNoRing() {
        #expect(IconColor.colors(rgba: grid { _, _ in (30, 30, 30, 255) }) == nil)
    }

    private static func png(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data? {
        guard let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
