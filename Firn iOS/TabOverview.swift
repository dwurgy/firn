import FirnCore
import SwiftUI

/// The overview behind the page (phase 2, step 2: plain): one column of
/// slim rows, opening scrolled to the tab on screen, which carries a frost
/// ring. Tap a row to show it; swipe it sideways to close it. The glass bar
/// at the bottom: + for a new tab, the space's name in a pill, and a check
/// to go back. Behind it all, the space glow (step 2b). Looks from
/// docs/ios-overview-design.html; tall cards come in step 4, groups and
/// Basecamp in phase 3.
struct TabOverview: View {
    let store: BrowserStore
    /// Back to the page, showing the tab on screen.
    let done: () -> Void
    /// A new tab: back to the page, with the address field ready to type.
    let newTab: () -> Void

    private var space: String { store.activeSpace.color }

    var body: some View {
        ScrollViewReader { scroller in
            List {
                ForEach(store.openTabs) { tab in
                    OverviewRow(tab: tab, isOnScreen: tab.id == store.activeTab?.id) {
                        store.select(tab)
                        done()
                    }
                    .id(tab.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    // iOS's own swipe, as in Safari; a full swipe closes at once.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { store.close(tab) } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        .tint(Theme.muted)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .overlay {
                if store.openTabs.isEmpty {
                    Text("No open tabs")
                        .font(.subheadline)
                        .foregroundStyle(Theme.faint)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OverviewBar(space: store.activeSpace, newTab: newTab, done: done)
            }
            .onAppear {
                if let id = store.activeTab?.id { scroller.scrollTo(id, anchor: .center) }
            }
        }
        .background { SpaceGlow(space: space) }
    }
}

/// The overview's backdrop: a still mesh in the space's color with Firn's
/// glacier and apricot glow, so the glass rows have something to show.
/// Nothing animates while idle; a space change cross-fades.
private struct SpaceGlow: View {
    let space: String

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.42], [0.58, 0.5], [1, 0.38],
                [0, 1], [0.45, 1], [1, 1],
            ],
            colors: Theme.overviewGlow(space)
        )
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: space)
        .accessibilityHidden(true)
    }
}

/// A slim row on glass: the site's icon and the page's title, one line, as
/// in Safari and Firn's Mac sidebar. The tab on screen stands out on solid page white with a frost
/// ring.
private struct OverviewRow: View {
    let tab: FirnCore.Tab
    let isOnScreen: Bool
    let open: () -> Void

    private var site: String { WebAddress.site(of: tab.url) }
    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                SiteIconView(icon: tab.icon, size: 24) { LetterMark(site: site) }
                Text(tab.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background {
                if isOnScreen {
                    Self.shape.fill(Theme.page)
                    Self.shape.strokeBorder(Theme.frost, lineWidth: 2)
                }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        // Other tabs sit on glass over the space glow.
        .glassEffect(isOnScreen ? .identity : .regular, in: Self.shape)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isOnScreen ? "On screen" : "")
        .accessibilityAddTraits(isOnScreen ? .isSelected : [])
    }
}

/// A site with no icon yet: its first letter on a calm color of its own.
private struct LetterMark: View {
    let site: String

    var body: some View {
        Text(site.first.map { String($0).uppercased() } ?? "")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.page)
            .frame(width: 24, height: 24)
            .background(Theme.siteColor(for: site), in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a tinted glass pill in the middle (the switcher and its dots come
/// with phase 4), and a round check on the right in a vivid version of the
/// space's color.
private struct OverviewBar: View {
    let space: Space
    let newTab: () -> Void
    let done: () -> Void

    private static let height: CGFloat = 50

    var body: some View {
        ZStack {
            Text(space.name)
                .font(.headline)
                .foregroundStyle(Theme.spaceInk(space.color))
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(height: Self.height)
                .glassEffect(.regular.tint(Theme.frameTint(space.color)), in: .capsule)
                .padding(.horizontal, Self.height + 16)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: newTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.frameTint(space.color)).interactive(), in: .circle)
                .accessibilityLabel("New Tab")
                Spacer()
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.spaceVivid(space.color)).interactive(), in: .circle)
                .accessibilityLabel("Done")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
