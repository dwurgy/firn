import FirnCore
import SwiftUI

/// The one screen of phase 1: the page, edge to edge, with Firn's address
/// bar floating over its bottom edge.
struct BrowserScreen: View {
    let store: BrowserStore
    @FocusState private var editing: Bool
    /// Where the bar's top edge and the page's bottom edge sit on screen, so
    /// the page knows how much of it the bar covers.
    @State private var barTop: CGFloat = 0
    @State private var pageBottom: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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

            AddressBar(store: store, editing: $editing)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                    // Only the bar at rest counts: while it rides the
                    // keyboard, the page underneath shouldn't lay out again.
                    if !editing { barTop = top }
                }
                // The bar rises with the keyboard only for typing an
                // address; a page's own fields leave it resting behind the
                // keyboard, as in Safari.
                .ignoresSafeArea(.keyboard, edges: editing ? [] : .bottom)
        }
        .background(Theme.page.ignoresSafeArea())
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25), value: editing)
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
}
