import FirnCore
import SwiftUI

/// The command bar's results on iOS (phase 2, step 6): one frosted card just
/// above the address field while typing, the best row nearest the field,
/// where the thumb is. The rows are the Mac's, from FirnCore
/// (`BrowserStore.commandRows`); this only draws them. They change in place
/// as you type, with no glide on every key.
struct CommandResults: View {
    let rows: [CommandRow]
    let engine: SearchEngine
    let space: String
    let pick: (CommandRow) -> Void
    /// A swipe down on the card ends typing, but only while every row fits:
    /// when the card scrolls, a swipe down scrolls it, nothing more.
    let swipedDown: () -> Void
    @State private var scrolls = false

    static let rowHeight: CGFloat = 48
    static let padding: CGFloat = 6
    /// The field's capsule is 24pt round; the card matches its curve, and
    /// the rows' wash sits inside it, concentric.
    static let cornerRadius: CGFloat = 24
    private static var rowRadius: CGFloat { cornerRadius - padding }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        // As tall as its rows, and scrolling only when the room above the
        // keyboard is shorter, resting on the rows nearest the field.
        ScrollView {
            VStack(spacing: 0) {
                // The best row is drawn last, so it sits by the field.
                ForEach(Array(rows.enumerated().reversed()), id: \.element.id) { index, row in
                    CommandResultRow(row: row, engine: engine, radius: Self.rowRadius) { pick(row) }
                        // VoiceOver reads the best first, as the Mac's does.
                        .accessibilitySortPriority(Double(rows.count - index))
                }
            }
            .padding(Self.padding)
            // On the rows themselves: on the scroll view around them, the
            // swipe never started.
            .gesture(SwipeDown(enabled: !scrolls, action: swipedDown))
        }
        .defaultScrollAnchor(.bottom)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height > $0.containerSize.height + 1 } action: { _, now in
            scrolls = now
        }
        // Rows that fit don't scroll at all, so the scroll view never takes
        // the swipe down from the card.
        .scrollDisabled(!scrolls)
        .frame(maxHeight: CGFloat(rows.count) * Self.rowHeight + Self.padding * 2)
        .clipShape(shape)
        // The same glass and tint as the field beneath it: one piece of the
        // bar, not a panel of its own.
        .glassEffect(.regular.tint(Theme.frameTint(space)), in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Results")
    }
}

private struct CommandResultRow: View {
    let row: CommandRow
    let engine: SearchEngine
    let radius: CGFloat
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                icon
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.muted)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        // A long title gives way, never the hint.
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: CommandResults.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ResultPress(radius: radius))
        // Larger text grows the words only as far as the 48pt row holds them.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(hint.map { "\(title), \($0)" } ?? title)
    }

    @ViewBuilder private var icon: some View {
        switch row {
        case .go:
            Image(systemName: "globe")
        case .search:
            Image(systemName: "magnifyingglass")
        case let .tab(tab), let .tidied(tab):
            SiteIconView(icon: tab.icon, size: 24) { LetterMark(site: WebAddress.site(of: tab.url)) }
        case let .closed(entry):
            if entry.kind == .group {
                Image(systemName: "square.on.square")
            } else {
                SiteIconView(icon: entry.icon, size: 24) { Image(systemName: "globe") }
            }
        case .history:
            Image(systemName: "clock")
        case let .action(action):
            Image(systemName: Self.symbol(for: action.id))
        }
    }

    /// Each action's own symbol, as in the page menu (the Mac shows its
    /// shortcut instead; iOS has none to show).
    private static func symbol(for id: String) -> String {
        switch id {
        case "reload": "arrow.clockwise"
        case "back": "chevron.backward"
        case "forward": "chevron.forward"
        case "copy-link": "link"
        case "share": "square.and.arrow.up"
        case "new-group": "folder.badge.plus"
        case "add-basecamp": "mountain.2"
        case "close": "xmark"
        case "reopen": "arrow.uturn.backward"
        default: "circle"
        }
    }

    /// The Mac's words (`Firn/CommandBar.swift`, `CommandRowView`).
    private var title: String {
        switch row {
        // The whole address, scheme and all, so it never hides an http.
        case let .go(url): url.absoluteString
        case let .search(text, _, _): text
        case let .tab(tab), let .tidied(tab): tab.title.isEmpty ? WebAddress.site(of: tab.url) : tab.title
        case let .closed(entry): entry.title
        case let .history(page): page.title.isEmpty ? page.url.absoluteString : page.title
        case let .action(action): action.name
        }
    }

    private var hint: String? {
        switch row {
        case .go: "Open"
        case .search(_, _, isSuggestion: false): "Search \(engine.name)"
        case .search: nil
        case .tab: "Switch to tab"
        case .tidied: "Tidied away"
        case .closed: "Recently closed"
        case .history: "History"
        case .action: nil
        }
    }
}

/// A row pressed: the warm wash, as the Mac's rows (no wash at rest; the
/// glass is enough).
private struct ResultPress: ButtonStyle {
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.press : .clear)
            }
    }
}

/// A swipe down while typing (on the field or the results card): far
/// enough, or quick enough, after starting more down than across. Taps and
/// sideways moves are left to the rows and the field. UIKit's pan, because
/// SwiftUI's DragGesture never saw the swipe over the card's scroll view,
/// and the field's own gestures kept it from starting (Simulator,
/// 2026-11-05).
struct SwipeDown: UIGestureRecognizerRepresentable {
    var enabled = true
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = enabled
    }

    /// Acts while the finger is still moving, so the card (and the row
    /// under the finger) is gone before it lifts: a row is never picked by
    /// the end of a swipe.
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        guard pan.state == .changed else { return }
        let dy = pan.translation(in: pan.view).y
        let speed = pan.velocity(in: pan.view).y
        if dy > 44 || (dy > 20 && speed > 500) { action() }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let speed = pan.velocity(in: pan.view)
            return speed.y > 0 && speed.y > abs(speed.x) * 1.5
        }

        /// Alongside the text field's own gestures (moving the cursor,
        /// selecting), which otherwise keep the swipe from ever starting.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
