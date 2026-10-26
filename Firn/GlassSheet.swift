import SwiftUI

/// Firn's sheets: the New space card's glass, tinted by the space on
/// screen, over its dimmed window, in place of the system's sheet (David,
/// 2026-10-26: one look for every panel). A system sheet is its own window,
/// so it can't be Firn's glass over the window behind it.
///
/// A window installs the host (`glassSheetHost`) at its root and puts the
/// layer (`GlassSheetLayer`) where the dim should fall; a view anywhere
/// inside then shows a sheet with `glassSheet(item:)`. As with a system
/// sheet, a click on the dim does nothing: each sheet closes with its own
/// buttons (Esc is its Cancel), so nothing is lost by a stray click.
@MainActor @Observable
final class GlassSheetPresenter {
    struct Shown {
        let id: AnyHashable
        let content: AnyView
        let onDismiss: () -> Void
    }

    fileprivate(set) var shown: Shown?
    /// The glass's tint: the space on screen.
    fileprivate(set) var color: Color = .clear

    fileprivate func show(_ sheet: Shown) { shown = sheet }

    /// Closes the sheet showing (if it's `id`'s), then tells its owner.
    fileprivate func close(_ id: AnyHashable? = nil) {
        guard let sheet = shown, id == nil || sheet.id == id else { return }
        shown = nil
        sheet.onDismiss()
    }
}

/// What a sheet calls to close itself, in place of `dismiss`.
struct DismissGlassSheet {
    fileprivate var action: @MainActor () -> Void = {}
    @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var dismissGlassSheet = DismissGlassSheet()
}

extension View {
    /// Makes this window able to show Firn's glass sheets, tinted `color`.
    func glassSheetHost(color: Color) -> some View {
        modifier(GlassSheetHost(color: color))
    }

    /// Shows `content` as a glass sheet while `item` is set, as `.sheet(item:)` does.
    func glassSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(GlassSheetModifier(item: item, onDismiss: onDismiss, sheet: content))
    }
}

private struct GlassSheetHost: ViewModifier {
    let color: Color
    @State private var presenter = GlassSheetPresenter()

    func body(content: Content) -> some View {
        content
            .environment(presenter)
            .onChange(of: color, initial: true) { presenter.color = color }
    }
}

private struct GlassSheetModifier<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet
    @Environment(GlassSheetPresenter.self) private var presenter: GlassSheetPresenter?

    func body(content: Content) -> some View {
        content.onChange(of: item?.id, initial: true) { old, new in
            guard let presenter else { return }
            if let old, old != new { presenter.close(AnyHashable(old)) }
            guard let item, let new else { return }
            let id = AnyHashable(new)
            let close = DismissGlassSheet { [presenter] in presenter.close(id) }
            presenter.show(.init(
                id: id,
                content: AnyView(sheet(item).environment(\.dismissGlassSheet, close)),
                onDismiss: {
                    // Closed by its own button: the owner's item goes too.
                    if self.item?.id == new { self.item = nil }
                    onDismiss?()
                }
            ))
        }
    }
}

/// The dim and the card, where a window wants them. It rises a hair as it
/// fades in (Reduce Motion: fades), as the New space card does.
struct GlassSheetLayer: View {
    /// The dim's corners: the page's in the browser, none over a whole window.
    var cornerRadius: CGFloat = 0
    @Environment(GlassSheetPresenter.self) private var presenter: GlassSheetPresenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let presenter, let sheet = presenter.shown {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.commandDim)
                    .ignoresSafeArea()
                    // Holds clicks, so nothing under the sheet is reached.
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                    .transition(.opacity)
                GlassCard(color: presenter.color) { sheet.content }
                    .id(sheet.id)
                    .padding(24)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: presenter?.shown?.id)
    }
}

/// The New space card's glass and shadows around any content.
struct GlassCard<Content: View>: View {
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        content
            .background { CommandBarGlass(shape: shape, color: color) }
            .clipShape(shape)
            .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
            .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}
