import AppKit

// Scratch test: a window with no toolbar. Mode "A" leaves the lights where AppKit puts them;
// mode "B" moves the real buttons into the content view at Dia's spot (17, 19 from the top-left).
let mode = CommandLine.arguments.dropFirst().first ?? "A"
let shotDir = CommandLine.arguments.dropFirst(2).first ?? "/tmp"

final class FlippedView: NSView { override var isFlipped: Bool { true } }

func describe(_ label: String, _ window: NSWindow) {
    print("== \(label)  fullScreen=\(window.styleMask.contains(.fullScreen)) frame=\(window.frame)")
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        guard let b = window.standardWindowButton(type) else { print("  \(type.rawValue): none"); continue }
        var chain: [String] = []
        var v: NSView? = b.superview
        while let s = v { chain.append(String(describing: Swift.type(of: s))); v = s.superview }
        let w = b.window
        let inWin = b.convert(b.bounds, to: nil)
        let onScreen = w.map { $0.convertToScreen(inWin) } ?? .zero
        let fromTop = w.map { $0.frame.maxY - onScreen.maxY } ?? -1
        let fromLeft = w.map { onScreen.minX - $0.frame.minX } ?? -1
        print("  btn\(type.rawValue) hidden=\(b.isHidden) alpha=\(b.alphaValue) win=\(w.map { String(describing: Swift.type(of: $0)) } ?? "nil") winAlpha=\(w?.alphaValue ?? -1) winVisible=\(w?.isVisible ?? false) left=\(fromLeft) top=\(fromTop) chain=\(chain.prefix(4).joined(separator: "<"))")
    }
    for w in NSApp.windows {
        print("  window \(Swift.type(of: w)) frame=\(w.frame) visible=\(w.isVisible) alpha=\(w.alphaValue) parent=\(w.parent.map { String(describing: Swift.type(of: $0)) } ?? "-")")
    }
}

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 900, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self

        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(red: 0.79, green: 0.88, blue: 0.84, alpha: 1).cgColor
        // A stand-in for Firn's 36pt top row, so screenshots show where the lights sit against it.
        let row = NSView(frame: NSRect(x: 100, y: 8, width: 300, height: 36))
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor(white: 1, alpha: 0.6).cgColor
        if mode == "S" {
            let c = FlippedView(frame: content.bounds)
            c.autoresizingMask = [.width, .height]
            content.addSubview(c)
            c.addSubview(row)
            chrome = c
        } else {
            content.addSubview(row)
        }
        window.contentView = content

        if mode == "S" { _ = menuBarHeight; print("  menu bar height: \(menuBarHeight)") }
        if mode == "K" || mode == "S" { makeCopies() } else if mode != "A" { moveButtonsIntoContent() }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        describe("windowed", window)
        shoot("windowed", after: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.window.toggleFullScreen(nil) }
    }

    func moveButtonsIntoContent() {
        guard let content = window.contentView else { return }
        var x: CGFloat = 17
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = window.standardWindowButton(type) else { continue }
            b.removeFromSuperview()
            b.translatesAutoresizingMaskIntoConstraints = true
            b.setFrameOrigin(NSPoint(x: x, y: 19 - 2)) // the button's frame is a bit taller than its 14pt circle
            content.addSubview(b)
            if mode == "P" { pin(b, at: b.frame.origin) }
            x += 23
        }
    }

    var pins: [ObjectIdentifier: NSPoint] = [:]
    var pinObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    // AppKit still lays the buttons out as its own when the menu bar comes down; put them back at once.
    func pin(_ b: NSButton, at origin: NSPoint) {
        let id = ObjectIdentifier(b)
        pins[id] = origin
        b.postsFrameChangedNotifications = true
        if pinObservers[id] != nil { return }
        pinObservers[id] = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: b, queue: nil) { [weak self, weak b] _ in
            MainActor.assumeIsolated {
                guard let self, let b, let want = self.pins[ObjectIdentifier(b)] else { return }
                if b.frame.origin != want && b.superview === self.window.contentView {
                    print("  pin: AppKit moved btn to \(b.frame.origin), putting back")
                    b.setFrameOrigin(want)
                }
            }
        }
    }

    var stripObserver: NSObjectProtocol?

    // The strip AppKit slides down under the menu bar: see-through and click-through.
    func quietStrip() {
        guard let strip = window.childWindows?.first(where: { String(describing: type(of: $0)).contains("ToolbarFullScreen") }) else {
            print("  no strip window"); return
        }
        strip.isOpaque = false
        strip.backgroundColor = .clear
        strip.hasShadow = false
        strip.ignoresMouseEvents = true
        strip.contentView?.isHidden = true
        print("  strip quieted: \(strip.frame)")
        stripObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: strip, queue: nil) { [weak self, weak strip] _ in
            MainActor.assumeIsolated {
                guard let self, let strip else { return }
                let top = self.window.frame.maxY - strip.frame.maxY
                if mode == "S" {
                    // Glide once per direction instead of following AppKit's uneven steps.
                    if top > self.lastStripTop && !self.slidDown {
                        self.slidDown = true
                        self.slide(to: self.menuBarHeight, animated: true)
                    } else if top < self.lastStripTop && self.slidDown {
                        self.slidDown = false
                        self.slide(to: 0, animated: true)
                    }
                    self.lastStripTop = top
                }
                let c = self.copies.first.map { "copy0=\($0.frame.origin)" } ?? ""
                let r = self.window.standardWindowButton(.closeButton).map { "realHidden=\($0.isHidden) realWin=\(String(describing: type(of: $0.window!)))" } ?? ""
                print("  strip moved: top=\(top) alpha=\(strip.alphaValue) \(c) \(r)")
            }
        }
    }

    func windowDidEnterFullScreen(_ note: Notification) {
        if mode == "P" || mode == "K" || mode == "S" { DispatchQueue.main.async { self.quietStrip(); self.hideRealButtons() } }
        describe("didEnterFullScreen", window)
        if mode == "C" || mode == "H" || mode == "P" { DispatchQueue.main.async { self.moveButtonsIntoContent(); describe("C: moved back in", self.window) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            describe("fullScreen +1.5s", self.window)
        }
        shoot("fullscreen", after: 2.0)
        if mode != "H" && mode != "P" && mode != "K" && mode != "S" { DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.window.toggleFullScreen(nil) } }
    }

    var copies: [NSButton] = []
    var chrome: NSView?

    // Dia's slide: once the menu bar's lower edge passes the screen's top, everything moves down with it.
    var lastStripTop: CGFloat = -32
    var slidDown = false
    // Taken while windowed; taller on Macs with a notch.
    lazy var menuBarHeight: CGFloat = max(NSApp.mainMenu?.menuBarHeight ?? 0, 24)

    func slide(to offset: CGFloat, animated: Bool = false) {
        guard let chrome else { return }
        if offset == 0 && !animated { slidDown = false; lastStripTop = -32 }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                chrome.animator().setFrameOrigin(NSPoint(x: 0, y: offset))
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            chrome.setFrameOrigin(NSPoint(x: 0, y: offset))
            CATransaction.commit()
        }
    }

    // Our own copies of the lights: AppKit never lays these out, so it can't move them.
    func makeCopies() {
        guard let content = chrome ?? window.contentView else { return }
        var x: CGFloat = 17
        let actions: [(NSWindow.ButtonType, Selector)] = [
            (.closeButton, #selector(NSWindow.performClose(_:))),
            (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))),
            (.zoomButton, #selector(NSWindow.toggleFullScreen(_:))),
        ]
        for (type, action) in actions {
            guard let b = NSWindow.standardWindowButton(type, for: window.styleMask) else { continue }
            b.target = window
            b.action = action
            b.setFrameOrigin(NSPoint(x: x, y: 17))
            content.addSubview(b)
            copies.append(b)
            x += 23
        }
        hideRealButtons()
    }

    func hideRealButtons() {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
    }

    func windowDidExitFullScreen(_ note: Notification) {
        if mode == "K" || mode == "S" { DispatchQueue.main.async { self.hideRealButtons(); self.slide(to: 0); print("  K after exit: copy0=\(self.copies.first?.frame.origin ?? .zero) realHidden=\(self.window.standardWindowButton(.closeButton)?.isHidden ?? false)") } }
        describe("didExitFullScreen", window)
        if mode == "C" || mode == "H" || mode == "P" { DispatchQueue.main.async { self.moveButtonsIntoContent(); describe("C: moved back after exit", self.window) } }
        shoot("after", after: 1.0)
        if mode != "H" && mode != "P" && mode != "K" && mode != "S" { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) } }
    }

    func shoot(_ name: String, after: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "\(shotDir)/\(mode)-\(name).png"]
            try? p.run()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
