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

/// The welcome's finish: the sidebar and the page wait low behind the snow,
/// at 86% of their size, then rise into place (the approved source's
/// `fl-browser-rise`). Transforms only, from the top's middle; at rest
/// they're plain identities.
struct WelcomeLift: ViewModifier {
    let finish: WindowModel.WelcomeFinish?
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        let low = finish == .begun
        content
            .scaleEffect(low ? 0.86 : 1, anchor: .top)
            .offset(y: low ? height * 0.96 : 0)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }
}

/// Behind the real window while the welcome is open: First light's sky,
/// sun, and flakes, "Welcome in.", and the warm shadow the window casts as
/// it rises. All of it stays under the window until the finish lowers it;
/// the snow stays in front, in the welcome (`FirstLightScene.Part`).
struct WelcomeBackdrop: View {
    let window: WindowModel

    var body: some View {
        if window.showsWelcome {
            let finishing = window.welcomeFinish != nil
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    FirstLightScene(spaceColor: "glacier", part: .back, sunRises: finishing)
                    // "Welcome in." sits in the sky; the window rises over it.
                    Text("Welcome in.")
                        .font(Theme.fraunces(44, weight: 360))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, proxy.size.height * 0.15)
                        .opacity(finishing ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: finishing)
                    // The rising window's frame: Firn's frame color in the
                    // space's tint, with a panel's corners; it gives way to
                    // the real glass as the snow fades.
                    let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    shape.fill(Theme.frame)
                        .overlay { SpaceTint(color: window.store.activeSpace.color).clipShape(shape) }
                        .shadow(color: Theme.shadowPeek.opacity(0.64), radius: 4, y: 2)
                        .shadow(color: Theme.shadowPeek, radius: 24, y: 18)
                        .opacity(window.welcomeFinish == .begun || window.welcomeFinish == .rising ? 1 : 0)
                        .modifier(WelcomeLift(finish: window.welcomeFinish))
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// The welcome, the first time Firn opens (and from Help): the First light
/// scene and a few short steps. The steps and words come from the Electron
/// app (docs/electron-welcome), updated for the native Firn (plan in
/// docs/HISTORY.md, Phase 6); the card, buttons, and controls are the Mac's
/// own: the command bar's glass, glass buttons, and the space sheet's pickers.
/// Every choice applies right away; from the space step on, the snow and the
/// card take the space's color, so choices show live. Esc or "Skip setup"
/// leaves it at any point.
private struct Welcome: View {
    let window: WindowModel
    @State private var step = WelcomeStep.hello
    @State private var name = ""
    /// Whether "Open links in Firn?" is one of the steps: decided once, on
    /// leaving Hello, so the steps don't shift under the person afterwards.
    @State private var offersDefault = false
    /// Arc's spaces, read while Hello is up; nil if Arc isn't on this Mac or has none.
    @State private var arcPlan: ArcImportPlan?
    /// Whether "Coming from Arc?" is one of the steps: decided once, on
    /// leaving Hello, like `offersDefault`.
    @State private var offersArc = false
    /// Arc's spaces came over, so the space and Basecamp steps go.
    @State private var importedArc = false
    /// The suggested sites' icons, fetched while the welcome is open.
    @State private var siteIcons: [URL: Data] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: BrowserStore { window.store }
    private var space: Space { store.activeSpace }
    private var finish: WindowModel.WelcomeFinish? { window.welcomeFinish }
    private var steps: [WelcomeStep] {
        WelcomeStep.allCases.filter { step in
            switch step {
            case .defaultBrowser: offersDefault
            case .arc: offersArc
            case .space, .basecamp: !importedArc
            default: true
            }
        }
    }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLast: Bool { index == steps.count - 1 }
    /// Glacier until the space step (or until Arc's spaces come over), then the space's own.
    private var colorName: String {
        if importedArc { return space.color }
        guard let start = steps.firstIndex(of: .space), index >= start else { return "glacier" }
        return space.color
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The sky and sunrise are always Firn's own; the snow takes the
            // space's color from the space step on. At the finish only the
            // snow stays here, in front of the rising window; the sky is
            // behind it (`WelcomeBackdrop`).
            FirstLightScene(spaceColor: colorName, part: finish == nil ? .whole : .front)
            // The scene's empty sky moves the window, like a title bar.
            WindowDragArea()
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if step == .hello {
                        HelloScreen(next: next)
                            .modifier(StepEntrance(duration: 0.3))
                    } else {
                        StepDots(count: steps.count - 1, current: index - 1)
                            .padding(.bottom, 18)
                        card
                    }
                }
                // Hello sits a little above the middle, clear of the snow. The
                // cards hang from one fixed line, so the dots and titles stay
                // put while each step's card grows or shrinks below them.
                .padding(EdgeInsets(top: step == .hello ? 24 : max(24, proxy.size.height * 0.18),
                                    leading: 24, bottom: 134, trailing: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: step == .hello ? .center : .top)
            }
            .modifier(FinishFade(finishing: finish != nil))
            // Faded, it isn't there for VoiceOver either.
            .accessibilityHidden(finish != nil)
            Button("Skip setup", action: finishWelcome)
                .modifier(WelcomeButton(prominent: false))
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .padding(.leading, 24)
                .padding(.bottom, 24)
                .modifier(FinishFade(finishing: finish != nil))
                .accessibilityHidden(finish != nil)
        }
        .foregroundStyle(Theme.ink)
        // Last, the snow fades away to the browser.
        .opacity(finish == .fading ? 0 : 1)
        .ignoresSafeArea()
        .onAppear { name = space.name }
        // Fetched from the start, so they're there by the Basecamp step; the
        // fetch stops if the welcome closes first. A site with none keeps its letter.
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
        // Arc's sidebar file, read on this Mac only (nothing is sent), while
        // Hello is up. Only when there's nothing in Firn yet to bring it beside.
        .task {
            guard store.hasOnlyUntouchedSpace,
                  case .ready(let plan) = await ArcImport.readArc(), !plan.spaces.isEmpty else { return }
            arcPlan = plan
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Firn")
        .accessibilityAddTraits(.isModal)
    }

    /// The steps after Hello: the command bar's glass, its words, and Back and Continue.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                switch step {
                case .hello: EmptyView()
                case .address: AddressStep(colorName: colorName)
                case .search: SearchStep(accent: Theme.spaceColor(colorName))
                case .arc: if let arcPlan { ArcStep(plan: arcPlan, store: store, imported: importedArc) }
                case .space: SpaceStep(store: store, name: $name)
                case .basecamp: BasecampStep(store: store, icons: siteIcons, colorName: colorName)
                case .defaultBrowser: DefaultBrowserStep()
                case .tips: TipsStep()
                }
            }
            // Each step is new, so it glides in; the last one simply goes.
            .id(step)
            .modifier(StepEntrance(duration: 0.22))
            HStack(spacing: 8) {
                Button("Back", action: back)
                    .modifier(WelcomeButton(prominent: false))
                Spacer()
                if step == .arc && !importedArc {
                    Button("Start Fresh", action: next)
                        .modifier(WelcomeButton(prominent: false))
                    Button("Bring Them Over", action: bringArcOver)
                        .modifier(WelcomeButton(prominent: true))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(isLast ? "Start Browsing" : "Continue", action: next)
                        .modifier(WelcomeButton(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.top, 28)
        }
        .padding(32)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            CommandBarGlass(shape: shape, color: Theme.spaceColor(colorName))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: colorName)
        }
        .clipShape(shape)
        .shadow(color: Theme.shadowPeek, radius: 24, y: 8)
        .shadow(color: Theme.shadowPeek.opacity(0.5), radius: 3, y: 1)
    }

    private func saveName() {
        store.updateSpace(space, name: name, icon: space.icon, color: space.color)
    }

    private func next() {
        if step == .hello {
            offersDefault = !DefaultBrowser.isFirn
            offersArc = arcPlan != nil && store.hasOnlyUntouchedSpace
        }
        if step == .space { saveName() }
        if isLast { finishWelcome() } else { step = steps[index + 1] }
    }

    /// Arc's spaces take the untouched first space's place, and the step
    /// says so where it stands; Continue then skips the space and Basecamp
    /// steps. The snow and card turn to the first Arc space's color.
    private func bringArcOver() {
        guard let arcPlan, !importedArc else { return }
        store.importFromArc(arcPlan) { existing in
            let style = WindowModel.freeStyle(among: existing)
            return (style.icon.rawValue, style.color)
        }
        importedArc = true
        // The space on screen is Arc's first now; finishing saves this name.
        name = space.name
    }

    private func back() {
        step = steps[max(0, index - 1)]
    }

    /// "Start Browsing", Skip, or Esc: "Welcome in.", and the browser rises.
    private func finishWelcome() {
        guard finish == nil else { return }
        saveName()
        window.finishWelcome(reduceMotion: reduceMotion)
    }
}

/// At the finish, the step and "Skip setup" fade first (250ms).
private struct FinishFade: ViewModifier {
    let finishing: Bool

    func body(content: Content) -> some View {
        content
            .opacity(finishing ? 0 : 1)
            .animation(.easeOut(duration: 0.25), value: finishing)
    }
}

/// The welcome's steps, in order. The default browser step shows only
/// while Firn isn't the default yet (see `offersDefault`), and the Arc step
/// only when Arc is on this Mac (see `offersArc`).
private enum WelcomeStep: CaseIterable {
    case hello, address, search, arc, space, basecamp, defaultBrowser, tips

    /// The address step waits for the "At the top" look (David, 2026-10-23):
    /// until then the choice would change nothing. Its view is kept, ready.
    static var allCases: [WelcomeStep] { [.hello, .search, .arc, .space, .basecamp, .defaultBrowser, .tips] }
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
            .frame(width: 80, height: 80)
            .shadow(color: Theme.Welcome.markShadow, radius: 12, y: 10)
            .padding(.bottom, 24)
            .accessibilityHidden(true)
            Text("Welcome to Firn")
                .font(Theme.fraunces(64, weight: 360))
                .tracking(-0.9)
                .accessibilityAddTraits(.isHeader)
            Text("A calm place for the web. Ads and trackers are blocked, and Firn never tracks you. Let’s set up a few things; it takes a minute, and you can change any of it later.")
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.bottom, 32)
            Button(action: next) {
                // Wide enough to answer the big heading above it.
                Text("Let’s Begin").frame(minWidth: 130)
            }
                .modifier(WelcomeButton(prominent: true))
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
        }
        .multilineTextAlignment(.center)
    }
}

/// Where the address bar goes: two little pictures of the window, picked
/// like System Settings' Appearance.
private struct AddressStep: View {
    let colorName: String
    @AppStorage(Preference.addressBar) private var place = AddressBarPlace.sidebar

    var body: some View {
        StepHeading(title: "Where should the address bar go?",
                    words: "You can change this anytime in Settings.")
        HStack(alignment: .top, spacing: 20) {
            LookChoice(top: false, title: "In the sidebar", note: "Everything in one calm place, with more room for the page.",
                       isOn: place == .sidebar, colorName: colorName) { place = .sidebar }
            LookChoice(top: true, title: "At the top", note: "A bar across the top of the window.",
                       isOn: place == .top, colorName: colorName) { place = .top }
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
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.engines, id: \.0) { choice, note in
                ChoiceRow(isSelected: engine == choice, title: Text(choice.name), caption: note) { engine = choice }
            }
        }
        // The rows' own padding lines their text up with the words above.
        .padding(.horizontal, -8)
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show suggestions as you type")
                    .font(Theme.tabFont)
                Text("Your search engine sees what you type.")
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.muted)
            }
            // VoiceOver reads these with the switch, once.
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle("Show suggestions as you type", isOn: $suggestions)
                .toggleStyle(.switch)
                // The space's color, not the system blue.
                .tint(accent)
                .labelsHidden()
                .accessibilityHint("Your search engine sees what you type.")
        }
        .padding(.top, 18)
    }
}

/// Coming from Arc: Arc's spaces as they'll look in Firn (each with the
/// color and icon it will get), what each brings, and whose sign-ins it
/// shares. Once they've come over, the same list says they're here.
private struct ArcStep: View {
    let plan: ArcImportPlan
    let store: BrowserStore
    let imported: Bool

    /// More than this, and the rest are "and 4 more spaces", so the card stays calm.
    private static let listedSpaces = 4

    /// Picked as the import picks them: the next free color and icon, in order.
    private var styles: [(icon: String, color: String)] {
        var existing = imported || store.hasOnlyUntouchedSpace ? [] : store.spaces
        return plan.spaces.map { space in
            let style = WindowModel.freeStyle(among: existing)
            existing.append(Space(name: space.name, icon: style.icon.rawValue, color: style.color,
                                  order: existing.count, dataStoreID: UUID()))
            return (style.icon.rawValue, style.color)
        }
    }

    var body: some View {
        if imported {
            StepHeading(title: "Your Arc spaces are here",
                        words: "\(plan.spaces.count == 1 ? "It’s" : "They’re") at the bottom of the sidebar. Each tab loads when you first click it.")
        } else {
            StepHeading(title: "Coming from Arc?",
                        words: "Firn can bring over your spaces: favorites become Basecamp, and pinned tabs become groups.")
        }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(zip(plan.spaces, styles).prefix(Self.listedSpaces).enumerated()), id: \.offset) { _, row in
                let (space, style) = row
                HStack(spacing: 10) {
                    SpaceIconView(icon: SpaceIcon(stored: style.icon), size: 16, color: Theme.spaceColor(style.color))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(space.name)
                            .font(Theme.tabFont)
                        Text(ArcImportSheet.contents(of: space))
                            .font(Theme.hintFont)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            let more = plan.spaces.count - Self.listedSpaces
            if more > 0 {
                Text(more == 1 ? "and 1 more space" : "and \(more) more spaces")
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 26)
            }
        }
        if !imported {
            Text("\(ArcImportSheet.signInsLine(plan)) Unpinned tabs and history stay in Arc.")
                .font(Theme.labelFont)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
    }
}

/// The first space: each space is its own browser. Its name, color, and
/// icon change as they're picked, with the space sheet's own pickers; the
/// card and the snow behind follow the color.
private struct SpaceStep: View {
    let store: BrowserStore
    @Binding var name: String
    @FocusState private var nameFocused: Bool

    private var space: Space { store.activeSpace }
    private var color: Color { Theme.spaceColor(space.color) }

    var body: some View {
        StepHeading(title: "Each space is its own browser",
                    words: "Like Work and Personal: each keeps its own tabs, sign-ins, and history. Start with this one; you can add more later.")
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            section("Name") {
                HStack(spacing: 8) {
                    SpaceIconView(icon: SpaceIcon(stored: space.icon), size: 16, color: color)
                        .accessibilityHidden(true)
                    TextField(Space.defaultName, text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.tabFont)
                        .focused($nameFocused)
                        .accessibilityLabel("Space name")
                        .onChange(of: name) { if name.count > 40 { name = String(name.prefix(40)) } }
                        .onSubmit { store.updateSpace(space, name: name, icon: space.icon, color: space.color) }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).fill(Theme.hover)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(nameFocused ? Theme.frost : .clear, lineWidth: 2)
                }
            }
            section("Color") {
                HStack(spacing: 6) {
                    ForEach(Theme.spaceColorNames, id: \.self) { choice in
                        ColorSwatch(name: choice, isSelected: space.color == choice) {
                            store.updateSpace(space, name: space.name, icon: space.icon, color: choice)
                        }
                    }
                }
                .padding(.leading, -4)
            }
            section("Icon") {
                // Two even rows of eight.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                    ForEach(SpaceIcon.allCases, id: \.self) { icon in
                        IconChoice(icon: icon, color: color, isSelected: SpaceIcon(stored: space.icon) == icon) {
                            store.updateSpace(space, name: space.name, icon: icon.rawValue, color: space.color)
                        }
                    }
                }
                .fixedSize()
                .padding(.leading, -6)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.labelFont)
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// Basecamp and the sidebar: the suggested sites to pick, and beside them
/// a small picture of this space's sidebar that builds itself as they're
/// picked. A pick is a tile at once (Firn's choices all apply right away);
/// taking it back closes that tile, which ⇧⌘T can bring back.
private struct BasecampStep: View {
    let store: BrowserStore
    let icons: [URL: Data]
    let colorName: String

    private var accent: Color { Theme.spaceColor(colorName) }

    var body: some View {
        StepHeading(title: "Start your Basecamp",
                    words: "Pick a few sites you use every day in this space, or none. You can add more anytime: right-click a tab and choose Add to Basecamp.")
        HStack(alignment: .top, spacing: 24) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 14), count: 4), alignment: .leading, spacing: 14) {
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
            .fixedSize()
            SidebarPicture(tiles: store.basecampTabs, colorName: colorName)
        }
        VStack(alignment: .leading, spacing: 8) {
            SidebarLine(title: "Groups", words: "Keep tabs together: drag one tab onto another.")
            SidebarLine(title: "Tabs", words: "Everything else. Tabs you’re done with tidy themselves away.")
        }
        .padding(.top, 22)
    }
}

/// One suggested site: a tile of Basecamp's frost with its icon (its letter
/// until the icon arrives, or if it has none), ringed and checked in the
/// space's color when picked, and its name below.
private struct SiteChoice: View {
    let name: String
    let icon: Data?
    let accent: Color
    let isOn: Bool
    let canPick: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    frost
                    if let icon {
                        SiteIconView(icon: icon, size: 30) { EmptyView() }
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .transition(.opacity)
                    } else {
                        Text(name.prefix(1))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .transition(.opacity)
                    }
                }
                .frame(width: 64, height: 64)
                .overlay { shape.strokeBorder(accent.opacity(isOn ? 1 : 0), lineWidth: 2) }
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            // Never pure white, as on Basecamp's letter tiles.
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(width: 20, height: 20)
                            .background { Circle().fill(accent) }
                            .background { Circle().fill(Theme.page).padding(-2) }
                            .offset(x: 7, y: -7)
                            .transition(.opacity)
                    }
                }
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !canPick)
        .opacity(!isOn && !canPick ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: icon != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// Basecamp's own frost (see `TileGlass`), brighter on hover.
    @ViewBuilder private var frost: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else {
            shape.fill(hovering ? Theme.tileFillHover : Theme.tileFill)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5).padding(-0.5) }
                .shadow(color: Theme.shadowSoft, radius: 1, y: 0.5)
        }
    }
}

/// A small picture of this space's sidebar, on the frame tinted by its
/// color: the traffic lights, the address bar, its real Basecamp tiles
/// (each frosting in as it's picked), a group's card, and a few tabs.
private struct SidebarPicture: View {
    let tiles: [FirnCore.Tab]
    let colorName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { Theme.spaceColor(colorName) }
    private var rows: [[FirnCore.Tab]] {
        stride(from: 0, to: tiles.count, by: 4).map { Array(tiles[$0..<min($0 + 4, tiles.count)]) }
    }

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Theme.faint.opacity(0.7)).frame(width: 5, height: 5)
                }
            }
            .padding(.top, 10)
            Capsule().fill(Theme.Welcome.pill)
                .frame(width: 84, height: 10)
                .padding(.top, 8)
            if !tiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            ForEach(rows[index]) { tile in
                                MiniTile(icon: tile.icon, accent: accent)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
            // A group: its card, its name, and two of its tabs.
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Theme.faint.opacity(0.45)).frame(width: 26, height: 5)
                MiniRow(width: 44)
                MiniRow(width: 34)
            }
            .padding(7)
            .frame(width: 84, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.groupFill)
                    .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent.opacity(Theme.groupTint)) }
                    .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
            }
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 9) {
                MiniRow(width: 50)
                MiniRow(width: 36)
                MiniRow(width: 44)
            }
            .padding(.leading, 7)
            .padding(.top, 12)
        }
        .padding(.horizontal, 10)
        .frame(width: 104, height: 216, alignment: .topLeading)
        .background { frame.fill(Theme.frame).overlay { frame.fill(Theme.frameTint(colorName)) } }
        .clipShape(frame)
        .overlay { frame.strokeBorder(Theme.faint.opacity(0.4), lineWidth: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: tiles.map(\.id))
        .accessibilityHidden(true)
    }
}

/// A Basecamp tile in the sidebar picture: frost washed with the space's
/// color, and the site's icon, small.
private struct MiniTile: View {
    let icon: Data?
    let accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        shape.fill(Theme.tileFill)
            .overlay { shape.fill(accent.opacity(0.3)) }
            .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
            .overlay { SiteIconView(icon: icon, size: 10) { EmptyView() } }
            .frame(width: 18, height: 18)
    }
}

/// A tab in the sidebar picture: its icon's dot and its title.
private struct MiniRow: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.Welcome.pill).frame(width: 7, height: 7)
            Capsule().fill(Theme.Welcome.pill).frame(width: width, height: 7)
        }
    }
}

/// One line under the sidebar picture: a part of the sidebar, and what it's for.
private struct SidebarLine: View {
    let title: String
    let words: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 60, alignment: .leading)
            Text(words)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Open links in Firn? macOS asks the person to confirm, then the button
/// gives way to a quiet "Firn is your default browser".
private struct DefaultBrowserStep: View {
    @State private var isDefault = DefaultBrowser.isFirn
    @State private var asking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Firn's own Settings has no such choice, so the words point to the Mac's.
        StepHeading(title: "Open links in Firn?",
                    words: "Make Firn your default browser, so links from mail, chat, and other apps open here, as new tabs. You can change this anytime in System Settings.")
        ZStack(alignment: .topLeading) {
            if isDefault {
                Label("Firn is your default browser", systemImage: "checkmark")
                    .font(.system(size: 14))
                    .frame(height: 32)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Make Firn Default") {
                        asking = true
                        Task {
                            await DefaultBrowser.makeFirn()
                            isDefault = DefaultBrowser.isFirn
                            asking = false
                        }
                    }
                    .modifier(WelcomeButton(prominent: false))
                    .controlSize(.large)
                    .disabled(asking)
                    Text("Your Mac will ask you to confirm.")
                        .font(Theme.labelFont)
                        .foregroundStyle(Theme.muted)
                }
                .transition(.opacity)
            }
        }
        // Room for the button and its note, kept when it turns into the
        // line above, so the card doesn't jump.
        .frame(minHeight: 68, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isDefault)
        // Changed in System Settings meanwhile, perhaps.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isFirn
        }
    }
}

/// You're all set: three things worth knowing, each with its keys.
private struct TipsStep: View {
    var body: some View {
        StepHeading(title: "You’re all set", words: "Three things worth knowing:")
        VStack(alignment: .leading, spacing: 0) {
            tip(keys: ["⌘", "T"], spoken: "Command T", words: "Go anywhere, or do anything by name.")
            line
            tip(keys: ["Right-click"], spoken: "Right-click", words: "Tabs, links, and spaces each have a short menu.")
            line
            tip(keys: ["⌘", "S"], spoken: "Command S", words: "Hide the sidebar for more room. It peeks back at the left edge.")
        }
    }

    private var line: some View {
        Rectangle().fill(Theme.tileHairline).frame(height: 1)
    }

    private func tip(keys: [String], spoken: String, words: String) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { KeyCap(key: $0) }
            }
            .frame(width: 120, alignment: .leading)
            Text(words)
                .font(.system(size: 14))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spoken): \(words)")
    }
}

/// A key, drawn as a small frosted cap.
private struct KeyCap: View {
    let key: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Text(key)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 26)
            .background { shape.fill(reduceTransparency ? Theme.tileSolid : Theme.tileFill) }
            .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 1) }
    }
}

/// Whether Firn opens web links, and asking macOS to make it so.
@MainActor
private enum DefaultBrowser {
    /// Asked of Launch Services on this Mac; nothing goes over the network.
    static var isFirn: Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the person first. Setting http should carry https with
    /// it (the Mac has one default browser); if it didn't, https is asked
    /// for too. A "no" isn't an error to show: the step stays as it was.
    static func makeFirn() async {
        let firn = Bundle.main.bundleURL
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: firn, toOpenURLsWithScheme: "http")
            if !isFirn { try await NSWorkspace.shared.setDefaultApplication(at: firn, toOpenURLsWithScheme: "https") }
        } catch {}
    }
}

// MARK: - Pieces

/// A step's title (Fraunces) and its few words.
private struct StepHeading: View {
    let title: String
    let words: String

    var body: some View {
        Text(title)
            .font(Theme.fraunces(28, weight: 360))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
            // VoiceOver stays on Continue from step to step, so it says
            // where it is now.
            .onAppear { AccessibilityNotification.Announcement(title).post() }
        Text(words)
            .font(.system(size: 14))
            .lineSpacing(2)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 22)
    }
}

/// Where the step is: a dot for each, as a page control draws them.
private struct StepDots: View {
    let count: Int
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Theme.ink)
                    .opacity(index == current ? 0.7 : 0.22)
                    .frame(width: 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
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

/// One look to pick: its picture (always edged, so it stands off the card),
/// ringed in the space's color when chosen and faintly on hover, and its
/// name and a few words below.
private struct LookChoice: View {
    let top: Bool
    let title: String
    let note: String
    let isOn: Bool
    let colorName: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let picture = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            VStack(spacing: 0) {
                LookPicture(top: top, colorName: colorName)
                    .clipShape(picture)
                    .overlay { picture.strokeBorder(Theme.faint.opacity(0.4), lineWidth: 1) }
                    .shadow(color: Theme.shadowSoft, radius: 2, y: 1)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isOn ? Theme.spaceColor(colorName) : Theme.faint.opacity(hovering ? 0.45 : 0),
                                          lineWidth: 2.5)
                    }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 10)
                Text(note)
                    .font(Theme.hintFont)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
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

/// A small drawing of Firn's window, on a 200 × 120 grid: the traffic
/// lights, the address bar in the sidebar or in a bar along the top, a few
/// tabs, and the page, on the frame tinted by the space as Firn's own is.
private struct LookPicture: View {
    let top: Bool
    let colorName: String
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
            rect(0, 0, 200, 120, 0, Theme.frame)
            rect(0, 0, 200, 120, 0, Theme.frameTint(colorName))
            // The traffic lights never move between the two looks.
            for x in [11.0, 19, 27] {
                let dot = CGRect(x: (x - 2.6) * scale, y: (12 - 2.6) * scale, width: 5.2 * scale, height: 5.2 * scale)
                context.fill(Path(ellipseIn: dot), with: .color(Theme.faint.opacity(0.7)))
            }
            if top {
                rect(92, 6.5, 64, 11, 5.5, Theme.Welcome.pill)
                rect(54, 25, 140, 89, 6, Theme.page)
                for (y, w) in [(30.0, 38.0), (42, 30), (54, 34)] { rect(8, y, w, 7, 3.5, Theme.Welcome.pill) }
            } else {
                rect(8, 22, 40, 10, 5, Theme.Welcome.pill)
                rect(54, 6, 140, 108, 6, Theme.page)
                for (y, w) in [(40.0, 38.0), (52, 30), (64, 34)] { rect(8, y, w, 7, 3.5, Theme.Welcome.pill) }
            }
        }
        .aspectRatio(200 / 120, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The welcome's buttons: the system's glass buttons on macOS 26 (the main
/// one ink-tinted, since Firn's buttons are ink, never the system blue), and
/// a capsule of the same weight before. Size comes from `.controlSize`.
private struct WelcomeButton: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .tint(Theme.ink)
                    .foregroundStyle(Theme.page)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(CapsuleButtonStyle(prominent: prominent))
        }
    }
}

/// macOS 14 and 15: ink for the main button, a frosted capsule for the rest.
private struct CapsuleButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButton(configuration: configuration, prominent: prominent)
    }
}

private struct CapsuleButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.controlSize) private var controlSize

    private var height: CGFloat {
        switch controlSize {
        case .extraLarge: 44
        case .large: 32
        default: 26
        }
    }

    var body: some View {
        let shape = Capsule()
        configuration.label
            .font(.system(size: controlSize == .extraLarge ? 15 : 13, weight: .medium))
            .foregroundStyle(prominent ? Theme.page : Theme.ink)
            .padding(.horizontal, height * 0.55)
            .frame(height: height)
            .background {
                if prominent {
                    shape.fill(Theme.ink.opacity(configuration.isPressed ? 0.8 : hovering ? 0.9 : 1))
                } else {
                    shape.fill(.regularMaterial)
                        .overlay { shape.fill(configuration.isPressed ? Theme.press : hovering ? Theme.hover : .clear) }
                        .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
                }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
