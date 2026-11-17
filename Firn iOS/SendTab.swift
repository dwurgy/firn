import FirnCore
import SwiftUI

// Send to My Mac (docs/SYNC-PLAN.md, step 6, part 3): the tab on screen, or
// any tab from its hold menu, sent to another of your devices, where it
// opens without being switched to. Shown only with sync on and another
// device known. Tabs sent here open while Firn is in front, with a quiet
// pill just above the bar ("From Mac"), as "Saved to Files" does.

/// The pill's note as sent tabs arrive, or as one is sent.
struct SentNote: Equatable {
    let id = UUID()
    let text: String
    let from: SyncedDevice.Kind?
    /// The first tab that arrived: a tap on the pill shows it. None for a
    /// tab sent from here.
    let tabID: UUID?
}

/// The devices a tab can go to, and the note, kept current by the sync
/// engine (`ICloudSync.onTargetsChange`, `onArrival`). In the environment,
/// so the bar, the page menu, and the overview's menus read only this.
@MainActor @Observable
final class Sending {
    /// The other devices, none while sync is off or before its first sync.
    private(set) var targets: [SendTarget] = []
    /// The pill's words, until it has shown a moment (`SentPill`).
    var note: SentNote?
    @ObservationIgnored private let sync: ICloudSync
    @ObservationIgnored private let store: BrowserStore

    init(sync: ICloudSync, store: BrowserStore) {
        self.sync = sync
        self.store = store
        sync.onTargetsChange = { [weak self] in self?.targets = $0 }
        sync.onArrival = { [weak self] in self?.arrived($0) }
    }

    /// The devices this tab can go to: none for a page that isn't a web page.
    func targets(for tab: FirnCore.Tab?) -> [SendTarget] {
        guard let url = tab?.url, WebAddress.isWebURL(url) else { return [] }
        return targets
    }

    /// Sends a tab, and the pill quietly says so ("Sent to Mac"), so it's
    /// clear it went.
    func send(_ tab: FirnCore.Tab, to target: SendTarget) {
        guard sync.send(tab, to: target) else { return }
        let text = "Sent to \(target.kind.plainName)"
        note = SentNote(text: text, from: target.kind, tabID: nil)
        AccessibilityNotification.Announcement(text).post()
    }

    /// Tabs sent here opened (`ICloudSync.openSentTabs`): the pill shows,
    /// and VoiceOver hears it. Never switched to.
    private func arrived(_ arrival: SentTabsArrival) {
        guard let text = arrival.note else { return }
        note = SentNote(text: text, from: arrival.from, tabID: arrival.tabIDs.first)
        AccessibilityNotification.Announcement(text).post()
    }

    /// The pill was tapped: the tab that arrived comes on screen, in its
    /// own space.
    func showArrivedTab() {
        guard let id = note?.tabID, let tab = store.tabs.first(where: { $0.id == id }) else { return }
        note = nil
        if tab.spaceID != store.activeSpaceID, let space = store.spaces.first(where: { $0.id == tab.spaceID }) {
            store.selectSpace(space)
        }
        store.select(tab)
    }

    /// Menu rows for a tab: "Send to My Mac", or, with several devices,
    /// "Send to…" and each one's name. Nothing without another device.
    func menuItems(for tab: FirnCore.Tab) -> [HoldMenuItem] {
        let targets = targets(for: tab)
        guard let title = SendTarget.menuTitle(for: targets), let first = targets.first else { return [] }
        if targets.count == 1 {
            return [HoldMenuItem(title: title, systemImage: first.kind.symbol) { self.send(tab, to: first) }]
        }
        return [HoldMenuItem(title: title, systemImage: "laptopcomputer.and.iphone", children: targets.map { target in
            HoldMenuItem(title: target.name, systemImage: target.kind.symbol) { self.send(tab, to: target) }
        })]
    }
}

/// Just above the bar as sent tabs arrive ("From Mac") or one is sent
/// ("Sent to Mac"): the device's symbol and the words, on the bar's frost.
/// It waits while the page is away (the overview, typing, the page menu) and
/// shows once it's back, holds a few seconds, then fades. A tap on an
/// arrival shows the tab.
struct SentPill: View {
    let sending: Sending
    let hold: Hold
    let away: Bool
    /// The bar's top edge (global), as `DownloadPill`'s.
    let barTop: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 36
    private static let gap: CGFloat = 10

    var body: some View {
        let on = sending.note != nil && !away && hold.pull == nil && !hold.swiping
        GeometryReader { geo in
            let top = barTop - geo.frame(in: .global).minY
            ZStack {
                if on, let note = sending.note {
                    pill(note)
                        .transition(reduceMotion ? .opacity
                                    : .opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(width: geo.size.width)
            .position(x: geo.size.width / 2, y: top - Self.gap - Self.height / 2)
            .animation(.easeOut(duration: 0.2), value: barTop)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: on)
        // Its few seconds count only while it's seen; a note that came while
        // the overview was open waits for the page.
        .task(id: on ? sending.note?.id : nil) {
            guard on, let id = sending.note?.id else { return }
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled, sending.note?.id == id else { return }
            sending.note = nil
        }
    }

    private func pill(_ note: SentNote) -> some View {
        Button {
            sending.showArrivedTab()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: note.from?.symbol ?? "laptopcomputer.and.iphone")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 20, height: 20)
                Text(note.text)
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
            }
            .font(.subheadline)
            // Fits its 36pt (the bar's own cap); VoiceOver reads it whole.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: Self.height)
            .fixedSize(horizontal: true, vertical: false)
            .background { BarFrost(shape: Capsule()) }
            .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 9, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(note.tabID == nil)
        .accessibilityLabel(note.text)
        .accessibilityHint(note.tabID == nil ? "" : "Shows the tab")
    }
}
