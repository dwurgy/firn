import AppKit
import FirnCore
import SwiftUI

/// ⌃Tab's keys, as ⌘Tab's: pressed, a switch starts (`WindowModel.pressTabSwitch`);
/// Tab, ⇧Tab, and ← → move the pick while ⌃ is held; letting go of ⌃ (or
/// Return) shows it; Esc stays put. AppKit, because letting go of ⌃ is
/// only a modifier change, which SwiftUI's shortcuts never report.
struct TabSwitchKeys: NSViewRepresentable {
    let window: WindowModel

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) { view.model = window }

    final class KeyView: NSView {
        var model: WindowModel?
        private var monitor: Any?
        private var resignObserver: (any NSObjectProtocol)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            monitor = nil
            resignObserver = nil
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                let caught = MainActor.assumeIsolated { self?.catches(event) ?? false }
                return caught ? nil : event
            }
            // Another window or app in front mid-switch: ⌃'s release won't reach us.
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model?.cancelTabSwitch() }
            }
        }

        /// Only in this window. While a switch is on, every key is its own,
        /// so nothing types into the page meanwhile.
        private func catches(_ event: NSEvent) -> Bool {
            guard let model, let window, event.window === window else { return false }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let switching = model.tabSwitcher != nil
            if event.type == .flagsChanged {
                if switching, !flags.contains(.control) { model.finishTabSwitch() }
                return false
            }
            switch event.keyCode {
            case 48 where flags.subtracting(.shift) == .control: // Tab
                model.pressTabSwitch(backward: flags.contains(.shift))
                return true
            case 53 where switching: model.cancelTabSwitch() // Esc
            case 36, 76: if switching { model.finishTabSwitch() } // Return, Enter
            case 123: model.moveTabSwitch(by: -1) // ←
            case 124: model.moveTabSwitch(by: 1) // →
            default: break
            }
            return switching
        }
    }
}
