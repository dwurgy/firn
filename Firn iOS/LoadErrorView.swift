import FirnCore
import SwiftUI

/// What the page shows when an address couldn't load, the iPhone's twin of
/// the Mac's: where, why in one line, and Try Again. Native, over the page,
/// so nothing is put into the web view; it covers whatever page was there.
/// It fills the page below the status bar on warm paper, its words a touch
/// above the middle of what the bar leaves free.
struct LoadErrorView: View {
    let error: LoadError
    let isRetrying: Bool
    let retry: () -> Void
    /// Opens an address; offered only when Firn guessed https for a site
    /// that may answer only over http (`LoadError.insecureFallback`).
    var load: (URL) -> Void = { _ in }
    /// The status bar's height and the bar's room at the bottom, so the
    /// words sit in the free space between them.
    var topRoom: CGFloat = 0
    var bottomRoom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.faint)
                .frame(height: 42)
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(error.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(error.explanation)
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Button(action: retry) {
                // As wide as its longer words, so it doesn't jump between them.
                ZStack {
                    Text("Trying Again…").hidden()
                    Text(isRetrying ? "Trying Again…" : "Try Again")
                }
            }
                .buttonStyle(InkButtonStyle())
                .disabled(isRetrying)
                .padding(.top, 28)
            if let http = error.insecureFallback {
                // Quieter than Try Again, and never automatic, so a network
                // can't quietly push a site onto http.
                Button(LoadError.continueInsecurelyTitle) { load(http) }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isRetrying)
                    .accessibilityHint(LoadError.continueInsecurelyNote)
                    .padding(.top, 8)
                Text(LoadError.continueInsecurelyNote)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .frame(maxWidth: 340)
        .padding(.horizontal, 32)
        // A touch above the middle, where the eye expects it.
        .padding(.top, topRoom)
        .padding(.bottom, bottomRoom + 48)
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

/// Firn's one strong button: ink, with page-colored words; 44pt to tap.
private struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.page)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(Theme.ink)
                    .opacity(!isEnabled ? 0.55 : configuration.isPressed ? 0.78 : 1)
            }
            .contentShape(Capsule())
    }
}

/// The quieter way through: ink words, no fill, 44pt to tap.
private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
    }
}

/// The error over the live page, following it while a finger holds it: the
/// engine moves the page by its layer (`PageHold`), and this does the same
/// sums, so the two move as one. Reads the hold here, so a pull runs only
/// this, never the screen.
struct LoadErrorCover: View {
    let page: any PageController
    let hold: Hold
    /// The status bar's height, and the bar's room at the bottom.
    let topRoom: CGFloat
    let bottomRoom: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if let error = page.loadError {
                let size = geometry.size
                let held = hold.livePull && hold.box.width > 0 && size.width > 0 && size.height > topRoom
                let scale = held ? hold.box.width / size.width : 1
                // The page below the status bar; with its strip on a sideways swipe.
                let shown = held && !hold.swiping
                    ? CGRect(x: 0, y: topRoom, width: size.width, height: size.height - topRoom)
                    : CGRect(origin: .zero, size: size)
                let origin = geometry.frame(in: .global).origin
                LoadErrorView(error: error, isRetrying: page.isLoading, retry: page.reload, load: page.load,
                              topRoom: topRoom, bottomRoom: bottomRoom)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: held ? hold.boxRadius / scale : 0, style: .continuous)
                            .frame(width: shown.width, height: shown.height)
                            .offset(y: shown.minY)
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: held ? hold.box.minX - origin.x : 0,
                            y: held ? hold.box.minY - origin.y - topRoom * scale : 0)
                    .allowsHitTesting(!held)
                    .transition(.opacity)
            }
        }
        // A plain fade either way; quicker with Reduce Motion.
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: page.loadError)
    }
}
