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
