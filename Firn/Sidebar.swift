import FirnCore
import SwiftUI

/// The sidebar: the top row (traffic lights, back, forward, reload), the
/// address bar, and the space's tabs.
struct Sidebar: View {
    let store: BrowserStore
    let window: WindowModel
    /// Where macOS put the traffic lights; the top row lines up with them.
    let lights: TrafficLights

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            AddressBar(store: store, window: window)
                .padding(.top, 8)
                .padding(.bottom, Theme.sectionSpacing)
            TabList(store: store, window: window)
        }
        .padding(.leading, Theme.pageInset)
    }

    /// Centered on the traffic lights, which sit at its left.
    private var topRow: some View {
        HStack(spacing: 2) {
            Spacer(minLength: lights.trailingX + Theme.trafficLightGap - Theme.pageInset)
            if let page = store.activeTab?.page {
                NavigationButtons(page: page)
            } else {
                NavigationButtons.placeholder
            }
        }
        .frame(height: Theme.rowHeight)
        .padding(.top, max(lights.centerY - Theme.rowHeight / 2, 0))
    }
}

// MARK: - Back, forward, and reload

private struct NavigationButtons: View {
    let page: any PageController

    var body: some View {
        ChromeButton("Back", systemImage: "chevron.left") { page.goBack() }
            .disabled(!page.canGoBack)
        ChromeButton("Forward", systemImage: "chevron.right") { page.goForward() }
            .disabled(!page.canGoForward)
        if page.isLoading {
            ChromeButton("Stop loading", systemImage: "xmark") { page.stopLoading() }
        } else {
            ChromeButton("Reload this page", systemImage: "arrow.clockwise") { page.reload() }
                .disabled(page.url == nil)
        }
    }

    /// The same buttons, disabled, when no tab is open.
    @ViewBuilder static var placeholder: some View {
        ChromeButton("Back", systemImage: "chevron.left") {}.disabled(true)
        ChromeButton("Forward", systemImage: "chevron.right") {}.disabled(true)
        ChromeButton("Reload this page", systemImage: "arrow.clockwise") {}.disabled(true)
    }
}

/// A small icon button for the sidebar: quiet until hovered.
struct ChromeButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(ChromeButtonStyle())
            .help(label)
    }
}

private struct ChromeButtonStyle: ButtonStyle {
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
private struct AddressBar: View {
    let store: BrowserStore
    let window: WindowModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var url: URL? { window.addressTarget == .newTab ? nil : store.activeTab?.url }

    var body: some View {
        TextField("Search or enter address", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(.horizontal, Theme.rowPadding)
            .frame(height: Theme.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(focused ? Theme.page : hovering ? Theme.press : Theme.hover)
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(Theme.frost, lineWidth: 2)
                }
            }
            .onHover { hovering = $0 }
            .accessibilityLabel(window.addressTarget == .newTab ? "New tab address" : "Address")
            .onSubmit(open)
            .onExitCommand(perform: cancel)
            .onChange(of: window.addressRequest) {
                text = url?.absoluteString ?? ""
                focused = true
            }
            .onChange(of: focused) {
                if !focused { cancel() } else { text = url?.absoluteString ?? "" }
            }
            .onChange(of: store.activeTab?.url) { showRestingAddress() }
            .onChange(of: store.activeTabID) { showRestingAddress() }
            .onAppear(perform: showRestingAddress)
    }

    private func open() {
        guard let url = AddressInput.url(for: text) else { return }
        if window.addressTarget == .newTab || store.activeTab == nil {
            store.openTab(url)
        } else {
            store.activeTab?.page?.load(url)
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
        text = Self.site(of: store.activeTab?.url)
    }

    private static func site(of url: URL?) -> String {
        guard let url, let host = url.host(percentEncoded: false) else { return "" }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let port = url.port { return "\(site):\(port)" }
        return site
    }
}

// MARK: - Tabs

private struct TabList: View {
    let store: BrowserStore
    let window: WindowModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.rowSpacing) {
                NewTabRow { window.editAddress(.newTab) }
                ForEach(store.openTabs) { tab in
                    TabRow(tab: tab, isActive: tab.id == store.activeTabID) {
                        store.select(tab)
                        window.focusPage()
                    } close: {
                        store.close(tab)
                    }
                }
            }
            .padding(.bottom, Theme.pageInset)
        }
        .scrollIndicators(.never)
    }
}

private struct NewTabRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New tab", systemImage: "plus")
                .labelStyle(RowLabelStyle(color: Theme.muted))
        }
        .buttonStyle(RowButtonStyle(isActive: false))
        .help("New tab (⌘T)")
    }
}

private struct TabRow: View {
    let tab: FirnCore.Tab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Label(tab.title, systemImage: "globe")
                    .labelStyle(RowLabelStyle(color: Theme.ink))
                Spacer(minLength: 0)
            }
            // Room for the close button, so long titles stop short of it.
            .padding(.trailing, hovering ? 20 : 0)
        }
        .buttonStyle(RowButtonStyle(isActive: isActive))
        .overlay(alignment: .trailing) {
            if hovering {
                Button("Close tab", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CloseButtonStyle())
                    .help("Close tab (⌘W)")
                    .padding(.trailing, 8)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            if let page = tab.page {
                Button("Reload") { page.reload() }
            }
            if let url = tab.url {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            Divider()
            Button("Close Tab", action: close)
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: "Close tab", close)
    }
}

/// Icon and title, as every sidebar row shows them.
private struct RowLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 16)
            configuration.title
                .font(Theme.tabFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// A 36pt sidebar row: a warm wash on hover and press, lifted when it's the tab on screen.
private struct RowButtonStyle: ButtonStyle {
    let isActive: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.rowPadding)
            .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
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
        return hovering ? Theme.hover : .clear
    }
}

private struct CloseButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(width: 20, height: 20)
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
