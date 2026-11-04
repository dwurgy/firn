import SwiftUI

/// The iOS twin of the Mac's loading frost (Firn/Sidebar.swift): while the
/// page loads, a wash of the space's color forms across the address field
/// from the left, like frost on glass, then thaws once the page is in. Its
/// front edge stays soft, so it never reads as a hard progress bar. Reduce
/// Motion: it fades in and out whole. Kept as a copy so the Mac's file never
/// changes for iOS.
struct LoadingFrost: View {
    let isLoading: Bool
    let progress: Double
    let space: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far across the frost has formed, 0 to 1.
    @State private var formed = 0.0
    @State private var shown = false
    /// Counts loads, so an old load's thaw stands down when a new one starts.
    @State private var load = 0

    var body: some View {
        GeometryReader { geo in
            let tint = colorScheme == .dark ? Theme.loadingTintDark : Theme.loadingTint
            let color = Theme.spaceColor(space).opacity(tint)
            // A little past the end, so the soft edge leaves the field when it's done.
            let width = geo.size.width * (reduceMotion ? 1.25 : formed * 1.25)
            LinearGradient(stops: [.init(color: color, location: 0), .init(color: color, location: 0.8),
                                   .init(color: color.opacity(0), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
            if !reduceMotion {
                let glow = Theme.spaceColor(space).opacity(min(tint * 2, 0.6))
                Ellipse()
                    .fill(RadialGradient(colors: [glow, glow.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: Theme.glowRadius))
                    .frame(width: Theme.glowRadius * 2, height: geo.size.height * 1.6)
                    .position(x: width * 0.84, y: geo.size.height / 2)
            }
        }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isLoading, initial: true) { _, loading in
            if loading { start() } else if shown { thaw() }
        }
        .onChange(of: progress) { _, value in
            guard isLoading, value > formed else { return }
            withAnimation(.easeOut(duration: 0.3)) { formed = value }
        }
    }

    private func start() {
        load += 1
        formed = 0
        withAnimation(.easeOut(duration: 0.2)) { shown = true }
        withAnimation(.easeOut(duration: 0.3)) { formed = max(progress, 0.1) }
    }

    /// Finishes forming, then fades.
    private func thaw() {
        let this = load
        withAnimation(.easeOut(duration: 0.2)) {
            formed = 1
        } completion: {
            guard load == this else { return }
            withAnimation(.easeOut(duration: 0.45)) { shown = false }
        }
    }
}
