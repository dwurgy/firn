import FirnCore
import SwiftUI

/// The bar at the bottom of the screen, laid out as Safari's: Back (widening
/// to hold Forward) in a small glass pill, and the address field beside it,
/// with the page menu on its left and reload (or stop) on its right.
/// Tapping the field hides the pill so the field has the whole width, picks
/// out the whole address, and the bar rides up with the keyboard. Go opens
/// it; tapping the page cancels. At rest it shows only the committed
/// address's site, never a pending one.
struct AddressBar: View {
    let store: BrowserStore
    var editing: FocusState<Bool>.Binding
    /// Typing from the overview's +: the field starts empty and Go opens a
    /// new tab.
    let typingNewTab: Bool
    let showTabs: () -> Void
    /// After Go has opened what was typed (the overview closes then).
    var opened: () -> Void = {}
    /// While the page menu is open, it's all the bar shows, as in Safari.
    @State private var menuOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: (any PageController)? { store.activeTab?.page }
    private var space: String { store.activeSpace.color }

    /// The pill and the field each carry their own glass, with no
    /// `GlassEffectContainer`: a container morphs its glass on its own
    /// timing, so the glass trailed Firn's frost and words as a grey ghost
    /// whenever the pill changed width (David's recordings, 2026-11-03).
    var body: some View {
        HStack(spacing: 10) {
            if let tab = store.activeTab, let page, !editing.wrappedValue {
                hidesForMenu { NavigationPill(store: store, tab: tab, page: page, space: space) }
                    .transition(.opacity)
            }
            AddressField(store: store, editing: editing, typingNewTab: typingNewTab,
                         menuOpen: $menuOpen, opened: opened)
            if !editing.wrappedValue {
                hidesForMenu { TabsButton(space: space, action: showTabs) }
                    .transition(.opacity)
            }
        }
        // The rest of the bar fades as the menu grows out of its button,
        // and back as it closes (a fade, so it stays with Reduce Motion).
        .animation(.easeOut(duration: 0.2), value: menuOpen)
        // Forward coming or going moves the pill and the field together, in
        // one glide. Reduce Motion: a short plain ease rather than a jump
        // (it's a small change of width, not movement across the screen).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: page?.canGoForward)
        .frame(maxWidth: 640)
        // Larger text grows the bar's words only as far as its 48pt height
        // holds them, as in Safari's bar.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, editing.wrappedValue ? 16 : Self.sideInset)
        .padding(.top, 8)
        .padding(.bottom, editing.wrappedValue ? 8 : 4)
    }

    /// Leaves while the page menu is open and comes back after, keeping its
    /// place so nothing else moves. Glass is taken away and brought back
    /// rather than faded: Liquid Glass doesn't follow `.opacity`, so a fade
    /// left empty grey discs behind (David's recording, 2026-11-04).
    private func hidesForMenu(@ViewBuilder _ content: () -> some View) -> some View {
        let view = content()
        return ZStack {
            view.hidden()
            if !menuOpen { view.transition(.opacity) }
        }
    }

    /// How far the bar's round buttons sit from the screen's edges, at rest.
    /// Safari's spot (about 35pt on David's iPhone, from his screenshots,
    /// 2026-11-04), shared with the overview's bar so + and the check sit
    /// exactly where Back and the tabs button were. Typing gives the field
    /// the usual 16pt instead.
    static let sideInset: CGFloat = 34
}

/// Back, as one round button that widens to hold Forward once there's
/// somewhere to go forward (as Safari does). Back with nowhere to go fades
/// rather than leaving, so the field never jumps.
private struct NavigationPill: View {
    let store: BrowserStore
    let tab: FirnCore.Tab
    let page: any PageController
    let space: String

    /// On a tab a link opened, with no page to go back to, Back closes it
    /// and shows the tab it came from, as in Safari.
    private var opener: FirnCore.Tab? { page.canGoBack ? nil : store.opener(of: tab) }

    private func goBack() {
        if let opener {
            store.close(tab, showing: opener)
        } else {
            page.goBack()
        }
    }

    /// Round (Back alone) or wide (Back and Forward). Forward is always
    /// there, faded out and clipped away when it can't be used: a width
    /// that glides is smooth both ways, where adding and removing the
    /// button snapped the pill narrow before the field had moved over.
    private static let padding: CGFloat = 2
    private static let roundWidth = BarButton.size + padding * 2
    private static let wideWidth = BarButton.size * 2 + padding * 2

    var body: some View {
        HStack(spacing: 0) {
            BarButton(symbol: "chevron.backward", label: "Back", action: goBack)
                .disabled(!page.canGoBack && opener == nil)
                .accessibilityHint(opener != nil ? "Closes this tab and goes back to the one it came from" : "")
            BarButton(symbol: "chevron.forward", label: "Forward", action: page.goForward)
                .opacity(page.canGoForward ? 1 : 0)
                .disabled(!page.canGoForward)
                .accessibilityHidden(!page.canGoForward)
        }
        .padding(.horizontal, Self.padding)
        .frame(width: page.canGoForward ? Self.wideWidth : Self.roundWidth,
               height: AddressField.height, alignment: .leading)
        .clipShape(.capsule)
        .glassEffect(.regular.tint(Theme.frameTint(space)), in: .capsule)
    }
}

private struct AddressField: View {
    static let height: CGFloat = 48
    let store: BrowserStore
    var editing: FocusState<Bool>.Binding
    let typingNewTab: Bool
    @Binding var menuOpen: Bool
    let opened: () -> Void
    @State private var text = ""
    @State private var selection: TextSelection?

    private var page: (any PageController)? { store.activeTab?.page }
    private var frontURL: URL? { page?.url }
    private var isEditing: Bool { editing.wrappedValue }

    var body: some View {
        HStack(spacing: 0) {
            // The page menu also balances the button on the right, so the
            // site sits centered.
            if !isEditing, let frontURL { PageMenu(url: frontURL, isOpen: $menuOpen) }
            TextField("Address", text: $text, selection: $selection,
                      prompt: Text("Search or enter address").foregroundStyle(Theme.muted))
                .font(.body)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(isEditing ? .leading : .center)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused(editing)
                .padding(.leading, isEditing ? 18 : 0)
                .opacity(menuOpen ? 0 : 1)
                .accessibilityLabel("Address")
                .onSubmit(open)
                // VoiceOver's scrub cancels, as tapping the page does (the
                // dimmed page is hidden from VoiceOver).
                .accessibilityAction(.escape) { editing.wrappedValue = false }
                // At rest the field only shows the site; a tap on it starts
                // editing (below), so the finger never drops a cursor into
                // the middle of the address.
                .allowsHitTesting(isEditing)
                .accessibilityHidden(!isEditing)
                .overlay {
                    if !isEditing {
                        Button(action: beginEditing) { Color.clear.contentShape(.rect) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Address")
                            .accessibilityValue(text)
                            .accessibilityHint("Edit the address or search")
                    }
                }
            trailingButton
                // Reload and Stop cross-fade rather than snap (a fade, so
                // it stays with Reduce Motion).
                .animation(.easeOut(duration: 0.15), value: page?.isLoading)
                .opacity(menuOpen ? 0 : 1)
        }
        .frame(height: Self.height)
        // The glass is its own layer, so it can leave while the page menu
        // is open and the menu's button stays (it's what the menu hangs
        // from). Switching the glass to `.identity` showed a blank blob.
        .background {
            if !menuOpen {
                LoadingFrost(isLoading: page?.isLoading ?? false, progress: page?.progress ?? 0, space: store.activeSpace.color)
                    .clipShape(.capsule)
                    .glassEffect(.regular.tint(Theme.frameTint(store.activeSpace.color)), in: .capsule)
                    .transition(.opacity)
            }
        }
        .onChange(of: isEditing) { startOrEndEditing() }
        .onChange(of: frontURL) { showRestingAddress() }
        .onAppear(perform: showRestingAddress)
    }

    @ViewBuilder private var trailingButton: some View {
        if isEditing {
            BarButton(symbol: "xmark.circle.fill", label: "Clear", tint: Theme.faint) { text = "" }
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty)
                .accessibilityHidden(text.isEmpty)
        } else if let page, page.isLoading {
            BarButton(symbol: "xmark", label: "Stop", action: page.stopLoading)
        } else if let page, page.url != nil {
            BarButton(symbol: "arrow.clockwise", label: "Reload", action: page.reload)
        }
    }

    /// Typing starts from the whole address, all picked out, so it can be
    /// edited or simply typed over.
    private func beginEditing() {
        text = frontURL?.absoluteString ?? ""
        editing.wrappedValue = true
    }

    private func startOrEndEditing() {
        guard isEditing else { return showRestingAddress() }
        if typingNewTab { text = ""; return }
        // The field takes focus first, then the selection; set together,
        // UIKit puts the cursor at the end instead.
        Task { @MainActor in
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func open() {
        defer { editing.wrappedValue = false }
        guard let url = AddressInput.url(for: text, searchEngine: SearchEngine.chosen) else { return }
        if let page, !typingNewTab {
            page.load(url)
        } else {
            store.openTab(url)
        }
        opened()
    }

    private func showRestingAddress() {
        guard !isEditing else { return }
        selection = nil
        text = WebAddress.site(of: frontURL)
    }
}

/// The page's own short menu, at the field's left (where Safari keeps its).
/// Only what people reach for; Find, Zoom, Stop Blocking, and Request
/// Desktop Site join it in phase 6.
///
/// UIKit, because the bar hides while the menu is open (as Safari's does)
/// and SwiftUI's `Menu` doesn't say when it opens or closes: watching its
/// items appear missed the closing, so the bar stayed hidden. A `UIButton`
/// hears both from its own menu.
private struct PageMenu: UIViewRepresentable {
    let url: URL
    @Binding var isOpen: Bool

    func makeUIView(context: Context) -> PageMenuButton {
        let button = PageMenuButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        var look = UIButton.Configuration.plain()
        look.image = UIImage(systemName: "line.3.horizontal",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        look.baseForegroundColor = UIColor(Theme.ink)
        button.configuration = look
        button.accessibilityLabel = "Page Menu"
        return button
    }

    func updateUIView(_ button: PageMenuButton, context: Context) {
        let isOpen = $isOpen
        button.openChanged = { isOpen.wrappedValue = $0 }
        button.menu = UIMenu(children: [
            UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak button] _ in
                button?.share(url)
            },
            UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                UIPasteboard.general.url = url
            },
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PageMenuButton, context: Context) -> CGSize? {
        CGSize(width: BarButton.size, height: BarButton.size)
    }
}

private final class PageMenuButton: UIButton {
    var openChanged: (Bool) -> Void = { _ in }
    private var closing: Task<Void, Never>?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        closing?.cancel()
        openChanged(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        // The bar comes back once the menu has gone back into its button
        // (about 0.2s), not while it's still shrinking over it. A fixed wait:
        // the animator's completion never came. Reopening in the meantime
        // cancels it.
        closing?.cancel()
        closing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            self?.openChanged(false)
        }
    }

    /// iOS's own share sheet, from the menu's button.
    func share(_ url: URL) {
        guard var presenter = window?.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = self
        presenter.present(sheet, animated: true)
    }
}

/// The overview's button, at the bar's right: round glass, the same size
/// as Back's.
private struct TabsButton: View {
    let space: String
    let action: () -> Void

    var body: some View {
        BarButton(symbol: "square.on.square", label: "Tabs", action: action)
            .padding(2)
            .glassEffect(.regular.tint(Theme.frameTint(space)), in: .circle)
            .accessibilityHint("Shows all your tabs")
    }
}

/// A round 44pt tap target with an SF Symbol, in Firn's ink.
private struct BarButton: View {
    static let size: CGFloat = 44
    let symbol: String
    let label: String
    var tint: Color = Theme.ink
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.3))
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
