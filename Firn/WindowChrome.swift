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
