import FirnCore
import SwiftUI

struct NavigationButtons: View {
    let page: any PageController

    var body: some View {
        ChromeButton("Back", systemImage: "chevron.left") { page.goBack() }
            .disabled(!page.canGoBack)
        ChromeButton("Forward", systemImage: "chevron.right") { page.goForward() }
            .disabled(!page.canGoForward)
    }

    /// The same buttons, disabled, when no tab is open.
    @ViewBuilder static var placeholder: some View {
        ChromeButton("Back", systemImage: "chevron.left") {}.disabled(true)
        ChromeButton("Forward", systemImage: "chevron.right") {}.disabled(true)
    }
}

/// A small icon button for the sidebar: quiet until hovered.
struct ChromeButton<Icon: View>: View {
    let label: String
    let icon: Icon
    let action: () -> Void

    /// For Firn's own drawings; the label is still what VoiceOver reads.
    init(_ label: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.label = label
        self.icon = icon()
        self.action = action
    }

    var body: some View {
        Button(action: action) { Label { Text(label) } icon: { icon } }
            .labelStyle(.iconOnly)
            .buttonStyle(ChromeButtonStyle())
            .help(label)
    }
}

extension ChromeButton where Icon == Image {
    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.init(label, action: action) { Image(systemName: systemImage) }
    }
}

struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Theme.muted : Theme.faint.opacity(0.6))
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering && isEnabled ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Address bar

/// Shows where the tab on screen is, and takes an address or a search.
/// At rest it shows just the site; clicking in shows the whole address.
/// The page's zoom in the address bar: quiet text; a click goes back to actual size.
/// While the page in front loads, a wash of the space's color forms across
/// the address field from the left, like frost on glass, then thaws once the
/// page is in (David, 2026-10-23, after trying a sinking horizon and a
/// sunrise: just the space color, no sunrise). Its front edge stays soft, so
/// it never reads as a hard progress bar. Reduce Motion: it fades in and out whole.
struct LoadingFrost: View {
    let isLoading: Bool
    let progress: Double
    @Environment(\.spaceColorName) private var space
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far across the frost has formed, 0 to 1.
    @State private var formed = 0.0
    @State private var shown = false
    /// Counts loads, so an old load's thaw stands down when a new one starts
    /// (a view's closures see its values from when they were made).
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
            // A soft glow rides the front edge, brighter where the frost is
            // forming (David, 2026-10-24). A gradient, not a blur, and it goes
            // with the frost; Reduce Motion has no moving edge, so no glow.
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

struct ZoomLabel: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Theme.hintFont.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .frame(width: 38, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .fill(hovering ? Theme.hover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Actual Size")
        .accessibilityLabel("Zoomed to \(text)")
        .accessibilityHint("Goes back to actual size")
    }
}

struct AddressBar: View {
    let store: BrowserStore
    let window: WindowModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false
    @AppStorage(Preference.searchEngine) private var searchEngine = SearchEngine.default

    /// The page in front: a Lookout's while one is open, so the bar always
    /// tells the truth about what's on screen, and typing goes there too.
    private var frontPage: (any PageController)? { window.frontPage }
    private var frontURL: URL? { window.frontURL }
    /// Reload sits inside the bar, as in Safari, so the top row fits at the narrowest width.
    private var reloadablePage: (any PageController)? {
        guard !focused, window.canReloadFront else { return nil }
        return frontPage
    }
    /// The page's zoom, shown only while it isn't actual size, so a page
    /// zoomed and forgotten doesn't just look wrong.
    private var zoomLabel: String? {
        guard !focused, window.canZoomFront(.actualSize), let zoom = frontPage?.zoom else { return nil }
        return PageZoom.percent(zoom)
    }

    /// Room kept clear at the right for the zoom and reload buttons.
    private var trailingRoom: CGFloat {
        let reload: CGFloat = reloadablePage == nil ? 0 : 24
        let zoom: CGFloat = zoomLabel == nil ? 0 : 40
        return Theme.rowPadding + reload + zoom
    }

    var body: some View {
        TextField("Search or enter address", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            // At rest, a long address fades out before the zoom and reload
            // buttons, as tab titles do before the close button. Not while
            // typing, where the end of the text is where the cursor is.
            .mask { TrailingFade(width: focused ? 0 : 18) }
            .padding(.leading, Theme.rowPadding)
            .padding(.trailing, trailingRoom)
            .frame(height: Theme.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(focused ? Theme.page : hovering ? Theme.press : Theme.hover)
                    .overlay {
                        LoadingFrost(isLoading: frontPage?.isLoading ?? false, progress: frontPage?.progress ?? 0)
                            // A new page in front starts fresh, never thawing the last one's frost.
                            .id(frontPage.map { ObjectIdentifier($0) })
                            .clipShape(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                    }
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(Theme.frost, lineWidth: 2)
                }
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    if let zoomLabel {
                        ZoomLabel(text: zoomLabel) { window.zoomFront(.actualSize) }
                    }
                    if let page = reloadablePage {
                        if page.isLoading {
                            ChromeButton("Stop loading", systemImage: "xmark") { page.stopLoading() }
                        } else {
                            ChromeButton("Reload this page", systemImage: "arrow.clockwise") { page.reload() }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .onHover { hovering = $0 }
            .accessibilityLabel(store.lookout != nil ? "Lookout address" : "Address")
            .onSubmit(open)
            .onExitCommand(perform: cancel)
            .onChange(of: window.addressRequest) {
                text = frontURL?.absoluteString ?? ""
                focused = true
            }
            .onChange(of: focused) {
                if !focused { cancel() } else { text = frontURL?.absoluteString ?? "" }
            }
            .onChange(of: frontURL) { showRestingAddress() }
            .onChange(of: store.lookout?.id) { showRestingAddress() }
            .onChange(of: store.activeTabID) { showRestingAddress() }
            .onAppear(perform: showRestingAddress)
            // The offer to save a password just used drops from here.
            .modifier(SavePasswordPopover(store: store, window: window))
    }

    private func open() {
        guard let url = AddressInput.url(for: text, searchEngine: searchEngine) else { return }
        if store.activeTab == nil {
            store.openTab(url)
        } else {
            frontPage?.load(url)
        }
        window.finishEditingAddress()
        focused = false
        window.focusPage()
    }

    private func cancel() {
        window.finishEditingAddress()
        if focused, store.activeTab != nil {
            focused = false
            window.focusPage()
        }
        showRestingAddress()
    }

    /// While someone isn't typing, the bar shows the committed address (never a
    /// pending one, so it can't claim to be a page that isn't there yet), as just the site.
    private func showRestingAddress() {
        guard !focused else { return }
        text = WebAddress.site(of: frontURL)
    }
}
