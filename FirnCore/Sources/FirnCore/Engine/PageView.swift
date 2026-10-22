#if os(macOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI. The only place a view and WKWebView meet.
/// AppKit wrapper because SwiftUI's own WebView needs macOS 26.
public struct PageView: NSViewRepresentable {
    private let page: any PageController
    private let cornerRadius: CGFloat
    private let zoom: CGFloat
    private let onPointerDown: (() -> Void)?

    /// `zoom` below 1 shows the page smaller but laid out as if it were
    /// wider (a Lookout shows it as the tab would, scaled to fit).
    /// `onPointerDown` hears a press anywhere on the page (split view uses
    /// it to tell which half is in use); the page still gets the press.
    public init(
        page: any PageController, cornerRadius: CGFloat, zoom: CGFloat = 1,
        onPointerDown: (() -> Void)? = nil
    ) {
        self.page = page
        self.cornerRadius = cornerRadius
        self.zoom = zoom
        self.onPointerDown = onPointerDown
    }

    public func makeNSView(context: Context) -> PageHolder {
        let webView = webKitPage.webView
        webView.wantsLayer = true
        webView.layer?.masksToBounds = true
        webView.layer?.cornerCurve = .continuous
        webView.layer?.cornerRadius = cornerRadius
        webView.pageZoom = zoom
        let holder = PageHolder(webView: webView)
        holder.onPointerDown = onPointerDown
        return holder
    }

    public func updateNSView(_ holder: PageHolder, context: Context) {
        holder.onPointerDown = onPointerDown
        holder.webView.layer?.cornerRadius = cornerRadius
        if holder.webView.pageZoom != zoom { holder.webView.pageZoom = zoom }
    }

    private var webKitPage: WebKitPageController {
        guard let page = page as? WebKitPageController else {
            preconditionFailure("PageView shows pages made by BrowserEngine.makePage")
        }
        return page
    }
}
/// Holds a page's web view and passes on only real sizes. SwiftUI sizes a
/// newly shown view at 0×0 before its real size, and each size change makes
/// WebKit lay the whole page out again: on a long article (Wikipedia) that
/// took long enough to freeze the window for a third of a second on every
/// tab switch. With the holder, the page keeps its size while off screen.
///
/// It also tells when the page is pressed. The web view takes every click
/// before SwiftUI could see one, so the holder listens to the window's
/// presses (an AppKit event monitor) and passes each one on untouched. It
/// learns only that the page was pressed, never where or on what.
public final class PageHolder: NSView {
    let webView: WKWebView
    var onPointerDown: (() -> Void)? {
        didSet { listenForPresses() }
    }
    private var pressMonitor: Any?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        if webView.frame.isEmpty { webView.frame = bounds }
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        webView.frame = bounds
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        listenForPresses()
    }

    /// Listens only while it's in a window and someone wants to know.
    private func listenForPresses() {
        let wanted = onPointerDown != nil && window != nil
        if wanted, pressMonitor == nil {
            pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.heard(event) }
                return event
            }
        } else if !wanted, let monitor = pressMonitor {
            NSEvent.removeMonitor(monitor)
            pressMonitor = nil
        }
    }

    private func heard(_ event: NSEvent) {
        guard event.window === window, let onPointerDown else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Only a press that really lands on this page (not on a Lookout or
        // the command bar floating over it).
        guard bounds.contains(point), window?.contentView?.hitTest(event.locationInWindow)?
            .isDescendant(of: webView) == true else { return }
        onPointerDown()
    }
}
#endif
