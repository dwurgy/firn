import FirnCore
import SwiftUI

/// Basecamp: the space's everyday sites as square tiles at the top of the
/// sidebar. Hidden while empty. Shows nothing but this space's own tiles.
struct BasecampGrid: View {
    let store: BrowserStore
    let window: WindowModel

    var body: some View {
        let tiles = store.basecampTabs
        if !tiles.isEmpty {
            BasecampFlow {
                ForEach(tiles) { tab in
                    BasecampTile(tab: tab, isActive: tab.id == store.activeTabID) {
                        store.select(tab)
                        window.focusPage()
                    } goHome: {
                        store.goHome(tab)
                        window.focusPage()
                    } remove: {
                        store.removeFromBasecamp(tab)
                    } close: {
                        store.close(tab)
                    }
                }
            }
            .padding(.bottom, Theme.sectionSpacing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Basecamp")
        }
    }
}

/// Places tiles by `BasecampLayout` (balanced rows, never-tiny tiles), left-aligned.
private struct BasecampFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = BasecampLayout.make(count: subviews.count, width: proposal.width ?? 240)
        let rows = CGFloat(layout.rows.count)
        let width = layout.rows.first.map { CGFloat($0) * layout.tileSize + CGFloat($0 - 1) * BasecampLayout.gap } ?? 0
        return CGSize(width: width, height: rows * layout.tileSize + max(rows - 1, 0) * BasecampLayout.gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = BasecampLayout.make(count: subviews.count, width: bounds.width)
        let size = CGFloat(layout.tileSize)
        var index = 0
        for (row, count) in layout.rows.enumerated() {
            for column in 0..<count {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(column) * (size + BasecampLayout.gap),
                        y: bounds.minY + CGFloat(row) * (size + BasecampLayout.gap)),
                    proposal: ProposedViewSize(width: size, height: size))
                index += 1
            }
        }
    }
}

private struct BasecampTile: View {
    let tab: FirnCore.Tab
    let isActive: Bool
    let select: () -> Void
    let goHome: () -> Void
    let remove: () -> Void
    let close: () -> Void
    @State private var hovering = false

    /// The site's first letter, until its own icon is read from the page (3c).
    private var initial: String {
        let host = (tab.homeURL ?? tab.url)?.host(percentEncoded: false) ?? ""
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return site.first.map { String($0).uppercased() } ?? "•"
    }

    private var siteName: String {
        let host = (tab.homeURL ?? tab.url)?.host(percentEncoded: false) ?? tab.title
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        Button(action: select) {
            Text(initial)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.muted)
                .opacity(tab.isResting && !isActive ? 0.6 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileButtonStyle(isActive: isActive))
        .help(siteName)
        .onHover { hovering = $0 }
        .contextMenu {
            if tab.isAwayFromHome {
                Button("Go Back to Home", action: goHome)
            }
            Button("Remove from Basecamp", action: remove)
            Divider()
            Button("Close", action: close)
        }
        .accessibilityLabel(siteName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// A rounded tile: a quiet wash at rest, warm wash on hover and press, lifted when on screen.
private struct TileButtonStyle: ButtonStyle {
    let isActive: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
                    .shadow(color: isActive ? Theme.shadowSoft : .clear, radius: 1, y: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.tabRadius, style: .continuous))
            .onHover { hovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if isActive { return Theme.activeTab }
        if pressed { return Theme.press }
        return hovering ? Theme.press : Theme.hover
    }
}
