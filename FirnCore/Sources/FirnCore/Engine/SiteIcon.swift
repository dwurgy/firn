import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A site's own icon: picked from what the page lists, fetched, and made
/// small and safe. The page is hostile input throughout: what it lists, the
/// file it points to, and the image inside.
public enum SiteIcon {
    /// Icons are kept this many pixels across at most (16–18pt at 2x, with room).
    static let pixelSize = 64
    static let maxDownloadBytes = 512 * 1024
    /// No icon needs more than about 1024 × 1024; bigger files aren't decoded,
    /// so a small file can't unpack into a huge image.
    static let maxSourcePixels = 1024 * 1024
    /// What a saved icon may weigh (a 64px PNG is a few KB).
    static let maxStoredBytes = 64 * 1024
    static let maxCandidates = 4

    /// One `<link rel=…>` as the page described it.
    struct Link: Equatable {
        var rel: Set<String>
        var url: URL
        /// The largest side named in `sizes`, or nil if none.
        var size: Int?
        var isSVG: Bool
        var matchesMedia: Bool
    }

    /// What the page script found: its icon links and the browser's user agent,
    /// so the icon request looks like the page's own (not a "Firn" fingerprint).
    struct Found {
        var links: [Link] = []
        var userAgent: String?
    }

    // MARK: - Reading the page

    /// Run in Firn's own content world, so the page can't see or change it.
    /// Returns plain strings and booleans; anything else is thrown away.
    /// Only icon links are taken before the cap: GitHub has over a hundred
    /// stylesheet links ahead of its icons.
    static let script = """
        (function () {
            try {
                var links = Array.from(document.querySelectorAll('link[href][rel*="icon" i]')).slice(0, 40);
                return {
                    links: links.map(function (link) {
                        var media = link.media;
                        return [String(link.rel), String(link.href), link.sizes ? String(link.sizes.value) : '',
                                String(link.type), !media || window.matchMedia(media).matches];
                    }),
                    userAgent: String(navigator.userAgent)
                };
            } catch (e) {
                return null;
            }
        })()
        """

    /// Checks the script's result field by field. A page can't change the script,
    /// but it controls every value the script reads.
    static func parse(scriptResult: Any?) -> Found {
        guard let result = scriptResult as? [String: Any] else { return Found() }
        var found = Found()
        if let agent = result["userAgent"] as? String, agent.utf8.count <= 512,
           agent.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) {
            found.userAgent = agent
        }
        let rows = (result["links"] as? [Any]) ?? []
        found.links = rows.prefix(40).compactMap { row in
            guard let fields = row as? [Any], fields.count == 5,
                  let rel = fields[0] as? String, let href = fields[1] as? String,
                  let sizes = fields[2] as? String, let type = fields[3] as? String,
                  let matches = fields[4] as? Bool,
                  rel.utf8.count <= 200, href.utf8.count <= 2048, sizes.utf8.count <= 200,
                  let url = URL(string: href), WebAddress.isWebURL(url) else { return nil }
            let tokens = Set(rel.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            // `sizes="any"` is common on plain .ico files too, so it doesn't mean SVG.
            let isSVG = type.lowercased().contains("svg") || url.pathExtension.lowercased() == "svg"
            return Link(rel: tokens, url: url, size: largestSide(in: sizes), isSVG: isSVG, matchesMedia: matches)
        }
        return found
    }

    /// "16x16 32x32" → 32.
    static func largestSide(in sizes: String) -> Int? {
        sizes.lowercased().split(whereSeparator: \.isWhitespace).compactMap { size -> Int? in
            let sides = size.split(separator: "x")
            guard sides.count == 2, let w = Int(sides[0]), let h = Int(sides[1]), w > 0, h > 0 else { return nil }
            return max(w, h)
        }.max()
    }

    /// Where to look, best first: the page's icons, then the site's
    /// `/favicon.ico`, then Apple touch icons (often full-bleed squares, so last).
    /// SVG is skipped (ImageIO can't read it), as are icons for the other
    /// light/dark mode.
    static func candidates(from links: [Link], pageURL: URL) -> [URL] {
        let usable = links.filter { $0.matchesMedia && !$0.isSVG && mayFetch($0.url, for: pageURL) }
        let icons = usable.filter { $0.rel.contains("icon") }
        let touch = usable.filter { $0.rel.contains("apple-touch-icon") || $0.rel.contains("apple-touch-icon-precomposed") }

        var urls = ranked(icons).map(\.url)
        var origin = URLComponents()
        origin.scheme = pageURL.scheme
        origin.host = pageURL.host()
        origin.port = pageURL.port
        origin.path = "/favicon.ico"
        if let favicon = origin.url { urls.append(favicon) }
        urls += ranked(touch).map(\.url)

        var seen = Set<URL>()
        return Array(urls.filter { seen.insert($0).inserted }.prefix(maxCandidates))
    }

    /// Closest to 64px from above first, then sizes not given, then smaller ones.
    private static func ranked(_ links: [Link]) -> [Link] {
        func key(_ link: Link) -> (Int, Int) {
            guard let size = link.size else { return (1, 0) }
            return size >= pixelSize ? (0, size) : (2, -size)
        }
        return links.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
    }

    /// Only web addresses; https pages only fetch https icons; and a page can't
    /// point Firn at the local network (localhost, `.local`, IP addresses)
    /// unless the page itself lives there.
    static func mayFetch(_ url: URL, for pageURL: URL) -> Bool {
        guard WebAddress.isWebURL(url), let host = url.host()?.lowercased() else { return false }
        if pageURL.scheme?.lowercased() == "https", url.scheme?.lowercased() != "https" { return false }
        if host == pageURL.host()?.lowercased() { return true }
        return !isLocal(host)
    }

    private static func isLocal(_ host: String) -> Bool {
        let host = host.hasSuffix(".") ? String(host.dropLast()) : host
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if host.contains(":") || host.hasPrefix("[") { return true } // IPv6
        return host.allSatisfy { $0.isNumber || $0 == "." } // IPv4, in any spelling
    }

    // MARK: - Fetching

    /// No cookies, no cache, no saved passwords, nothing written to disk: the
    /// request can't be tied to anyone's sign-ins.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    /// The first candidate that yields a usable image, as a small PNG.
    static func fetch(_ candidates: [URL], userAgent: String?) async -> Data? {
        for url in candidates.prefix(maxCandidates) {
            if Task.isCancelled { return nil }
            if let data = await download(url, userAgent: userAgent), let png = smallPNG(from: data) {
                return png
            }
        }
        return nil
    }

    private static func download(_ url: URL, userAgent: String?) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("image/webp,image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, WebAddress.isWebURL(finalURL),
              // A redirect may not drop from https to http.
              url.scheme?.lowercased() != "https" || finalURL.scheme?.lowercased() == "https",
              http.expectedContentLength <= Int64(maxDownloadBytes) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxDownloadBytes {
                    bytes.task.cancel()
                    return nil
                }
            }
        } catch {
            return nil
        }
        return data
    }

    // MARK: - Making it small and safe

    private static let allowedTypes: Set<String> = [
        UTType.png.identifier, UTType.ico.identifier, UTType.jpeg.identifier,
        UTType.gif.identifier, UTType.webP.identifier, UTType.bmp.identifier,
    ]

    /// Decodes with ImageIO only known bitmap formats, refuses images too big
    /// to be an icon (before decoding them), picks the best size in a
    /// multi-size .ico, and re-draws it as a fresh PNG of at most 64px. Only
    /// that PNG is ever kept or shown.
    static func smallPNG(from data: Data) -> Data? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, noCache),
              let type = CGImageSourceGetType(source) as String?, allowedTypes.contains(type) else { return nil }

        var best: (index: Int, side: Int)?
        for index in 0..<min(CGImageSourceGetCount(source), 16) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, noCache) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width * height <= maxSourcePixels else { continue }
            let side = max(width, height)
            if isBetter(side, than: best?.side) { best = (index, side) }
        }
        guard let best else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, best.index, options) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let png = output as Data
        return isValidStored(png) ? png : nil
    }

    /// The smallest size at or above 64px, otherwise the largest.
    private static func isBetter(_ side: Int, than current: Int?) -> Bool {
        guard let current else { return true }
        switch (side >= pixelSize, current >= pixelSize) {
        case (true, true): return side < current
        case (false, false): return side > current
        case (let sideIsBigEnough, _): return sideIsBigEnough
        }
    }

    /// A saved icon is a PNG of reasonable weight; anything else is dropped.
    static func isValidStored(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count <= maxStoredBytes && data.starts(with: signature)
    }
}
