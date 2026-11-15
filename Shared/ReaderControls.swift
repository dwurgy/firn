import FirnCore
import SwiftUI

/// Reader's look (Serif or Sans, and the text size), one for the whole app,
/// saved on this device only (`ReaderLook.saved`). Every reader on screen
/// follows it (`PagePane`).
@MainActor @Observable
final class ReaderStyle {
    static let shared = ReaderStyle()

    var look = ReaderLook.saved {
        didSet { ReaderLook.saved = look }
    }

    private init() {}

    /// Reader on or off for `page` (the book, the command bar, or ⇧⌘R on
    /// the Mac). A page that turns out too short just loses its book.
    func toggle(_ page: any PageController, space: String) {
        if page.isReading {
            page.closeReader()
            return
        }
        guard page.isArticle else { return }
        let look = look
        let accent = Theme.spaceHex(space)
        Task { _ = await page.openReader(look: look, accent: accent) }
    }

    /// Summarize (View › Summarize Article, the command bar, or the
    /// iPhone's page menu): opens Reader first if it's off, then the
    /// summary at the top of the article.
    func summarize(_ page: any PageController, space: String) {
        if page.isReading { return page.summarizeArticle() }
        guard page.isArticle else { return }
        let look = look
        let accent = Theme.spaceHex(space)
        Task {
            if await page.openReader(look: look, accent: accent) { page.summarizeArticle() }
        }
    }
}

/// Tap room on the iPhone: Apple's 44pt, around the same small drawing.
#if os(iOS)
private let tapHeight: CGFloat = 44
#else
private let tapHeight: CGFloat? = nil
#endif

// MARK: - The book

/// The book from the approved design (`docs/reader-design.html`), its
/// 16-point drawing traced exactly: two pages meeting at the spine.
struct ReaderBookShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: p(8, 4.2))
        path.addCurve(to: p(2.2, 3), control1: p(6.6, 3.2), control2: p(4.6, 2.8))
        path.addLine(to: p(2.2, 12.4))
        path.addCurve(to: p(8, 13.6), control1: p(4.6, 12.2), control2: p(6.6, 12.6))
        path.addCurve(to: p(13.8, 12.4), control1: p(9.4, 12.6), control2: p(11.4, 12.2))
        path.addLine(to: p(13.8, 3))
        path.addCurve(to: p(8, 4.2), control1: p(11.4, 2.8), control2: p(9.4, 3.2))
        path.closeSubpath()
        path.move(to: p(8, 4.2))
        path.addLine(to: p(8, 13.6))
        return path
    }
}

/// The book itself, outlined, its pages washed with `color` while `isOn`.
/// The wash lives inside the book, never in a box around it (David,
/// 2026-11-13: no other button keeps a colored square).
struct ReaderBookIcon: View {
    let isOn: Bool
    let color: Color
    var off: Color = Theme.muted
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.4

    var body: some View {
        ZStack {
            ReaderBookShape()
                .fill(color.opacity(isOn ? 0.28 : 0))
            ReaderBookShape()
                .stroke(isOn ? color : off, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

/// The book in the address field: muted while off; the space's color, its
/// pages washed with it, while Reader is on. Hover is the same warm wash as
/// the reload and zoom buttons beside it.
struct ReaderBookButton: View {
    let isOn: Bool
    let space: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ReaderBookIcon(isOn: isOn, color: Theme.spaceColor(space))
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .fill(hovering ? Theme.hover : .clear)
                }
                .frame(height: tapHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isOn)
        .help(isOn ? "Hide Reader" : "Show Reader")
        .accessibilityLabel("Reader")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(isOn ? "Goes back to the page" : "Shows just the article's text")
    }
}

// MARK: - Aa

/// The Aa pill in the reader's top corner, on the bar's frost
/// (`BarFrost`). Tapped, the pill itself grows into a small card with the
/// only two choices, Serif or Sans and text size, the way the iPhone's page
/// menu grows out of the address field: one piece of frost, down and to
/// the left from the corner, in one bounce-free glide; the words come in
/// once it has mostly grown and go first as it closes (David, 2026-11-13:
/// never a system popover). A tap anywhere else, or Esc, closes it. Reduce
/// Motion: the pill and the card cross-fade in place. The reader runs no
/// scripts, so this lives in Firn, over it.
///
/// Place it filling the reader's area: it lays itself out in the top
/// right corner, `inset` in, and catches taps elsewhere only while open.
struct ReaderTextButton: View {
    let space: String
    var inset: CGFloat = 14
    @State private var open = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if open {
                // A tap or click anywhere else closes it, as the page menu does.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { open = false }
                    .accessibilityHidden(true)
            }
            card
                .padding(.top, inset)
                .padding(.trailing, inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        // The page menu's glide. Reduce Motion: a fade (on the pieces).
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0), value: open)
        #if os(macOS)
        .onExitCommand { open = false }
        #endif
        .onDisappear { open = false }
    }

    private var size: CGSize { open ? ReaderTextCard.size : ReaderTextCard.pill }

    @ViewBuilder private var card: some View {
        let radius = open ? ReaderTextCard.radius : ReaderTextCard.pill.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .topTrailing) {
            glass(shape)
            if open {
                ReaderTextChoices { open = false }
                    .frame(width: ReaderTextCard.size.width, height: ReaderTextCard.size.height)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.16).delay(reduceMotion ? 0 : 0.12)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))))
            } else {
                pillButton(shape)
                    .transition(.asymmetric(
                        // Back once the pill has nearly settled; sooner, the word sat
                        // off-center in frost still shrinking (Simulator, 2026-11-13).
                        insertion: .opacity.animation(.easeOut(duration: 0.16).delay(reduceMotion ? 0 : 0.2)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topTrailing)
        .clipShape(shape)
        // Open, taps on the card's own frost stay on it.
        .background { if open { shape.fill(.clear).contentShape(shape).onTapGesture {} } }
    }

    @ViewBuilder private func glass(_ shape: RoundedRectangle) -> some View {
        let frost = BarFrost(shape: shape)
            .frame(width: size.width, height: size.height)
        if reduceMotion {
            // No growing: the pill's frost and the card's swap with a fade.
            frost.id(open).transition(.opacity.animation(.easeOut(duration: 0.2)))
        } else {
            frost
        }
    }

    private func pillButton(_ shape: RoundedRectangle) -> some View {
        Button { open = true } label: {
            Text("Aa")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: ReaderTextCard.pill.width, height: ReaderTextCard.pill.height)
                .overlay { shape.fill(Theme.hover).opacity(hovering ? 1 : 0).allowsHitTesting(false) }
                // Apple's 44pt to tap on the iPhone, around the small pill.
                .contentShape(Rectangle().inset(by: -ReaderTextCard.pillReach))
        }
        .buttonStyle(FrostPress(shape: shape))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Text")
        .accessibilityLabel("Reader text")
        .accessibilityHint("Font and text size")
    }
}

/// The Aa card's measures: the iPhone's are the page menu's (22pt corners,
/// 44pt rows); the Mac's are its panels' (14pt corners).
private enum ReaderTextCard {
    static let pill = CGSize(width: 46, height: 30)
    #if os(iOS)
    static let pillReach: CGFloat = 7
    static let radius: CGFloat = 22
    static let inset: CGFloat = 8
    static let sizeRow: CGFloat = 44
    #else
    static let pillReach: CGFloat = 0
    static let radius: CGFloat = 14
    static let inset: CGFloat = 6
    static let sizeRow: CGFloat = 34
    #endif
    static let fontRow: CGFloat = 50
    static let gap: CGFloat = 6
    /// Each pair of choices sits in a soft well, its corners one step in
    /// from the card's.
    static let wellRadius = radius - inset
    static let size = CGSize(width: 232,
                             height: inset * 2 + (fontRow + 6) + gap + (sizeRow + 6))
}

/// Inside the Aa card: Serif or Sans, each shown in its own font, then
/// smaller and larger text.
private struct ReaderTextChoices: View {
    let close: () -> Void
    @Bindable private var style = ReaderStyle.shared
    @AccessibilityFocusState private var firstFocused: Bool

    var body: some View {
        VStack(spacing: ReaderTextCard.gap) {
            well {
                fontChoice(.serif, name: "Serif", design: .serif)
                    .accessibilityFocused($firstFocused)
                fontChoice(.sans, name: "Sans", design: .default)
            }
            well {
                sizeChoice(smaller: true)
                sizeChoice(smaller: false)
            }
        }
        .padding(ReaderTextCard.inset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { firstFocused = true }
    }

    private func well(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 4) { content() }
            .padding(3)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: ReaderTextCard.wellRadius, style: .continuous))
    }

    private func fontChoice(_ font: ReaderLook.Font, name: String, design: Font.Design) -> some View {
        let isOn = style.look.font == font
        return Button { style.look.font = font } label: {
            VStack(spacing: 2) {
                Text("Aa").font(.system(size: 15, design: design))
                Text(name).font(Theme.hintFont).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: ReaderTextCard.fontRow)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: ReaderTextCard.wellRadius - 3, style: .continuous)
                        .fill(Theme.page)
                        .shadow(color: Theme.shadowSoft, radius: 1.5, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func sizeChoice(smaller: Bool) -> some View {
        let enabled = smaller ? style.look.canShrink : style.look.canGrow
        return Button { style.look.size += smaller ? -1 : 1 } label: {
            Text("A")
                .font(.system(size: smaller ? 13 : 19))
                .foregroundStyle(Theme.ink.opacity(enabled ? 1 : 0.3))
                .frame(maxWidth: .infinity)
                .frame(height: ReaderTextCard.sizeRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(FrostPress(shape: RoundedRectangle(cornerRadius: ReaderTextCard.wellRadius - 3, style: .continuous)))
        .disabled(!enabled)
        .accessibilityLabel(smaller ? "Smaller text" : "Larger text")
        // The size it's at, so a press is heard to do something.
        .accessibilityValue("Size \(style.look.size + 1) of \(ReaderLook.sizes.count)")
    }
}
