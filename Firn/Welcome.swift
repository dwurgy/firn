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

/// The welcome's finish: the sidebar and the page wait just below the
/// window's bottom edge, at 86% of their size, then rise into place.
/// Transforms only, from the top's middle; at rest they're plain identities.
struct WelcomeLift: ViewModifier {
    let finish: WindowModel.WelcomeFinish?
    @State private var height: CGFloat = 0

    /// Past the edge by this much, so the rising window's shadow is too.
    private static let below: CGFloat = 30

    func body(content: Content) -> some View {
        let low = finish == .begun
        content
            .scaleEffect(low ? 0.86 : 1, anchor: .top)
            .offset(y: low ? height + Self.below : 0)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }
}

/// Behind the real window while the welcome is open: Frost with the logo
/// out of focus, coming into focus at the finish beside "Welcome in."
/// (docs/design/frost, welcome-mac/welcome-in), and the warm shadow the
/// window casts as it rises over them. All of it stays under the window
/// until the finish lowers it.
struct WelcomeBackdrop: View {
    let window: WindowModel

    var body: some View {
        if window.showsWelcome {
            let finishing = window.welcomeFinish != nil
            GeometryReader { proxy in
                let wide = proxy.size.width >= 760
                ZStack(alignment: .bottomLeading) {
                    // The logo and the words go at once when the window is in
                    // place over them: they'd show through its glass.
                    let covered = window.welcomeFinish == .fading
                    FrostScene(focus: covered ? .sky : finishing ? .sharp : .blurred, footer: window.welcomeFooter)
                        .animation(finishing && !covered ? .easeInOut(duration: 0.85).delay(0.25) : nil, value: finishing)
                        .animation(nil, value: covered)
                    FrostTitle("Welcome", "in.", size: 38)
                        .padding(.leading, wide ? 72 : 32)
                        .padding(.bottom, wide ? 64 : 32)
                        .opacity(finishing ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: finishing)
                        .opacity(covered ? 0 : 1)
                        .animation(nil, value: covered)
                    // The rising window's frame: Firn's frame color in the
                    // space's tint, with a panel's corners; it gives way to
                    // the real glass once it's in place.
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

/// The welcome, the first time Firn opens (and from Help): Frost
/// (docs/design/frost) and a few short steps. Hello is the logo out of
/// focus; each step is the plain sky, a question on the left, its choices
/// on the right, and one row along the bottom. The plan is in
/// docs/HISTORY.md ("Plan: Frost"). Every choice applies right away. Esc or
/// "Skip setup" leaves it at any point.
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
            // At the finish it gives way to the same sky behind the window,
            // with the logo (`WelcomeBackdrop`).
            FrostScene(focus: step == .hello ? .blurred : .sky, footer: window.welcomeFooter)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: step == .hello)
                .modifier(FinishFade(finishing: finish != nil))
            // The scene's empty sky moves the window, like a title bar.
            WindowDragArea()
            Group {
                if step == .hello {
                    HelloScreen(next: next)
                        .modifier(StepEntrance(duration: 0.3))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { window.welcomeFooter = $0 }
                    // As drawn, Hello has no Skip button: only Esc.
                    Button("Skip setup", action: finishWelcome)
                        .keyboardShortcut(.cancelAction)
                        .focusable(false)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    GeometryReader { proxy in
                        stepScreen(wide: proxy.size.width >= 960, width: proxy.size.width)
                    }
                }
            }
            .modifier(FinishFade(finishing: finish != nil))
            // Faded, it isn't there for VoiceOver either.
            .accessibilityHidden(finish != nil)
        }
        .foregroundStyle(Theme.Frost.ink)
        .ignoresSafeArea()
        .onAppear {
            name = space.name
            stageShot()
        }
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

    /// A step: the small mark, the question, its choices, and the row along
    /// the bottom. Two columns, or one in a narrow window; scrolling only
    /// when the window is too short.
    private func stepScreen(wide: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cream on blue hour, Glacier on the morning sky.
            Image("FirnMark")
                .resizable()
                .foregroundStyle(Theme.Frost.mark)
                .frame(width: 34, height: 34)
                .padding(.leading, -4)
                .accessibilityHidden(true)
            let question = question(size: wide ? 42 : 32)
            let choices = VStack(alignment: .leading, spacing: 0) { choices }
                .frame(maxWidth: 480, alignment: .leading)
            let columns = Group {
                if wide {
                    HStack(spacing: 72) {
                        question.frame(width: min(max(width - 144 - 72 - 440, 260), 380), alignment: .leading)
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
            ViewThatFits(in: .vertical) {
                columns
                ScrollView(.vertical) {
                    // Room for focus rings and the glass's edge.
                    columns.padding(8).padding(.bottom, 20)
                }
                // No soft edge: a mask breaks the glass inside it.
                .padding(-8)
            }
            // Each step is new, so it glides in; the last one simply goes.
            .id(step)
            .modifier(StepEntrance(duration: 0.22))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wide ? .leading : .topLeading)
            .padding(.vertical, 20)
            bottomRow
        }
        .padding(.horizontal, wide ? 72 : 32)
        .padding(.top, wide ? 56 : 36)
        .padding(.bottom, wide ? 56 : 28)
    }

    private func question(size: CGFloat) -> some View {
        let heading = heading
        return VStack(alignment: .leading, spacing: 12) {
            FrostTitle(heading.plain, heading.strong, size: size)
                .lineSpacing(2)
                // VoiceOver stays on Continue from step to step, so it says
                // where it is now.
                .id(heading.plain)
                .onAppear { AccessibilityNotification.Announcement("\(heading.plain) \(heading.strong)").post() }
            Text(heading.words)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(Theme.Frost.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The step's question, its second half in SemiBold, and its few words.
    private var heading: (plain: String, strong: String, words: String) {
        switch step {
        case .hello: ("", "", "")
        case .address: ("Where should the", "address bar go?", "You can change this anytime in Settings.")
        case .search: ("Which search", "do you like?",
                       "What you type in the address bar searches here. More choices are in Settings.")
        case .arc where importedArc:
            ("Your Arc spaces", "are here",
             "\(arcPlan?.spaces.count == 1 ? "It’s" : "They’re") at the bottom of the sidebar. Each tab loads when you first click it.")
        case .arc: ("Coming", "from Arc?",
                    "Firn can bring over your spaces: favorites become Basecamp, and pinned tabs become groups.")
        case .space: ("Name your", "first space.",
                      "A space is its own browser, with its own tabs, sign\u{2011}ins, and history. You can add more later.")
        case .basecamp: ("Start your", "Basecamp",
                         "Pick a few sites you use every day in this space, or none. You can add more anytime: right-click a tab and choose Add to Basecamp.")
        // Firn's own Settings has no such choice, so the words point to the Mac's.
        case .defaultBrowser: ("Open links", "in Firn?",
                               "Make Firn your default browser, so links from mail, chat, and other apps open here, as new tabs. You can change this anytime in System Settings.")
        }
    }

    @ViewBuilder private var choices: some View {
        switch step {
        case .hello: EmptyView()
        case .address: AddressStep(colorName: colorName)
        case .search: SearchStep(accent: Theme.spaceColor(colorName))
        case .arc: if let arcPlan { ArcStep(plan: arcPlan, store: store, imported: importedArc) }
        case .space: SpaceStep(store: store, name: $name)
        case .basecamp: BasecampStep(store: store, icons: siteIcons, colorName: colorName)
        case .defaultBrowser: DefaultBrowserStep()
        }
    }

    /// The dots and "Skip setup", Back, and the one pill.
    private var bottomRow: some View {
        let dots = StepDots(count: steps.count - 1, current: index - 1)
        let skip = Button("Skip setup", action: finishWelcome)
            .buttonStyle(FrostPlainStyle(quiet: true))
            .keyboardShortcut(.cancelAction)
        let back = Button("Back", action: back).buttonStyle(FrostPlainStyle())
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                HStack(spacing: 28) {
                    dots
                    skip
                }
                Spacer(minLength: 0)
                back
                forward
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 24) {
                    dots
                    Spacer(minLength: 0)
                    skip
                }
                HStack(spacing: 20) {
                    back
                    Spacer(minLength: 0)
                    forward
                }
            }
        }
    }

    @ViewBuilder private var forward: some View {
        if step == .arc && !importedArc {
            Button("Start Fresh", action: next)
                .buttonStyle(FrostPlainStyle())
            Button("Bring Them Over", action: bringArcOver)
                .buttonStyle(FrostPillStyle())
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
        } else {
            Button(isLast ? "Start Browsing" : "Continue", action: next)
                .buttonStyle(FrostPillStyle())
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
        }
    }

    /// A demo screenshot of one step (`--shot=welcome --step=search`).
    private func stageShot() {
        guard let named = DemoShot.welcomeStep else { return }
        arcPlan = DemoShot.arcPlan
        offersArc = arcPlan != nil
        offersDefault = true
        importedArc = named == "arrived"
        switch named {
        case "finish":
            step = .basecamp
            Task {
                while !FileManager.default.fileExists(atPath: DemoMode.shotReadyFile.path(percentEncoded: false)) {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                try? await Task.sleep(for: .seconds(1))
                finishWelcome()
            }
        case "search": step = .search
        case "arc", "arrived": step = .arc
        case "space": step = .space
        case "basecamp": step = .basecamp
        case "default": step = .defaultBrowser
        default: break
        }
    }

    private func saveName() {
        store.updateSpace(space, name: name, color: space.color)
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
    /// steps.
    private func bringArcOver() {
        guard let arcPlan, !importedArc else { return }
        store.importFromArc(arcPlan) { WindowModel.freeColor(among: $0) }
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

/// At the finish, the sky in front and the step on it fade first (250ms).
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
    case hello, address, search, arc, space, basecamp, defaultBrowser

    /// The address step waits for the "At the top" look (David, 2026-10-23):
    /// until then the choice would change nothing. Its view is kept, ready.
    static var allCases: [WelcomeStep] { [.hello, .search, .arc, .space, .basecamp, .defaultBrowser] }
}

// MARK: - Steps

/// Hello: the words and the one pill along the bottom, under the blurred
/// logo (docs/design/frost, welcome-mac/hello). In a narrow
/// window the pill goes below the words.
private struct HelloScreen: View {
    let next: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 48) {
                words.frame(width: 520, alignment: .leading)
                Spacer(minLength: 0)
                pill
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 64)
            VStack(alignment: .leading, spacing: 24) {
                words
                pill
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 10) {
            FrostTitle("A calm place", "for the web.", size: 38)
            Text("Ads and trackers are blocked, and Firn never tracks you. Setup takes a minute, and you can change any of it later.")
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(Theme.Frost.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pill: some View {
        Button("Let’s Begin", action: next)
            .buttonStyle(FrostPillStyle())
            .focusEffectDisabled()
            .keyboardShortcut(.defaultAction)
    }
}

/// Where the address bar goes: two little pictures of the window, picked
/// like System Settings' Appearance.
private struct AddressStep: View {
    let colorName: String
    @AppStorage(Preference.addressBar) private var place = AddressBarPlace.sidebar

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            LookChoice(top: false, title: "In the sidebar", note: "Everything in one calm place, with more room for the page.",
                       isOn: place == .sidebar, colorName: colorName) { place = .sidebar }
            LookChoice(top: true, title: "At the top", note: "A bar across the top of the window.",
                       isOn: place == .top, colorName: colorName) { place = .top }
        }
    }
}

/// Coming from Arc: Arc's spaces as they'll look in Firn (each with the
/// color and icon it will get), what each brings, and whose sign-ins it
/// shares. Once they've come over, the same list says they're here.
private struct ArcStep: View {
    let plan: ArcImportPlan
    let store: BrowserStore
    let imported: Bool

    /// More than this, and the rest are "and 4 more spaces", so the step stays calm.
    private static let listedSpaces = 4

    /// Picked as the import picks them: the next free color, in order.
    private var colors: [String] {
        var existing = imported || store.hasOnlyUntouchedSpace ? [] : store.spaces
        return plan.spaces.map { space in
            let color = WindowModel.freeColor(among: existing)
            existing.append(Space(name: space.name, color: color, order: existing.count, dataStoreID: UUID()))
            return color
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(zip(plan.spaces, colors).prefix(Self.listedSpaces).enumerated()), id: \.offset) { _, row in
                let (space, color) = row
                HStack(spacing: 10) {
                    // The space's color, as a dot like the bottom row's.
                    Circle()
                        .fill(Theme.spaceColor(color))
                        .frame(width: 10, height: 10)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(space.name)
                            .font(.system(size: 16, weight: .semibold))
                        Text(ArcImportSheet.contents(of: space))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Frost.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            let more = plan.spaces.count - Self.listedSpaces
            if more > 0 {
                Text(more == 1 ? "and 1 more space" : "and \(more) more spaces")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Frost.muted)
                    .padding(.leading, 26)
            }
        }
        if !imported {
            Text("\(ArcImportSheet.signInsLine(plan)) Unpinned tabs and history stay in Arc.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Frost.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
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
        let sites = LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 14), count: 4), alignment: .leading, spacing: 14) {
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
        // A narrow window has room for the sites alone.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                sites
                SidebarPicture(tiles: store.basecampTabs, colorName: colorName)
            }
            sites
        }
        VStack(alignment: .leading, spacing: 8) {
            SidebarLine(title: "Groups", words: "Keep tabs together: drag one tab onto another.")
            SidebarLine(title: "Tabs", words: "Everything else. Tabs you’re done with tidy themselves away.")
        }
        .padding(.top, 22)
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
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 60, alignment: .leading)
            Text(words)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Frost.muted)
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
        ZStack(alignment: .topLeading) {
            if isDefault {
                Label("Firn is your default browser", systemImage: "checkmark")
                    .font(.system(size: 16))
                    .frame(height: 44)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Button("Make Firn Default") {
                        asking = true
                        Task {
                            await DefaultBrowser.makeFirn()
                            isDefault = DefaultBrowser.isFirn
                            asking = false
                        }
                    }
                    .buttonStyle(FrostPlainStyle(underlined: true))
                    .disabled(asking)
                    Text("Your Mac will ask you to confirm.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Frost.muted)
                }
                .transition(.opacity)
            }
        }
        // Room for the button and its note, kept when it turns into the
        // line above, so nothing jumps.
        .frame(minHeight: 68, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isDefault)
        // Changed in System Settings meanwhile, perhaps.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isFirn
        }
    }
}

/// Whether Firn opens web links, and asking macOS to make it so.
@MainActor
private enum DefaultBrowser {
    /// Asked of Launch Services on this Mac; nothing goes over the network.
    static var isFirn: Bool {
        if DemoShot.welcomeStep != nil { return false }
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
