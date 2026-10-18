import Foundation
import Observation

/// One tab. It owns its page, made the first time the tab is shown, and
/// knows nothing about views or WebKit.
@MainActor
@Observable
public final class Tab: Identifiable {
    public enum Place: String, Codable, Sendable {
        case basecamp, pinned, open, archived
    }

    public let id: UUID
    public let spaceID: UUID
    public internal(set) var place: Place
    /// Where a Basecamp or pinned tab goes back to: its address when it was
    /// pinned or added to Basecamp.
    public internal(set) var homeURL: URL?
    /// The tab whose link opened this one, if any.
    public var openerTabID: UUID?
    public internal(set) var lastActiveAt: Date

    /// The page, once the tab has been shown. Until then the tab only
    /// remembers where it was.
    public private(set) var page: (any PageController)?
    private var restingURL: URL?
    private var restingTitle: String

    init(
        id: UUID = UUID(), spaceID: UUID, place: Place = .open,
        url: URL?, title: String = "", homeURL: URL? = nil, openerTabID: UUID? = nil, lastActiveAt: Date,
        page: (any PageController)? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.place = place
        self.homeURL = homeURL
        self.openerTabID = openerTabID
        self.lastActiveAt = lastActiveAt
        self.restingURL = url
        self.restingTitle = title
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

    /// Whether the tab has no page right now (closed pins and Basecamp
    /// tiles rest until clicked, as do tabs not yet shown since launch).
    public var isResting: Bool { page == nil }

    /// A Basecamp or pinned tab that has wandered from its home address.
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
        restingURL = page.url ?? restingURL
        restingTitle = page.title
        page.stopLoading()
        self.page = nil
    }
}
