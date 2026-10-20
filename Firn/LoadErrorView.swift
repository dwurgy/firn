import FirnCore
import SwiftUI

/// What the page area shows when an address couldn't load: where, why in
/// one line, and a way to try again. Native, over the page, so nothing is
/// put into the web view; it covers whatever page was there before.
struct LoadErrorView: View {
    let error: LoadError
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.faint)
                .frame(height: 36)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(error.headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(error.explanation)
                    .font(Theme.tabFont)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Button(isRetrying ? "Trying Again…" : "Try Again", action: retry)
                .buttonStyle(InkButtonStyle())
                .disabled(isRetrying)
                .padding(.top, 26)
        }
        .frame(maxWidth: 360)
        .padding(32)
        // A touch above the middle, where the eye expects it.
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }

    private var symbol: String {
        switch error.reason {
        case .offline: "wifi.slash"
        case .noSuchSite: "signpost.right"
        case .notAnswering: "hourglass"
        case .notSecure: "lock.slash"
        case .other: "circle.dashed"
        }
    }
}

/// Firn's one strong button: ink, with page-colored words.
private struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.page)
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .fill(Theme.ink)
                    .opacity(!isEnabled ? 0.55 : configuration.isPressed ? 0.78 : hovering ? 0.88 : 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
