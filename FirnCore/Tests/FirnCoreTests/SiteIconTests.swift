import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FirnCore

struct SiteIconTests {
    private let page = URL(string: "https://news.example/today")!

    private func row(_ rel: String, _ href: String, sizes: String = "", type: String = "", matches: Bool = true) -> [Any] {
        [rel, href, sizes, type, matches]
    }

    private func candidates(_ rows: [Any]) -> [String] {
        let found = SiteIcon.parse(scriptResult: ["links": rows, "userAgent": "Mozilla/5.0"])
        return SiteIcon.candidates(from: found.links, pageURL: page).map(\.absoluteString)
    }

    @Test func prefersTheIconClosestToSixtyFourPixels() {
        let urls = candidates([
            row("icon", "https://news.example/16.png", sizes: "16x16"),
            row("icon", "https://news.example/192.png", sizes: "192x192"),
            row("shortcut icon", "https://news.example/96.png", sizes: "96x96"),
            row("icon", "https://news.example/plain.png"),
        ])
        #expect(urls == [
            "https://news.example/96.png", "https://news.example/192.png",
            "https://news.example/plain.png", "https://news.example/16.png",
        ])
    }

    @Test func fallsBackToFaviconThenTouchIcon() {
        let urls = candidates([row("apple-touch-icon", "https://news.example/touch.png")])
        #expect(urls == ["https://news.example/favicon.ico", "https://news.example/touch.png"])
    }

    @Test func skipsSVGOtherModeAndOddLinks() {
        let urls = candidates([
            row("icon", "https://news.example/a.svg", type: "image/svg+xml"),
            row("icon", "https://news.example/dark.png", matches: false),
            row("stylesheet", "https://news.example/site.css"),
            row("icon", "javascript:alert(1)"),
            row("icon", "data:image/png;base64,AAAA"),
            ["icon", 42, "", "", true],
            "not a row",
        ])
        #expect(urls == ["https://news.example/favicon.ico"])
    }

    @Test func refusesInsecureAndLocalNetworkIcons() {
        let urls = candidates([
            row("icon", "http://news.example/plain-http.png"),
            row("icon", "https://localhost/a.png"),
            row("icon", "https://192.168.1.1/a.png"),
            row("icon", "https://[::1]/a.png"),
            row("icon", "https://printer.local/a.png"),
            row("icon", "https://cdn.example/ok.png"),
        ])
        #expect(urls == ["https://cdn.example/ok.png", "https://news.example/favicon.ico"])
    }

    @Test func dropsAUserAgentThatCouldBreakAHeader() {
        let found = SiteIcon.parse(scriptResult: ["links": [], "userAgent": "Mozilla\r\nCookie: x"])
        #expect(found.userAgent == nil)
        #expect(SiteIcon.parse(scriptResult: "nonsense").links.isEmpty)
    }

    @Test func readsSizes() {
        #expect(SiteIcon.largestSide(in: "16x16 32X32") == 32)
        #expect(SiteIcon.largestSide(in: "any") == nil)
        #expect(SiteIcon.largestSide(in: "0x0 -1x5 axb") == nil)
    }

    // MARK: - Images

    private func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func pixelWidth(_ data: Data) -> Int? {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int
    }

    @Test func shrinksBigIconsToSixtyFourPixels() throws {
        let small = try #require(SiteIcon.smallPNG(from: png(width: 256, height: 256)))
        #expect(pixelWidth(small) == 64)
        #expect(SiteIcon.isValidStored(small))
    }

    @Test func refusesHugeImagesAndNonImages() {
        #expect(SiteIcon.smallPNG(from: png(width: 2048, height: 2048)) == nil)
        #expect(SiteIcon.smallPNG(from: Data("<html>Not found</html>".utf8)) == nil)
        #expect(SiteIcon.smallPNG(from: Data()) == nil)
    }

    @Test func storedIconsMustBeSmallPNGs() {
        #expect(!SiteIcon.isValidStored(Data("GIF89a".utf8)))
        #expect(!SiteIcon.isValidStored(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 70_000)))
    }
}

@MainActor
struct TabIconTests {
    private let space = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())
    private let iconPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    @Test func iconIsSavedAndComesBack() throws {
        let store = BrowserStore(spaces: [space], makePage: { FakePage(dataStoreID: $0) })
        let tab = store.openTab(URL(string: "https://a.example")!)
        (tab.page as? FakePage)?.icon = iconPNG
        let session = store.session(sidebarWidth: 260, sidebarCollapsed: false)
        #expect(session.tabs.first?.icon == iconPNG)

        let data = try JSONEncoder().encode(session)
        let restored = BrowserStore(
            restoring: try JSONDecoder().decode(Session.self, from: data), defaultSpaces: [space],
            makePage: { FakePage(dataStoreID: $0) }
        )
        #expect(restored.tabs.first?.icon == iconPNG)
    }

    @Test func aRestoredIconThatIsntAPNGIsDropped() {
        let record = TabRecord(
            id: UUID(), spaceID: space.id, place: .open, url: URL(string: "https://a.example"), title: "",
            icon: Data("<svg/>".utf8), homeURL: nil, order: 0, lastActiveAt: .now, openerTabID: nil, lastChangedAt: .now
        )
        let window = WindowRecord(id: UUID(), activeSpaceID: space.id, activeTabID: nil, sidebarWidth: 260, sidebarCollapsed: false)
        let store = BrowserStore(
            restoring: Session(spaces: [space], tabs: [record], window: window), defaultSpaces: [space],
            makePage: { FakePage(dataStoreID: $0) }
        )
        #expect(store.tabs.first?.icon == nil)
    }

    @Test func theOldIconStaysOnlyWhileOnTheSameSite() {
        let tab = Tab(spaceID: space.id, url: URL(string: "https://a.example/1"), icon: iconPNG, lastActiveAt: .now)
        let page = FakePage(dataStoreID: space.dataStoreID)
        tab.wake { page }
        #expect(tab.icon == iconPNG)
        page.url = URL(string: "https://other.example")
        #expect(tab.icon == nil)
    }

    @Test func filesFromBeforeIconsStillOpen() throws {
        let json = """
            {"id":"\(UUID())","spaceID":"\(UUID())","place":"open","url":"https://a.example","title":"A",
             "order":0,"lastActiveAt":0,"lastChangedAt":0}
            """
        let record = try JSONDecoder().decode(TabRecord.self, from: Data(json.utf8))
        #expect(record.icon == nil)
    }
}
