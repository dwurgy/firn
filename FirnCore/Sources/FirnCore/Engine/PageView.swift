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
        holder.show(reader: reader, motion: .instant)
        return holder
    }

    public func updateNSView(_ holder: PageHolder, context: Context) {
        holder.onPointerDown = onPointerDown
        holder.cornerRadius = cornerRadius
        holder.webView.layer?.cornerRadius = cornerRadius
        // In and out of Reader, an edge scrolling down, then back up
        // (`ReaderSweep`). Reduce Motion: cross-fades.
        holder.show(reader: reader, motion: context.environment.accessibilityReduceMotion ? .fade : .sweep)
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

    // MARK: Reader

    /// How Reader's view comes and goes.
    enum ReaderMotion {
        /// At once (a page shown again with Reader already on).
        case instant
        /// A short cross-fade (Reduce Motion).
        case fade
        /// An edge scrolling down from the top into Reader, and back up out
        /// of it (`ReaderSweep`).
        case sweep
    }

    /// Where the reader's edge is, while it sweeps: uncovered above it.
    private var sweepMask: CALayer?
    /// Waits for the reader's first drawn frame.
    private var drawWait: Task<Void, Never>?
    /// Counts each coming and going, so a late wait or end is ignored.
    private var sweepTurn = 0
    /// The reader in front is fully there, and takes the clicks.
    private var readerIsIn = false
    /// What takes the clicks and VoiceOver: the reader once it's there, or the page.
    private var front: WKWebView { reader.flatMap { readerIsIn ? $0 : nil } ?? webView }
    /// The page's touch of dark as it comes back: warm ink, never grey.
    private let leaveDim: NSView = {
        let dim = NSView()
        dim.wantsLayer = true
        dim.layer?.backgroundColor = CGColor(red: 0x24 / 255, green: 0x1F / 255, blue: 0x1B / 255, alpha: 1)
        dim.layer?.cornerCurve = .continuous
        dim.setAccessibilityElement(false)
        return dim
    }()

    /// Shows Reader's view over the page, or takes it away. Keyboard focus
    /// follows: whichever was being typed into or scrolled hands it to the
    /// other. Once covered, the page is hidden, so neither clicks nor
    /// VoiceOver reach it behind the reader; until then, and as the reader
    /// leaves, clicks go to the page (`hitTest`).
    ///
    /// In, the reader goes in front at once, masked away, until its page has
    /// drawn (it's its own web view, empty at first); then the edge comes
    /// down. Out, the edge goes back up, from where it is if it was still
    /// on its way down.
    func show(reader newReader: WKWebView?, motion: ReaderMotion) {
        guard newReader !== reader else { return }
        let old = reader
        let hadFocus = hasFocus(in: old ?? webView)
        reader = newReader
        sweepTurn += 1
        drawWait?.cancel()
        readerIsIn = false
        let edge = sweepMask?.presentation()?.bounds.height
        sweepMask = nil
        old?.setAccessibilityHidden(newReader == nil)
        if motion == .sweep, window != nil, (old == nil) != (newReader == nil) {
            if let newReader {
                prepare(newReader)
                newReader.alphaValue = 1
                addSubview(newReader, positioned: .above, relativeTo: webView)
                if hadFocus { window?.makeFirstResponder(newReader) }
                sweep(in: newReader)
            } else if let old {
                webView.isHidden = false
                if hadFocus { window?.makeFirstResponder(webView) }
                sweep(out: old, from: edge ?? old.bounds.height)
            }
            return
        }
        old?.layer?.mask = nil
        let fade: TimeInterval = motion == .instant ? 0 : 0.15
        if let newReader {
            prepare(newReader)
            readerIsIn = true
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

    private func prepare(_ reader: WKWebView) {
        reader.wantsLayer = true
        reader.layer?.masksToBounds = true
        reader.layer?.cornerCurve = .continuous
        reader.layer?.cornerRadius = cornerRadius
        reader.frame = bounds
    }

    /// Masks the reader down to `height` from its top.
    private func mask(_ reader: WKWebView, to height: CGFloat) -> CALayer? {
        guard let layer = reader.layer else { return nil }
        let mask = CALayer()
        mask.backgroundColor = .black
        // The layer's top, whichever way up AppKit made it.
        let flipped = layer.contentsAreFlipped()
        mask.anchorPoint = CGPoint(x: 0, y: flipped ? 0 : 1)
        mask.position = CGPoint(x: 0, y: flipped ? 0 : layer.bounds.height)
        mask.bounds = CGRect(x: 0, y: 0, width: layer.bounds.width, height: height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.mask = mask
        CATransaction.commit()
        return mask
    }

    private func sweep(in reader: WKWebView) {
        let turn = sweepTurn
        sweepMask = mask(reader, to: 0)
        reader.setAccessibilityHidden(true)
        let start = { [weak self, weak reader] in
            guard let self, let reader, self.sweepTurn == turn, !self.readerIsIn else { return }
            self.readerIsIn = true
            let height = reader.bounds.height
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self, weak reader] in
                MainActor.assumeIsolated {
                    guard let self, let reader, self.sweepTurn == turn else { return }
                    reader.layer?.mask = nil
                    reader.setAccessibilityHidden(false)
                    self.sweepMask = nil
                    self.webView.isHidden = true
                }
            }
            if let mask = self.sweepMask { ReaderSweep.move(mask, from: 0, to: height) }
            CATransaction.commit()
        }
        // Drawn, or long enough: never a stuck press.
        drawWait?.cancel()
        drawWait = Task { [weak reader] in
            guard let reader else { return }
            await ReaderSweep.waitUntilDrawn(reader)
            if !Task.isCancelled { start() }
        }
        Task {
            try? await Task.sleep(for: .seconds(ReaderSweep.wait))
            start()
        }
    }

    private func sweep(out reader: WKWebView, from edge: CGFloat) {
        let turn = sweepTurn
        guard edge > 0, let mask = mask(reader, to: edge) else {
            // Never seen: it simply goes.
            return reader.removeFromSuperview()
        }
        leaveDim.frame = bounds
        leaveDim.layer?.cornerRadius = cornerRadius
        leaveDim.alphaValue = ReaderSweep.dim
        addSubview(leaveDim, positioned: .below, relativeTo: reader)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak reader] in
            MainActor.assumeIsolated {
                reader?.removeFromSuperview()
                reader?.layer?.mask = nil
                if let self, self.sweepTurn == turn { self.leaveDim.removeFromSuperview() }
            }
        }
        ReaderSweep.move(mask, from: edge, to: 0)
        CATransaction.commit()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ReaderSweep.dimDelay))
            guard let self, self.sweepTurn == turn else { return }
            self.clearDim()
        }
    }

    private func clearDim() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ReaderSweep.dimDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            leaveDim.animator().alphaValue = 0
        }
    }

    /// A reader still on its way in or out lets clicks through to the page.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard !hit.isDescendant(of: front), hit !== self else { return hit }
        return front.hitTest(convert(point, from: superview))
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
            .isDescendant(of: self) == true else { return }
        onPointerDown()
    }
}
#endif
