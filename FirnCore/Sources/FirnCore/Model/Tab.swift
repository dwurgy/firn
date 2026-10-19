import Foundation
import Observation

/// One tab. It owns its page, made the first time the tab is shown, and
/// knows nothing about views or WebKit.
@MainActor
@Observable
public final class Tab: Identifiable {
    public enum Place: String, Codable, Sendable {
        case basecamp, open, archived
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

    /// The page, once the tab has been shown. Until then the tab only
    /// remembers where it was.
    public private(set) var page: (any PageController)?
    private var restingURL: URL?
    private var restingTitle: String
    private var restingIcon: Data?

    init(
        id: UUID = UUID(), spaceID: UUID, place: Place = .open,
        url: URL?, title: String = "", icon: Data? = nil, homeURL: URL? = nil, groupID: UUID? = nil, openerTabID: UUID? = nil, lastActiveAt: Date,
        page: (any PageController)? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.place = place
        self.homeURL = homeURL
        self.groupID = groupID
        self.openerTabID = openerTabID
        self.lastActiveAt = lastActiveAt
        self.restingURL = url
        self.restingTitle = title
        self.restingIcon = icon
        self.page = page
    }

    /// The committed address, or where the tab rests if it has no page yet.
    public var url: URL? { page?.url ?? restingURL }

    /// The page's title, falling back to its host, so a row is never blank.
    public var title: String {
        let title = page?.title ?? restingTitle
        if !title.isEmpty { return title }
        return url?.host() ?? "New Tab"
    }

    /// The page's own title, or the last one it had; empty if it never had one.
    var savedTitle: String {
        if let title = page?.title, !title.isEmpty { return title }
        return restingTitle
    }

    /// The site's icon (a small PNG): the page's own once found, or the one
    /// from last time while it's still on that site.
    public var icon: Data? {
        guard let page else { return restingIcon }
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
        restingURL = page.url ?? restingURL
        restingTitle = page.title
        page.stopLoading()
        self.page = nil
    }
}
