import FirnCore
import SwiftUI

/// Basecamp on the iPhone: the space's everyday sites as frosted tiles at
/// the top of the overview, scrolling away with the list. Hidden while
/// empty. Icon only (the menu and VoiceOver name the site), 56pt tall so a
/// tile is easy to tap, rows balanced up to 4 across (`BasecampLayout`).
/// Shows only this space's own tiles.
struct BasecampTiles: View {
    let store: BrowserStore
    let spots: OverviewSpots
    /// The tile the page is gliding into or out of: hidden, so the page is
    /// the only one of it on screen.
    var gliding: UUID?
    /// The tab on screen (or still held as it while a picked tab grows).
    let onScreen: UUID?
    let open: (FirnCore.Tab) -> Void

    @State private var width: CGFloat = 0

    static let tileHeight: CGFloat = 56
    /// A touch crisper than the rows' 14pt, as the Mac's tiles are to its
    /// rows, so the glass reads as ice.
    static let cornerRadius: CGFloat = 12
    static let gap: CGFloat = 8
    /// Tiles never get narrower than this (the brief's "about 56pt").
    static let minimumWidth: Double = 56
    static let maximumColumns = 4

    private var space: String { store.activeSpace.color }

    var body: some View {
        let tiles = store.basecampTabs
        if !tiles.isEmpty {
            let layout = BasecampLayout.make(count: tiles.count, width: width,
                                             maximumColumns: Self.maximumColumns,
                                             minimumWidth: Self.minimumWidth)
            let tileWidth = tileWidth(for: layout)
            VStack(spacing: Self.gap) {
                ForEach(Array(rows(tiles, layout).enumerated()), id: \.offset) { _, row in
                    // A shorter row sits centered under the longer one.
                    HStack(spacing: Self.gap) {
                        ForEach(row) { tab in
                            tile(tab).frame(width: tileWidth, height: Self.tileHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Basecamp")
        }
    }

    /// The tiles split into the layout's rows, top to bottom.
    private func rows(_ tiles: [FirnCore.Tab], _ layout: BasecampLayout) -> [[FirnCore.Tab]] {
        guard !layout.rows.isEmpty else { return [tiles] }
        var rest = tiles[...]
        return layout.rows.map { count in
            defer { rest = rest.dropFirst(count) }
            return Array(rest.prefix(count))
        }
    }

    /// Every tile the same width: the longest row fills the list's width.
    private func tileWidth(for layout: BasecampLayout) -> CGFloat {
        let columns = CGFloat(layout.rows.first ?? 1)
        return max((width - (columns - 1) * Self.gap) / columns, 0)
    }

    private func tile(_ tab: FirnCore.Tab) -> some View {
        BasecampTile(tab: tab, space: space, isOnScreen: tab.id == onScreen) {
            open(tab)
        }
        .opacity(gliding == tab.id ? 0 : 1)
        // Where it is, so the page can glide into it as the overview opens.
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            spots.frames[tab.id] = frame
            spots.cards.remove(tab.id)
        }
        .id(tab.id)
        .transition(.opacity)
    }
}

/// One tile: the site's icon on Firn's frost, ringed in the space's color
/// while it's the tab on screen.
private struct BasecampTile: View {
    let tab: FirnCore.Tab
    let space: String
    let isOnScreen: Bool
    let open: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let shape = RoundedRectangle(cornerRadius: BasecampTiles.cornerRadius, style: .continuous)

    var body: some View {
        Button(action: open) {
            SiteIconView(icon: tab.icon, size: 24) { LetterMark(site: WebAddress.site(of: tab.homeURL ?? tab.url)) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Frost(shape: Self.shape, space: space, fill: Theme.groupCardFill,
                          solid: reduceTransparency, shadow: Theme.groupCardShadow,
                          shadowRadius: 8, shadowY: 2)
                }
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .overlay {
            if isOnScreen {
                Self.shape.inset(by: -3.5)
                    .strokeBorder(Theme.spaceColor(space), lineWidth: 3)
                    .shadow(color: Theme.spaceColor(space).opacity(0.55), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("\(tab.title.isEmpty ? WebAddress.site(of: tab.homeURL ?? tab.url) : tab.title), Basecamp")
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
    }
}

extension View {
    /// The plain-words answer to a 13th Add to Basecamp.
    func basecampFullAlert(isPresented: Binding<Bool>) -> some View {
        alert("Basecamp is full", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Basecamp holds \(BrowserStore.basecampLimit) sites. To add this one, remove another first.")
        }
    }
}
