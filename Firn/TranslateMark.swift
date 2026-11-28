import FirnCore
import SwiftUI

/// The translate mark in the address field, beside Reader's book and
/// looking just like it (design: `docs/translate-design.html`). Shown only
/// on pages that are offered; one click translates, another puts the page
/// back. Muted while offered; the space's color from the click on, as the
/// book is while Reader is on (David, 2026-11-27), breathing gently while
/// translating (Reduce Motion: simply dimmed). Pointing at it says what it
/// will do. The iPhone shows the same in its page menu's button.
struct TranslateMarkButton: View {
    let translator: PageTranslator
    let space: String
    let action: () -> Void
    @State private var hovering = false
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: PageTranslator.State { translator.state }
    private var target: String { translator.targetName ?? "" }

    var body: some View {
        Button(action: action) {
            Image(systemName: "translate")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(state == .translated || state == .translating ? Theme.spaceColor(space) : Theme.muted)
                .opacity(markOpacity)
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .fill(hovering ? Theme.hover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: state)
        .onChange(of: state == .translating && !reduceMotion, initial: true) { _, breathes in
            // Only while working: nothing moves once it's done.
            if breathes {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathing = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { breathing = false }
            }
        }
        .help(help)
        .accessibilityLabel(state == .translating || state == .translated ? "Show Original" : "Translate to \(target)")
        .accessibilityValue(accessibilityValue)
    }

    private var markOpacity: Double {
        switch state {
        case .translating: reduceMotion ? 0.5 : (breathing ? 0.4 : 1)
        default: 1
        }
    }

    /// What VoiceOver adds after the label; it hears a failed try too.
    private var accessibilityValue: String {
        switch state {
        case .none, .offered: ""
        case .translating: "Translating"
        case .translated: "Translated from \(translator.sourceName ?? "")"
        case .failed: "Couldn't translate this page"
        }
    }

    private var help: String {
        switch state {
        case .none, .offered: "Translate to \(target)"
        case .translating: "Translating to \(target)…"
        case .translated: "Translated from \(translator.sourceName ?? "") · Show Original"
        case .failed: "Couldn't translate this page"
        }
    }
}
