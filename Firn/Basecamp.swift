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

/// Places tiles by `BasecampLayout`: balanced rows, the longest filling
/// the width, shorter rows starting at the left.
private struct BasecampFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        let layout = BasecampLayout.make(count: subviews.count, width: width)
        return CGSize(width: width, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = BasecampLayout.make(count: subviews.count, width: bounds.width)
        let size = ProposedViewSize(width: layout.tileWidth, height: BasecampLayout.tileHeight)
        var index = 0
        for (row, count) in layout.rows.enumerated() {
            for column in 0..<count {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(column) * (layout.tileWidth + BasecampLayout.gap),
                        y: bounds.minY + CGFloat(row) * (BasecampLayout.tileHeight + BasecampLayout.gap)),
                    proposal: size)
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

    private var site: String {
        let host = (tab.homeURL ?? tab.url)?.host(percentEncoded: false) ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        Button(action: select) {
            // Resting tiles (not loaded yet) look the same as loaded ones, as in
            // Dia: a faded tile reads as broken, or as a promise of a slow load.
            SiteMark(site: site, icon: tab.icon)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileButtonStyle(isActive: isActive, accent: Theme.tileAccent(site: site, icon: tab.icon)))
        .help(tab.title)
        .contextMenu {
            if tab.isAwayFromHome {
                Button("Go Back to Home", action: goHome)
            }
            Button("Remove from Basecamp", action: remove)
            Divider()
            Button("Close", action: close)
        }
        .accessibilityLabel(site.isEmpty ? tab.title : site)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// The site's own icon, or until it's found (or if the site has none), a
/// soft rounded square in a calm color with the site's first letter.
private struct SiteMark: View {
    let site: String
    let icon: Data?

    var body: some View {
        SiteIconView(icon: icon, size: 18) { letterMark }
    }

    private var letterMark: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.siteColor(for: site).gradient)
            .frame(width: 18, height: 18)
            .overlay {
                Text(site.first.map { String($0).uppercased() } ?? "")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .accessibilityHidden(true)
    }
}

/// A tile of frosted ice: Liquid Glass with a cool snowy tint and a crisp
/// edge on macOS 26 and later, a frosted fill and lit rim before it.
/// Brighter on hover, a gentle press. The chosen tile keeps its glass and
/// takes the colors of the site's icon: a soft wash, a ring of colored glass
/// that follows where each color sits in the icon, and a faint glow.
private struct TileButtonStyle: ButtonStyle {
    let isActive: Bool
    let accent: Theme.TileAccent
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
    }

    private var dark: Bool { colorScheme == .dark }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isActive { chosen } else { resting }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isActive)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: accent)
            .onHover { hovering = $0 }
    }

    /// The page on screen: the same glass, washed in the icon's main color
    /// (stronger at the top, like light through ice), ringed in its colors.
    private var chosen: some View {
        resting
            .overlay {
                shape.fill(LinearGradient(
                    colors: [accent.main.opacity(dark ? 0.18 : 0.2), accent.main.opacity(dark ? 0.12 : 0.07)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                // AngularGradient starts at 3 o'clock and runs clockwise, as the ring does.
                shape.strokeBorder(
                    AngularGradient(colors: accent.ring + accent.ring.prefix(1), center: .center),
                    lineWidth: Theme.tileRingWidth)
                    .opacity(reduceTransparency ? 1 : (dark ? 0.85 : 0.75))
            }
            .overlay {
                shape.inset(by: Theme.tileRingWidth)
                    .strokeBorder(Theme.tileLip, lineWidth: 0.5)
            }
            .shadow(color: accent.main.opacity(dark ? 0.18 : 0.28), radius: 5)
    }

    @ViewBuilder private var resting: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else if #available(macOS 26, *) {
            // Glass on the plain frame (the sidebar itself isn't glass), so
            // it never stacks glass on glass.
            shape.fill(hovering ? Theme.tileFillHover : .clear)
                .overlay { shape.strokeBorder(Theme.tileFrostEdge, lineWidth: 0.5) }
                .glassEffect(.regular.tint(Theme.tileFrost), in: shape)
        } else {
            shape.fill(hovering ? Theme.tileFillHover : Theme.tileFill)
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
