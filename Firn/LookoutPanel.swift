import FirnCore
import SwiftUI

/// A Lookout over the page area: the page itself as a card, over a dimmed
/// page, with two small frosted buttons beside it (close, and "Open as
/// tab"). No frame and no address: the sidebar's address bar shows the
/// Lookout's site while it's open. Esc, a click on the dimmed page, or the
/// close button closes it; "Open as tab" grows the card to fill the page
/// area as it becomes the tab. Reduce Motion: fades.
struct LookoutLayer: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 as a card; 1 once grown to fill the page area, just before it
    /// becomes the tab.
    @State private var growth: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pageCornerRadius, style: .continuous)
        ZStack {
            if let lookout = store.lookout {
                shape.fill(Theme.lookoutDim)
                    .opacity(1 - growth)
                    .contentShape(shape)
                    .onTapGesture(perform: close)
                    // Once it's growing into a tab, a stray click can't undo it.
                    .allowsHitTesting(growth == 0)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                LookoutCard(
                    lookout: lookout,
                    color: Theme.spaceColor(store.activeSpace.color),
                    growth: growth,
                    keep: keep,
                    close: close
                )
                .background { EscapeCatcher(onEscape: close) }
                // A new Lookout is a new card, holding its own page.
                .id(lookout.id)
                // It rises a hair as it fades in, and sinks back as it goes.
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.lookout?.id)
        .onChange(of: store.lookout?.id) {
            growth = 0
            // Its page takes the keys, so space and the arrows scroll it.
            if store.lookout != nil { window.focusPage() }
        }
    }

    private func close() {
        guard growth == 0 else { return }
        store.closeLookout()
        window.focusPage()
    }

    /// Grows the card to fill the page area, then hands its page to a new
    /// tab in exactly that spot, so the swap can't be seen. Reduce Motion:
    /// the card fades away from the tab.
    private func keep() {
        guard growth == 0, let id = store.lookout?.id else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { _ = store.keepLookout() }
            window.focusPage()
            return
        }
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.25)) {
            growth = 1
        } completion: {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                // Closed (Esc, ⌘W) or replaced mid-grow: keep nothing.
                if store.lookout?.id == id { store.keepLookout() }
                growth = 0
            }
            window.focusPage()
        }
    }
}

/// The page as a card, with its buttons in the gap to its right. SwiftUI
/// calls `body` on every frame of the grow with the in-between `growth`,
/// so the page's real size and corners follow it smoothly, as the
/// sidebar's slide does.
private struct LookoutCard: View, Animatable {
    let lookout: Lookout
    let color: Color
    var growth: CGFloat
    let keep: () -> Void
    let close: () -> Void

    /// Room around the card, so the dimmed page shows it's a glance and is
    /// easy to click. Even on both sides; the buttons sit in the right-hand gap.
    private static let inset = EdgeInsets(top: 52, leading: 88, bottom: 52, trailing: 88)
    private static let buttonSize: CGFloat = 32
    /// The buttons sit just off the card's right edge, so they read as its own.
    private static let buttonGap: CGFloat = 10

    nonisolated var animatableData: CGFloat {
        get { growth }
        set { growth = newValue }
    }

    var body: some View {
        let shrink = 1 - growth
        let radius = Theme.panelRadius + (Theme.pageCornerRadius - Theme.panelRadius) * growth
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let page = lookout.page
        // The page lays out at the card's own size, full size (as in a
        // narrower window), and again as the card grows into a tab.
        PageView(page: page, cornerRadius: radius)
            .overlay {
                if let error = page.loadError {
                    LoadErrorView(error: error, isRetrying: page.isLoading, retry: page.reload)
                        .background(Theme.page)
                        .clipShape(shape)
                } else if page.url == nil {
                    // Firn's calm page color until something loads, not WebKit's white.
                    shape.fill(Theme.page).allowsHitTesting(false)
                }
            }
            // A hairline keeps the card's edge crisp on the dimmed page.
            .overlay { shape.strokeBorder(Theme.peekEdgeLine.opacity(shrink), lineWidth: 0.5).allowsHitTesting(false) }
            .background {
                shape.fill(Theme.page)
                    .shadow(color: Theme.shadowPeek.opacity(shrink), radius: 24, y: 8)
            }
            .padding(EdgeInsets(
                top: Self.inset.top * shrink,
                leading: Self.inset.leading * shrink,
                bottom: Self.inset.bottom * shrink,
                trailing: Self.inset.trailing * shrink
            ))
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    LookoutButton(label: "Close Lookout", systemImage: "xmark", color: color, action: close)
                    LookoutButton(label: "Open as tab", systemImage: "arrow.up.left.and.arrow.down.right",
                                  color: color, showsLabel: true, action: keep)
                }
                // Just off the card's edge, level with its top.
                .padding(.top, Self.inset.top)
                .padding(.trailing, Self.inset.trailing - Self.buttonGap - Self.buttonSize)
                .opacity(shrink)
                .allowsHitTesting(growth == 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Lookout")
            .accessibilityAddTraits(.isModal)
    }
}

/// A small round frosted button in the space's color. With `showsLabel`,
/// its words slide out to the left while the pointer is on it, so the
/// icon never has to be guessed.
private struct LookoutButton: View {
    let label: String
    let systemImage: String
    let color: Color
    var showsLabel = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsLabel && hovering {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize()
                        .padding(.leading, 12)
                        .transition(.opacity)
                }
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .foregroundStyle(Theme.ink)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                ZStack {
                    // The lifted tabs' backing under the frost, so it stays
                    // frost over a bright or dark page and the words never wash out.
                    FrostGlass(shape: shape, color: color, lifted: true)
                    shape.fill(hovering ? Theme.hover : .clear)
                }
                .shadow(color: Theme.shadowSoft, radius: 6, y: 2)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(LookoutButtonPress())
        .accessibilityLabel(label)
        .help(showsLabel ? "" : label)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2), value: hovering)
    }
}

/// A gentle press: a little dimmer, never a bounce.
private struct LookoutButtonPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Esc closes the Lookout wherever the keys are going, even into a page.
/// AppKit, because the web view takes Esc before SwiftUI's shortcuts see it.
/// Typing in a field (the address bar) keeps its own Esc.
private struct EscapeCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onEscape = onEscape }

    final class CatcherView: NSView {
        var onEscape: (() -> Void)?
        private var monitor: Any?

        // Only listens for keys: clicks pass through to the dimmed page.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let caught = MainActor.assumeIsolated { self?.catches(event) ?? false }
                return caught ? nil : event
            }
        }

        private func catches(_ event: NSEvent) -> Bool {
            guard event.keyCode == 53, let window, event.window === window,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  (window.firstResponder as? NSTextView)?.isFieldEditor != true,
                  let onEscape else { return false }
            onEscape()
            return true
        }
    }
}
