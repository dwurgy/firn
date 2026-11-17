import FirnCore
import SwiftUI

// Send to My iPhone (docs/SYNC-PLAN.md, step 6): the tab on screen, or any
// tab from its right-click menu, sent to another of your devices, where it
// opens without being switched to. Shown only with sync on and another
// device known. Tabs sent here open while Firn is in front, with a quiet
// frost note in the bottom row ("From iPhone").

/// The bottom row's note as sent tabs arrive, or as one is sent.
struct SentArrivalNote: Equatable {
    let id = UUID()
    let text: String
    let from: SyncedDevice.Kind?
    /// The first tab that arrived: a click on the note shows it. None for
    /// a tab sent from here.
    let tabID: UUID?
}

extension WindowModel {
    /// Tabs sent here opened (`ICloudSync.openSentTabs`): the note shows,
    /// and VoiceOver hears it. Never switched to.
    func tabsArrived(_ arrival: SentTabsArrival) {
        guard let text = arrival.note else { return }
        sentArrival = SentArrivalNote(text: text, from: arrival.from, tabID: arrival.tabIDs.first)
        AccessibilityNotification.Announcement(text).post()
    }

    /// Sends a tab, and the bottom row quietly says so ("Sent to iPhone"),
    /// so it's clear it went.
    func send(_ tab: FirnCore.Tab, to target: SendTarget) {
        guard sendTab(tab, target) else { return }
        let text = "Sent to \(target.kind.plainName)"
        sentArrival = SentArrivalNote(text: text, from: target.kind, tabID: nil)
        AccessibilityNotification.Announcement(text).post()
    }

    /// The devices this tab can go to: none for a page that isn't a web page.
    func sendTargets(for tab: FirnCore.Tab?) -> [SendTarget] {
        guard let url = tab?.url, WebAddress.isWebURL(url) else { return [] }
        return sendTargets
    }

    /// The note was clicked: the tab that arrived comes to the front.
    func showArrivedTab() {
        guard let id = sentArrival?.tabID, let tab = store.tabs.first(where: { $0.id == id }) else { return }
        if tab.spaceID != store.activeSpaceID, let space = store.spaces.first(where: { $0.id == tab.spaceID }) {
            showSpace { store.selectSpace(space) }
        }
        store.select(tab)
        focusPage()
    }
}

extension SyncedDevice.Kind {
    /// Its symbol: an iPhone, an iPad, or a Mac laptop.
    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }
}

/// "Send to My iPhone" in a menu, or, with several devices, "Send to…" with
/// each one's name. Nothing without another device to send to.
struct SendTabMenu: View {
    let tab: FirnCore.Tab?
    let window: WindowModel
    /// The File menu's words ("Send Tab to My iPhone"), with no symbol.
    var inFileMenu = false

    var body: some View {
        let targets = window.sendTargets(for: tab)
        if let tab, let first = targets.first, let title = SendTarget.menuTitle(for: targets) {
            let words = inFileMenu ? title.replacingOccurrences(of: "Send to", with: "Send Tab to") : title
            if targets.count == 1 {
                if inFileMenu {
                    Button(words) { window.send(tab, to: first) }
                } else {
                    Button(words, systemImage: first.kind.symbol) { window.send(tab, to: first) }
                }
            } else {
                Menu {
                    ForEach(targets) { target in
                        Button(target.name, systemImage: target.kind.symbol) { window.send(tab, to: target) }
                    }
                } label: {
                    if inFileMenu {
                        Text(words)
                    } else {
                        Label(words, systemImage: "laptopcomputer.and.iphone")
                    }
                }
            }
        }
    }
}

/// The note in the bottom row, over the space's name: frost forms in the
/// space's color, it widens to say "From iPhone", holds, and thaws back, as
/// the "Tidied away" pill does. A click shows the tab.
struct SentPill: View {
    let note: SentArrivalNote
    let open: Bool
    let color: Color
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: note.from?.symbol ?? "laptopcomputer.and.iphone")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
                if open {
                    Text(note.text)
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 12)
                        .transition(.opacity)
                }
            }
            .frame(width: open ? nil : 28, height: 28, alignment: .leading)
            .background { FrostGlass(shape: shape, color: color) }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(note.tabID == nil ? "" : "Show the tab")
        // The announcement covers it (`tabsArrived`).
        .accessibilityHidden(true)
    }
}
