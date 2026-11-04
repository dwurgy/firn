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
    /// The page menu. Open, the field's glass grows into it and the rest of
    /// the bar slips into the field, as in Safari; closing is the same move
    /// back. The screen closes it on a tap anywhere else.
    @Binding var menuOpen: Bool
    /// Where the field sits in the bar, so its glass knows where to grow
    /// from and come back to.
    @State private var fieldFrame: CGRect = .zero
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
                hidesForMenu(toward: .trailing) { NavigationPill(store: store, tab: tab, page: page, space: space) }
                    .transition(.opacity)
            }
            AddressField(store: store, editing: editing, typingNewTab: typingNewTab,
                         menuOpen: $menuOpen, opened: opened)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinates)) } action: { fieldFrame = $0 }
            if !editing.wrappedValue {
                hidesForMenu(toward: .leading) { TabsButton(space: space, action: showTabs) }
                    .transition(.opacity)
            }
        }
        .background { fieldGlass }
        .overlay { menuPanel }
        .coordinateSpace(.named(Self.coordinates))
        // One glide, no bounce: Safari's move, made calm. Reduce Motion: the
        // menu fades in place instead (below).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0), value: menuOpen)
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
        .onChange(of: page?.url) { menuOpen = false }
        .onChange(of: editing.wrappedValue) { if editing.wrappedValue { menuOpen = false } }
    }

    private nonisolated static let coordinates = "AddressBar"

    /// The menu's spot: from the field's left edge up, its bottom on the
    /// field's, kept inside the bar's right edge (the tabs button's).
    private var menuFrame: CGRect {
        let width = max(fieldFrame.width, PageMenuPanel.width)
        let rightEdge = fieldFrame.maxX + 10 + BarButton.size + 4
        let x = min(fieldFrame.minX, rightEdge - width)
        return CGRect(x: x, y: fieldFrame.maxY - PageMenuPanel.height, width: width, height: PageMenuPanel.height)
    }

    /// The field's glass, as one piece that becomes the menu: the same tint
    /// and the same glass as the bar, because it is the bar.
    @ViewBuilder private var fieldGlass: some View {
        let open = menuOpen && fieldFrame != .zero
        let frame = open ? menuFrame : fieldFrame
        let radius = open ? PageMenuPanel.cornerRadius : AddressField.height / 2
        let glass = LoadingFrost(isLoading: page?.isLoading ?? false, progress: page?.progress ?? 0, space: space)
            .opacity(open ? 0 : 1)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .glassEffect(.regular.tint(Theme.frameTint(space)), in: .rect(cornerRadius: radius, style: .continuous))
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        if reduceMotion {
            // Reduce Motion: no growing; the bar's glass and the menu's
            // swap with a fade.
            glass.id(open).transition(.opacity)
        } else {
            glass
        }
    }

    @ViewBuilder private var menuPanel: some View {
        if menuOpen, let url = page?.url, fieldFrame != .zero {
            let frame = menuFrame
            PageMenuPanel(url: url) { menuOpen = false }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                // The words come in once the glass has mostly grown, and go
                // first when it closes.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.16).delay(reduceMotion ? 0 : 0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.08))))
        }
    }

    /// Slips into the field while the page menu is open and comes back
    /// out after, keeping its place so nothing else moves. Shrunk rather
    /// than removed or faded: Liquid Glass follows neither a removal nor
    /// `.opacity`, and both left dark discs behind (David's recordings,
    /// 2026-11-04); a glass view's size it does follow.
    private func hidesForMenu(toward anchor: UnitPoint, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .scaleEffect(menuOpen && !reduceMotion ? 0.01 : 1, anchor: anchor)
            .opacity(menuOpen ? 0 : 1)
            .allowsHitTesting(!menuOpen)
            .accessibilityHidden(menuOpen)
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
            if !isEditing, frontURL != nil {
                BarButton(symbol: "line.3.horizontal", label: "Page Menu") { menuOpen.toggle() }
                    .accessibilityHint("Share or copy this page's link")
                    .opacity(menuOpen ? 0 : 1)
                    .animation(.easeOut(duration: 0.1), value: menuOpen)
            }
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
                .animation(.easeOut(duration: 0.1), value: menuOpen)
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
                .animation(.easeOut(duration: 0.1), value: menuOpen)
        }
        .frame(height: Self.height)
        // The field's glass is the bar's (`AddressBar.fieldGlass`), so it
        // can grow into the page menu.
        .allowsHitTesting(!menuOpen)
        .accessibilityHidden(menuOpen)
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

/// The page's own short menu, grown out of the field's glass (Firn's own,
/// not iOS's, so it carries the bar's tint and glass). Only what people
/// reach for; Find, Zoom, Stop Blocking, and Request Desktop Site join it
/// in phase 6.
private struct PageMenuPanel: View {
    let url: URL
    let close: () -> Void
    @AccessibilityFocusState private var firstFocused: Bool

    static let width: CGFloat = 250
    static let cornerRadius: CGFloat = 22
    private static let rowHeight: CGFloat = 48
    private static let rows = 2
    private static let inset: CGFloat = 6
    static var height: CGFloat { rowHeight * CGFloat(rows) + inset * 2 }

    var body: some View {
        VStack(spacing: 0) {
            row("Share…", symbol: "square.and.arrow.up") {
                close()
                ShareSheet.present(url)
            }
            .accessibilityFocused($firstFocused)
            row("Copy Link", symbol: "link") {
                UIPasteboard.general.url = url
                close()
            }
        }
        .padding(Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { firstFocused = true }
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
    }
}

/// A row pressed: Firn's warm wash, in the row's rounded shape.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.press : .clear,
                        in: .rect(cornerRadius: PageMenuPanel.cornerRadius - 6, style: .continuous))
    }
}

/// iOS's own share sheet, over whatever's on screen.
@MainActor private enum ShareSheet {
    static func present(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.keyWindow, var presenter = window.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad: from the bottom of the screen, where the menu was.
        sheet.popoverPresentationController?.sourceView = window
        sheet.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 60, width: 1, height: 1)
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
