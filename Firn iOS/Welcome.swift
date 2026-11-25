import FirnCore
import SwiftUI
import UIKit

/// The welcome on the iPhone and iPad (docs/design/frost, welcome-iphone;
/// docs/HISTORY.md, "Plan: Frost"): Hello is the logo out of focus; each
/// step is the plain sky, a question, its choices, and one pill. On an iPad
/// (or an iPhone on its side) the steps take the Mac's layout. Every choice
/// applies right away.
struct Welcome: View {
    let presenter: WelcomePresenter
    let store: BrowserStore
    @State private var step = WelcomeStep.hello
    @State private var name = ""
    /// The suggested sites' icons, fetched while the welcome is open.
    @State private var siteIcons: [URL: Data] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var space: Space { store.activeSpace }
    private var finishing: Bool { presenter.finish != nil }
    private var clear: Bool { presenter.finish == .clearing || presenter.finish == .rising }
    private var isLast: Bool { step == WelcomeStep.allCases.last }
    /// Glacier until the space step, then the space's own.
    private var colorName: String { step.rawValue < WelcomeStep.space.rawValue ? "glacier" : space.color }

    var body: some View {
        GeometryReader { proxy in
            let layout = WelcomeLayout(size: proxy.size, bottomInset: proxy.safeAreaInsets.bottom)
            ZStack(alignment: .bottomLeading) {
                FrostScene(focus: clear ? .sharp : finishing || step == .hello ? .blurred : .sky,
                           footer: presenter.footer)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: step == .hello)
                    .animation(.easeOut(duration: 0.25), value: finishing)
                    .animation(.easeInOut(duration: 0.85), value: clear)
                    .ignoresSafeArea()

                Group {
                    if step == .hello {
                        hello(layout)
                            .modifier(StepEntrance(duration: 0.3))
                    } else {
                        stepScreen(layout)
                    }
                }
                .opacity(finishing ? 0 : 1)
                .animation(.easeOut(duration: 0.25), value: finishing)
                .allowsHitTesting(!finishing)
                .hiddenFromVoiceOver(finishing)

                FrostTitle("Welcome", "in.", size: layout.titleSize)
                    .padding(.horizontal, layout.side)
                    .padding(.bottom, layout.bottom)
                    .opacity(clear ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: clear)
                    .hiddenFromVoiceOver(!clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .foregroundStyle(Theme.Frost.ink)
        .tint(Theme.Frost.ink)
        .onAppear { name = space.name }
        // Fetched from the start, so they're there by the Basecamp step; the
        // fetch stops if the welcome closes first. A site with none keeps its
        // letter. The Mac welcome's same fixed addresses, with no cookies.
        .task {
            await withTaskGroup(of: (URL, Data?).self) { group in
                for site in WelcomeSite.suggestions {
                    group.addTask { (site.url, await site.fetchIcon()) }
                }
                for await (url, icon) in group {
                    if let icon { siteIcons[url] = icon }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Firn")
    }

    // MARK: Hello

    private func hello(_ layout: WelcomeLayout) -> some View {
        let words = VStack(alignment: .leading, spacing: 10) {
            FrostTitle("A calm place", "for the web.", size: layout.titleSize)
            Text("Ads and trackers are blocked, and Firn never tracks you. Setup takes a minute.")
                .frostFont(16)
                .lineSpacing(4)
                .foregroundStyle(Theme.Frost.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        return Group {
            if layout.roomy {
                HStack(alignment: .bottom, spacing: 48) {
                    words.frame(maxWidth: 480, alignment: .leading)
                    Spacer(minLength: 0)
                    WelcomePill("Let’s Begin", fills: false, action: next)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    words
                    WelcomePill("Let’s Begin", fills: true, action: next)
                }
            }
        }
        .padding(.horizontal, layout.side)
        .padding(.bottom, layout.bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { presenter.footer = $0 + layout.bottomInset }
    }

    // MARK: The steps

    private func stepScreen(_ layout: WelcomeLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if layout.roomy {
                if !layout.short {
                    Image("FirnMark")
                        .resizable()
                        .foregroundStyle(Theme.Frost.mark)
                        .frame(width: 34, height: 34)
                        .padding(.leading, -4)
                        .accessibilityHidden(true)
                }
            } else {
                HStack {
                    Button("Back", action: back).buttonStyle(FrostPlainStyle())
                    Spacer(minLength: 16)
                    Button("Skip setup", action: finishWelcome).buttonStyle(FrostPlainStyle(quiet: true))
                }
            }
            ScrollView(.vertical) {
                columns(layout)
                    // Room for the glass's edge and the checks.
                    .padding(8)
                    .padding(.vertical, layout.roomy ? 0 : 12)
                    .frame(minHeight: layout.roomy ? layout.middleHeight : 0)
            }
            // No soft edge: a mask breaks the glass inside it.
            .padding(.horizontal, -8)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // Each step is new, so it glides in; the last one simply goes.
            .id(step)
            .modifier(StepEntrance(duration: 0.22))
            if layout.roomy { roomyBottom } else { phoneBottom }
        }
        .padding(.horizontal, layout.side)
        .padding(.top, layout.top)
        .padding(.bottom, layout.bottom)
    }

    @ViewBuilder private func columns(_ layout: WelcomeLayout) -> some View {
        let question = question(layout)
        let choices = VStack(alignment: .leading, spacing: 0) { choices }
            .frame(maxWidth: layout.roomy ? 480 : .infinity, alignment: .leading)
        if layout.twoColumns {
            HStack(spacing: layout.short ? 48 : 72) {
                question.frame(width: layout.questionWidth, alignment: .leading)
                choices
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 28) {
                question.frame(maxWidth: 480, alignment: .leading)
                choices
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func question(_ layout: WelcomeLayout) -> some View {
        let heading = step.heading
        return VStack(alignment: .leading, spacing: 10) {
            FrostTitle(heading.plain, heading.strong, size: layout.questionSize)
                // VoiceOver stays on Continue from step to step, so it says
                // where it is now.
                .id(heading.plain)
                .onAppear { AccessibilityNotification.Announcement("\(heading.plain) \(heading.strong)").post() }
            Text(heading.words)
                .frostFont(16)
                .lineSpacing(4)
                .foregroundStyle(Theme.Frost.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var choices: some View {
        switch step {
        case .hello: EmptyView()
        case .search: SearchStep(accent: Theme.spaceColor(colorName))
        case .space: SpaceStep(store: store, name: $name)
        case .basecamp: SitesStep(store: store, icons: siteIcons, accent: Theme.spaceColor(colorName))
        case .defaultBrowser: DefaultBrowserStep()
        }
    }

    private var dots: some View {
        StepDots(count: WelcomeStep.allCases.count - 1, current: step.rawValue - 1)
    }

    private var forwardTitle: String { isLast ? "Start Browsing" : "Continue" }

    private var phoneBottom: some View {
        VStack(spacing: 20) {
            dots
            WelcomePill(forwardTitle, fills: true, action: next)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    /// The Mac's bottom row.
    private var roomyBottom: some View {
        HStack(spacing: 24) {
            dots
            Button("Skip setup", action: finishWelcome)
                .buttonStyle(FrostPlainStyle(quiet: true))
                .keyboardShortcut(.cancelAction)
                .padding(.leading, 4)
            Spacer(minLength: 0)
            Button("Back", action: back).buttonStyle(FrostPlainStyle())
            WelcomePill(forwardTitle, fills: false, action: next)
        }
        .padding(.top, 12)
    }

    // MARK: Moving

    private func next() {
        if step == .space { saveName() }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if let following = WelcomeStep(rawValue: step.rawValue + 1) { step = following } else { finishWelcome() }
    }

    private func back() {
        if step == .space { saveName() }
        step = WelcomeStep(rawValue: step.rawValue - 1) ?? .hello
    }

    private func saveName() {
        store.updateSpace(space, name: name, color: space.color)
    }

    private func finishWelcome() {
        saveName()
        presenter.finish(reduceMotion: reduceMotion)
    }
}

/// How the welcome lays out in a window this size (inside the safe area).
private struct WelcomeLayout {
    let size: CGSize
    /// The home bar's room: the words' 48pt from the screen's edge, as
    /// drawn, is this and `bottom`.
    let bottomInset: CGFloat

    /// Room for the Mac's layout: an iPad, or an iPhone on its side.
    var roomy: Bool { size.width >= 640 }
    /// An iPhone on its side.
    var short: Bool { size.height < 500 }
    var twoColumns: Bool { size.width >= 940 || (short && roomy) }
    var side: CGFloat { !roomy ? 24 : short ? 24 : twoColumns ? 72 : 56 }
    var top: CGFloat { !roomy ? 4 : short ? 12 : 40 }
    var bottom: CGFloat { !roomy ? 14 : short ? 8 : 44 }
    var titleSize: CGFloat { roomy && !short ? 38 : 32 }
    var questionSize: CGFloat { twoColumns && !short ? 42 : 32 }
    var questionWidth: CGFloat {
        short ? size.width * 0.36 : min(max(size.width - 144 - 72 - 440, 260), 380)
    }
    /// About what's left between the mark and the bottom row, so the step
    /// sits in the middle of it.
    var middleHeight: CGFloat { max(size.height - (short ? 84 : 184) - 16, 0) }
}

private enum WelcomeStep: Int, CaseIterable {
    case hello, search, space, basecamp, defaultBrowser

    /// The step's question, its second half in SemiBold, and its few words.
    var heading: (plain: String, strong: String, words: String) {
        switch self {
        case .hello: ("", "", "")
        case .search: ("Which search", "do you like?",
                       "What you type in the address bar searches here. More choices are in Settings.")
        case .space: ("Name your", "first space.",
                      "A space is its own browser, with its own tabs, sign\u{2011}ins, and history. You can add more later.")
        case .basecamp: ("Start your", "Basecamp",
                         "Pick a few sites you use every day in this space, or none. They sit at the top of your tabs.")
        case .defaultBrowser: ("Open links", "in Firn?",
                               "Make Firn your default browser, so links from mail, chat, and other apps open here. You can change this anytime in the Settings app.")
        }
    }
}

// MARK: - Pieces

/// The one pill on each screen: iOS's own glass button, "Frosty, no tint".
private struct WelcomePill: View {
    let title: String
    let fills: Bool
    let action: () -> Void

    init(_ title: String, fills: Bool, action: @escaping () -> Void) {
        self.title = title
        self.fills = fills
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frostFont(17)
                .foregroundStyle(Theme.Frost.ink)
                .lineLimit(1)
                .padding(.horizontal, fills ? 0 : 28 - GlassButton.padding)
                .frame(minHeight: GlassButton.label(52))
                .frame(maxWidth: fills ? .infinity : nil)
        }
        .firnGlassButton(.capsule)
        .keyboardShortcut(.defaultAction)
        .fixedSize(horizontal: !fills, vertical: true)
    }
}

/// Basecamp: the suggested sites. A pick is a tile at once (Firn's choices
/// all apply right away); taking it back closes that tile.
private struct SitesStep: View {
    let store: BrowserStore
    let icons: [URL: Data]
    let accent: Color

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 64), spacing: 8), count: 4), spacing: 18) {
            ForEach(WelcomeSite.suggestions) { site in
                let tile = store.basecampTile(for: site.url)
                SiteChoice(name: site.name, icon: icons[site.url] ?? tile?.icon, accent: accent,
                           isOn: tile != nil, canPick: store.canAddToBasecamp) {
                    if let tile {
                        store.closeTile(tile)
                    } else {
                        store.addBasecampTile(site.url, title: site.name, icon: icons[site.url])
                    }
                }
            }
        }
        .frame(maxWidth: 400)
        // Four names side by side have only so much room.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Open links in Firn? Only iOS's Settings can set it, and Firn can't tell
/// whether it's set (`SettingsSheet`), so this only opens the way there.
private struct DefaultBrowserStep: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(FrostPlainStyle(underlined: true))
            .accessibilityHint("Opens the Settings app")
            Text("Choose Default Browser App there, then Firn.")
                .frostFont(14)
                .foregroundStyle(Theme.Frost.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
