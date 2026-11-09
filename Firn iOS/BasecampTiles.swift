import FirnCore
import SwiftUI

/// Basecamp on the iPhone: the space's everyday sites as frosted tiles at
/// the top of the overview, scrolling away with the list. Hidden while
/// empty. Icon only (the menu and VoiceOver name the site), 56pt tall so a
/// tile is easy to tap, rows balanced up to 4 across (`BasecampLayout`).
/// Shows only this space's own tiles. Holding a tile opens its menu, which
/// the overview gives (it owns the glides and the shake's undo).
struct BasecampTiles: View {
    let store: BrowserStore
    let spots: OverviewSpots
    /// The tile the page is gliding into or out of: hidden, so the page is
    /// the only one of it on screen.
    var gliding: UUID?
    /// The tab on screen (or still held as it while a picked tab grows).
    let onScreen: UUID?
    /// How far the gliding tile shows: it fades in as the page's picture
    /// lands in it, and out as the picture grows from it.
    var reveal: Double = 1
    /// The tiles' order while one is dragged (the others glide aside);
    /// nil: the store's.
    var order: [UUID]? = nil
    /// The tile lifted and following the finger: its spot stays empty.
    var held: UUID? = nil
    /// A drag is running: iOS's menu lift stops at once.
    var dragging = false
    let open: (FirnCore.Tab) -> Void
    /// The tile's hold menu, in sections split by dividers.
    let menu: @MainActor (FirnCore.Tab) -> [[HoldMenuItem]]
    /// VoiceOver's Move Left and Move Right: the tile to a new spot
    /// (counted without it, as the store counts).
    let move: (FirnCore.Tab, Int) -> Void

    @State private var width: CGFloat = 0

    static let tileHeight: CGFloat = 56
    static let gap: CGFloat = 8
    /// Tiles never get narrower than this (the brief's "about 56pt").
    static let minimumWidth: Double = 56
    static let maximumColumns = 4
    /// The iPhone's rows' 14pt corners, not the Mac's 9pt: on the Mac a
    /// tile is about as round as a tab, and so it is here (David, 2026-11-08).
    static let cornerRadius: CGFloat = 14
    /// Thicker than the Mac's 2.5pt: the iPhone's tile is much bigger.
    static let ringWidth: CGFloat = 3.5

    private var space: String { store.activeSpace.color }

    var body: some View {
        let tiles = shownTiles
        if !tiles.isEmpty {
            let layout = BasecampLayout.make(count: tiles.count, width: width,
                                             maximumColumns: Self.maximumColumns,
                                             minimumWidth: Self.minimumWidth)
            let tileWidth = tileWidth(for: layout)
            let centers = places(count: tiles.count, layout, tileWidth: tileWidth)
            // One stack with every tile placed by its spot, not a stack per
            // row: a tile moving to another row while one is dragged glides
            // there instead of fading out of one row and into the next.
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tab in
                    tile(tab, at: index, of: tiles.count)
                        .frame(width: tileWidth, height: Self.tileHeight)
                        .position(centers[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height(rows: max(layout.rows.count, 1)))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Basecamp")
        }
    }

    /// The tiles in the order shown: the drag's while one moves.
    private var shownTiles: [FirnCore.Tab] {
        let tiles = store.basecampTabs
        guard let order else { return tiles }
        let byID = Dictionary(tiles.map { ($0.id, $0) }) { a, _ in a }
        let ordered = order.compactMap { byID[$0] }
        // A tile added mid-drag (never, but nothing goes missing) at the end.
        return ordered + tiles.filter { !order.contains($0.id) }
    }

    private func height(rows: Int) -> CGFloat {
        CGFloat(rows) * Self.tileHeight + CGFloat(rows - 1) * Self.gap
    }

    /// Each tile's middle, in the layout's rows top to bottom; a shorter
    /// row sits centered under the longer one.
    private func places(count: Int, _ layout: BasecampLayout, tileWidth: CGFloat) -> [CGPoint] {
        let rows = layout.rows.isEmpty ? [count] : layout.rows
        var places: [CGPoint] = []
        for (row, inRow) in rows.enumerated() {
            let rowWidth = CGFloat(inRow) * tileWidth + CGFloat(inRow - 1) * Self.gap
            let left = (width - rowWidth) / 2
            let y = CGFloat(row) * (Self.tileHeight + Self.gap) + Self.tileHeight / 2
            for column in 0..<inRow {
                places.append(CGPoint(x: left + CGFloat(column) * (tileWidth + Self.gap) + tileWidth / 2, y: y))
            }
        }
        // Never fewer spots than tiles, whatever the layout says.
        while places.count < count { places.append(places.last ?? CGPoint(x: width / 2, y: Self.tileHeight / 2)) }
        return places
    }

    /// A tile as it lifts out of the grid to follow the finger: the same
    /// tile, on the solid base (as while its menu is open), so the list
    /// doesn't show through the glass as it passes over it.
    static func lifted(_ tab: FirnCore.Tab, space: String, onScreen: Bool) -> some View {
        BasecampTile(tab: tab, space: space, isOnScreen: onScreen, open: {})
            .background(Theme.tileSolid, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Every tile the same width: the longest row fills the list's width.
    private func tileWidth(for layout: BasecampLayout) -> CGFloat {
        let columns = CGFloat(layout.rows.first ?? 1)
        return max((width - (columns - 1) * Self.gap) / columns, 0)
    }

    private func tile(_ tab: FirnCore.Tab, at index: Int, of count: Int) -> some View {
        BasecampTile(tab: tab, space: space, isOnScreen: tab.id == onScreen) {
            open(tab)
        }
        // Dragging can't be found by VoiceOver: the same moves as actions.
        .accessibilityAction(named: "Move Left") { if index > 0 { move(tab, index - 1) } }
        .accessibilityAction(named: "Move Right") { if index < count - 1 { move(tab, index + 1) } }
        // Holding opens iOS's own menu beside the tile, its shape lifting on
        // a solid base (the Reduce Transparency look), so the glass doesn't
        // darken as iOS's shadow shows through it. 1pt wider than the tile,
        // so the lifted copy keeps the hairline and shadow just outside it;
        // cut to the tile's own shape, the edge popped in late, once iOS put
        // the real tile back (David's recording, 2026-11-08).
        // A hold that moves becomes a drag, and the menu's lift stops.
        .holdMenu(cornerRadius: Self.cornerRadius, outset: 1, base: Theme.tileSolid,
                  dragging: dragging) { menu(tab) }
        .opacity(gliding == tab.id ? reveal : 1)
        // Lifted, its spot stays empty, at once (never faded).
        .opacity(held == tab.id ? 0 : 1)
        .animation(nil, value: held)
        // Where it is, so the page can glide into it as the overview opens.
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            spots.frames[tab.id] = frame
            spots.cards.remove(tab.id)
        }
        .id(tab.id)
        .transition(.opacity)
    }
}

/// One tile, exactly the Mac's (`Firn/Basecamp.swift`: `BasecampTile`,
/// `TileButtonStyle`, `TileGlass`, `SiteMark`), at the iPhone's size: the
/// Mac's frosted ice at rest, and the tile on screen washed in its icon's
/// main color, ringed in the icon's own colors (each where it sits in the
/// icon), with light on the ring's top edge and a faint glow. No hover.
private struct BasecampTile: View {
    let tab: FirnCore.Tab
    let space: String
    let isOnScreen: Bool
    let open: () -> Void

    private var site: String { WebAddress.site(of: tab.homeURL ?? tab.url) }

    var body: some View {
        Button(action: open) {
            TileMark(site: site, icon: tab.icon)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileButtonStyle(isActive: isOnScreen, accent: Theme.tileAccent(site: site, icon: tab.icon)))
        .accessibilityLabel("\(site.isEmpty ? tab.title : site), Basecamp")
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
    }
}

/// The Mac's `SiteMark`, scaled from its 18pt to the iPhone tile's 24pt:
/// the icon, or the site's first letter on a rounded square of its color.
private struct TileMark: View {
    let site: String
    let icon: Data?
    static let size: CGFloat = 24

    var body: some View {
        SiteIconView(icon: icon, size: Self.size) { letterMark }
    }

    private var letterMark: some View {
        RoundedRectangle(cornerRadius: Self.size * 5 / 18, style: .continuous)
            .fill(Theme.siteColor(for: site).gradient)
            .frame(width: Self.size, height: Self.size)
            .overlay {
                Text(site.first.map { String($0).uppercased() } ?? "")
                    .font(.system(size: Self.size * 11 / 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .accessibilityHidden(true)
    }
}

/// The Mac's `TileButtonStyle`, without hover or lifting (those come with
/// dragging, step 3), and without the press shrink: a hold opens iOS's
/// menu, which copies the tile while it's shrunk, and the copy and the
/// tile springing back drew the icon twice as the menu closed (David's
/// recording, 2026-11-08). The overview's rows don't shrink either.
private struct TileButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Theme.TileAccent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BasecampTiles.cornerRadius, style: .continuous)
    }

    private var dark: Bool { colorScheme == .dark }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isActive { chosen } else { TileGlass() }
            }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isActive)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: accent)
    }

    /// The page on screen: the same glass, washed in the icon's main color
    /// (stronger at the top, like light through ice), ringed in its colors.
    private var chosen: some View {
        TileGlass()
            .overlay {
                shape.fill(LinearGradient(
                    colors: [accent.main.opacity(dark ? 0.18 : 0.2), accent.main.opacity(dark ? 0.12 : 0.07)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                // AngularGradient starts at 3 o'clock and runs clockwise, as the ring does.
                shape.strokeBorder(
                    AngularGradient(colors: accent.ring + accent.ring.prefix(1), center: .center),
                    lineWidth: BasecampTiles.ringWidth)
                    .opacity(reduceTransparency ? 1 : (dark ? 0.95 : 0.9))
            }
            .overlay {
                // Light catching the ring's outer edge along the top, gone by
                // the middle: a thin line, so the color underneath stays full.
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.tileRingSheen, Theme.tileRingSheen.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .shadow(color: accent.main.opacity(dark ? 0.18 : 0.28), radius: 5)
    }
}

/// The Mac's `TileGlass`: frosted ice with a lit rim and a hairline.
private struct TileGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BasecampTiles.cornerRadius, style: .continuous)
    }

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else {
            shape.fill(Theme.tileFill)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5).padding(-0.5) }
                .shadow(color: Theme.shadowSoft, radius: 1, y: 0.5)
        }
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
