import FirnCore
import SwiftUI

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a frosted pill in the middle, and a round check on the right in
/// a vivid version of the space's color. All on Firn's frost (`BarFrost`),
/// over the list's soft edge blur; pressed, the warm wash.
///
/// The pill is the space switcher (phase 4, step 1): a dot per space under
/// the name, as on the Mac; a tap opens the space menu (iOS's own, David,
/// 2026-11-17, as the grid's cards); a sideways swipe on
/// it changes space with the address bar's sliding pills (`BarSlide`; David,
/// 2026-11-13: the same movement as swiping between tabs).
struct OverviewBar: View {
    let space: Space
    let spaces: [Space]
    let newTab: () -> Void
    let done: () -> Void
    let select: (Space) -> Void
    /// The space menu's last rows, when the app offers them.
    let newSpace: SheetAction?
    let spaceSettings: SheetAction?

    /// Back's and the tabs button's size, so + and the check sit exactly
    /// where they were.
    private static let height = BarButton.glassSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the pill has slid toward the next space, as the address
    /// bar's: positive to the right (the space before coming in from +'s
    /// side). Only where there's a space to come in.
    @State private var progress: CGFloat = 0
    /// Let go past the middle: the pills finish the slide, then it changes.
    @State private var finishing = false
    /// The arriving space's name, fading in once its pill is whole (as the
    /// next tab's words do on the address bar), rather than cross-fading
    /// out of the old one.
    @State private var wordsIn: Double = 1
    /// True while a finger is on the pill. A swipe iOS cancels never
    /// reports its end, so the pills settle back when this goes false.
    @GestureState private var touching = false
    /// Each space's label at its own width (name, dots, and padding), so
    /// the pill hugs the name and can glide to the next one's width.
    @State private var labelWidths: [UUID: CGFloat] = [:]
    /// The room between + and the check: the widest a pill can be.
    @State private var room: CGFloat = 0
    /// A finished slide's width, held until the new space arrives: the
    /// slide resets a moment before the space changes, and in between the
    /// pill took the old space's width again, then glided back (David's
    /// recording, 2026-11-13).
    @State private var landedWidth: CGFloat?
    /// Whether the space menu is open: + and the check slip toward the
    /// name, as Back and Tabs do for the page menu, since iOS lays its menu
    /// over them (David's recording, 2026-11-17). Kept in an object only
    /// the two buttons read: as a plain state, changing it ran the bar
    /// again, which rebuilt the menu's rows and told them they'd appeared
    /// again, so the buttons stayed hidden after the menu closed.
    @State private var menu = SpaceMenuState()
    /// Bumped by a tap on the pill: the menu opens.
    @State private var opens = 0

    private var index: Int { spaces.firstIndex { $0.id == space.id } ?? 0 }

    /// The space a slide this way brings in, if any (no wrapping: the ends
    /// hold still, as the address bar's last tab does).
    private func neighbor(_ direction: CGFloat) -> Space? {
        let next = index + (direction > 0 ? -1 : 1)
        return spaces.indices.contains(next) ? spaces[next] : nil
    }

    private var slide: BarSlide? { progress == 0 ? nil : BarSlide(progress: progress) }

    /// A space's pill at rest: as wide as its name (David, 2026-11-13), never
    /// narrower than two buttons, so it stays a pill to swipe, nor wider
    /// than the room (a long name ends in "…").
    private func restWidth(_ space: Space) -> CGFloat {
        let fit = max(labelWidths[space.id] ?? room, Self.height * 2)
        return room > 0 ? min(fit, room) : fit
    }

    /// The pill's width now: mid-slide it goes from this space's width to
    /// the coming one's as the seam crosses, so the two pills share a
    /// frame that's changing size under them.
    private var pillWidth: CGFloat {
        if let landedWidth { return landedWidth }
        let held = restWidth(space)
        guard progress != 0, let next = neighbor(progress) else { return held }
        let t = min(abs(progress), 1)
        return held + (restWidth(next) - held) * t
    }

    var body: some View {
        ZStack {
            spaceMenu
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
                .padding(.horizontal, Self.height + 16)
                .background { measuring }
            HStack {
                Button(action: newTab) {
                    Image(systemName: "plus")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(Theme.ink)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(FrostPress(shape: Circle()))
                .background { BarFrost(shape: Circle()) }
                .accessibilityLabel("New Tab")
                .modifier(HidesForMenu(menu: menu, toward: .trailing))
                Spacer()
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(.white)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(FrostPress(shape: Circle()))
                // The one solid button, as Firn's buttons are ink: the
                // space's vivid color under the frost's rim and hairline.
                .background {
                    FirnFrost(shape: Circle(), fill: Theme.spaceVivid(space.color))
                }
                .accessibilityLabel("Done")
                .modifier(HidesForMenu(menu: menu, toward: .leading))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, AddressBar.sideInset)
        .padding(.top, 8)
        .padding(.bottom, 0)
        // A space changed elsewhere (the menu, the command bar) mid-slide.
        .onChange(of: space.id) {
            if !finishing { progress = 0 }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { landedWidth = nil }
        }
        .onChange(of: touching) { _, now in
            guard !now, !finishing, progress != 0 else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) { progress = 0 }
        }
    }

    /// Every space's label, unseen, at the width it wants.
    private var measuring: some View {
        ZStack {
            ForEach(spaces) { each in
                label(each)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidths[each.id] = $0 }
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    /// The name, and the dots under it once there's more than one space.
    private func label(_ space: Space) -> some View {
        VStack(spacing: 4) {
            Text(space.name)
                .font(.headline)
                // The same ink as + : the glass is already tinted, so the
                // words carry no color of their own (David, 2026-11-04).
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                // A long name tightens a little before it ends in "…", as
                // the address bar's site name does.
                .allowsTightening(true)
                .minimumScaleFactor(0.85)
            if spaces.count > 1 {
                SpaceDots(spaces: spaces, current: space.id)
            }
        }
        .padding(.horizontal, 24)
    }

    /// iOS's own menu on the pill (David, 2026-11-17: the grid's cards have
    /// iOS's menus, so this one matches): the spaces, the one on screen
    /// checked, then New Space… and Space Settings…, in the Mac's order. A
    /// tap opens it and a sideways swipe changes space, as before.
    ///
    /// UIKit, not SwiftUI's `Menu`: + and the check hide while the menu is
    /// open, and SwiftUI's `Menu` never says when it closes (going by its
    /// rows' appearing left them hidden on David's iPhone). A UIKit menu
    /// button reports both, and is opened by Firn's own tap.
    private var spaceMenu: some View {
        pill
            .background {
                SpaceMenuAnchor(menu: spaceUIMenu, opens: opens) { setMenuShown($0) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onTapGesture { if progress == 0 { opens += 1 } }
            .gesture(spaceSwipe)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { opens += 1 }
    }

    /// The menu's rows, as UIKit's.
    private var spaceUIMenu: UIMenu {
        let pick = select
        let spaceRows = spaces.map { each in
            UIAction(title: each.name, image: Self.dot(each.color), state: each.id == space.id ? .on : .off) { _ in
                MainActor.assumeIsolated { pick(each) }
            }
        }
        var more: [UIMenuElement] = []
        if let newSpace {
            more.append(UIAction(title: "New Space…", image: UIImage(systemName: "plus")) { _ in
                MainActor.assumeIsolated { newSpace() }
            })
        }
        if let spaceSettings {
            more.append(UIAction(title: "Space Settings…", image: UIImage(systemName: "gearshape")) { _ in
                MainActor.assumeIsolated { spaceSettings() }
            })
        }
        let sections = [spaceRows, more].filter { !$0.isEmpty }
            .map { UIMenu(options: .displayInline, children: $0) }
        return UIMenu(children: sections)
    }

    private func setMenuShown(_ shown: Bool) {
        guard menu.shown != shown else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) { menu.shown = shown }
    }

    /// A space's dot in the menu: its own color, which iOS's menus keep only
    /// for an image drawn in it (they tint symbols otherwise).
    private static func dot(_ color: String) -> UIImage {
        let symbol = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        return (symbol ?? UIImage()).withTintColor(UIColor(Theme.spaceColor(color)), renderingMode: .alwaysOriginal)
    }

    private var pill: some View {
        label(space)
            // The name and dots change at once, never cross-fading (the old
            // name came back for a frame as a slide landed).
            .transaction { $0.animation = nil }
            .opacity(wordsIn)
            // Sliding, the words fade and dissolve toward the seam with
            // their pill, as the address bar's do.
            .opacity(slide?.wordsOpacity ?? 1)
            .frame(maxWidth: .infinity)
            // A space picked from the menu or the command bar glides to its
            // own width; a swipe already moves it with the seam.
            .transaction { t in
                if progress == 0, t.animation == nil, !t.disablesAnimations {
                    t.animation = reduceMotion ? nil : .smooth(duration: 0.25)
                }
            } body: { $0.frame(width: pillWidth) }
            .frame(height: Self.height)
            .mask {
                if let slide {
                    GeometryReader { geo in
                        let held = slide.pills(in: geo.size).held
                        slide.wordsMask(width: held.width)
                            .clipShape(Capsule())
                            .frame(width: held.width, height: held.height)
                            .position(x: held.midX, y: held.midY)
                    }
                } else {
                    Rectangle().padding(-400)
                }
            }
            .background {
                GeometryReader { geo in
                    let pills = (slide ?? BarSlide(progress: 0)).pills(in: geo.size)
                    BarFrost(shape: Capsule())
                        .frame(width: pills.held.width, height: pills.held.height)
                        .opacity(pills.heldOpacity)
                        .position(x: pills.held.midX, y: pills.held.midY)
                    // The coming space's own pill, growing out from the
                    // other button.
                    if let coming = pills.coming, neighbor(progress) != nil {
                        BarFrost(shape: Capsule())
                            .frame(width: coming.width, height: coming.height)
                            .opacity(pills.comingOpacity)
                            .position(x: coming.midX, y: coming.midY)
                    }
                }
            }
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spaces.count > 1 ? "\(space.name), space \(index + 1) of \(spaces.count)" : space.name)
            .accessibilityHint("Shows your spaces.")
            .accessibilityAddTraits(.isHeader)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if let next = neighbor(-1) { select(next) }
                case .decrement: if let next = neighbor(1) { select(next) }
                @unknown default: break
                }
            }
    }

    /// Sideways on the pill: the seam follows the finger across it.
    private var spaceSwipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { drag in
                // Reduce Motion: nothing slides; the swipe is judged as it ends.
                guard !reduceMotion, !finishing,
                      abs(drag.translation.width) > abs(drag.translation.height) || progress != 0
                else { return }
                let width = max(restWidth(space), 1)
                let t = min(max(drag.translation.width / width, -1), 1)
                progress = neighbor(t) == nil ? 0 : t
            }
            .onEnded { drag in
                if reduceMotion { return swipeWithoutSliding(drag) }
                guard !finishing, progress != 0 else { return }
                let width = max(restWidth(space), 1)
                let flung = drag.predictedEndTranslation.width / width
                let direction: CGFloat = progress > 0 ? 1 : -1
                guard let next = neighbor(direction),
                      abs(progress) > 0.4 || (flung * direction > 0.8) else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) { progress = 0 }
                    return
                }
                finishing = true
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
                    progress = direction
                } completion: {
                    // The coming pill is whole: it becomes the space's own,
                    // in the same spot, with nothing to see as it swaps.
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) {
                        landedWidth = restWidth(next)
                        progress = 0
                        wordsIn = 0
                    }
                    finishing = false
                    select(next)
                    withAnimation(.easeOut(duration: 0.18)) { wordsIn = 1 }
                }
            }
    }

    /// Reduce Motion, as the address bar's tab swipe (which it leaves out):
    /// no pills slide. A swipe mostly sideways, past 40% of the pill or
    /// flung, changes space; the new name fades in where the old one was.
    private func swipeWithoutSliding(_ drag: DragGesture.Value) {
        let dx = drag.translation.width
        guard abs(dx) > abs(drag.translation.height) else { return }
        let width = max(pillWidth, 1)
        let direction: CGFloat = dx > 0 ? 1 : -1
        guard abs(dx) / width > 0.4 || drag.predictedEndTranslation.width / width * direction > 0.8,
              let next = neighbor(direction) else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { wordsIn = 0 }
        select(next)
        withAnimation(.easeOut(duration: 0.2)) { wordsIn = 1 }
    }
}

/// One small dot per space under its name, the space on screen's in its
/// color, the rest faint, as on the Mac (`Firn/SpaceRow.swift`). Silent:
/// VoiceOver hears "space 2 of 3" on the pill instead.
private struct SpaceDots: View {
    let spaces: [Space]
    let current: UUID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = Theme.spaceInk(spaces.first { $0.id == current }?.color ?? "glacier")
        HStack(spacing: 6) {
            ForEach(spaces) { space in
                Circle()
                    .fill(space.id == current ? ink : Theme.faint.opacity(0.6))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: current)
        .accessibilityHidden(true)
    }
}

/// + or the check while the space menu is open: shrinking toward the name
/// as it fades (only fading with Reduce Motion), and out of reach.
@MainActor @Observable final class SpaceMenuState {
    var shown = false
}

private struct HidesForMenu: ViewModifier {
    let menu: SpaceMenuState
    let toward: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let hidden = menu.shown
        return content
            .scaleEffect(hidden && !reduceMotion ? 0.01 : 1, anchor: toward)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// The space menu's UIKit button, sized to the pill behind it: opened when
/// `opens` changes, and telling Firn as its menu shows and goes.
private struct SpaceMenuAnchor: UIViewRepresentable {
    let menu: UIMenu
    let opens: Int
    let shown: (Bool) -> Void

    func makeUIView(context: Context) -> SpaceMenuButton {
        let button = SpaceMenuButton()
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.opens = opens
        return button
    }

    func updateUIView(_ button: SpaceMenuButton, context: Context) {
        button.menu = menu
        button.shown = shown
        if opens != button.opens {
            button.opens = opens
            button.performPrimaryAction()
        }
    }
}

final class SpaceMenuButton: UIButton {
    var opens = 0
    var shown: (Bool) -> Void = { _ in }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        shown(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        shown(false)
    }
}
