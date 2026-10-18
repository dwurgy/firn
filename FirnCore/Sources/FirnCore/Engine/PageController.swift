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

    /// Opens an http or https address. Anything else is ignored.
    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    /// Gives the page keyboard focus, so arrow keys and space scroll it.
    func focus()

    /// Where the page sends what it asks of the browser (new tabs, closing).
    /// Set by whoever owns the page; nil means nobody is listening.
    var onRequest: (@MainActor (PageRequest) -> Void)? { get set }
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
}
