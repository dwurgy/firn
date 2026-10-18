import AppKit
import SwiftUI

/// An empty stretch of frame that moves the window when dragged, and zooms or
/// minimizes it on double-click (following the system setting), like a title bar.
/// AppKit because SwiftUI's WindowDragGesture needs macOS 15.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
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

/// Where the traffic lights sit, measured from the window's top-left corner.
struct TrafficLights: Equatable {
    /// How far below the top edge their centers are.
    var centerY: CGFloat = Theme.pageInset + Theme.rowHeight / 2
    /// How far from the left edge the last one ends.
    var trailingX: CGFloat = 76
}

/// Gives the window an empty, invisible toolbar, so macOS itself places the
/// traffic lights in the roomier spot every app with a toolbar has, then
/// reports where they landed so the sidebar's top row can line up with them.
/// AppKit because SwiftUI only makes a toolbar when it has items to show.
struct WindowSetup: NSViewRepresentable {
    @Binding var lights: TrafficLights
    func makeNSView(context: Context) -> NSView {
        SetupView { measured in
            if measured != lights { lights = measured }
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SetupView: NSView {
        let report: (TrafficLights) -> Void

        init(report: @escaping (TrafficLights) -> Void) {
            self.report = report
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "Firn")
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            // The title bar lays its buttons out after this, so measure on the next turn.
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private func measure() {
            guard let window, let content = window.contentView,
                  let close = window.standardWindowButton(.closeButton),
                  let zoom = window.standardWindowButton(.zoomButton) else { return }
            let closeRect = close.convert(close.bounds, to: content)
            let zoomRect = zoom.convert(zoom.bounds, to: content)
            let centerY = content.isFlipped ? closeRect.midY : content.bounds.height - closeRect.midY
            guard centerY > 0 else { return }
            report(TrafficLights(centerY: centerY, trailingX: zoomRect.maxX))
        }
    }
}

/// Moves the window's own traffic lights sideways (or fades them, with Reduce
/// Motion), so they travel with the sidebar they sit in. macOS still draws and
/// runs them; Firn only shifts them. AppKit puts them back in their home spot
/// whenever it lays out the title bar (a resize, for one), so this notices
/// and shifts them again.
struct TrafficLightsMover: NSViewRepresentable {
    var offset: CGFloat
    var alpha: CGFloat
    /// Fully slid away: hidden, so they can't be clicked.
    var hidden: Bool

    func makeNSView(context: Context) -> MoverView { MoverView() }

    func updateNSView(_ view: MoverView, context: Context) {
        view.offset = offset
        view.alpha = alpha
        view.lightsHidden = hidden
        view.apply()
    }

    final class MoverView: NSView {
        var offset: CGFloat = 0
        var alpha: CGFloat = 1
        var lightsHidden = false
        /// Where macOS puts each button, and where Firn last put it.
        private var home: [NSWindow.ButtonType: CGFloat] = [:]
        private var placed: [NSWindow.ButtonType: CGFloat] = [:]
        private var observers: [NSObjectProtocol] = []
        private var reapplyQueued = false
        private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            for type in Self.types {
                guard let button = window.standardWindowButton(type) else { continue }
                button.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: button, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.buttonMoved(type) }
                })
            }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        /// A button moved. If Firn didn't move it, macOS did: that's its new home.
        private func buttonMoved(_ type: NSWindow.ButtonType) {
            guard let button = window?.standardWindowButton(type) else { return }
            let x = button.frame.origin.x
            guard x != placed[type] else { return }
            home[type] = x
            // macOS is mid-layout; shifting it back right now wouldn't stick.
            guard !reapplyQueued else { return }
            reapplyQueued = true
            DispatchQueue.main.async { [weak self] in
                self?.reapplyQueued = false
                self?.apply()
            }
        }

        func apply() {
            guard let window else { return }
            // In full screen the lights live in the menu bar's drop-down; leave them be.
            let fullScreen = window.styleMask.contains(.fullScreen)
            for type in Self.types {
                guard let button = window.standardWindowButton(type) else { continue }
                let shouldHide = lightsHidden && !fullScreen
                // Changing isHidden makes macOS lay the title bar out again, so do it first.
                if button.isHidden != shouldHide { button.isHidden = shouldHide }
                let homeX = home[type] ?? button.frame.origin.x
                home[type] = homeX
                let x = homeX + (fullScreen ? 0 : offset)
                placed[type] = x
                if button.frame.origin.x != x { button.setFrameOrigin(NSPoint(x: x, y: button.frame.origin.y)) }
                let a = fullScreen ? 1 : alpha
                if button.alphaValue != a { button.alphaValue = a }
            }
        }

        deinit {
            MainActor.assumeIsolated { observers.forEach(NotificationCenter.default.removeObserver) }
        }
    }
}

/// The strip between the sidebar and the page that resizes the sidebar.
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
        override func mouseExited(with event: NSEvent) { onLeave() }

        private func report(_ event: NSEvent) {
            onMove(event.locationInWindow.x)
        }
    }
}
