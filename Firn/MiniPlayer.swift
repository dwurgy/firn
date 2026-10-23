import FirnCore
import SwiftUI

/// The mini player: a small frosted card above the spaces row while a tab
/// in this space plays out of sight (`BrowserStore.miniPlayerTab`). It shows
/// the site's icon, the tab's title and site, and one play or pause button;
/// a click anywhere else goes to the tab, and the card leaves as it comes
/// on screen. Paused from here, it stays, so the sound can be picked up.
struct MiniPlayer: View {
    let store: BrowserStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tab = store.miniPlayerTab
        ZStack {
            if let tab {
                MiniPlayerCard(tab: tab) { store.select(tab) }
                    .id(tab.id)
                    .padding(.top, Theme.rowSpacing)
                    // Room above the spaces row, so it doesn't sit on them.
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: tab?.id)
    }
}

private struct MiniPlayerCard: View {
    let tab: FirnCore.Tab
    let show: () -> Void
    @State private var hovering = false

    private var site: String {
        let host = tab.url?.host(percentEncoded: false) ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        // A pill, so it reads as its own thing, not a tile or a group card
        // (David, 2026-10-23). The radius is clamped to half its height.
        let shape = RoundedRectangle(cornerRadius: 100, style: .continuous)
        let paused = tab.showsPlay
        Button(action: show) {
            HStack(spacing: 10) {
                SiteIconView(icon: tab.icon, size: 16) {
                    Image(systemName: "globe").foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title)
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.ink)
                    Text(site)
                        .font(Theme.hintFont)
                        .foregroundStyle(Theme.faint)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            // Room for the play or pause button.
            .padding(.leading, 16)
            .padding(.trailing, 44)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { FrostGlass(shape: shape) }
            .overlay { shape.fill(hovering ? Theme.hover : .clear) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show tab")
        .accessibilityLabel("Playing: \(tab.title)")
        .accessibilityHint("Shows the tab")
        .overlay(alignment: .trailing) {
            ChromeButton(paused ? "Play" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") {
                tab.togglePaused()
            }
            .contentTransition(.symbolEffect(.replace))
            .padding(.trailing, 9)
        }
    }
}
