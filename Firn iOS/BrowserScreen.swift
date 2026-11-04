import FirnCore
import SwiftUI

/// The page, edge to edge, with Firn's address bar floating over its bottom
/// edge, and the tab overview behind it (the tabs button, or a swipe up on
/// the bar, shows it).
struct BrowserScreen: View {
    let store: BrowserStore
    @FocusState private var editing: Bool
    /// Whether the overview is showing instead of the page.
    @State private var showingTabs = false
    /// Whether the address being typed opens a new tab (from the overview's
    /// +) rather than replacing the page on screen.
    @State private var typingNewTab = false
    /// Where the bar's top edge and the page's bottom edge sit on screen, so
    /// the page knows how much of it the bar covers.
    @State private var barTop: CGFloat = 0
    @State private var pageBottom: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showingTabs {
                TabOverview(store: store, done: hideTabs, newTab: startNewTab)
                    .transition(.opacity)
            }
            pageAndBar
                // The page steps back a little as it fades, so the overview
                // reads as behind it. Reduce Motion: only the fade.
                .scaleEffect(showingTabs && !reduceMotion ? 0.94 : 1)
                .opacity(showingTabs ? 0 : 1)
                .allowsHitTesting(!showingTabs)
                .accessibilityHidden(showingTabs)
        }
        .background(Theme.page.ignoresSafeArea())
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: editing)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: showingTabs)
        .onChange(of: editing) { if !editing { typingNewTab = false } }
    }

    private var pageAndBar: some View {
        ZStack(alignment: .bottom) {
            pageLayer
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { pageBottom = $0 }

            // While typing, the page dims a little; a tap on it cancels.
            if editing {
                Theme.lookoutDim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { editing = false }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }

            AddressBar(store: store, editing: $editing, typingNewTab: typingNewTab, showTabs: showTabs)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                    // Only the bar at rest counts: while it rides the
                    // keyboard, the page underneath shouldn't lay out again.
                    if !editing { barTop = top }
                }
                // A swipe up on the bar shows the overview, as in Safari.
                // Alongside the bar's own buttons, so a tap still taps.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20).onEnded { drag in
                        if !editing, drag.translation.height < -40,
                           abs(drag.translation.height) > abs(drag.translation.width) {
                            showTabs()
                        }
                    }
                )
                // The bar rises with the keyboard only for typing an
                // address; a page's own fields leave it resting behind the
                // keyboard, as in Safari.
                .ignoresSafeArea(.keyboard, edges: editing ? [] : .bottom)
        }
    }

    @ViewBuilder private var pageLayer: some View {
        if let page = store.activeTab?.page {
            PageView(page: page, obscuredBottom: barTop > 0 ? pageBottom - barTop : 0)
                // A new tab gets a new web view, not the last one's.
                .id(ObjectIdentifier(page))
        } else {
            Theme.page
        }
    }

    private func showTabs() {
        editing = false
        showingTabs = true
    }

    private func hideTabs() {
        showingTabs = false
    }

    /// Until the command bar comes (step 6), + goes back to the page with an
    /// empty address field; Go opens what's typed as a new tab, and
    /// cancelling opens nothing.
    private func startNewTab() {
        typingNewTab = true
        showingTabs = false
        editing = true
    }
}
