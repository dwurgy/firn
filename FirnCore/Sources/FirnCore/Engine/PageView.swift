#if os(macOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI. The only place a view and WKWebView meet.
/// AppKit wrapper because SwiftUI's own WebView needs macOS 26.
public struct PageView: NSViewRepresentable {
    private let page: any PageController
    private let cornerRadius: CGFloat
    private let onPointerDown: (() -> Void)?
    /// Reader's own view, while Reader is on. Read here, in the caller's
    /// body, so SwiftUI updates the holder when Reader opens or closes.
    private let reader: WKWebView?

    /// `onPointerDown` hears a press anywhere on the page (split view uses
    /// it to tell which half is in use); the page still gets the press.
    public init(
        page: any PageController, cornerRadius: CGFloat,
        onPointerDown: (() -> Void)? = nil
    ) {
        self.page = page
        self.cornerRadius = cornerRadius
        self.onPointerDown = onPointerDown
        let webKitPage = page as? WebKitPageController
        self.reader = webKitPage?.isReading == true ? webKitPage?.reader?.webView : nil
    }

    public func makeNSView(context: Context) -> PageHolder {
        let webView = webKitPage.webView
        webView.wantsLayer = true
        webView.layer?.masksToBounds = true
        webView.layer?.cornerCurve = .continuous
        webView.layer?.cornerRadius = cornerRadius
        let holder = PageHolder(webView: webView)
        holder.onPointerDown = onPointerDown
        holder.cornerRadius = cornerRadius
        holder.show(reader: reader, fade: 0)
        return holder
    }

    public func updateNSView(_ holder: PageHolder, context: Context) {
        holder.onPointerDown = onPointerDown
        holder.cornerRadius = cornerRadius
        holder.webView.layer?.cornerRadius = cornerRadius
        // A cross-fade either way; a little quicker with Reduce Motion.
        holder.show(reader: reader, fade: context.environment.accessibilityReduceMotion ? 0.15 : 0.2)
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
    /// Reader's view, over the page while Reader is on.
    private(set) var reader: WKWebView?
    var cornerRadius: CGFloat = 0 {
        didSet { reader?.layer?.cornerRadius = cornerRadius }
    }
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
        reader?.frame = bounds
    }

    /// Cross-fades Reader's view in over the page, or out again. Keyboard
    /// focus follows: whichever was being typed into or scrolled hands it
    /// to the other. Once covered, the page is hidden, so neither clicks
    /// nor VoiceOver reach it behind the reader.
    func show(reader newReader: WKWebView?, fade: TimeInterval) {
        guard newReader !== reader else { return }
        let old = reader
        let hadFocus = hasFocus(in: old ?? webView)
        reader = newReader
        if let newReader {
            newReader.wantsLayer = true
            newReader.layer?.masksToBounds = true
            newReader.layer?.cornerCurve = .continuous
            newReader.layer?.cornerRadius = cornerRadius
            newReader.frame = bounds
            newReader.alphaValue = 0
            addSubview(newReader, positioned: .above, relativeTo: old ?? webView)
        } else {
            webView.isHidden = false
        }
        if hadFocus { window?.makeFirstResponder(newReader ?? webView) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newReader?.animator().alphaValue = 1
            old?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let old, old !== self.reader { old.removeFromSuperview() }
                if self.reader != nil, self.reader === newReader { self.webView.isHidden = true }
            }
        }
    }

    private func hasFocus(in view: NSView) -> Bool {
        (window?.firstResponder as? NSView)?.isDescendant(of: view) == true
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
            .isDescendant(of: reader ?? webView) == true else { return }
        onPointerDown()
    }
}
#endif
