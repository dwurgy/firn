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

/// The panel ⌃Tab shows while ⌃ is held: the space's recent tabs as cards,
/// newest first, the pick wearing a frost ring, centered over the page on
/// the command bar's glass. Pointing at a card picks it; a click shows it.
/// It leaves at once when ⌃ is let go, so the page never waits on it.
struct TabSwitcherLayer: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if window.showsTabSwitcher, let switcher = window.tabSwitcher {
                    let tabs = switcher.tabIDs.compactMap { id in store.tabs.first { $0.id == id } }
                    TabSwitcherPanel(tabs: tabs, pickedID: switcher.pickedID,
                                     cardWidth: Self.cardWidth(count: tabs.count, in: proxy.size.width),
                                     window: window, store: store)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.15), value: window.showsTabSwitcher)
    }

    /// The lifted tab's card size, smaller only when the page is too narrow
    /// for five side by side.
    private static func cardWidth(count: Int, in width: CGFloat) -> CGFloat {
        let n = CGFloat(max(count, 1))
        let room = width - 48 - 2 * TabSwitcherPanel.padding - (n - 1) * TabSwitcherPanel.spacing
            - n * 2 * TabSwitcherPanel.cardPadding
        return max(72, min(Theme.liftedCard.width, room / n))
    }
}

private struct TabSwitcherPanel: View {
    let tabs: [FirnCore.Tab]
    let pickedID: UUID
    let cardWidth: CGFloat
    let window: WindowModel
    let store: BrowserStore

    static let padding: CGFloat = 12
    static let spacing: CGFloat = 4
    static let cardPadding: CGFloat = 8

    /// Where the pointer was as the panel appeared: a pointer resting there
    /// doesn't pick; only one that moves does, as with ⌘Tab.
    @State private var restingPointer: CGPoint?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        HStack(spacing: Self.spacing) {
            ForEach(tabs) { tab in
                card(tab, isPicked: tab.id == pickedID)
            }
        }
        .padding(Self.padding)
        .background { CommandBarGlass(shape: shape, color: Theme.spaceColor(store.activeSpace.color)) }
        .clipShape(shape)
        .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
        .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent tabs")
        .onAppear { restingPointer = NSEvent.mouseLocation }
    }

    private func card(_ tab: FirnCore.Tab, isPicked: Bool) -> some View {
        let height = cardWidth * Theme.liftedCard.height / Theme.liftedCard.width
        let picture = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image = window.tabPictures[tab.id] {
                    LiftPicture(image: image)
                } else {
                    // A sleeping page, or one never left yet: its icon on page white.
                    Theme.page.overlay {
                        SiteIconView(icon: tab.icon, size: 28) {
                            Image(systemName: "globe").font(.system(size: 22)).foregroundStyle(Theme.faint)
                        }
                    }
                }
            }
            .frame(width: cardWidth, height: height)
            .clipShape(picture)
            .overlay { picture.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
            .overlay {
                // The pick: the frost ring Firn uses for focus, just outside the picture.
                picture.inset(by: -3)
                    .strokeBorder(Theme.frost, lineWidth: 3)
                    .opacity(isPicked ? 1 : 0)
            }
            HStack(spacing: 6) {
                SiteIconView(icon: tab.icon, size: 14) {
                    Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(Theme.labelFont)
                    .foregroundStyle(isPicked ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .padding(Self.cardPadding)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard case .active = phase, NSEvent.mouseLocation != restingPointer else { return }
            restingPointer = nil
            window.pickTabSwitch(tab.id)
        }
        .onTapGesture {
            window.pickTabSwitch(tab.id)
            window.finishTabSwitch()
        }
        .animation(.easeOut(duration: 0.12), value: isPicked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { window.pickTabSwitch(tab.id); window.finishTabSwitch() }
    }
}
