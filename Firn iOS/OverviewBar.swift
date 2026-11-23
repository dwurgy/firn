import FirnCore
import SwiftUI

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a frosted pill in the middle, and a round check on the right in
/// a vivid version of the space's color. All iOS's own glass, made frosty
/// (`FirnGlass`; David, 2026-11-17): + and the check are iOS glass buttons,
/// with iOS's glass press; the pill takes the glass press too.
///
/// The pill is the space switcher (phase 4, step 1): a dot per space under
/// the name, as on the Mac; a tap turns the pill itself into the space menu,
/// as the address bar's field turns into the page menu (David, 2026-11-22,
/// after Apple Sports' Home button); a sideways swipe on
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
    /// The swipe between spaces, shared with the overview's list and
    /// backdrop, which move with the pills (`SpaceSlide`).
    let slide: SpaceSlide
    /// The space a swipe is heading for (its tabs are readied to slide
    /// in), or nil once it has settled back.
    let aim: (Space?) -> Void
    /// A finger has come down on the name, or lifted: the spaces beside
    /// this one are readied before it moves.
    let ready: (Bool) -> Void

    /// Back's and the tabs button's size, so + and the check sit exactly
    /// where they were.
    private static let height = BarButton.glassSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the pill has slid toward the next space, as the address
    /// bar's: positive to the right (the space before coming in from +'s
    /// side). Only where there's a space to come in. Kept in `slide`.
    private var progress: CGFloat {
        get { slide.progress }
        nonmutating set { if slide.progress != newValue { slide.progress = newValue } }
    }
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
    /// The pill has grown into the space menu.
    @State private var menuOpen = false
    /// A finger is holding the pill (from the touch, before it's a hold).
    @State private var held = BarQuiet()
    /// The pill sinks a little while it's held, as the address bar's field
    /// does before its menu (`pressedScale`).
    @State private var pillPressed = false
    /// Bumped as a hold opens the menu: a medium tap.
    @State private var holdOpenings = 0
    /// The hold that opened the menu is still down.
    @State private var holdTracking = false
    /// Where that finger is (global), once it has slid toward the rows.
    @State private var menuPoint: CGPoint?
    /// Bumped as the sliding finger lifts, at `menuLiftPoint`.
    @State private var menuLift = 0
    @State private var menuLiftPoint: CGPoint?
    /// How far the holding finger moves before it's pointing at rows.
    private static let pointSlop: CGFloat = 10

    private var index: Int { spaces.firstIndex { $0.id == space.id } ?? 0 }

    /// The space a slide this way brings in, if any (no wrapping: the ends
    /// hold still, as the address bar's last tab does).
    private func neighbor(_ direction: CGFloat) -> Space? {
        let next = index + (direction > 0 ? -1 : 1)
        return spaces.indices.contains(next) ? spaces[next] : nil
    }

    private var pills: BarSlide? { progress == 0 ? nil : BarSlide(progress: progress) }

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
                hidesForMenu(toward: .trailing) {
                Button(action: newTab) {
                    Image(systemName: "plus")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(Theme.ink)
                        .frame(width: GlassButton.label(Self.height), height: GlassButton.label(Self.height))
                        .contentShape(.circle)
                }
                .firnGlassButton()
                .accessibilityLabel("New Tab")
                }
                Spacer()
                hidesForMenu(toward: .leading) {
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(.white)
                        .frame(width: GlassButton.label(Self.height), height: GlassButton.label(Self.height))
                        .contentShape(.circle)
                }
                // The one solid button, as Firn's buttons are ink: iOS's
                // prominent glass in the space's vivid color.
                // Mid-swipe, on its way to the coming space's.
                .firnGlassButton(tint: checkTint)
                .accessibilityLabel("Done")
                }
            }
        }
        // The menu closes on a tap anywhere else, as the page menu does
        // (no dim: it's a small menu, not a mode). Far past the bar's own
        // edges, without taking room in its layout.
        .background {
            if menuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 4000, height: 4000)
                    .onTapGesture { menuOpen = false }
                    .accessibilityHidden(true)
            }
        }
        // One glide, no bounce, the page menu's own.
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0), value: menuOpen)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, AddressBar.sideInset)
        .padding(.top, 8)
        .padding(.bottom, 0)
        // A space changed elsewhere (the menu, the command bar) mid-slide.
        .onChange(of: space.id) {
            menuOpen = false
            if !finishing { progress = 0 }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { landedWidth = nil }
        }
        .onChange(of: touching) { _, now in
            guard !now, !finishing, progress != 0 else { return }
            settleBack()
        }
    }

    /// The check's color: the space's, mixed toward the coming space's as
    /// far as a swipe has gone, as the backdrop is.
    private var checkTint: Color {
        let own = Theme.spaceVivid(space.color)
        guard let coming = slide.coming, slide.mix > 0 else { return own }
        return own.mix(with: Theme.spaceVivid(coming.color), by: slide.mix)
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

    /// The space menu: the pill's own glass grows upward into it, as the
    /// address bar's field grows into the page menu (David, 2026-11-22,
    /// after Apple Sports' Home button): the name fades in place, the rows
    /// come in once the glass has mostly grown, and + and the check slip
    /// into it. A tap opens it, and so does a hold, exactly as the address
    /// bar's field (David, 2026-11-22): the pill sinks from 0.15s, then at
    /// 0.5s a medium tap and the menu grows; the same finger can slide onto
    /// a row (a highlight follows it, a tick per row) and let go to pick
    /// it. Let go without sliding, the menu stays open for a tap. A
    /// sideways swipe changes space, as before (moving ends the hold).
    private var spaceMenu: some View {
        pill
            .onTapGesture { if progress == 0, !menuOpen { menuOpen = true } }
            .gesture(spaceSwipe)
            // Kept on while the hold that opened the menu is down, so the
            // finger can go on to a row.
            .modifier(FieldHold(including: canHoldForMenu || holdTracking ? .all : .subviews,
                                changed: holdChanged, ended: holdEnded) { now in
                held.on = now
                pressHeld()
                ready(now)
            })
            .sensoryFeedback(.impact(weight: .medium), trigger: holdOpenings)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { menuOpen = true }
            .accessibilityHidden(menuOpen)
            // After the pill's own tap shape (its capsule), so the rows,
            // which reach above it, take their taps.
            .overlay { GeometryReader { menuPanel(pill: $0.size) } }
            // Reduce Motion: no sinking.
            .scaleEffect(pillPressed && !reduceMotion ? pressedScale : 1)
            .animation(pillPressed ? .easeIn(duration: HoldThenMove.menuHold - HoldThenMove.hold)
                                   : .smooth(duration: 0.2), value: pillPressed)
    }

    /// The pill can be held for the menu: at rest, not mid-swipe.
    private var canHoldForMenu: Bool { !menuOpen && progress == 0 && !finishing }

    private func holdChanged(_ value: FieldHold.Value) {
        guard case let .second(true, drag) = value else { return }
        if !holdTracking {
            guard canHoldForMenu else { return }
            holdTracking = true
            pillPressed = false
            holdOpenings += 1
            menuOpen = true
        }
        guard menuOpen, let drag else { return }
        let moved = hypot(drag.translation.width, drag.translation.height)
        if menuPoint != nil || moved > Self.pointSlop { menuPoint = drag.location }
    }

    private func holdEnded() {
        if holdTracking, menuOpen, let point = menuPoint {
            menuLiftPoint = point
            menuLift += 1
        }
        holdTracking = false
        menuPoint = nil
    }

    /// The sinking starts a beat into the touch, as a held tab's does, so a
    /// tap never dips the pill.
    private func pressHeld() {
        guard held.on else {
            pillPressed = false
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(HoldThenMove.hold))
            if held.on, canHoldForMenu { pillPressed = true }
        }
    }

    /// The pill's size, for the shape its glass takes.
    @State private var pillSize: CGSize = .zero

    /// The name's glass: the whole pill at rest, its share of the gap
    /// mid-slide.
    private var heldGlass: GlassFrame {
        guard let slide = pills, pillSize != .zero else { return GlassFrame(frame: .zero, radius: 0) }
        let held = slide.pills(in: pillSize).held
        return GlassFrame(frame: held, radius: held.height / 2)
    }

    private var menuSize: CGSize {
        CGSize(width: SpaceMenuPanel.width,
               height: SpaceMenuPanel.height(spaces: spaces.count,
                                             more: (newSpace == nil ? 0 : 1) + (spaceSettings == nil ? 0 : 1)))
    }

    /// The pill's one glass, grown into the menu while it's open.
    private var pillGlass: GrowingGlass {
        GrowingGlass(base: heldGlass, grown: menuSize, radius: SpaceMenuPanel.cornerRadius, open: menuOpen ? 1 : 0)
    }

    @ViewBuilder private func menuPanel(pill: CGSize) -> some View {
        if menuOpen {
            let size = menuSize
            SpaceMenuPanel(spaces: spaces, current: space.id, select: { each in
                menuOpen = false
                if each.id != space.id { select(each) }
            }, newSpace: newSpace, spaceSettings: spaceSettings, pointer: menuPoint, lift: menuLift,
               liftPoint: menuLiftPoint) { menuOpen = false }
                .frame(width: size.width, height: size.height)
                .position(x: pill.width / 2, y: pill.height - size.height / 2)
                // The words come in once the glass has mostly grown, and go
                // first when it closes, as the page menu's.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.16).delay(reduceMotion ? 0 : 0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.08))))
        }
    }

    /// Slips into the pill while the menu is open and comes back out after,
    /// keeping its place, as Back and the tabs button do for the page menu.
    private func hidesForMenu(toward anchor: UnitPoint, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .scaleEffect(menuOpen && !reduceMotion ? 0.01 : 1, anchor: anchor)
            .opacity(menuOpen ? 0 : 1)
            .allowsHitTesting(!menuOpen)
            .accessibilityHidden(menuOpen)
    }

    /// How near the two sliding pills have to come before iOS melts them
    /// together: just past their 6pt seam.
    private static let meltDistance: CGFloat = 10

    private var pill: some View {
        label(space)
            // The name and dots change at once, never cross-fading (the old
            // name came back for a frame as a slide landed).
            .transaction { $0.animation = nil }
            .opacity(wordsIn)
            // Sliding, the words fade and dissolve toward the seam with
            // their pill, as the address bar's do.
            .opacity(pills?.wordsOpacity ?? 1)
            // The name goes at once as the glass starts to grow, and comes
            // back only as the glass is nearly the pill again (sooner, it
            // showed inside the shrinking menu, over its rows).
            .opacity(menuOpen ? 0 : 1)
            .animation(menuOpen || reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.12).delay(0.18),
                       value: menuOpen)
            .frame(maxWidth: .infinity)
            // A space picked from the menu or the command bar glides to its
            // own width; a swipe already moves it with the seam.
            .transaction { t in
                if progress == 0, t.animation == nil, !t.disablesAnimations {
                    t.animation = reduceMotion ? nil : .smooth(duration: 0.25)
                }
            } body: { $0.frame(width: pillWidth) }
            .frame(height: Self.height)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { pillSize = $0 }
            .mask {
                if let slide = pills {
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
            // The name's one glass, iOS's own, on the pill itself (David,
            // 2026-11-18: one native glass per button), so a finger on the
            // name reaches it and it takes iOS's press. Sliding, this same
            // glass narrows to its share of the gap (`GlassFrame`), and
            // open, it is the menu (`GrowingGlass`).
            .firnGlassSurface(pillGlass, interactive: pills == nil && !menuOpen)
            .background {
                GeometryReader { geo in
                    let pills = (pills ?? BarSlide(progress: 0)).pills(in: geo.size)
                    // The coming space's own pill, growing out from the
                    // other button.
                    if let coming = pills.coming, let next = neighbor(progress) {
                        FirnGlass(shape: Capsule())
                            .frame(width: coming.width, height: coming.height)
                            .opacity(pills.comingOpacity)
                            .position(x: coming.midX, y: coming.midY)
                    }
                }
            }
            // The name's glass and the coming pill's in one container, so
            // they melt into each other across their seam as they slide.
            .glassContainer(spacing: Self.meltDistance)
            // The coming space's name rides its pill in, over the glass,
            // once the pill is most of the way, as the leaving name went:
            // by the landing it's in the spot the space's own name takes.
            .overlay {
                GeometryReader { geo in
                    if let slide = pills, let coming = slide.pills(in: geo.size).coming, let next = neighbor(progress) {
                        label(next)
                            .fixedSize()
                            .opacity(BarSlide(progress: 1 - min(abs(progress), 1)).wordsOpacity)
                            .frame(width: coming.width, height: coming.height)
                            .clipShape(Capsule())
                            .position(x: coming.midX, y: coming.midY)
                    }
                }
                .allowsHitTesting(false)
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

    /// How far a finger travels for a whole swipe: the bar's own width,
    /// about the screen's, so the spaces' tabs keep up with the finger as
    /// two pages do (the pills' seam crosses the name at the same share).
    /// Over the pill's own width, as before the tabs slid too, they flew
    /// four times as fast as the finger.
    private var travel: CGFloat { max(room + 2 * (Self.height + 16), restWidth(space), 1) }

    /// Sideways on the pill: the tabs follow the finger, and the seam
    /// crosses the name with them.
    private var spaceSwipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { drag in
                // Reduce Motion: nothing slides; the swipe is judged as it ends.
                guard !reduceMotion, !finishing, !menuOpen,
                      abs(drag.translation.width) > abs(drag.translation.height) || progress != 0
                else { return }
                let width = travel
                let t = min(max(drag.translation.width / width, -1), 1)
                let next = neighbor(t)
                if let next { aim(next) }
                progress = next == nil ? 0 : t
            }
            .onEnded { drag in
                guard !menuOpen else { return }
                if reduceMotion { return swipeWithoutSliding(drag) }
                guard !finishing, progress != 0 else { return }
                let width = travel
                let flung = drag.predictedEndTranslation.width / width
                let direction: CGFloat = progress > 0 ? 1 : -1
                guard let next = neighbor(direction),
                      abs(progress) > 0.3 || (flung * direction > 0.6) else {
                    settleBack()
                    return
                }
                finishing = true
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3)) {
                    progress = direction
                } completion: {
                    // The coming pill is whole: it becomes the space's own,
                    // in the same spot, with nothing to see as it swaps.
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) {
                        landedWidth = restWidth(next)
                        // The coming space's tabs stand where they landed
                        // while the real list takes their place.
                        slide.settling = slide.comingPeek?.id == next.id
                        progress = 0
                    }
                    finishing = false
                    // The coming name rode its pill in: nothing to fade.
                    select(next)
                }
            }
    }

    /// Let go short of the next space: everything glides back, and the
    /// coming space's tabs are dropped once they're out of sight.
    private func settleBack() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) { progress = 0 } completion: {
            if progress == 0, !finishing, !touching { aim(nil) }
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

/// The space menu's rows, inside the pill's grown glass: every space (its
/// dot, its name, and a check on the one on screen), then New Space… and
/// Settings…, in the Mac's order. The page menu's rows, sizes, and press.
private struct SpaceMenuPanel: View {
    let spaces: [Space]
    let current: UUID
    let select: (Space) -> Void
    let newSpace: SheetAction?
    let spaceSettings: SheetAction?
    /// The finger that held the pill open, once it has slid (global).
    let pointer: CGPoint?
    /// Bumped as that finger lifts, at `liftPoint`: the row there runs.
    let lift: Int
    let liftPoint: CGPoint?
    let close: () -> Void
    /// VoiceOver starts on the space on screen.
    @AccessibilityFocusState private var focused: UUID?
    /// Each row's frame (global), for the sliding finger.
    @State private var frames: [String: CGRect] = [:]
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let newKey = "new"
    private static let settingsKey = "settings"

    /// The row under a point (global), if any.
    private func key(at point: CGPoint?) -> String? {
        guard let point else { return nil }
        return frames.first { $0.value.contains(point) }?.key
    }

    private func run(_ key: String) {
        if key == Self.newKey, let newSpace {
            close()
            newSpace()
        } else if key == Self.settingsKey, let spaceSettings {
            close()
            spaceSettings()
        } else if let space = spaces.first(where: { $0.id.uuidString == key }) {
            select(space)
        }
    }

    static let width: CGFloat = 250
    static let cornerRadius: CGFloat = 22
    private static let rowHeight: CGFloat = 48
    private static let inset: CGFloat = 6
    /// The hairline between the spaces and the two rows under them.
    private static let ruleHeight: CGFloat = 9

    static func height(spaces: Int, more: Int) -> CGFloat {
        rowHeight * CGFloat(spaces + more) + (more > 0 ? ruleHeight : 0) + inset * 2
    }

    var body: some View {
        let lit = key(at: pointer)
        VStack(spacing: 0) {
            ForEach(spaces) { space in
                row(space.id.uuidString, space.name, checked: space.id == current, lit: lit) {
                    Circle()
                        .fill(Theme.spaceColor(space.color))
                        .frame(width: 10, height: 10)
                }
                    .accessibilityFocused($focused, equals: space.id)
                    .accessibilityAddTraits(space.id == current ? .isSelected : [])
            }
            if newSpace != nil || spaceSettings != nil {
                Rectangle()
                    .fill(Theme.ink.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .frame(height: Self.ruleHeight)
                    .accessibilityHidden(true)
            }
            if newSpace != nil {
                row(Self.newKey, "New Space…", checked: false, lit: lit) {
                    Image(systemName: "plus").font(BarButton.symbolFont)
                }
            }
            if spaceSettings != nil {
                row(Self.settingsKey, "Settings…", checked: false, lit: lit) {
                    Image(systemName: "gearshape").font(BarButton.symbolFont)
                }
            }
        }
        // The highlight glides from row to row: quick, no bounce; none
        // with Reduce Motion.
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: lit)
        // A tick each time the sliding finger reaches another row.
        .sensoryFeedback(trigger: lit) { _, now in now == nil ? nil : .selection }
        // Let go on a row: it runs, as a tap. Elsewhere, the menu stays.
        .onChange(of: lift) {
            if let key = key(at: liftPoint) { run(key) }
        }
        .padding(Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { focused = current }
    }

    /// A row; lit while the sliding finger is on it.
    private func row(_ key: String, _ title: String, checked: Bool, lit: String?,
                     @ViewBuilder mark: () -> some View) -> some View {
        Button { run(key) } label: {
            HStack(spacing: 14) {
                mark()
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(SpaceRowPress())
        .background {
            if lit == key {
                RoundedRectangle(cornerRadius: Self.cornerRadius - 6, style: .continuous)
                    .fill(Theme.press)
                    .matchedGeometryEffect(id: "lit", in: highlight)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[key] = $0 }
    }
}

/// A row pressed: Firn's warm wash, in the row's rounded shape, as the page
/// menu's rows.
private struct SpaceRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.press : .clear,
                        in: .rect(cornerRadius: SpaceMenuPanel.cornerRadius - 6, style: .continuous))
    }
}
