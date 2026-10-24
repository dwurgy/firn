import FirnCore
import SwiftUI

/// The welcome, over the whole window while it's open, fading in and out.
struct WelcomeLayer: View {
    let window: WindowModel

    var body: some View {
        ZStack {
            if window.showsWelcome {
                Welcome(window: window)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: window.showsWelcome)
    }
}

/// The welcome, the first time Firn opens (and from Help): the First light
/// scene and a few short steps. Ported from the Electron app
/// (docs/electron-welcome: Welcome.tsx and styles.css, "Welcome"), updated
/// for the native Firn (plan in docs/HISTORY.md, Phase 6). Every choice
/// applies right away; from the space step on, the snow takes the space's
/// color, so choices show live. Esc or "Skip setup" leaves it at any point.
private struct Welcome: View {
    let window: WindowModel
    @State private var step = WelcomeStep.hello
    @State private var name = ""

    private var store: BrowserStore { window.store }
    private var space: Space { store.activeSpace }
    private var steps: [WelcomeStep] { WelcomeStep.allCases }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The sky and sunrise are always Firn's own; the snow takes the
            // space's color from the space step on.
            FirstLightScene(spaceColor: index >= steps.firstIndex(of: .space)! ? space.color : "glacier")
            // The scene's empty sky moves the window, like a title bar.
            WindowDragArea()
            VStack(spacing: 0) {
                if step == .hello {
                    HelloScreen(next: next)
                        .modifier(StepEntrance(duration: 0.3))
                } else {
                    StepDots(count: steps.count, current: index)
                        .padding(.bottom, 22)
                    card
                }
            }
            // A little above the middle, clear of the snow.
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 134, trailing: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            SkipButton(action: finish)
                .padding(.leading, 28)
                .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.ink)
        .ignoresSafeArea()
        .onAppear { name = space.name }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Firn")
        .accessibilityAddTraits(.isModal)
    }

    /// The steps after Hello: a frosted card, its words, and Back and Continue.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                switch step {
                case .hello: EmptyView()
                case .address: AddressStep(accent: Theme.spaceColor(space.color))
                case .search: SearchStep(accent: Theme.spaceColor(space.color))
                case .space: SpaceStep(store: store, name: $name)
                }
            }
            // Each step is new, so it glides in; the last one simply goes.
            .id(step)
            .modifier(StepEntrance(duration: 0.22))
            HStack {
                QuietButton(title: "Back", action: back)
                Spacer()
                InkButton(title: isLast ? "Start browsing" : "Continue", height: 42, padding: 20, size: 14, action: next)
            }
            .padding(.top, 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 40, leading: 44, bottom: 30, trailing: 44))
        .background {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            shape
                .fill(Theme.Welcome.card)
                .shadow(color: Theme.Welcome.cardShadowNear, radius: 1, y: 1)
                .shadow(color: Theme.Welcome.cardShadowFar, radius: 24, y: 18)
                .overlay { shape.strokeBorder(Theme.Welcome.edge, lineWidth: 1) }
        }
        .frame(maxWidth: 620)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveName() {
        store.updateSpace(space, name: name, icon: space.icon, color: space.color)
    }

    private func next() {
        if step == .space { saveName() }
        if isLast { finish() } else { step = steps[index + 1] }
    }

    private func back() {
        step = steps[max(0, index - 1)]
    }

    /// "Start browsing", Skip, or Esc. The full finish ("Welcome in.") is a later step.
    private func finish() {
        saveName()
        window.closeWelcome()
    }
}

/// The welcome's steps, in order. Basecamp and sidebar, default browser,
/// and tips come in later steps (Phase 6, steps 3 and 4).
private enum WelcomeStep: CaseIterable {
    case hello, address, search, space
}

// MARK: - Steps

/// Hello: no card, just the mark and the words.
private struct HelloScreen: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Theme.Welcome.markTop, Theme.Welcome.markBottom],
                // CSS's 160deg: down, leaning a little right.
                startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)
            )
            .mask { Image("FirnMark").resizable().scaledToFit() }
            .frame(width: 86, height: 86)
            .shadow(color: Theme.Welcome.markShadow, radius: 12, y: 10)
            .padding(.bottom, 26)
            .accessibilityHidden(true)
            Text("Welcome to Firn")
                .font(Theme.fraunces(72, weight: 360))
                .tracking(-1.08)
                .accessibilityAddTraits(.isHeader)
            Text("A calm place for the web. Ads and trackers are blocked, and Firn never tracks you. Let’s set up a few things; it takes a minute, and you can change any of it later.")
                .font(.system(size: 19))
                .lineSpacing(7)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .padding(.bottom, 34)
            InkButton(title: "Let’s begin", height: 50, padding: 26, size: 16, action: next)
        }
        .multilineTextAlignment(.center)
    }
}

/// Where the address bar goes: two little pictures of the window.
private struct AddressStep: View {
    let accent: Color
    @AppStorage(Preference.addressBar) private var place = AddressBarPlace.sidebar

    var body: some View {
        StepHeading(title: "Where should the address bar go?",
                    words: "You can change this anytime in Settings.")
        HStack(spacing: 14) {
            look(.sidebar, "In the sidebar", "Everything in one calm place, with more room for the page.")
            look(.top, "At the top", "A bar across the top of the window.")
        }
    }

    private func look(_ value: AddressBarPlace, _ title: String, _ note: String) -> some View {
        ChoiceTile(isOn: place == value, accent: accent, action: { place = value }) {
            LookPicture(top: value == .top)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 12)
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
        }
    }
}

/// Which search, and whether to show suggestions (the one place typing
/// goes over the network, so nothing is sent until the answer is yes).
private struct SearchStep: View {
    let accent: Color
    @AppStorage(Preference.searchEngine) private var engine = SearchEngine.default
    @AppStorage(Preference.searchSuggestions) private var suggestions = false

    /// The welcome's three; more are in Settings.
    private static let engines: [(SearchEngine, String)] = [
        (.google, "The search most people know."),
        (.duckDuckGo, "Doesn’t keep track of your searches."),
        (.bing, "Microsoft’s search."),
    ]

    var body: some View {
        StepHeading(title: "Which search do you like?",
                    words: "What you type in the address bar searches here. More choices are in Settings.")
        HStack(alignment: .top, spacing: 12) {
            ForEach(Self.engines, id: \.0) { choice, note in
                ChoiceTile(isOn: engine == choice, accent: accent, action: { engine = choice }) {
                    Text(choice.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 2)
                }
            }
        }
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show suggestions as you type?")
                    .font(.system(size: 13))
                Text("Your search engine sees what you type.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            YesNoSwitch(isOn: $suggestions, label: "Show suggestions as you type")
        }
        .padding(.top, 16)
    }
}

/// The first space: each space is its own browser. Its name, color, and
/// icon change as they're picked; the snow behind follows the color.
private struct SpaceStep: View {
    let store: BrowserStore
    @Binding var name: String

    private var space: Space { store.activeSpace }
    private var color: Color { Theme.spaceColor(space.color) }

    var body: some View {
        StepHeading(title: "Each space is its own browser",
                    words: "Like Work and Personal: each keeps its own tabs, sign-ins, and history. Start with this one; you can add more later.")
        HStack(spacing: 12) {
            SpaceIconView(icon: SpaceIcon(stored: space.icon), size: 18, color: color)
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .accessibilityLabel("Space name")
                .onChange(of: name) { if name.count > 40 { name = String(name.prefix(40)) } }
                .onSubmit { store.updateSpace(space, name: name, icon: space.icon, color: space.color) }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(tile(cornerRadius: 12, edge: Theme.Welcome.tileEdge))
        HStack(spacing: 12) {
            ForEach(Theme.spaceColorNames, id: \.self) { choice in
                ColorDot(name: choice, isOn: space.color == choice) {
                    store.updateSpace(space, name: space.name, icon: space.icon, color: choice)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 18)
        // Two even rows of eight.
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
            ForEach(SpaceIcon.allCases, id: \.self) { icon in
                IconTile(icon: icon, color: color, isOn: SpaceIcon(stored: space.icon) == icon) {
                    store.updateSpace(space, name: space.name, icon: icon.rawValue, color: space.color)
                }
            }
        }
        .fixedSize()
    }
}

// MARK: - Pieces

/// A step's title (Fraunces) and its few words.
private struct StepHeading: View {
    let title: String
    let words: String

    var body: some View {
        Text(title)
            .font(Theme.fraunces(34, weight: 380))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
        Text(words)
            .font(.system(size: 16))
            .lineSpacing(6)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 26)
    }
}

/// Where the step is: a dot for each, the current one drawn out long.
private struct StepDots: View {
    let count: Int
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.ink : Theme.faint)
                    .opacity(index == current ? 0.75 : 0.45)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}

/// A new step's words fade up into place (6pt), once, as they appear.
/// Reduce Motion: they're simply there.
private struct StepEntrance: ViewModifier {
    let duration: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: duration)) { shown = true }
            }
    }
}

/// The welcome's frosted tiles: a light tile with a fine edge.
private func tile(cornerRadius: CGFloat, edge: Color, width: CGFloat = 1) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return shape
        .fill(Theme.Welcome.tile)
        .overlay {
            // A 2pt ring sits half outside, as CSS's border plus a 1px shadow.
            shape.inset(by: width > 1 ? -1 : 0).strokeBorder(edge, lineWidth: width)
        }
}

/// One choice on a light tile; the chosen one gets a 2pt ring in the space's color.
private struct ChoiceTile<Content: View>: View {
    let isOn: Bool
    let accent: Color
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) { content }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
                .background(tile(cornerRadius: 14, edge: isOn ? accent : Theme.Welcome.tileEdge,
                                 width: isOn || hovering ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOn)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A small drawing of Firn's window: the address bar in the sidebar, or in
/// a bar along the top (Welcome.tsx, `LookPicture`, on a 200 × 120 grid).
private struct LookPicture: View {
    let top: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Read so a change of look redraws it.
        let _ = colorScheme
        Canvas { context, size in
            let scale = size.width / 200
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: Color) {
                let box = CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
                context.fill(Path(roundedRect: box, cornerRadius: r * scale), with: .color(color))
            }
            rect(0, 0, 200, 120, 10, Theme.frame)
            if top {
                rect(92, 7, 64, 11, 5.5, Theme.Welcome.pill)
                rect(54, 25, 140, 89, 6, Theme.page)
            } else {
                rect(8, 10, 40, 11, 5.5, Theme.Welcome.pill)
                rect(54, 6, 140, 108, 6, Theme.page)
            }
            for (y, w) in [(30.0, 38.0), (42, 30), (54, 34)] { rect(8, y, w, 7, 3.5, Theme.Welcome.pill) }
        }
        .aspectRatio(200 / 120, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Yes or No, side by side; the chosen half lifts to the page color.
private struct YesNoSwitch: View {
    @Binding var isOn: Bool
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            half("Yes", value: true)
            half("No", value: false)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.hover))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOn)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func half(_ title: String, value: Bool) -> some View {
        let chosen = isOn == value
        return Button { isOn = value } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(chosen ? Theme.ink : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(chosen ? Theme.page : .clear)
                        .shadow(color: chosen ? Theme.Welcome.segmentShadow : .clear, radius: 1.5, y: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// A space color to pick; the chosen one gets an ink ring, a little apart.
private struct ColorDot: View {
    let name: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.spaceColor(name))
                .frame(width: 30, height: 30)
                .overlay {
                    Circle()
                        .strokeBorder(Theme.ink.opacity(isOn ? 1 : 0), lineWidth: 2)
                        .padding(-5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOn)
        .help(name.capitalized)
        .accessibilityLabel(name.capitalized)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A space icon to pick, in the space's color on a light tile.
private struct IconTile: View {
    let icon: SpaceIcon
    let color: Color
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SpaceIconView(icon: icon, size: 18, color: color)
                .frame(width: 38, height: 38)
                .background(tile(cornerRadius: 10, edge: isOn ? color : Theme.Welcome.tileEdge,
                                 width: isOn || hovering ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOn)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: color)
        .help(icon.spokenName)
        .accessibilityLabel(icon.spokenName)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// The welcome's main button: ink, dark on light and light on dark. Return presses it.
private struct InkButton: View {
    let title: String
    let height: CGFloat
    let padding: CGFloat
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.page)
                .padding(.horizontal, padding)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink))
                .opacity(hovering ? 0.88 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
    }
}

/// Back: quiet words, a warm wash on hover.
private struct QuietButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -10)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
    }
}

/// "Skip setup": a small frosted pill, bottom left, on every step. Esc presses it.
private struct SkipButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Skip setup")
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(Theme.Welcome.card)
                        .overlay { Capsule().strokeBorder(Theme.Welcome.edge, lineWidth: 1) }
                }
                .opacity(hovering ? 0.85 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
    }
}
