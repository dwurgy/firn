import FirnCore
import SwiftUI

/// Basecamp on the iPhone: the space's everyday sites as frosted tiles at
/// the top of the overview, scrolling away with the list. Hidden while
/// empty. Icon only (the menu and VoiceOver name the site), 56pt tall so a
/// tile is easy to tap, rows balanced up to 4 across (`BasecampLayout`).
/// The tiles are cells of the overview's grid (`BasecampCell`, `GridPlan`);
/// here are their measures and places.
@MainActor enum BasecampTiles {
    /// How far above its spot a tile arrives: 4%, about 2pt (a card's
    /// 1.5% is under a point on a tile), for David to judge.
    static let settleLift: CGFloat = 1.04
    /// The stretch of a glide's way (`reveal`, run on the glide's own
    /// curve) where the page's picture and the tile swap: the last 8%,
    /// once the picture is nearly the tile's size and in its spot. Timed
    /// apart, the picture faded out in mid-air, still 40% too big, and the
    /// tile was just there (David's recording, 2026-11-09).
    static let glideSwap: ClosedRange<CGFloat> = 0.92...1

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

    /// A tile's size with `count` tiles across `width` (the list's width):
    /// a tab carried up becomes this size as the grid makes room for it.
    static func tileSize(count: Int, width: CGFloat) -> CGSize {
        let layout = BasecampLayout.make(count: count, width: width,
                                         maximumColumns: maximumColumns, minimumWidth: minimumWidth)
        let columns = CGFloat(layout.rows.first ?? 1)
        return CGSize(width: max((width - (columns - 1) * gap) / columns, 0), height: tileHeight)
    }

    /// Between the tiles and the first tab: more than the list's 12pt
    /// between items (David, 2026-11-18).
    static let below: CGFloat = 24

    /// Every tile's frame with `count` tiles across `width`, from the top
    /// left of Basecamp: balanced rows, a shorter row centered under the
    /// longer one. For UIKit's grid (`GridPlan`), the same places as here.
    static func frames(count: Int, width: CGFloat) -> [CGRect] {
        guard count > 0, width > 0 else { return [] }
        let layout = BasecampLayout.make(count: count, width: width,
                                         maximumColumns: maximumColumns, minimumWidth: minimumWidth)
        let tile = tileSize(count: count, width: width)
        let rows = layout.rows.isEmpty ? [count] : layout.rows
        var frames: [CGRect] = []
        for (row, inRow) in rows.enumerated() {
            let rowWidth = CGFloat(inRow) * tile.width + CGFloat(inRow - 1) * gap
            let left = (width - rowWidth) / 2
            for column in 0..<inRow {
                frames.append(CGRect(x: left + CGFloat(column) * (tile.width + gap),
                                     y: CGFloat(row) * (tileHeight + gap), width: tile.width, height: tileHeight))
            }
        }
        // Never fewer spots than tiles, whatever the layout says.
        while frames.count < count { frames.append(frames.last ?? CGRect(origin: .zero, size: tile)) }
        return Array(frames.prefix(count))
    }

    /// The tile as a picture, for a page landing in it to turn into on the
    /// way (`BrowserScreen`'s stand-in, as iOS's app icon forms inside a
    /// closing app): the same glass and mark, at `size`, with corners of
    /// `cornerRadius`, so it matches the shrinking picture's shape. Not a
    /// button: nothing on the flying picture takes touches.
    static func face(_ tab: FirnCore.Tab, space: String, onScreen: Bool, cornerRadius: CGFloat) -> some View {
        BasecampTile(tab: tab, space: space, isOnScreen: onScreen, cornerRadius: cornerRadius, open: {})
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A tile as a cell of UIKit's grid (step 4 of "Plan: the drag
/// polish"): the same tile, its hold menu and its drag iOS's, from the
/// collection view. A view of its own so the landing's changes run it (a
/// cell's drawing made by the overview isn't run again by them).
struct BasecampCell: View {
    let tab: FirnCore.Tab
    let space: String
    let spots: OverviewSpots
    let landing: Landing
    let onScreen: UUID?
    let open: () -> Void
    /// Its menu's choices, for VoiceOver's actions.
    let menu: [[HoldMenuItem]]
    /// VoiceOver's Move Left and Move Right; nil at the ends.
    let moveLeft: (() -> Void)?
    let moveRight: (() -> Void)?

    var body: some View {
        let gliding = landing.gliding == tab.id
        BasecampTile(tab: tab, space: space, isOnScreen: tab.id == onScreen, pressLights: false, open: open)
            // Dragging can't be found by VoiceOver: the same moves as actions.
            .accessibilityActions {
                HoldMenuActions(menu: { menu })
                if let moveLeft { Button("Move Left", action: moveLeft) }
                if let moveRight { Button("Move Right", action: moveRight) }
            }
            // The set-down: the same scale as the page's picture over it.
            .background {
                if gliding {
                    SetDownShadow(radius: BasecampTiles.cornerRadius,
                                  lift: Double((landing.settle - 1) / (BasecampTiles.settleLift - 1)))
                }
            }
            .modifier(ArrivalBand(arrival: gliding ? landing.tileReveal : 1, range: BasecampTiles.glideSwap,
                                  fadesIn: true))
            .scaleEffect(gliding ? landing.settle : 1)
            // Where it is, so the page can glide into it as the overview opens.
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                spots.frames[tab.id] = frame
                spots.cards.remove(tab.id)
            }
    }
}

/// One tile, after the Mac's (`Firn/Basecamp.swift`: `BasecampTile`,
/// `TileButtonStyle`, `SiteMark`), at the iPhone's size, on iOS's own glass
/// instead of the Mac's frosted ice: the tile on screen tinted in its icon's
/// main color, ringed in the icon's own colors (each where it sits in the
/// icon), with a faint glow. No hover.
private struct BasecampTile: View {
    let tab: FirnCore.Tab
    let space: String
    let isOnScreen: Bool
    var cornerRadius: CGFloat = BasecampTiles.cornerRadius
    var pressLights = true
    let open: () -> Void

    private var site: String { WebAddress.site(of: tab.homeURL ?? tab.url) }

    var body: some View {
        Button(action: open) {
            TileMark(site: site, icon: tab.icon)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileButtonStyle(isActive: isOnScreen, accent: Theme.tileAccent(site: site, icon: tab.icon),
                                     cornerRadius: cornerRadius, pressLights: pressLights))
        .accessibilityLabel("\(site.isEmpty ? tab.title : site), Basecamp")
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
    }
}

/// The Mac's `SiteMark`, scaled from its 18pt to the iPhone tile's 30pt
/// (24pt until 2026-11-18; bigger, as the App Library's): the icon, or the
/// site's first letter on a rounded square of its color.
private struct TileMark: View {
    let site: String
    let icon: Data?
    static let size: CGFloat = 30

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

/// A tile's button: iOS's own glass (David, 2026-11-18, `docs/IOS-PLAN.md`,
/// "Plan: Basecamp tiles on iOS's own glass"), the iPhone's one recipe
/// (`FirnGlass`: the thinnest blur under regular glass, no tint) with iOS's
/// press, drawn on the tile itself so the finger reaches it. The tile on
/// screen keeps Firn's look on top: the glass tinted in the icon's main
/// color, ringed in its colors, with a faint glow. No sheen on the ring (the
/// Mac's light along its top): iOS's glass catches the light itself, and
/// both read as a doubled edge. No press shrink of Firn's: Firn's hold menu
/// sinks a held tile itself.
///
/// Reduce Transparency: the Mac's solid tile (`TileGlass`), the wash a
/// gradient over it, as before.
private struct TileButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Theme.TileAccent
    var cornerRadius: CGFloat = BasecampTiles.cornerRadius
    /// Whether the glass lights up under the finger (iOS's press).
    var pressLights = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var dark: Bool { colorScheme == .dark }

    func makeBody(configuration: Configuration) -> some View {
        // The ring is part of the glass's content: in Basecamp's glass
        // container iOS draws the glass above anything outside it.
        let face = configuration.label.overlay { if isActive { ring } }
        Group {
            if reduceTransparency {
                face
                    .background {
                        TileGlass(cornerRadius: cornerRadius)
                            .overlay { if isActive { shape.fill(accent.main.opacity(dark ? 0.18 : 0.16)) } }
                    }
            } else {
                face
                    .glassEffect(glass, in: shape)
                    // Under the glass, as every `FirnGlass`'s blur is.
                    .background { shape.fill(.ultraThinMaterial).allowsHitTesting(false) }
            }
        }
        .contentShape(shape)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isActive)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: accent)
    }

    /// Regular glass, the tile on screen's tinted in its icon's main color.
    private var glass: Glass {
        // Held for iOS's menu or drag (UIKit's grid), glass that answers
        // the finger lit up white, the icon washed out, for as long as the
        // hold lasted: the tile's "white flash" (David's recording,
        // 2026-11-23; the Simulator, frame by frame, 2026-11-24). There the
        // tile takes no press of its own, as a tab's card takes none.
        let base = pressLights ? Glass.regular.interactive() : Glass.regular
        return isActive ? base.tint(accent.main.opacity(dark ? 0.24 : 0.22)) : base
    }

    /// The icon's own colors around the inside edge, each where it sits in
    /// the icon, with a faint glow of its main color.
    private var ring: some View {
        // AngularGradient starts at 3 o'clock and runs clockwise, as the ring does.
        shape.gradientBorder(
            AngularGradient(colors: accent.ring + accent.ring.prefix(1), center: .center),
            lineWidth: BasecampTiles.ringWidth)
            .opacity(reduceTransparency ? 1 : (dark ? 0.95 : 0.9))
            .shadow(color: accent.main.opacity(dark ? 0.18 : 0.28), radius: 5)
            .allowsHitTesting(false)
    }
}

/// The Mac's `TileGlass`: frosted ice with a lit rim and a hairline. On the
/// iPhone only with Reduce Transparency (its solid form); otherwise tiles
/// are iOS's glass.
private struct TileGlass: View {
    var cornerRadius: CGFloat = BasecampTiles.cornerRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else {
            shape.fill(Theme.tileFill)
                .overlay {
                    shape.gradientBorder(
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

/// A tile's set-down shadow: the card's warm shadow (`Theme.shadowPageFar`),
/// scaled to a tile, with the tile's own shape cut out of it, so nothing
/// shows through the glass. `lift` 0 to 1, how far it's lifted.
private struct SetDownShadow: View {
    let radius: CGFloat
    let lift: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Color.black)
            .shadow(color: Theme.shadowPageFar, radius: 6, y: 3)
            .mask {
                // Everything but the tile itself.
                Rectangle()
                    .padding(-20)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .opacity(min(max(lift, 0), 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
