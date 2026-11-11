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
    }

    public func makeUIViewController(context: Context) -> PageHolder {
        PageHolder(page: webKitPage)
    }

    public func updateUIViewController(_ holder: PageHolder, context: Context) {
        holder.barTop = barTop
        guard let frame = holder.view as? PageFrame else { return }
        frame.onScroll = onScroll
        frame.held = held
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

    public init(box: CGRect, radius: CGFloat, includesTop: Bool = false) {
        self.box = box
        self.radius = radius
        self.includesTop = includesTop
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
            webView.scrollView.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scrolled() }
            },
        ]
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
    private func scrolled() {
        let scroller = webView.scrollView
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
        let end = scroller.contentSize.height + scroller.contentInset.bottom - scroller.bounds.height
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
        holdMask.frame = held.includesTop ? CGRect(origin: .zero, size: size) : source
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
        if webView.frame != mover.bounds { webView.frame = mover.bounds }
        // Held by a pull: the insets wait until it's let go.
        guard held == nil else { return }
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
            let wasAtEnd = scroller.contentOffset.y >= endOffset - 1
            scroller.contentInset = covered
            scroller.verticalScrollIndicatorInsets = covered
            if grew > 0, wasAtEnd { keepEndInView() }
        }
        // iOS's own choice, as Safari's: `.soft` ran the blur about 80pt
        // down and whiter; `.automatic` ends just under the clock (2026-11-05).
        scroller.topEdgeEffect.style = .automatic
    }

    /// The furthest the page scrolls down: its end just clear of the bar.
    private var endOffset: CGFloat {
        let scroller = webView.scrollView
        return scroller.contentSize.height + scroller.contentInset.bottom - scroller.bounds.height
    }

    /// The bar grew while the page rested at its end (a tap on the small
    /// pill): the page slides up by the difference in the bar's own glide,
    /// so its end stays whole above the full bar, as in Safari (phase 5,
    /// step 3). A page with nothing to scroll stays at its top.
    private func keepEndInView() {
        let scroller = webView.scrollView
        let top = -scroller.contentInset.top
        let target = endOffset
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
