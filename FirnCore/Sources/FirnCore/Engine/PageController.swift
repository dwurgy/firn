import CoreGraphics
import Foundation
import Observation

/// One web page, as the rest of Firn sees it. Views and app logic talk to
/// this, never to WebKit (CLAUDE.md, Architecture: the engine layer).
@MainActor
public protocol PageController: AnyObject, Observable {
    /// The committed address: what's really on screen, never a pending one.
    var url: URL? { get }
    var title: String { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var isLoading: Bool { get }
    /// The site's own icon as a small PNG (at most 64px), once found; nil
    /// until then, or if the site has none.
    var icon: Data? { get }
    /// Set when the last address couldn't load (a typo, offline, no answer,
    /// an unsafe connection); nil once a page loads again.
    var loadError: LoadError? { get }

    /// Opens an http or https address. Anything else is ignored.
    func load(_ url: URL)
    func goBack()
    func goForward()
    /// Loads the page again, or tries the address that failed once more.
    func reload()
    func stopLoading()
    /// Gives the page keyboard focus, so arrow keys and space scroll it.
    func focus()
    /// A small picture of the page as it is now, `width` points wide, or nil
    /// if there's nothing to show. Kept in memory only, never saved.
    func snapshot(width: CGFloat) async -> CGImage?
    /// Opens the Mac's print sheet for the page, attached to its window.
    /// Does nothing without a loaded page or while another sheet is up.
    func printPage()
    /// How big the page is drawn (1 is actual size). This tab's only; not saved.
    var zoom: Double { get }
    /// One of `PageZoom.steps`.
    func setZoom(_ zoom: Double)
    /// Finds `text` on the page, wrapping round at the end, and selects and
    /// scrolls to the match. Returns how many matches the page has (counted
    /// up to `FindOnPage.countLimit`); 0 if none, or nothing is loaded.
    func find(_ text: String, _ direction: FindOnPage.Direction) async -> Int
    /// The text selected on the page, at most `FindOnPage.maxLength`
    /// characters; "" if none.
    func selectedText() async -> String

    /// What the page needs to pick up where it left off after sleeping: its
    /// back and forward history and scroll position. Nil if there's nothing
    /// to keep. Kept in memory only, never saved.
    func memory() -> PageMemory?
    /// Picks up from `memory` instead of loading an address.
    func resume(from memory: PageMemory)
    /// Whether sleeping would stop something the page is doing: playing
    /// sound or video, or using the camera or microphone.
    func isInUse() async -> Bool

    /// Whether the page is making sound, or would be if Firn hadn't muted it.
    var sound: PageSound { get }
    /// Mutes or unmutes the page. In memory only, never saved; it stays
    /// muted as it moves from page to page, until unmuted.
    func setMuted(_ muted: Bool)
    /// Whether Firn paused the page's sound (from the mini player), so it
    /// can be played again. Cleared when the page changes, when it plays
    /// again on its own, or with `forgetPause()`.
    var isPausedByFirn: Bool { get }
    /// Asked to play again, and waiting for the page to start (it stays
    /// paused by Firn until then, or until it gives up after 2 seconds).
    var isResuming: Bool { get }
    /// Pauses what's playing on the page, or plays just that again.
    func setPaused(_ paused: Bool)
    /// Lets go of a pause, leaving the page as it is (the tab came on
    /// screen, so its own controls take over).
    func forgetPause()

    /// A Basecamp tile's page: a clicked link to another site, or one meant
    /// for a new window, goes to a Lookout instead, so the tile stays itself.
    var sendsOtherSitesToLookout: Bool { get set }

    /// Where the page sends what it asks of the browser (new tabs, closing).
    /// Set by whoever owns the page; nil means nobody is listening.
    var onRequest: (@MainActor (PageRequest) -> Void)? { get set }
}

/// A sleeping page's place (see `PageController.memory()`), opaque to all
/// but the engine that made it.
public struct PageMemory {
    let state: Any
}

/// Something a page asks of the browser. Always started by a click: sites
/// can't open windows on their own.
@MainActor
public enum PageRequest {
    /// A link meant for a new window, or `window.open`. The page already
    /// exists and stays connected to its opener (sign-in popups need that),
    /// so it must be shown as is, never reloaded elsewhere.
    case openPage(any PageController, inBackground: Bool)
    /// A ⌘-click or middle-click: this address, in a new tab.
    case openURL(URL, inBackground: Bool)
    /// A Shift-click, "Open in Lookout" from the link's menu, or a tile's
    /// link to another site: this
    /// address, in a Lookout over the page.
    case openInLookout(URL)
    /// A page opened as a popup closed itself (`window.close`).
    case close
}

/// Makes pages. The only place that knows which engine Firn uses.
@MainActor
public enum BrowserEngine {
    /// A page whose cookies, sign-ins, and site data live in the store named
    /// `dataStoreID` (one per space, or shared between spaces that share).
    public static func makePage(dataStoreID: UUID) -> any PageController {
        WebKitPageController(dataStoreID: dataStoreID)
    }

    /// Starts ad and tracker blocking: finds the compiled lists (or compiles
    /// them, in the background, the first time). Call once at launch, before
    /// pages load; pages made earlier still get the rules when they're ready.
    public static func startBlocking() {
        Task { await ContentBlocker.shared.start() }
    }
}
