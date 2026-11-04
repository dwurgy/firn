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
                NavigationPill(store: store, tab: tab, page: page, space: space)
                    .transition(.opacity)
            }
            AddressField(store: store, editing: editing, typingNewTab: typingNewTab)
            if !editing.wrappedValue {
                TabsButton(space: space, action: showTabs)
                    .transition(.opacity)
            }
        }
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
    @State private var text = ""
    @State private var selection: TextSelection?

    private var page: (any PageController)? { store.activeTab?.page }
    private var frontURL: URL? { page?.url }
    private var isEditing: Bool { editing.wrappedValue }

    var body: some View {
        HStack(spacing: 0) {
            // The page menu also balances the button on the right, so the
            // site sits centered.
            if !isEditing, let frontURL { PageMenu(url: frontURL) }
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
        }
        .frame(height: Self.height)
        .background {
            LoadingFrost(isLoading: page?.isLoading ?? false, progress: page?.progress ?? 0, space: store.activeSpace.color)
                .clipShape(.capsule)
        }
        .glassEffect(.regular.tint(Theme.frameTint(store.activeSpace.color)), in: .capsule)
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
private struct PageMenu: View {
    let url: URL

    var body: some View {
        Menu {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.url = url }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: BarButton.size, height: BarButton.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page Menu")
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
