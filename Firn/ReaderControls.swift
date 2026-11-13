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
}

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

/// The book in the address field: muted while off; the space's color, on a
/// soft wash of it, while Reader is on.
struct ReaderBookButton: View {
    let isOn: Bool
    let space: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = Theme.spaceColor(space)
        Button(action: action) {
            ReaderBookShape()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                .frame(width: 16, height: 16)
                .foregroundStyle(isOn ? color : Theme.muted)
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? color.opacity(0.16) : hovering ? Theme.hover : .clear)
                }
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

/// The Aa pill in the reader's top corner, on the same frost as the
/// iPhone's bar pills (`BarFrost`). It opens a native popover with the only
/// two choices: Serif or Sans, and text size. The reader runs no scripts,
/// so these live in Firn, over it.
struct ReaderTextButton: View {
    let space: String
    @State private var showsChoices = false
    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        Button { showsChoices.toggle() } label: {
            Text("Aa")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background { BarFrost(shape: shape, space: space) }
                .overlay { shape.fill(Theme.hover).opacity(hovering ? 1 : 0).allowsHitTesting(false) }
                .contentShape(shape)
        }
        .buttonStyle(FrostPress(shape: shape))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Text")
        .accessibilityLabel("Reader text")
        .accessibilityHint("Font and text size")
        .popover(isPresented: $showsChoices, arrowEdge: .bottom) {
            ReaderTextChoices()
        }
    }
}

/// Inside the Aa popover: Serif or Sans, each shown in its own font, then
/// smaller and larger text.
private struct ReaderTextChoices: View {
    @Bindable private var style = ReaderStyle.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                fontChoice(.serif, name: "Serif", design: .serif)
                fontChoice(.sans, name: "Sans", design: .default)
            }
            .padding(3)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 4) {
                sizeChoice(smaller: true)
                sizeChoice(smaller: false)
            }
            .padding(3)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .frame(width: 232)
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
            .padding(.vertical, 8)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.page)
                        .shadow(color: Theme.shadowSoft, radius: 1.5, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(FrostPress(shape: RoundedRectangle(cornerRadius: 8, style: .continuous)))
        .disabled(!enabled)
        .accessibilityLabel(smaller ? "Smaller text" : "Larger text")
    }
}
