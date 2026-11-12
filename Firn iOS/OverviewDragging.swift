import FirnCore
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// A tab or group being dragged: which, where its tile was when it
/// lifted, and where on the tile the finger holds it.
struct Drag {
    let id: UUID
    let start: CGRect
    /// Where down the tile the finger holds it.
    var grab: CGFloat
    /// A whole group, held by its name line.
    let group: Bool
    /// The group a held tab was in when it lifted.
    let from: UUID?
    /// False once let go, as the tile settles into its place.
    var lifted = true
    /// Where across the tile the finger holds it (Basecamp tiles move both ways).
    var grabX: CGFloat = 0
    /// A Basecamp tile: among the tiles, or carried down into the tabs (`tabs`).
    var tile = false
    /// A tab carried up over Basecamp: tile-shaped, `tileSize`, centered
    /// under the finger, with a spot open for it among the tiles.
    var basecamp = false
    var tileSize: CGSize = .zero
    /// Until then, the held tile glides after the finger rather than
    /// sitting right under it: it's changing shape (row to tile or back).
    var reshaping = Date.distantPast
    /// A tab that has moved (not only lifted for its menu): an empty
    /// Basecamp shows a blank tile to carry it onto.
    var moved = false
    /// The row's (or card's) own size while it changes shape: it's drawn
    /// at this size and shrunk or grown as one picture, so nothing inside
    /// it is laid out again mid-glide (David, 2026-11-12). Nil otherwise.
    var rowSize: CGSize?
    /// A Basecamp tile carried down below the grid: a card (`rowHeight`
    /// tall, the size it will be in the list), with a place open for it
    /// among the tabs.
    var tabs = false
    var rowHeight: CGFloat = 0

    /// How tall the held tab is now: a carried tile's card, or its own.
    var height: CGFloat { tile && tabs ? rowHeight : start.height }
}

/// A group forming while a held tab rests on a loose one: the loose tab,
/// the group as the store would make it (not saved), and whether the
/// held tab's gap is above the other.
struct Forming {
    let other: UUID
    let group: TabGroup
    var above: Bool
}

/// A loose tab's tile, with room for the group forming around it: at rest,
/// zero-height spacers and nothing else, so the tile keeps its identity
/// and glides to its place in the card. Forming, it's laid out exactly as
/// the group will be (`groupCard`): the name line, the held tab's gap and
/// this tab 8pt apart, 8pt in from the card's sides and bottom, so making
/// the group on letting go changes nothing on screen. The card fades in
/// as it grows out from the tile (the frost forming); the name line is
/// faint, as on the Mac, until the group is made and names itself.
struct FormingCard: ViewModifier {
    let forming: Forming?
    /// The held tab's height, for its gap.
    let gap: CGFloat
    let space: String
    @State private var line = GroupCard.headerHeight
    /// The last group shown, kept so the name line fades out where it is
    /// as the card thaws.
    @State private var shown: TabGroup?

    func body(content: Content) -> some View {
        let on = forming != nil
        let above = forming?.above ?? true
        VStack(spacing: 0) {
            Color.clear
                .frame(height: on ? line : 0)
                .overlay(alignment: .bottom) {
                    // Faded, never removed: a removed view keeps its old
                    // size while it fades, so the thawing card and its name
                    // line covered the card below (David's recording,
                    // 2026-11-08).
                    if let group = forming?.group ?? shown {
                        GroupLine(group: group, height: GroupCard.headerHeight, naming: false, toggle: {})
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { line = $0 }
                            .opacity(on ? 0.5 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            Color.clear.frame(height: on && above ? gap + GroupCard.inset : 0)
            content
            Color.clear.frame(height: on && !above ? gap + GroupCard.inset : 0)
        }
        .padding(.horizontal, on ? GroupCard.inset : 0)
        .padding(.bottom, on ? GroupCard.inset : 0)
        // Shrinks with the tile as it fades (see the name line).
        .background {
            if on || shown != nil { GroupCard(space: space).opacity(on ? 1 : 0) }
        }
        .onChange(of: forming?.group.id) { _, id in
            if id != nil { shown = forming?.group }
        }
    }
}

/// What a hold in the list lifts.
enum Liftable {
    case tab(FirnCore.Tab)
    case group(TabGroup)
    case tile(FirnCore.Tab)

    @MainActor var id: UUID {
        switch self {
        case let .tab(tab), let .tile(tab): tab.id
        case let .group(group): group.id
        }
    }
}

/// Where the held tile is (global points): observed only by the tile.
@MainActor @Observable final class DragFinger {
    /// The held tab, whose place in the list stays empty.
    var held: UUID?
    /// The tile's top.
    var top: CGFloat = 0
    /// The tile's left edge and width: a tab narrows inside a group.
    var left: CGFloat = 0
    var width: CGFloat = 0
    /// The finger itself.
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// Resting on another tab, waiting for their group to form: the held
    /// tile turns solid so the one under it doesn't show through.
    var solid = false
    /// A tab held still, sinking a little until its menu opens.
    var pressed: UUID?
    /// The size the lifted tile rises from: a pressed tab's, sunk.
    var liftFrom: CGFloat = 1
}

/// How far a held tab sinks before its menu opens (as iOS's items do).
let pressedScale: CGFloat = 0.97

/// A tab's place in the list, empty while the tab is held (or its page
/// glides). It reads which tab is held itself: the list doesn't redraw a
/// tab's tile when only the held tab changes, so on each tab's first drag
/// its tile stayed in place, a copy beside the lifted one, until the list
/// first moved (David's recordings, 2026-11-05). At once, never faded.
struct EmptyWhileHeld: ViewModifier {
    let finger: DragFinger
    let id: UUID
    let gliding: Bool

    func body(content: Content) -> some View {
        let empty = gliding || finger.held == id
        let pressed = finger.pressed == id
        content
            // Held still, it sinks a little over the rest of the hold, so
            // the finger feels the menu coming; let go early, it springs back.
            .scaleEffect(pressed ? pressedScale : 1)
            .animation(pressed ? .easeIn(duration: HoldThenMove.menuHold - HoldThenMove.hold)
                               : .smooth(duration: 0.2), value: pressed)
            .opacity(empty ? 0 : 1)
            .animation(nil, value: empty)
    }
}

/// The held tab, over the list: a little larger with a soft warm shadow
/// while held, settling back to its own size as it lands.
struct LiftedTile<Content: View>: View {
    let finger: DragFinger
    let height: CGFloat
    let lifted: Bool
    /// A slim row or a group: see-through at rest (a slim row is 10% in
    /// dark), so while it's held it sits on one steady base, menu, drag,
    /// and forming group alike, never switching with what's under it
    /// (David, 2026-11-09: a dragged group read too transparent).
    var steady = false
    /// The solid base's corners: a group card's are rounder than a tab's.
    var cornerRadius: CGFloat = OverviewRow.cornerRadius
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        let raised = lifted && up && !reduceMotion
        let based = steady ? lifted || finger.solid : finger.solid
        GeometryReader { box in
            let origin = box.frame(in: .global).origin
            content
                .modifier(LaneWidth(width: finger.width, height: height))
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.heldRowBase)
                        .opacity(based ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: based)
                }
                // From a held tab's sunk size (`liftFrom`), so the press
                // and the lift are one motion.
                .scaleEffect(raised ? 1.03 : (up ? 1 : finger.liftFrom))
                .shadow(color: Theme.shadowPeek.opacity(raised ? 1 : 0), radius: 18, y: 8)
                .modifier(LaneLeft(x: finger.left - origin.x))
                .offset(y: finger.top - origin.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.smooth(duration: 0.2)) { up = true } }
    }
}

/// The held tile's size, worked out afresh on every frame of a glide. A
/// plain `.frame` lays the row out at its new width at once and only
/// eases the picture, and the row's left edge jumped as it moved into or
/// out of a group while its right edge glided (David's recordings,
/// 2026-11-09). With these two, both edges move together, frame by frame.
/// The height glides too, as a tab carried up becomes a Basecamp tile.
struct LaneWidth: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { (width, height) = (newValue.first, newValue.second) }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height)
    }
}

/// The held tile's left edge (from its overlay's origin), frame by frame.
struct LaneLeft: ViewModifier, Animatable {
    var x: CGFloat

    nonisolated var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: x)
    }
}

/// Hold, then move: lifts a tab to drag it. Holding still instead opens
/// Firn's menu (at about 0.5s), and a quick move with no hold is a scroll
/// or a swipe, so the drag starts only when the finger moves after a short
/// hold, before the menu. As in Safari, where hold-and-move drags and
/// holding still opens the menu. UIKit, because SwiftUI has no gesture
/// that waits for a hold and then needs movement.
struct HoldToDrag: UIGestureRecognizerRepresentable {
    let enabled: Bool
    /// Whether there's something to lift where the finger came down
    /// (global); if not, the touch is left to scrolling.
    let canBegin: (CGPoint) -> Bool
    let began: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    /// True when iOS cancelled the touch rather than the finger lifting.
    let ended: (Bool) -> Void
    /// Whether holding still at a point (global) opens Firn's menu there,
    /// and opening it; then the finger lifting (false) or iOS cancelling
    /// the touch (true). The menu stays open after the finger lifts.
    let wantsMenu: (CGPoint) -> Bool
    let pressing: (CGPoint?) -> Void
    let menu: (CGPoint) -> Void
    let menuEnded: (Bool) -> Void
    /// The held finger moved from where the menu opened (the second
    /// point): from here its moves and its lift come as a drag's
    /// (`moved`, then `ended`), whether it drags or points at the menu.
    let leaveMenu: (CGPoint, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> HoldThenMove {
        let hold = HoldThenMove()
        hold.isEnabled = enabled
        hold.delegate = context.coordinator
        hold.wantsMenu = wantsMenu
        hold.pressing = pressing
        context.coordinator.canBegin = canBegin
        return hold
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (CGPoint) -> Bool = { _ in false }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let hold = gesture as? HoldThenMove else { return false }
            return canBegin(hold.startPoint)
        }

        /// The row's own tap would otherwise outrank it, so it runs
        /// alongside taps (a tap ends ignored during a drag); never
        /// alongside pans.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        /// The list's scroll and a row's sideways swipe wait until it's
        /// clear this isn't a drag. That's at once for a quick move, so
        /// scrolling and swiping feel the same as before.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
    }

    func updateUIGestureRecognizer(_ hold: HoldThenMove, context: Context) {
        hold.isEnabled = enabled
        hold.wantsMenu = wantsMenu
        hold.pressing = pressing
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ hold: HoldThenMove, context: Context) {
        let point = context.converter.location(in: .global)
        switch hold.state {
        case .began where hold.heldStill:
            menu(CGPoint(x: point.x - hold.moved.x, y: point.y - hold.moved.y))
        case .began:
            // Lifted from where the finger first came down, then follows it.
            began(CGPoint(x: point.x - hold.moved.x, y: point.y - hold.moved.y))
            moved(point)
        case .changed where hold.leftMenu:
            // Moved off an open menu: it thaws, and the tile drags.
            hold.leftMenu = false
            let move = hold.sinceMenu
            leaveMenu(point, CGPoint(x: point.x - move.x, y: point.y - move.y))
        case .changed:
            if !hold.heldStill { moved(point) }
        case .ended: hold.heldStill ? menuEnded(false) : ended(false)
        case .cancelled: hold.heldStill ? menuEnded(true) : ended(true)
        default: break
        }
    }
}

/// One finger held for `hold`, then moved `slop` points: begins. Moved
/// sooner: fails at once (a scroll or a swipe). Held still for `menuHold`
/// where `wantsMenu` says there's a menu: begins too, `heldStill`, for
/// Firn's hold menu. Otherwise never moved: fails when lifted.
final class HoldThenMove: UIGestureRecognizer {
    static let hold: TimeInterval = 0.15
    static let menuHold: TimeInterval = 0.5
    static let slop: CGFloat = 8
    private var start: CGPoint = .zero
    /// Where the finger came down, in the window.
    var startPoint: CGPoint { start }
    private var startTime: TimeInterval = 0
    /// How far the finger had moved when it began.
    private(set) var moved: CGPoint = .zero
    /// Whether a still hold at a point (window) opens Firn's menu there.
    var wantsMenu: (CGPoint) -> Bool = { _ in false }
    /// A still finger where a menu will open, from `hold` on (the tile
    /// starts to sink), and nil once it isn't (moved, lifted, or begun).
    var pressing: (CGPoint?) -> Void = { _ in }
    /// Began by holding still: a menu, not a drag.
    private(set) var heldStill = false
    /// The finger, still down, has just moved `slop` points from where the
    /// menu opened: from here it's a drag. Read once, by the action.
    var leftMenu = false
    /// The finger's latest point, and where it was as the menu opened.
    private var last: CGPoint = .zero
    private var menuPoint: CGPoint = .zero
    /// How far the finger has moved since the menu opened.
    var sinceMenu: CGPoint { CGPoint(x: last.x - menuPoint.x, y: last.y - menuPoint.y) }
    private var menuTimer: DispatchWorkItem?
    private var pressTimer: DispatchWorkItem?
    private var pressed = false

    private func endPress() {
        pressTimer?.cancel()
        pressTimer = nil
        guard pressed else { return }
        pressed = false
        pressing(nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, (event.allTouches?.count ?? 1) == 1 else {
            if state == .possible { state = .failed }
            return
        }
        start = touch.location(in: nil)
        last = start
        startTime = touch.timestamp
        let press = DispatchWorkItem { [weak self] in
            guard let self, self.state == .possible, self.wantsMenu(self.start) else { return }
            self.pressed = true
            self.pressing(self.start)
        }
        pressTimer = press
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold, execute: press)
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.state == .possible, self.wantsMenu(self.start) else { return }
            // The press stays set: the menu reads it (the tab is sunk) and
            // clears it; `reset` reports the end once the finger lifts.
            self.heldStill = true
            self.menuPoint = self.last
            self.state = .began
        }
        menuTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuHold, execute: timer)
    }

    override func reset() {
        endPress()
        menuTimer?.cancel()
        menuTimer = nil
        heldStill = false
        leftMenu = false
        moved = .zero
        super.reset()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: nil)
        last = point
        switch state {
        case .possible:
            moved = CGPoint(x: point.x - start.x, y: point.y - start.y)
            guard hypot(moved.x, moved.y) >= Self.slop else { return }
            menuTimer?.cancel()
            endPress()
            guard touch.timestamp - startTime >= Self.hold else { state = .failed; return }
            state = .began
        case .began, .changed:
            // Off the menu: the same touch carries on as a drag, so the
            // tile that lifted for the menu is the one that moves.
            if heldStill, hypot(point.x - menuPoint.x, point.y - menuPoint.y) >= Self.slop {
                heldStill = false
                leftMenu = true
            }
            state = .changed
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }
}

/// A held row or card changing shape (into a Basecamp tile and back):
/// drawn at its own size and scaled as one picture to fill the shape it's
/// gliding through, centered (the shape's mask trims the rest). Laid out
/// at each in-between size instead, its picture shifted and its pill
/// squeezed for a few frames (David's recording, 2026-11-12). Without a
/// size, it's laid out normally.
struct ScaledRow<Content: View>: View {
    let size: CGSize?
    @ViewBuilder let content: Content

    /// One view either way, so the row isn't rebuilt (its picture
    /// reloaded) as the glide starts or ends.
    var body: some View {
        GeometryReader { box in
            let own = size.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? box.size
            let scale = own.width > 0 && own.height > 0
                ? max(box.size.width / own.width, box.size.height / own.height) : 1
            content
                .frame(width: own.width, height: own.height)
                .scaleEffect(scale)
                .frame(width: box.size.width, height: box.size.height)
        }
    }
}
