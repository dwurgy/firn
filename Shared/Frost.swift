import SwiftUI

/// "Frost" (docs/design/frost): a frosted window on a snowy morning.
/// Everything outside is soft and out of focus, until the welcome's end,
/// when it comes into focus. The welcome and the "no tabs" screen, never
/// everyday browsing. No lens: that's the website's alone (David, 2026-11-24).
///
/// Performance (CLAUDE.md): the blurred logo is a picture, never a live blur;
/// everything draws once per size and look, and nothing moves by itself, so
/// nothing redraws while the scene sits idle.
struct FrostScene: View {
    enum Focus {
        /// The plain sky (the welcome's steps).
        case sky
        /// The logo out of focus (Hello).
        case blurred
        /// The whole logo sharp ("Welcome in.").
        case sharp
    }

    var focus = Focus.sky
    /// How much of the bottom the words take: the logo sits in the open
    /// space above them.
    var footer: CGFloat = 164

    var body: some View {
        GeometryReader { proxy in
            let logo = FrostLogoLayout(size: proxy.size, footer: footer)
            ZStack(alignment: .topLeading) {
                FrostSky()
                // Both always there, so one can come up through the other.
                FrostBlurredLogo(logo: logo)
                    .opacity(focus == .blurred ? Theme.Frost.logoOpacity : 0)
                FrostSharpLogo(logo: logo)
                    .opacity(focus == .sharp ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
        // Fades as one picture, not layer by layer.
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The sky, the same on every screen, and in light mode the faint warmth of
/// low sun along the bottom.
struct FrostSky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.Frost.skyTop, Theme.Frost.skyLow], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: Theme.Frost.horizonLow, location: 0),
                                   .init(color: Theme.Frost.horizonMid, location: 0.24),
                                   .init(color: Theme.Frost.horizonClear, location: 0.58)],
                           startPoint: .bottom, endPoint: .top)
        }
        .accessibilityHidden(true)
    }
}

/// Where the logo sits in a scene this size (BRAND.md, "The blurred logo").
struct FrostLogoLayout {
    /// The logo file's frame, before any blur spreads past it.
    let frame: CGRect

    init(size: CGSize, footer: CGFloat) {
        let open = max(size.height - footer, 1)
        let shape = 2595.2 / 5353.0
        // In a very short window, no taller than the open space can take.
        let width = min(size.width * 1.04, 1560, open * 1.2 / shape)
        let height = width * shape
        // The file has more empty space on the flake's side.
        let left = (size.width - width) / 2 - width * 0.025
        // A little above the open space's middle, as drawn.
        let middle = open * 0.46
        frame = CGRect(x: left, y: middle - height / 2, width: width, height: height)
    }
}

/// The logo out of focus: a ready-made picture, whose blur spreads past the
/// logo's frame into a clear margin (102 of its 2704 pixels on each side).
private struct FrostBlurredLogo: View {
    let logo: FrostLogoLayout

    var body: some View {
        let margin = logo.frame.width * 102 / 2500
        let frame = logo.frame.insetBy(dx: -margin, dy: -margin)
        Image("FrostLockupBlurred")
            .resizable()
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}

private struct FrostSharpLogo: View {
    let logo: FrostLogoLayout

    var body: some View {
        Image("FrostLockup")
            .resizable()
            .frame(width: logo.frame.width, height: logo.frame.height)
            .offset(x: logo.frame.minX, y: logo.frame.minY)
    }
}
