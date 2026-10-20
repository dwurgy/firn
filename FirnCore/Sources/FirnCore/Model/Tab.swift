import Foundation
import Observation

/// One tab. It owns its page, made the first time the tab is shown, and
/// knows nothing about views or WebKit.
@MainActor
@Observable
public final class Tab: Identifiable {
    public enum Place: String, Codable, Sendable {
        case basecamp, open, drifted

        /// Files from before Drifted tabs said "archived".
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let place = Place(rawValue: raw == "archived" ? "drifted" : raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown place"))
            }
            self = place
        }
    }

    public let id: UUID
    public let spaceID: UUID
    public internal(set) var place: Place
    /// Where a Basecamp tile goes back to: its address when it was added.
    public internal(set) var homeURL: URL?
    /// The group an everyday tab is kept in, if any.
    public internal(set) var groupID: UUID?
    /// The tab whose link opened this one, if any.
    public var openerTabID: UUID?
    public internal(set) var lastActiveAt: Date
    /// When a drifted tab drifted; it's deleted 30 calendar days later.
    public internal(set) var driftedAt: Date?

    /// The page, once the tab has been shown. Until then the tab only
    /// remembers where it was.
    public private(set) var page: (any PageController)?
    private var restingURL: URL?
    private var restingTitle: String
    private var restingIcon: Data?

    init(
        id: UUID = UUID(), spaceID: UUID, place: Place = .open,
        url: URL?, title: String = "", icon: Data? = nil, homeURL: URL? = nil, groupID: UUID? = nil, openerTabID: UUID? = nil, lastActiveAt: Date,
        driftedAt: Date? = nil,
        page: (any PageController)? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.place = place
        self.homeURL = homeURL
        self.groupID = groupID
        self.openerTabID = openerTabID
        self.lastActiveAt = lastActiveAt
        self.driftedAt = driftedAt
        self.restingURL = url
        self.restingTitle = title
        self.restingIcon = icon
        self.page = page
    }

    /// The committed address, or where the tab rests if it has no page yet.
    /// After a failed load it's the address that failed: the error page
    /// covers the old page, so its address must not claim it's on screen.
    public var url: URL? { page?.loadError?.url ?? page?.url ?? restingURL }

    /// The page's title, falling back to its host, so a row is never blank.
    public var title: String {
        let title = currentTitle
        if !title.isEmpty { return title }
        return url?.host() ?? "New Tab"
    }

    /// The page's own title, or the last one it had; empty if it never had one.
    var savedTitle: String {
        if page?.loadError != nil { return "" }
        if let title = page?.title, !title.isEmpty { return title }
        return restingTitle
    }

    /// The page's title, or the last one while a just-woken page hasn't
    /// arrived yet (so a row doesn't flicker to the bare site and back).
    private var currentTitle: String {
        guard let page else { return restingTitle }
        // The old page's title would name a page that isn't showing.
        if let failed = page.loadError { return failed.site }
        return page.title.isEmpty && page.url == nil ? restingTitle : page.title
    }

    /// The site's icon (a small PNG): the page's own once found, or the one
    /// from last time while it's still on that site.
    public var icon: Data? {
        guard let page else { return restingIcon }
        // After a failed load, an icon only if it's the very site that failed.
        if let failed = page.loadError {
            return Self.sameHost(failed.url, page.url) ? page.icon : Self.sameHost(failed.url, restingURL) ? restingIcon : nil
        }
        if let icon = page.icon { return icon }
        return Self.sameHost(page.url ?? restingURL, restingURL) ? restingIcon : nil
    }

    private static func sameHost(_ a: URL?, _ b: URL?) -> Bool {
        guard let a = a?.host()?.lowercased(), let b = b?.host()?.lowercased() else { return false }
        return a == b
    }

    /// Whether the tab has no page right now (closed Basecamp tiles rest
    /// until clicked, as do tabs not yet shown since launch).
    public var isResting: Bool { page == nil }

    /// A Basecamp tile that has wandered from its home address.
    public var isAwayFromHome: Bool {
        guard let homeURL else { return false }
        return url != homeURL
    }

    /// Back to the home address: loaded now if the tab is awake, or where
    /// it will wake if it's resting.
    func goHome() {
        guard let homeURL else { return }
        if let page {
            page.load(homeURL)
        } else {
            if !Self.sameHost(homeURL, restingURL) { restingIcon = nil }
            restingURL = homeURL
            restingTitle = ""
        }
    }

    /// Makes the page (if needed) and starts loading where the tab rests.
    func wake(using makePage: () -> any PageController) {
        guard page == nil else { return }
        let page = makePage()
        self.page = page
        if let restingURL { page.load(restingURL) }
    }

    /// Lets the page go, remembering where it was.
    func sleep() {
        guard let page else { return }
        restingIcon = icon
        restingTitle = page.loadError == nil ? currentTitle : ""
        restingURL = url
        page.stopLoading()
        self.page = nil
    }
}
