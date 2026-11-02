import AppKit
import FirnCore
import SwiftUI

/// An empty stretch of frame that moves the window when dragged, and zooms or
/// minimizes it on double-click (following the system setting), like a title bar.
/// AppKit because SwiftUI's WindowDragGesture needs macOS 15.
struct WindowDragArea: NSViewRepresentable {
    /// What a right-click on the blank space offers, built when it opens;
    /// nothing when nil.
    var menu: (@MainActor () -> [BlankSpaceMenuItem])?

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.items = menu
    }

    private final class DragView: NSView {
        var items: (@MainActor () -> [BlankSpaceMenuItem])?
        private var actions: [@MainActor () -> Void] = []

        override var mouseDownCanMoveWindow: Bool { true }

        // AppKit, since this blank space is an AppKit view and SwiftUI's
        // context menu doesn't reach it.
        override func menu(for event: NSEvent) -> NSMenu? {
            guard let items = items?(), !items.isEmpty else { return nil }
            let menu = NSMenu()
            actions = []
            for item in items {
                guard let title = item.title else {
                    menu.addItem(.separator())
                    continue
                }
                let menuItem = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: item.key)
                menuItem.keyEquivalentModifierMask = item.modifiers
                menuItem.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
                menuItem.target = self
                menuItem.tag = actions.count
                menuItem.isEnabled = item.enabled
                actions.append(item.action)
                menu.addItem(menuItem)
            }
            // Items turn themselves on and off from `isEnabled`, not validation.
            menu.autoenablesItems = false
            return menu
        }

        @objc private func run(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag]()
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // A click on blank space ends typing (a group's new name is
            // kept), as a click on the page does. Only then: dragging the
            // window never takes the keys away from the page.
            if (window.firstResponder as? NSTextView)?.isFieldEditor == true {
                window.makeFirstResponder(nil)
            }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// One line of the blank space's right-click menu, or a divider (`.divider`).
struct BlankSpaceMenuItem {
    var title: String?
    var symbol = ""
    /// The shortcut it shows (the app menu's own; this only displays it).
    var key = ""
    var modifiers: NSEvent.ModifierFlags = .command
    var enabled = true
    var action: @MainActor () -> Void = {}

    static let divider = BlankSpaceMenuItem(title: nil)
}

/// Sets up the window: no title or toolbar showing, the content running up
/// under the title bar, and see-through. The real traffic lights stay hidden
/// (Firn draws its own, `WindowLights`), and in full screen the strip macOS
/// slides down under the menu bar is made clear and click-through, so only
/// the menu bar itself comes down, as in Dia. As the strip starts down or
/// back up, it tells the window model, which glides the sidebar and the
/// page's top edge with it.
/// AppKit because SwiftUI can't reach the title bar or the full-screen strip.
struct WindowSetup: NSViewRepresentable {
    let window: WindowModel

    func makeNSView(context: Context) -> NSView { SetupView(model: window) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SetupView: NSView {
        private let model: WindowModel
        private var observers: [NSObjectProtocol] = []
        private var stripObserver: NSObjectProtocol?
        /// The strip's top edge, below the window's top, when it last moved.
        private var lastStripTop: CGFloat = 0
        /// The menu bar's height, read while windowed (taller with a notch).
        private var menuBarHeight: CGFloat = 24

        init(model: WindowModel) {
            self.model = model
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        // Invisible; clicks go through to the frame underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // No toolbar: with one, AppKit keeps laying the real lights out as
            // its own, and full screen gets a white bar across the top.
            window.toolbar = nil
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            // See-through, so the frame's glass shows the desktop behind it.
            window.isOpaque = false
            window.backgroundColor = .clear
            hideRealLights()
            readMenuBarHeight()
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] note in
                    let entered = note.name == NSWindow.didEnterFullScreenNotification
                    MainActor.assumeIsolated { self?.model.setFullScreen(entered) }
                    // AppKit attaches the strip, and shows the lights again, just after this.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.hideRealLights()
                            if entered { self?.quietStrip() }
                        }
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.readMenuBarHeight() }
            })
            // Back to rest before AppKit takes its picture for the exit, and
            // stop watching the strip: it moves while leaving and would set
            // off a glide (the lights twitched). Watched again on the next entry.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopWatchingStrip()
                    self?.model.menuBarMoved(to: 0, animated: false)
                }
            })
        }

        /// Only while windowed: in full screen the menu bar is hidden and may read 0.
        private func readMenuBarHeight() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let height = NSApp.mainMenu?.menuBarHeight ?? 0
            if height > 0 { menuBarHeight = height }
        }

        private func hideRealLights() {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window?.standardWindowButton(type)?.isHidden = true
            }
        }

        /// The strip under the menu bar (`NSToolbarFullScreenWindow`, a private
        /// class, so it's found by name): clear, no shadow, and clicks pass through.
        private func quietStrip() {
            guard let strip = window?.childWindows?.first(where: {
                String(describing: type(of: $0)).contains("ToolbarFullScreen")
            }) else { return }
            strip.isOpaque = false
            strip.backgroundColor = .clear
            strip.hasShadow = false
            strip.ignoresMouseEvents = true
            strip.contentView?.isHidden = true
            watch(strip)
        }

        /// The strip slides down with the menu bar and back up with it. The
        /// first move each way starts one glide, by the menu bar's height.
        private func watch(_ strip: NSWindow) {
            stopWatchingStrip()
            guard let window else { return }
            lastStripTop = window.frame.maxY - strip.frame.maxY
            stripObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: strip, queue: .main
            ) { [weak self, weak strip] _ in
                MainActor.assumeIsolated {
                    guard let self, let strip, let window = self.window else { return }
                    let top = window.frame.maxY - strip.frame.maxY
                    if top > self.lastStripTop {
                        self.model.menuBarMoved(to: self.menuBarHeight, animated: true)
                    } else if top < self.lastStripTop {
                        self.model.menuBarMoved(to: 0, animated: true)
                    }
                    self.lastStripTop = top
                }
            }
        }

        private func stopWatchingStrip() {
            if let stripObserver { NotificationCenter.default.removeObserver(stripObserver) }
            stripObserver = nil
        }

        deinit {
            MainActor.assumeIsolated {
                observers.forEach(NotificationCenter.default.removeObserver)
                stopWatchingStrip()
            }
        }
    }
}

/// Firn's own traffic lights: macOS's close, minimize, and full-screen
/// buttons (made with `NSWindow.standardWindowButton(_:for:)`), placed in the
/// sidebar's top row where macOS put them when Firn had a toolbar (19pt from
/// the window's top and left). They're copies because AppKit keeps moving the
/// window's real ones back as its own, in full screen most of all; copies sit
/// in Firn's own views, so they stay put and travel with the sidebar.
/// AppKit because SwiftUI has no traffic lights.
struct WindowLights: NSViewRepresentable {
    /// From the row's top-left: the row starts 8pt into the window each way.
    static let origin = CGPoint(x: 11, y: 11)
    static let spacing: CGFloat = 23

    func makeNSView(context: Context) -> LightsView { LightsView() }
    func updateNSView(_ view: LightsView, context: Context) {}

    final class LightsView: NSView {
        private var buttons: [NSButton] = []
        private var observers: [NSObjectProtocol] = []
        private var pointerInside = false

        override var isFlipped: Bool { true }

        // Only the buttons take clicks; the rest of the row still moves the window.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            buttons.forEach { $0.removeFromSuperview() }
            buttons = []
            guard let window else { return }
            let kinds: [(NSWindow.ButtonType, Selector)] = [
                (.closeButton, #selector(NSWindow.performClose(_:))),
                (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))),
                (.zoomButton, #selector(NSWindow.toggleFullScreen(_:))),
            ]
            for (index, (type, action)) in kinds.enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: window.styleMask) else { continue }
                button.target = window
                button.action = action
                button.setFrameOrigin(NSPoint(x: WindowLights.origin.x + CGFloat(index) * WindowLights.spacing, y: WindowLights.origin.y))
                addSubview(button)
                buttons.append(button)
            }
            // Grey while the window is in the background, lit when it comes forward.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.redrawButtons() }
                })
            }
        }

        // The whole view, not the buttons' frames: this can run before the
        // buttons exist, and a rectangle taken then would cover nothing.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { pointerMoved(event) }
        override func mouseMoved(with event: NSEvent) { pointerMoved(event) }
        override func mouseExited(with event: NSEvent) { setPointerInside(false) }

        /// Over the three lights themselves, not the air around them.
        private func pointerMoved(_ event: NSEvent) {
            guard let first = buttons.first, let last = buttons.last else { return }
            setPointerInside(first.frame.union(last.frame).contains(convert(event.locationInWindow, from: nil)))
        }

        private func setPointerInside(_ inside: Bool) {
            guard inside != pointerInside else { return }
            pointerInside = inside
            redrawButtons()
        }

        /// In SwiftUI's layer-backed views `needsDisplay` alone doesn't redraw
        /// them; `updateCell` makes each button take its look afresh.
        private func redrawButtons() {
            for button in buttons {
                if let cell = button.cell { button.updateCell(cell) }
                button.needsDisplay = true
            }
        }

        /// The buttons ask the view they sit in whether the pointer is over
        /// the group, to show ×, −, and + on all three at once. A private
        /// AppKit question (the title bar answers it for the real ones), long
        /// relied on by apps that place their own lights.
        @objc func _mouseInGroup(_ button: NSButton) -> Bool { pointerInside }

        deinit {
            MainActor.assumeIsolated { observers.forEach(NotificationCenter.default.removeObserver) }
        }
    }
}

/// The window's frosted frame: the desktop, blurred by macOS, under a warm
/// wash of the frame color, so it stays sand and brown whatever is behind it.
/// Over the page (the sidebar peeking) it frosts the page instead. With
/// Reduce Transparency, the plain frame color.
struct FrameGlass: View {
    var overPage = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Theme.frame
        } else {
            ZStack {
                if overPage {
                    Rectangle().fill(.ultraThinMaterial)
                } else {
                    BehindWindowBlur()
                }
                Theme.frameWash
            }
        }
    }
}

/// The system's behind-window blur. AppKit because SwiftUI's materials only
/// blur what's inside the window. Always active, so the frame doesn't change
/// when another app comes to the front.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The strip between the sidebar and the page that resizes the sidebar
/// (and the gap between split view's pages).
/// AppKit because a cursor rectangle is the only dependable way to show the
/// resize cursor next to a web view (which keeps setting its own), and mouse
/// tracking in screen points doesn't drift as the strip itself moves.
struct SidebarResizeGrip: NSViewRepresentable {
    /// How far the pointer has moved sideways since the press.
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> GripView { GripView() }

    func updateNSView(_ view: GripView, context: Context) {
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onDoubleClick = onDoubleClick
    }

    final class GripView: NSView {
        var onDrag: (CGFloat) -> Void = { _ in }
        var onEnd: () -> Void = {}
        var onDoubleClick: () -> Void = {}
        private var startX: CGFloat?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                startX = nil
                onDoubleClick()
            } else {
                startX = NSEvent.mouseLocation.x
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startX else { return }
            NSCursor.resizeLeftRight.set()
            onDrag(NSEvent.mouseLocation.x - startX)
        }

        override func mouseUp(with event: NSEvent) {
            guard startX != nil else { return }
            startX = nil
            onEnd()
        }
    }
}

/// Reports where the pointer is across the whole window, even over the web
/// page, and when it leaves. AppKit because a tracking area hears every mouse
/// movement regardless of which view is under the pointer, where SwiftUI's
/// hover only hears its own views (and reports neighbors in no fixed order).
struct PointerTracker: NSViewRepresentable {
    /// The pointer's distance from the window's left edge.
    var onMove: (CGFloat) -> Void
    var onLeave: () -> Void

    func makeNSView(context: Context) -> TrackerView { TrackerView() }
    func updateNSView(_ view: TrackerView, context: Context) {
        view.onMove = onMove
        view.onLeave = onLeave
    }

    final class TrackerView: NSView {
        var onMove: (CGFloat) -> Void = { _ in }
        var onLeave: () -> Void = {}

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            ))
        }

        // Only listens; clicks go through to whatever is underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) {
            window?.isMovable = true
            onLeave()
        }

        private func report(_ event: NSEvent) {
            onMove(event.locationInWindow.x)
            keepPageClickable(at: event.locationInWindow)
        }

        /// macOS drags the window from anywhere in the title bar's band, even
        /// over the web page beneath it, before Firn hears about the click.
        /// So the window can't be moved while the pointer is over a page.
        private func keepPageClickable(at point: NSPoint) {
            guard let window, let frame = window.contentView?.superview else { return }
            var view = frame.hitTest(frame.convert(point, from: nil))
            var overPage = false
            while let current = view, !overPage {
                overPage = current is PageHolder
                view = current.superview
            }
            if window.isMovable == overPage { window.isMovable = !overPage }
        }
    }
}

/// A window's title in Fraunces, as the Electron app's Settings and History
/// had it. macOS draws window titles in the system font and can't be told
/// otherwise, so the system title is hidden from the toolbar and Firn draws
/// its own in the same spot. The window keeps its real title (from
/// `.navigationTitle`) for the Window menu, Mission Control, and VoiceOver.
struct FrauncesWindowTitle: ViewModifier {
    let title: String
    var subtitle: String?

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .modifier(HidesSystemTitle())
            .toolbar {
                if #available(macOS 26, *) {
                    // No glass capsule around words.
                    ToolbarItem(placement: .navigation) { label }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigation) { label }
                }
            }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.panelTitleFont)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.leading, 4)
        .fixedSize()
        // The window's title already says it; this is the same words drawn.
        .accessibilityHidden(true)
    }
}

private struct HidesSystemTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content.background(TitleHider())
        }
    }
}

/// macOS 14 has no SwiftUI way to hide a window's title, so AppKit does it.
private struct TitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiderView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HiderView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titleVisibility = .hidden
        }
    }
}
