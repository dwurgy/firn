import SwiftUI

/// The menus that grow out of a button's own glass (the address bar's •••
/// and hold menus, and the overview's space name): one set of sizes and one
/// row, so they can't drift apart, measured from iOS's own menu so they sit
/// beside it (David, 2026-11-23). From a tab's hold menu in the overview
/// (iPhone 15 Pro Simulator, iOS 27): rows 42pt apart, 9pt above the first
/// and under the last, a section's line taking 21pt, the symbol's middle
/// 39pt in, the words 64pt in, the chevron's middle 30pt from the right.
enum GrownMenu {
    static let width: CGFloat = 250
    /// By eye from iOS's menu, which is rounder than the old 22pt.
    static let cornerRadius: CGFloat = 26
    static let rowHeight: CGFloat = 42
    /// A row with a second line (Stop Blocking and its site).
    static let tallRowHeight: CGFloat = 56
    /// A section's line: a hairline with 10pt above and below.
    static let lineHeight: CGFloat = 21
    /// Around the rows: the highlight stops this far from the glass's edge.
    static let sideInset: CGFloat = 6
    static let topInset: CGFloat = 9
    static var rowRadius: CGFloat { cornerRadius - sideInset }

    static func rowHeight(tall: Bool) -> CGFloat { tall ? tallRowHeight : rowHeight }
}

/// One row: its mark (a symbol, a dot, Reader's book), its words, and a
/// chevron or a check at the right. Lit while a sliding finger is on it.
struct GrownMenuRow<Mark: View>: View {
    let title: String
    var detail: String?
    var ink: Color = Theme.ink
    /// The way back from a list: smaller and quieter.
    var small = false
    /// Opens a list of its own.
    var more = false
    var checked = false
    let lit: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                mark()
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(small ? .footnote.weight(.semibold) : .body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let detail {
                        // A long site's name loses its middle, keeping both ends.
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if more {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 21)
            .frame(height: GrownMenu.rowHeight(tall: detail != nil))
            .contentShape(.rect)
        }
        .buttonStyle(GrownMenuPress())
        .background {
            if lit {
                RoundedRectangle(cornerRadius: GrownMenu.rowRadius, style: .continuous)
                    .fill(Theme.press)
                    .matchedGeometryEffect(id: "lit", in: highlight)
            }
        }
    }
}

/// The thin line between a menu's sections.
struct GrownMenuLine: View {
    var body: some View {
        Theme.holdMenuHairline
            .frame(height: 1)
            .padding(.horizontal, 17)
            .frame(height: GrownMenu.lineHeight)
            .accessibilityHidden(true)
    }
}

/// A row pressed: Firn's warm wash, in the row's rounded shape.
private struct GrownMenuPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.press : .clear,
                        in: .rect(cornerRadius: GrownMenu.rowRadius, style: .continuous))
    }
}
