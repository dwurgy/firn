#if os(iOS)
import SwiftUI
import WebKit

/// Shows a page in SwiftUI on iPhone and iPad. The only place a view and
/// WKWebView meet on iOS; the Mac's is PageView.swift. UIKit wrapper because
/// SwiftUI's own WebView would be its own step (see CLAUDE.md, Engine). A
/// view controller rather than a plain view, because only a view controller
/// can add Firn's bar to the safe area (below).
public struct PageView: UIViewControllerRepresentable {
    private let page: any PageController
    private let barTop: CGFloat
    private let held: PageHold?
    private let onScroll: ((BarScroll) -> Void)?
    /// Reader's own view, while Reader is on. Read here, in the caller's
    /// body, so SwiftUI updates the holder when Reader opens or closes.
    private let reader: WKWebView?

    /// `barTop` is where Firn's own bar starts, from the screen's top (0
    /// for no bar), so WebKit can scroll the page's end clear of it and keep
    /// fixed footers above it. `onScroll` hears when your own scrolling
    /// should shrink the bar or grow it back (`BarScroll`). `held` moves
    /// the live page while a finger pulls it (`PageHold`).
    public init(page: any PageController, barTop: CGFloat = 0, held: PageHold? = nil,
                onScroll: ((BarScroll) -> Void)? = nil) {
        self.page = page
        self.barTop = barTop
        self.held = held
        self.onScroll = onScroll
        let webKitPage = page as? WebKitPageController
        self.reader = webKitPage?.isReading == true ? webKitPage?.reader?.webView : nil
    }

    public func makeUIViewController(context: Context) -> PageHolder {
        let holder = PageHolder(page: webKitPage)
        (holder.view as? PageFrame)?.show(reader: reader, motion: .instant)
        return holder
    }

    public func updateUIViewController(_ holder: PageHolder, context: Context) {
        holder.barTop = barTop
        guard let frame = holder.view as? PageFrame else { return }
        frame.onScroll = onScroll
        frame.held = held
        // In and out of Reader, an edge sweeping down from the top, as
        // Safari's ("Plan: Reader comes down from the top", `docs/HISTORY.md`).
        // Reduce Motion: cross-fades.
        frame.show(reader: reader, motion: context.environment.accessibilityReduceMotion ? .fade : .sweep)
    }

    private var webKitPage: WebKitPageController {
        guard let page = page as? WebKitPageController else {
            preconditionFailure("PageView shows pages made by BrowserEngine.makePage")
        }
        return page
    }
}

/// Holds a page's web view, which fills the whole screen, as Safari's does:
/// under the status bar (where iOS's soft blur shows once it's scrolled) and
/// under Firn's bar. `PageFrame` tells WebKit which edges are covered.
public final class PageHolder: UIViewController {
    let webView: WKWebView
    private let page: WebKitPageController

    /// Where Firn's bar starts, from the screen's top; 0 for no bar.
    var barTop: CGFloat = 0 {
        didSet {
            guard barTop != oldValue else { return }
            updateBarInset()
        }
    }

    init(page: WebKitPageController) {
        self.page = page
        self.webView = page.webView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func loadView() {
        let frame = PageFrame(webView: webView)
        // Through the page's own reload, which also retries a failed address.
        frame.onRefresh = { [weak page] in page?.reload() }
        view = frame
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateBarInset()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBarInset()
    }

    /// The bar's room, from the screen's bottom edge up to the bar's top.
    /// Measured against the screen: SwiftUI reported the page's bottom edge
    /// at the home indicator rather than the screen's edge, so a long page's
    /// end rested 34pt behind the bar (phase 2, step 1's Known).
    private func updateBarInset() {
        guard let screen = view.window?.bounds, let frame = view as? PageFrame else { return }
        frame.barRoom = barTop > 0 ? max(screen.maxY - barTop, 0) : 0
    }
}

/// Where the live page goes while a finger pulls it up from the bar (or
/// sideways), until its picture takes over (`docs/IOS-PLAN.md`, the swipe
/// up's delay, step 2b): the page below the status bar, scaled into `box`
/// (screen points) with `radius` corners; the strip under the clock is
/// left out, as the picture leaves it out.
public struct PageHold: Equatable, Sendable {
    public var box: CGRect
    public var radius: CGFloat
    /// The strip under the clock comes along, above `box` (a sideways
    /// swipe, where each page carries its own).
    public var includesTop: Bool
    /// Otherwise, how much of that strip still rides above `box`, 1 to 0:
    /// pulled up, the page starts as the whole screen and the strip goes
    /// as it lifts (`docs/IOS-PLAN.md`, opening and closing as Safari's,
    /// step 2).
    public var topShown: CGFloat

    public init(box: CGRect, radius: CGFloat, includesTop: Bool = false, topShown: CGFloat = 0) {
        self.box = box
        self.radius = radius
        self.includesTop = includesTop
        self.topShown = topShown
    }
}

/// What your own scrolling says about the bar, as in Safari: scrolling
/// down to read shrinks it, scrolling back up (or reaching the page's top)
/// grows it (`docs/IOS-PLAN.md`, phase 5, step 1).
public enum BarScroll: Sendable {
    case shrink, grow
}

/// Passes on only real sizes, as on the Mac: SwiftUI sizes a newly shown
/// view at 0×0 first, and every size change makes WebKit lay the whole page
/// out again.
///
/// The page runs under the status bar and Firn's bar, as in Safari on iOS
/// 26, and WebKit is told both are covered in two places, which must agree:
/// `obscuredContentInsets` (so a bar a site pins to its top, like
/// apple.com's, sits below the clock, and fixed footers sit above Firn's
/// bar) and the scroll view's own `contentInset` (so the page's top and end
/// can be scrolled clear of them). With only the first, a new page opened
/// 62pt down but a restored one, or one pulled back to the top, stopped at 0
/// with its top row under the clock (firnbrowser.com's menu, 2026-11-04;
/// measured in `docs/IOS-PLAN.md`, step 3c.3). Under the clock the page
/// slides beneath iOS's own edge blur. Behind the page, the frame takes
/// the page's own color (its theme color, else its background) for the
/// moment before it draws.
private final class PageFrame: UIView {
    let webView: WKWebView
    private var colorWatchers: [NSKeyValueObservation] = []
    /// Pull down past the top to reload, as in Safari.
    var onRefresh: (() -> Void)?
    /// Hears whether your scrolling should shrink or grow the bar.
    var onScroll: ((BarScroll) -> Void)?
    /// The scroll position last seen, and how far the page has moved one
    /// way since it last turned around.
    private var lastOffset: CGFloat?
    private var travel: CGFloat = 0
    /// Moved by a pull: by its layer alone (a transform and a mask), never
    /// its frame. Moving the view itself made UIKit work out its safe area
    /// again every frame and WebKit lay the whole page out again, which
    /// froze the glide (step 3b); a layer change is invisible to both. The
    /// page's insets also stay as they were until it's let go.
    var held: PageHold? {
        didSet {
            guard held != oldValue else { return }
            if oldValue == nil { heldTop = min(safeAreaInsets.top, bounds.height) }
            applyHold()
            if held == nil { setNeedsLayout() }
        }
    }
    /// The status bar's height as the hold began.
    private var heldTop: CGFloat = 0
    /// Holds the web view and the page's color behind it, and is what a
    /// pull moves. A view of Firn's own that SwiftUI never sizes: SwiftUI
    /// sets this frame's own frame on every update, and with a scale on it
    /// UIKit grew its size to match (402 to 434pt wide mid-pull), so WebKit
    /// laid the page out again. Laid out by bounds and center only, which a
    /// transform leaves alone.
    private let mover = UIView()
    private let holdMask: CALayer = {
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.cornerCurve = .continuous
        return mask
    }()

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(mover)
        if webView.frame.isEmpty { webView.frame = mover.bounds }
        mover.addSubview(webView)
        updateStripColor()
        addRefreshControl()
        // KVO hands changes over on the main thread here: WebKit sets both
        // colors from the main thread.
        colorWatchers = [
            webView.observe(\.themeColor) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateStripColor() }
            },
            webView.observe(\.underPageBackgroundColor) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateStripColor() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.endRefreshing() }
            },
            webView.scrollView.observe(\.contentOffset) { [weak self] scroller, _ in
                MainActor.assumeIsolated { self?.scrolled(scroller) }
            },
        ]
    }

    // MARK: Reader

    /// Reader's view, over the page while Reader is on (`ReaderPage`).
    private(set) var reader: WKWebView?
    private var readerWatcher: NSKeyValueObservation?
    /// What's on screen and scrolled: Reader's view, or the page.
    private var front: WKWebView { reader ?? webView }

    /// How Reader's view comes and goes.
    enum ReaderMotion {
        /// At once (a page shown again with Reader already on).
        case instant
        /// A 0.2s cross-fade (Reduce Motion).
        case fade
        /// An edge sweeping down from the top, as Safari's: into Reader it
        /// uncovers the reader, out of it the page.
        case sweep
    }

    /// Into Reader: how long the edge takes to cross the screen, and how
    /// long it waits at most for the reader's first drawn frame.
    private static let sweepDuration: CFTimeInterval = 0.2
    /// Longer than the plan's 0.5s: in the Simulator's Debug build the
    /// reader took 0.5 to 0.65s to lay out, and sweeping in an empty page
    /// is the very cut this replaces.
    private static let sweepWait: TimeInterval = 0.8
    /// Fast at first, easing out, as Safari's edge.
    private static let sweepCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.3, 1)
    /// Uncovers Reader's view from the top while it sweeps in.
    private let sweepMask: CALayer = {
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.anchorPoint = .zero
        return mask
    }()
    /// Out of Reader (step 2): quicker, the page uncovered as the reader
    /// is cut away from the top, the page coming in a quarter darker and
    /// clearing just behind the edge.
    private static let leaveDuration: CFTimeInterval = 0.12
    private static let leaveDimDelay: TimeInterval = 0.04
    private static let leaveDimDuration: TimeInterval = 0.1
    /// Keeps the reader's part below the edge while it sweeps out. Its own
    /// layer, so Reader opened again mid-sweep has `sweepMask` to itself.
    private let leaveMask: CALayer = {
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.anchorPoint = CGPoint(x: 0, y: 1)
        return mask
    }()
    /// The page's quarter-dark as it comes back: ink at 25%, warm, never
    /// grey, over the page and under the leaving reader.
    private let leaveDim: UIView = {
        let dim = UIView()
        dim.backgroundColor = UIColor(red: 0x24 / 255, green: 0x1F / 255, blue: 0x1B / 255, alpha: 1)
        dim.isUserInteractionEnabled = false
        dim.isAccessibilityElement = false
        return dim
    }()
    /// The layer `sweepMask` was last put on.
    private weak var sweepMaskOwner: CALayer?
    /// Waits for the reader's first drawn frame before the sweep.
    private var sweepWatcher: NSKeyValueObservation?
    private var sweepTimeout: DispatchWorkItem?

    /// Shows Reader's view over the page, or takes it away. It sits in the
    /// mover with the page, so a pull carries it as it carries the page,
    /// and it gets the same room under the clock and above the bar, and
    /// shrinks the bar the same way. Once covered, the page is hidden, so
    /// neither touches nor VoiceOver reach it behind the reader. No pull to
    /// refresh in the reader: there's nothing of its own to reload.
    ///
    /// Into Reader (`docs/HISTORY.md`, "Plan: Reader comes down from the
    /// top", step 1): the reader goes in front at once, masked away and
    /// untouchable, until its page has drawn (it's its own web view, empty
    /// at first: shown straight away, the empty view and then its first
    /// frame made a cut). Then a straight edge uncovers it from the top of
    /// the screen to the bottom. Nothing moves or dims; only the mask does,
    /// on Core Animation. If it hasn't drawn within 0.8s, it sweeps anyway.
    ///
    /// Out of Reader (step 2): the same direction, quicker: an edge cuts
    /// the reader away from the top down, uncovering the page, which comes
    /// in a quarter darker and clears just behind the edge.
    func show(reader newReader: WKWebView?, motion: ReaderMotion) {
        guard newReader !== reader else { return }
        let old = reader
        reader = newReader
        lastOffset = nil
        travel = 0
        // Out of a reader still sweeping in: one never seen just goes; one
        // half uncovered fades from where its edge is, rather than jumping
        // whole and sweeping again.
        var motion = motion
        if old != nil, newReader == nil, motion != .instant {
            if sweepDone != nil {
                motion = .instant
            } else if sweepRunning != nil, let shown = sweepMask.presentation()?.bounds {
                sweepMask.removeAllAnimations()
                sweepMask.bounds = shown
                sweepRunning = nil
                motion = .fade
            }
        }
        cancelSweep(old, keepingMask: motion == .fade)
        readerWatcher = newReader?.scrollView.observe(\.contentOffset) { [weak self] scroller, _ in
            MainActor.assumeIsolated { self?.scrolled(scroller) }
        }
        if let newReader {
            newReader.frame = mover.bounds
            newReader.alpha = 0
            newReader.scrollView.contentInsetAdjustmentBehavior = .never
            mover.insertSubview(newReader, aboveSubview: old ?? webView)
            applyInsets(to: newReader)
        } else {
            webView.isHidden = false
        }
        let done = { [weak self] in
            guard let self else { return }
            if let old, old !== self.reader { old.removeFromSuperview() }
            if self.reader != nil, self.reader === newReader { self.webView.isHidden = true }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        guard motion != .instant, window != nil else {
            newReader?.alpha = 1
            old?.alpha = 0
            done()
            return
        }
        if motion == .sweep, let newReader, old == nil {
            sweep(in: newReader, then: done)
            return
        }
        if motion == .sweep, newReader == nil, let old {
            sweep(out: old, then: done)
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            newReader?.alpha = 1
            old?.alpha = 0
        } completion: { _ in
            MainActor.assumeIsolated { done() }
        }
    }

    /// Masks the reader away, waits for its first drawn frame, then sweeps.
    private func sweep(in reader: WKWebView, then done: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sweepMask.removeAllAnimations()
        sweepMask.frame = CGRect(x: 0, y: 0, width: reader.bounds.width, height: 0)
        // A reader that faded out half uncovered may still hold it.
        if let owner = sweepMaskOwner, owner.mask === sweepMask { owner.mask = nil }
        reader.layer.mask = sweepMask
        sweepMaskOwner = reader.layer
        CATransaction.commit()
        reader.alpha = 1
        reader.isUserInteractionEnabled = false
        reader.accessibilityElementsHidden = true
        sweepDone = done

        // Drawn: the reader's first layout reaching the screen, which is
        // when its content size first arrives (WebKit sends both with the
        // same commit), then a frame. Not its load's end: that waits for
        // every picture, often past the timeout, and swept in an empty
        // page (Simulator, 2026-11-18).
        sweepWatcher = reader.scrollView.observe(\.contentSize) { [weak self] scroller, _ in
            MainActor.assumeIsolated {
                guard scroller.contentSize.height > 0 else { return }
                self?.startSweepSoon()
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.startSweep() }
        }
        sweepTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sweepWait, execute: timeout)
    }

    /// What the sweep does once it starts; set only while one is waiting.
    private var sweepDone: (() -> Void)?

    private func startSweepSoon() {
        sweepWatcher = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            MainActor.assumeIsolated { self?.startSweep() }
        }
    }

    /// Once only, and only for the reader still on screen.
    private func startSweep() {
        guard let done = sweepDone, let reader else { return }
        sweepDone = nil
        sweepWatcher = nil
        sweepTimeout?.cancel()
        sweepTimeout = nil
        sweepRunning = done
        runSweep(on: reader)
    }

    /// What the running sweep does when it ends.
    private var sweepRunning: (() -> Void)?

    private func runSweep(on reader: WKWebView) {
        let full = reader.bounds
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak reader] in
            MainActor.assumeIsolated {
                guard let self, let reader, self.reader === reader,
                      let done = self.sweepRunning else { return }
                self.sweepRunning = nil
                self.finishSweep(reader)
                done()
            }
        }
        let grow = CABasicAnimation(keyPath: "bounds.size.height")
        grow.fromValue = 0
        grow.toValue = full.height
        grow.duration = Self.sweepDuration
        grow.timingFunction = Self.sweepCurve
        sweepMask.bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        sweepMask.add(grow, forKey: "sweep")
        CATransaction.commit()
    }

    /// Cuts the leaving reader away from the top, the page under it coming
    /// in dimmed and clearing behind the edge. The reader can't be touched
    /// as it goes; the page can at once.
    private func sweep(out reader: WKWebView, then done: @escaping () -> Void) {
        let full = reader.bounds
        reader.isUserInteractionEnabled = false
        reader.accessibilityElementsHidden = true
        leaveDim.layer.removeAllAnimations()
        leaveDim.frame = mover.bounds
        leaveDim.alpha = 0.25
        mover.insertSubview(leaveDim, belowSubview: reader)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leaveMask.removeAllAnimations()
        leaveMask.bounds = CGRect(x: 0, y: 0, width: full.width, height: 0)
        leaveMask.position = CGPoint(x: 0, y: full.height)
        reader.layer.mask = leaveMask
        CATransaction.commit()

        leaveDone = done
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak reader] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let reader, reader.layer.mask === self.leaveMask { reader.layer.mask = nil }
                let done = self.leaveDone
                self.leaveDone = nil
                done?()
            }
        }
        let shrink = CABasicAnimation(keyPath: "bounds.size.height")
        shrink.fromValue = full.height
        shrink.toValue = 0
        shrink.duration = Self.leaveDuration
        shrink.timingFunction = Self.sweepCurve
        leaveMask.add(shrink, forKey: "sweep")
        CATransaction.commit()

        UIView.animate(withDuration: Self.leaveDimDuration, delay: Self.leaveDimDelay,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.leaveDim.alpha = 0
        } completion: { _ in
            MainActor.assumeIsolated {
                if self.leaveDim.alpha == 0 { self.leaveDim.removeFromSuperview() }
            }
        }
    }

    /// What the sweep out does when it ends.
    private var leaveDone: (() -> Void)?

    private func finishSweep(_ reader: WKWebView, keepingMask: Bool = false) {
        if !keepingMask, reader.layer.mask === sweepMask { reader.layer.mask = nil }
        sweepMask.removeAllAnimations()
        reader.isUserInteractionEnabled = true
        reader.accessibilityElementsHidden = false
    }

    /// A sweep still waiting or running when Reader closes (or is swapped):
    /// it stops, and the old reader is left as it was otherwise.
    private func cancelSweep(_ old: WKWebView?, keepingMask: Bool = false) {
        sweepDone = nil
        sweepRunning = nil
        sweepWatcher = nil
        sweepTimeout?.cancel()
        sweepTimeout = nil
        if let old { finishSweep(old, keepingMask: keepingMask) }
    }

    /// iOS's own pull-to-refresh. The spinner tucks away as soon as the
    /// load starts (or at once if there was nothing to load): from then on
    /// the bar's loading frost shows it, so there's one sign, not two.
    private func addRefreshControl() {
        let refresher = UIRefreshControl()
        refresher.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onRefresh?()
            if !webView.isLoading {
                DispatchQueue.main.async { [weak self] in self?.endRefreshing() }
            }
        }, for: .valueChanged)
        // Shown again (a new holder for the same page) replaces the old one.
        webView.scrollView.refreshControl = refresher
    }

    private func endRefreshing() {
        guard let refresher = webView.scrollView.refreshControl,
              refresher.isRefreshing else { return }
        refresher.endRefreshing()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// How far the page must move one way before the bar changes, so a
    /// small wobble of the finger never flickers it.
    private static let turnDistance: CGFloat = 24

    /// Only your own scrolling counts (a drag and the glide after it), not a
    /// page jumping to a #link or scrolling itself. At the top the bar is
    /// always full; past the end (a bounce) nothing changes, as Safari
    /// leaves it small there; a page with nothing to scroll never shrinks.
    private func scrolled(_ scroller: UIScrollView) {
        // Only the view in front: the page under the reader keeps still.
        guard scroller === front.scrollView else { return }
        let y = scroller.contentOffset.y
        defer { lastOffset = y }
        guard let onScroll, let last = lastOffset else { return }
        let top = -scroller.contentInset.top
        if y <= top + 1 {
            travel = 0
            if scroller.isTracking || scroller.isDecelerating { onScroll(.grow) }
            return
        }
        guard scroller.isTracking || scroller.isDecelerating else {
            travel = 0
            return
        }
        let end = endOffset(front)
        guard end > top + Self.turnDistance, y < end, last < end else {
            travel = 0
            return
        }
        let moved = y - last
        guard moved != 0 else { return }
        if (moved > 0) != (travel > 0) { travel = 0 }
        travel += moved
        if travel > Self.turnDistance {
            onScroll(.shrink)
        } else if travel < -Self.turnDistance {
            onScroll(.grow)
        }
    }

    private func updateStripColor() {
        // The same color the page reports as `topColor`, for the glide.
        mover.backgroundColor = webView.themeColor ?? webView.underPageBackgroundColor
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        if held == nil { setNeedsLayout() }
    }

    /// Scales the page below the status bar into the hold's box, about the
    /// layer's own middle, worked out from where the view rests (its
    /// center and bounds, which a layer transform leaves alone).
    private func applyHold() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let size = mover.bounds.size
        guard let held, size.width > 0, size.height > heldTop, window != nil, held.box.width > 0 else {
            mover.layer.transform = CATransform3DIdentity
            mover.layer.mask = nil
            return
        }
        let rest = convert(mover.bounds, to: nil)
        let source = CGRect(x: 0, y: heldTop, width: size.width, height: size.height - heldTop)
        let scale = held.box.width / source.width
        let middle = CGPoint(x: rest.midX, y: rest.midY)
        let sourceTop = CGPoint(x: rest.minX + source.minX, y: rest.minY + source.minY)
        let shift = CGPoint(x: held.box.minX - middle.x - scale * (sourceTop.x - middle.x),
                            y: held.box.minY - middle.y - scale * (sourceTop.y - middle.y))
        mover.layer.transform = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: shift.x, ty: shift.y))
        let top = heldTop * min(max(held.topShown, 0), 1)
        holdMask.frame = held.includesTop ? CGRect(origin: .zero, size: size)
            : CGRect(x: 0, y: heldTop - top, width: size.width, height: source.height + top)
        holdMask.cornerRadius = held.radius / scale
        if mover.layer.mask !== holdMask { mover.layer.mask = holdMask }
    }

    /// Firn's bar's room from the screen's bottom edge; 0 for no bar.
    var barRoom: CGFloat = 0 {
        didSet { if barRoom != oldValue { setNeedsLayout() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Only on a real change: each new frame lays the page out again.
        // By bounds and center: the mover may be held (scaled), and its
        // frame then isn't its size.
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        if mover.bounds.size != bounds.size || mover.center != middle {
            mover.bounds = CGRect(origin: .zero, size: bounds.size)
            mover.center = middle
            if held != nil { applyHold() }
        }
        for view in [webView, reader].compactMap({ $0 }) where view.frame != mover.bounds {
            view.frame = mover.bounds
        }
        // Held by a pull: the insets wait until it's let go.
        guard held == nil else { return }
        applyInsets(to: webView)
        if let reader { applyInsets(to: reader) }
    }

    /// Tells a web view (the page, or Reader's) what the status bar and
    /// Firn's bar cover.
    private func applyInsets(to webView: WKWebView) {
        let top = min(safeAreaInsets.top, bounds.height)
        let covered = UIEdgeInsets(top: top, left: 0, bottom: barRoom, right: 0)
        if webView.obscuredContentInsets != covered {
            webView.obscuredContentInsets = covered
        }
        let scroller = webView.scrollView
        // Firn's inset already holds the status bar; left automatic, iOS
        // added the safe area again (124pt), and a page bounced back to the
        // top settled 62pt too low (David's recording, 2026-11-05).
        if scroller.contentInsetAdjustmentBehavior != .never {
            scroller.contentInsetAdjustmentBehavior = .never
        }
        if scroller.contentInset != covered {
            let grew = covered.bottom - scroller.contentInset.bottom
            let wasAtEnd = scroller.contentOffset.y >= endOffset(webView) - 1
            scroller.contentInset = covered
            scroller.verticalScrollIndicatorInsets = covered
            if grew > 0, wasAtEnd { keepEndInView(webView) }
        }
        // iOS's own choice, as Safari's: `.soft` ran the blur about 80pt
        // down and whiter; `.automatic` ends just under the clock (2026-11-05).
        scroller.topEdgeEffect.style = .automatic
    }

    /// The furthest the page scrolls down: its end just clear of the bar.
    private func endOffset(_ webView: WKWebView) -> CGFloat {
        let scroller = webView.scrollView
        return scroller.contentSize.height + scroller.contentInset.bottom - scroller.bounds.height
    }

    /// The bar grew while the page rested at its end (a tap on the small
    /// pill): the page slides up by the difference in the bar's own glide,
    /// so its end stays whole above the full bar, as in Safari (phase 5,
    /// step 3). A page with nothing to scroll stays at its top.
    private func keepEndInView(_ webView: WKWebView) {
        let scroller = webView.scrollView
        let top = -scroller.contentInset.top
        let target = endOffset(webView)
        guard target > top, !scroller.isTracking else { return }
        let move = { scroller.contentOffset.y = target }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: move)
        } else {
            // The bar's `shrinkGlide`: a 0.32s spring with no bounce.
            UIView.animate(springDuration: 0.32, bounce: 0, animations: move)
        }
    }
}
#endif
