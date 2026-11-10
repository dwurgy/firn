import SwiftUI
import UIKit

/// One choice in a hold menu: plain words and an SF Symbol, or a
/// sub-menu of choices (Move to Group).
struct HoldMenuItem {
    let title: String
    let systemImage: String?
    let action: @MainActor () -> Void
    let children: [HoldMenuItem]
    /// Closes something (Close Tab, Close Group, Remove from Basecamp):
    /// Firn's menu shows it in muted terracotta.
    var closes = false

    init(title: String, systemImage: String?, closes: Bool = false, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.closes = closes
        self.action = action
        children = []
    }

    init(title: String, systemImage: String?, children: [HoldMenuItem]) {
        self.title = title
        self.systemImage = systemImage
        action = {}
        self.children = children
    }

    @MainActor fileprivate var element: UIMenuElement {
        let image = systemImage.flatMap { UIImage(systemName: $0) }
        if !children.isEmpty {
            return UIMenu(title: title, image: image, children: children.map(\.element))
        }
        return UIAction(title: title, image: image) { _ in action() }
    }
}

/// iOS's menu for `sections`, split by its dividers (nil: no menu).
@MainActor private func holdMenuConfiguration(_ sections: [[HoldMenuItem]]) -> UIContextMenuConfiguration? {
    let sections = sections.filter { !$0.isEmpty }
    guard !sections.isEmpty else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
        UIMenu(children: sections.map { items in
            UIMenu(options: .displayInline, children: items.map(\.element))
        })
    }
}

extension View {
    /// iOS's own hold menu, lifting this view on a solid base.
    ///
    /// Why UIKit: SwiftUI's `.contextMenu` lifts a copy of the view with
    /// nothing behind it, so Firn's see-through glass turned dark about half
    /// a second into a hold, as iOS's shadow showed through it (David,
    /// 2026-11-08). SwiftUI has no say in that copy's background; UIKit's
    /// `UIContextMenuInteraction` (what SwiftUI uses underneath) does,
    /// through `UIPreviewParameters.backgroundColor`.
    ///
    /// `sections` are split by iOS's dividers. `outset` widens the lifted
    /// shape past the view, so a hairline and shadow just outside it come
    /// along. `dragging`: a hold that moved became a drag, so the menu's
    /// lift stops at once.
    func holdMenu(cornerRadius: CGFloat, outset: CGFloat = 0, base: Color, dragging: Bool = false,
                  sections: @escaping @MainActor () -> [[HoldMenuItem]]) -> some View {
        HoldMenuHost(content: self, cornerRadius: cornerRadius, outset: outset,
                     base: UIColor(base), dragging: dragging, sections: sections)
    }
}

/// Hosts the view in UIKit so the menu's interaction can sit on it; taps
/// still reach the SwiftUI view inside.
private struct HoldMenuHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let cornerRadius: CGFloat
    let outset: CGFloat
    let base: UIColor
    let dragging: Bool
    let sections: @MainActor () -> [[HoldMenuItem]]

    func makeUIViewController(context: Context) -> HoldMenuController<Content> {
        let controller = HoldMenuController(rootView: content)
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: HoldMenuController<Content>, context: Context) {
        controller.rootView = content
        update(controller)
    }

    private func update(_ controller: HoldMenuController<Content>) {
        controller.cornerRadius = cornerRadius
        controller.outset = outset
        controller.base = base
        controller.sections = sections
        controller.dragging = dragging
    }
}

private final class HoldMenuController<Content: View>: UIHostingController<Content>,
                                                       UIContextMenuInteractionDelegate {
    var cornerRadius: CGFloat = 0
    var outset: CGFloat = 0
    var base: UIColor = .clear
    var sections: @MainActor () -> [[HoldMenuItem]] = { [] }
    private var interaction: UIContextMenuInteraction?
    /// iOS keeps its lift until the finger lifts, even once Firn's drag has
    /// the touch; taking the interaction off and back on ends it (as the
    /// list's menu does).
    var dragging = false {
        didSet {
            guard dragging, !oldValue, let interaction else { return }
            view.removeInteraction(interaction)
            view.addInteraction(interaction)
        }
    }

    override init(rootView: Content) {
        super.init(rootView: rootView)
        // The SwiftUI frame decides the size; the host never asks for one.
        sizingOptions = []
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let interaction = UIContextMenuInteraction(delegate: self)
        view.addInteraction(interaction)
        self.interaction = interaction
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        holdMenuConfiguration(sections())
    }

    // The same lifted shape going up and coming down, so nothing pops at either end.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        preview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configuration: UIContextMenuConfiguration,
                                dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        preview()
    }

    private func preview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        let rect = view.bounds.insetBy(dx: -outset, dy: -outset)
        parameters.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius + outset)
        // Solid, so iOS's shadow can't show through the glass.
        parameters.backgroundColor = base.resolvedColor(with: view.traitCollection)
        return UITargetedPreview(view: view, parameters: parameters)
    }
}

// MARK: - The overview's list

/// Something in a list that a hold opens a menu on: a tab's tile or a group.
struct HoldMenuTarget {
    let id: UUID
    let cornerRadius: CGFloat
    let sections: [[HoldMenuItem]]
}

extension View {
    /// iOS's hold menu for the tiles in a scrolling list, each lifting
    /// solid, never darkened, as `holdMenu` does for one view.
    ///
    /// Why not `holdMenu` on each tile: it hosts the tile in UIKit, and
    /// SwiftUI's glides inside (a card shrinking to a row, a group folding)
    /// don't reliably cross into a separate host. Instead one interaction
    /// sits on the list's scroll view, as SwiftUI's own `.contextMenu` does
    /// underneath, and lifts a picture of the tile taken from the screen at
    /// the start of the hold: exactly what was there, glass and all, as
    /// solid pixels, so iOS's shadow can't darken it. `held` hides the real
    /// tile from the moment the picture lifts (it may move to make room for
    /// the menu, and both showed at once; David's recording, 2026-11-08)
    /// and shows it again just before the landed picture leaves.
    ///
    /// `target` finds what's under a point and `frame` where a target is
    /// now (both in global points, nil: nothing there). `dragging`: a hold
    /// that moved became a drag, so the menu's lift stops at once (its
    /// solid base stayed behind in the tab's place; same recording).
    ///
    /// `handOff` and `handOffEnded`: with the menu open, moving the finger
    /// away from it picks the tile up, as in Safari (see `MenuHandOff`).
    func listHoldMenu(dragging: Bool,
                      target: @escaping @MainActor (CGPoint) -> HoldMenuTarget?,
                      frame: @escaping @MainActor (UUID) -> CGRect?,
                      held: @escaping @MainActor (UUID?) -> Void,
                      handOff: @escaping @MainActor (UUID, CGPoint) -> Void,
                      handOffEnded: @escaping @MainActor () -> CGRect?,
                      handOffLanded: @escaping @MainActor () -> Void,
                      handOffAlone: @escaping @MainActor () -> Void) -> some View {
        background(ListHoldMenu(dragging: dragging, target: target,
                                frame: frame, held: held,
                                handOff: handOff, handOffEnded: handOffEnded,
                                handOffLanded: handOffLanded, handOffAlone: handOffAlone))
    }
}

private struct ListHoldMenu: UIViewRepresentable {
    let dragging: Bool
    let target: @MainActor (CGPoint) -> HoldMenuTarget?
    let frame: @MainActor (UUID) -> CGRect?
    let held: @MainActor (UUID?) -> Void
    let handOff: @MainActor (UUID, CGPoint) -> Void
    let handOffEnded: @MainActor () -> CGRect?
    let handOffLanded: @MainActor () -> Void
    let handOffAlone: @MainActor () -> Void

    func makeCoordinator() -> ListHoldMenuDelegate { ListHoldMenuDelegate() }

    func makeUIView(context: Context) -> ListHoldMenuAnchor {
        let anchor = ListHoldMenuAnchor()
        anchor.delegate = context.coordinator
        anchor.isUserInteractionEnabled = false
        update(context.coordinator)
        return anchor
    }

    func updateUIView(_ anchor: ListHoldMenuAnchor, context: Context) {
        update(context.coordinator)
    }

    private func update(_ delegate: ListHoldMenuDelegate) {
        delegate.target = target
        delegate.frame = frame
        delegate.held = held
        delegate.handOffs.moved = handOff
        delegate.handOffs.ended = handOffEnded
        delegate.handOffs.landed = handOffLanded
        delegate.handOffs.alone = handOffAlone
        if dragging { delegate.cancel() }
    }
}

/// An invisible view in the list that puts the menu's interaction on the
/// scroll view holding it, so a hold anywhere on the list reaches it.
@MainActor final class ListHoldMenuAnchor: UIView {
    weak var delegate: ListHoldMenuDelegate?
    private weak var host: UIView?
    private var interaction: UIContextMenuInteraction?
    private var drag: UIDragInteraction?
    private var drop: UIDropInteraction?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let interaction { host?.removeInteraction(interaction) }
        if let drag { host?.removeInteraction(drag) }
        if let drop { host?.removeInteraction(drop) }
        interaction = nil
        drag = nil
        drop = nil
        host = nil
        guard window != nil, let delegate else { return }
        var view = superview
        while let candidate = view, !(candidate is UIScrollView) { view = candidate.superview }
        guard let scroll = view else { return }
        let new = UIContextMenuInteraction(delegate: delegate)
        scroll.addInteraction(new)
        // On the same view as the menu: iOS hands a menu off only to a drag there.
        let handOff = delegate.handOffs.interaction()
        scroll.addInteraction(handOff)
        let probe = TouchProbe()
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        scroll.addGestureRecognizer(probe)
        if HandOffTrial.number == 2 { HandOffTrial.show(in: scroll) }
        if HandOffTrial.number == 2 {
            let landing = UIDropInteraction(delegate: delegate.handOffs)
            scroll.addInteraction(landing)
            drop = landing
        }
        host = scroll
        interaction = new
        drag = handOff
        delegate.interaction = new
    }
}

@MainActor final class ListHoldMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    var target: @MainActor (CGPoint) -> HoldMenuTarget? = { _ in nil }
    var frame: @MainActor (UUID) -> CGRect? = { _ in nil }
    var held: @MainActor (UUID?) -> Void = { _ in }
    weak var interaction: UIContextMenuInteraction?
    /// Moving off the open menu picks its tile up.
    let handOffs = MenuHandOff()
    /// A hand-off started: iOS's copy of the tile goes at once, shadow and
    /// all, so only Firn's own lifted tile shows. (It faded out over Firn's
    /// for a few frames, see-through, with a dark shadow box; David's
    /// recording, 2026-11-08.)
    private var handingOff = false

    override init() {
        super.init()
        handOffs.started = { [weak self] in
            self?.handingOff = true
            self?.picture?.alpha = 0
        }
        handOffs.endMenu = { [weak self] in
            guard let self, let interaction, let view = interaction.view else { return }
            view.removeInteraction(interaction)
            view.addInteraction(interaction)
        }
        handOffs.lift = { [weak self] in
            guard let self, let picture, let current else { return nil }
            return HandOffLift(view: picture, cornerRadius: current.cornerRadius + outset, outset: outset)
        }
    }

    /// The tile the open menu is for, and its picture from the hold's start.
    private var current: HoldMenuTarget?
    private var picture: UIImageView?
    /// The lifted shape reaches 1pt past the tile, so its hairline comes along.
    private let outset: CGFloat = 1

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let view = interaction.view, let window = view.window else { return nil }
        let point = view.convert(location, to: nil)
        guard let found = target(point), let rect = frame(found.id) else { return nil }
        let area = rect.insetBy(dx: -outset, dy: -outset)
        // The tile as it is on screen, glass and all, drawn into an image.
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        let image = UIGraphicsImageRenderer(size: area.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds.offsetBy(dx: -area.minX, dy: -area.minY),
                                 afterScreenUpdates: false)
        }
        picture?.removeFromSuperview()
        picture = UIImageView(image: image)
        current = found
        return holdMenuConfiguration(found.sections)
    }

    // The picture covers the tile exactly, so the tile can hide at once.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        let preview = preview(in: interaction)
        if preview != nil { held(current?.id) }
        return preview
    }

    // Back to where the tile is now; nil (a fade) if it's gone, as after Close Tab.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configuration: UIContextMenuConfiguration,
                                dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        FrameWatch.mark("menu dismissal preview asked, handing off: \(handingOff)")
        if handingOff, HandOffTrial.number == 2, HandOffTrial.variant == 3 { return nil }
        return preview(in: interaction)
    }

    // Only now may iOS's drag start: the menu is showing (see MenuHandOff).
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        handOffs.showing = current?.id
        #if DEBUG
        FrameWatch.mark("menu willDisplay")
        #endif
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        handOffs.showing = nil
        #if DEBUG
        FrameWatch.mark("menu willEnd")
        animator?.addCompletion { FrameWatch.mark("menu ended") }
        #endif
        let done = { [weak self] in self?.land(); return }
        if let animator { animator.addCompletion(done) } else { done() }
    }

    /// The tile shows again first; the picture over it leaves a moment
    /// later, once the tile has been drawn, so nothing blinks or shifts.
    private func land() {
        handingOff = false
        handOffs.menuEnded()
        guard current != nil else { return }
        held(nil)
        current = nil
        // Carried by iOS's drag (trial 2): the hand-off keeps the picture.
        let landed = handOffs.running ? nil : picture
        picture = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            landed?.removeFromSuperview()
        }
    }

    /// A drag took over the hold: the lift stops and its picture goes.
    func cancel() {
        // A hand-off is Firn's drag carried by iOS's: nothing to stop.
        guard current != nil, !handOffs.running else { return }
        current = nil
        held(nil)
        picture?.removeFromSuperview()
        picture = nil
        // iOS keeps its lift until the finger lifts, even once Firn's drag
        // has the touch; taking the interaction off and back on ends it.
        if let interaction, let view = interaction.view {
            view.removeInteraction(interaction)
            view.addInteraction(interaction)
        }
    }

    /// iOS lifts only a view that's on screen: the picture goes into the
    /// list exactly over the tile (the same pixels, so nothing shows),
    /// and leaves once the menu has closed.
    private func preview(in interaction: UIContextMenuInteraction) -> UITargetedPreview? {
        guard let view = interaction.view, let current, let picture,
              let rect = frame(current.id) else {
            picture?.removeFromSuperview()
            return nil
        }
        picture.frame = view.convert(rect.insetBy(dx: -outset, dy: -outset), from: nil)
        if picture.superview !== view { view.addSubview(picture) }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: picture.bounds,
                                              cornerRadius: current.cornerRadius + outset)
        // No base of its own: the picture is the screen's own pixels, already
        // solid, so iOS's shadow can't show through it (a base stayed behind
        // as a solid slot when a hold became a drag; David's recording).
        parameters.backgroundColor = .clear
        if handingOff {
            picture.alpha = 0
            parameters.shadowPath = UIBezierPath()
        }
        return UITargetedPreview(view: picture, parameters: parameters)
    }
}

// MARK: - Moving off an open menu

/// With a hold menu open, moving the finger away from it closes the menu
/// and picks its tile up, as in Safari. iOS hands a menu off only to its
/// own drag, on the same view, so there is one; but it may start only
/// while a menu is showing (`showing`), never otherwise. (SwiftUI's
/// `.onDrag` couldn't be told that, and iOS's drag started with nearly
/// every drag of Firn's, copying and snapping tabs back; David's phone's
/// log, 2026-11-05. With this, his log showed it refused 60 times and
/// starting only the 4 times a menu was open.) It carries an empty item
/// kept inside Firn and shows nothing of its own: it only tells Firn's own
/// drag where the finger is (`moved`), which lifts its own tile, and lands
/// it as the finger lifts (`ended`).
///
/// The finger is read every frame while carrying (a display link), from
/// the moment the lift starts: iOS reports moves only now and then during
/// its lift, and the card stalled for about 0.4s after the menu closed.
/// And it lands as the finger lifts (`willEndWith`), not once iOS's own
/// (invisible) cancel animation has run, which froze the card in place for
/// a moment first (David's recording, 2026-11-08).
struct HandOffLift {
    let view: UIImageView
    let cornerRadius: CGFloat
    let outset: CGFloat
}

@MainActor final class MenuHandOff: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
    // Trial 2: iOS's drag shows the menu's picture of the tile the whole
    // way, and iOS's own drop animation lands it in the gap.
    var lift: @MainActor () -> HandOffLift? = { nil }
    var landed: @MainActor () -> Void = {}
    var endMenu: @MainActor () -> Void = {}
    /// iOS's own picture has gone (trial 6): only Firn's tile is left.
    var alone: @MainActor () -> Void = {}

    /// The menu has finished closing. Until now iOS's drag showed the
    /// menu's own lifted copy, whatever preview it was given; now it takes
    /// the item's provider, which hides it.
    func menuEnded() {
        guard hybrid, carrying != nil else { return }
        FrameWatch.mark("handoff menu ended while carrying")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.alone()
        }
    }
    private var lifted: HandOffLift?
    /// Where the tile lands (global), once let go.
    private var landing: CGRect??
    /// iOS said it will animate the landing.
    private var animating = false
    private var safety: Task<Void, Never>?
    private var shows: Bool { HandOffTrial.number == 2 }
    /// Trial 6: iOS's drag lifts the menu's picture at full size, so the
    /// menu's copy becomes the dragged tile with nothing to shrink into;
    /// then iOS's preview is hidden and Firn's own lifted tile, already
    /// under it, carries on as in any drag of Firn's, and lands as one.
    private var hybrid: Bool { HandOffTrial.number == 6 }

    private func parameters(_ lift: HandOffLift) -> UIDragPreviewParameters {
        let parameters = UIDragPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: lift.view.bounds, cornerRadius: lift.cornerRadius)
        parameters.backgroundColor = .clear
        return parameters
    }

    /// Let go: Firn saves the new place and says where the tile lands.
    private func land() -> CGRect? {
        if let landing { return landing }
        ticker?.invalidate()
        ticker = nil
        let rect = ended()
        FrameWatch.mark("handoff land \(rect.map { "\(Int($0.minY))" } ?? "nil")")
        landing = .some(rect)
        safety = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { self?.settled() }
        }
        return rect
    }

    /// iOS's preview, aimed at the gap.
    private func retarget(_ preview: UITargetedDragPreview, in view: UIView?) -> UITargetedDragPreview? {
        guard let view, let lifted, let rect = land() else { return nil }
        let area = rect.insetBy(dx: -lifted.outset, dy: -lifted.outset)
        let size = lifted.view.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let center = view.convert(CGPoint(x: area.midX, y: area.midY), from: nil)
        let scale = CGAffineTransform(scaleX: area.width / size.width, y: area.height / size.height)
        return preview.retargetedPreview(with: UIDragPreviewTarget(container: view, center: center, transform: scale))
    }

    /// iOS's preview reaches the gap in about 0.2s and stays there, solid,
    /// until its animation reports done (about 0.85s): the real tile is
    /// saved and shown under it once it has arrived, so the let-go frame
    /// itself does no work (a save there left the screen without the tile
    /// for one frame; David's recording, 2026-11-09).
    private var reveal: Task<Void, Never>?
    private var revealed = false

    private func revealSoon() {
        reveal?.cancel()
        reveal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, carrying != nil, !revealed else { return }
            FrameWatch.mark("handoff reveal")
            revealed = true
            landed()
        }
    }

    /// iOS's preview has landed and gone: the picture covers the gap for a
    /// moment more, over the real tile.
    private func settled() {
        guard carrying != nil else { return }
        FrameWatch.mark("handoff settled")
        reveal?.cancel()
        reveal = nil
        safety?.cancel()
        safety = nil
        let cover = lifted?.view
        if let cover, let view = cover.superview, case let .some(.some(rect)) = landing, let lifted {
            cover.transform = .identity
            cover.frame = view.convert(rect.insetBy(dx: -lifted.outset, dy: -lifted.outset), from: nil)
            cover.alpha = 1
        }
        carrying = nil
        offered = nil
        session = nil
        lifted = nil
        landing = nil
        animating = false
        HandOffTrial.drags += 1
        HandOffTrial.show(in: cover?.superview)
        if !revealed { landed() }
        revealed = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            cover?.removeFromSuperview()
        }
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        carrying != nil && session.localDragSession != nil
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
        let proposal = UIDropProposal(operation: carrying != nil ? .move : .cancel)
        // Full size on the drop's side too, or iOS rescales the preview
        // (a cross-fade to a slightly smaller copy) partway through.
        proposal.prefersFullSizePreview = true
        return proposal
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {
        FrameWatch.mark("handoff drop session entered")
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) {
        FrameWatch.mark("handoff drop session exited")
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        FrameWatch.mark("handoff performDrop")
        _ = land()
    }

    func dropInteraction(_ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
                         withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        FrameWatch.mark("handoff previewForDropping")
        return retarget(defaultPreview, in: interaction.view)
    }

    func dropInteraction(_ interaction: UIDropInteraction, item: UIDragItem,
                         willAnimateDropWith animator: any UIDragAnimating) {
        FrameWatch.mark("handoff willAnimateDrop")
        animating = true
        revealSoon()
        animator.addCompletion { [weak self] _ in
            FrameWatch.mark("handoff drop animation done")
            self?.settled()
        }
    }

    /// The tile whose menu is showing now; nil: no drag may start.
    var showing: UUID?
    var moved: @MainActor (UUID, CGPoint) -> Void = { _, _ in }
    var ended: @MainActor () -> CGRect? = { nil }
    /// The hand-off has started (the menu's lifted copy should go).
    var started: @MainActor () -> Void = {}
    /// The tile iOS's drag was offered, until its lift starts.
    private var offered: UUID?
    /// The tile a running hand-off carries.
    private var carrying: UUID?
    var running: Bool { carrying != nil }
    private var session: (any UIDragSession)?
    private weak var view: UIView?
    private var ticker: CADisplayLink?
    /// The invisible view iOS's drag lifts and returns to.
    private let nothing = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    func interaction() -> UIDragInteraction {
        let drag = UIDragInteraction(delegate: self)
        // Off by default on the iPhone.
        drag.isEnabled = true
        return drag
    }

    func dragInteraction(_ interaction: UIDragInteraction,
                         itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
        #if DEBUG
        print("[handoff] itemsForBeginning, menu showing: \(showing != nil)")
        #endif
        guard carrying == nil, let id = showing, let view = interaction.view else { return [] }
        offered = id
        #if DEBUG
        FrameWatch.mark("handoff itemsForBeginning, trial \(HandOffTrial.number)")
        if shows || hybrid {
            guard let lift = lift() else { return [] }
            lifted = lift
            return [UIDragItem(itemProvider: NSItemProvider())]
        }
        if HandOffTrial.number == 1 {
            // Trial 1: the documented invisible drag (no lift preview, a
            // provider that returns nil), instead of a 1pt view.
            let item = UIDragItem(itemProvider: NSItemProvider())
            item.previewProvider = { nil }
            return [item]
        }
        #endif
        nothing.backgroundColor = .clear
        nothing.isUserInteractionEnabled = false
        nothing.center = session.location(in: view)
        view.addSubview(nothing)
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.previewProvider = { [nothing] in UIDragPreview(view: nothing) }
        return [item]
    }

    // Full size, as when reordering: iOS otherwise shrinks a large preview
    // to a thumbnail under the finger (the "small grey box" of the first
    // tries was that shrink, aimed at a 1pt view).
    func dragInteraction(_ interaction: UIDragInteraction,
                         prefersFullSizePreviewsFor session: any UIDragSession) -> Bool { true }

    // Never offered to another app.
    func dragInteraction(_ interaction: UIDragInteraction,
                         sessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { true }

    func dragInteraction(_ interaction: UIDragInteraction,
                         previewForLifting item: UIDragItem, session: any UIDragSession) -> UITargetedDragPreview? {
        #if DEBUG
        if HandOffTrial.number == 1 { return nil }
        #endif
        if shows || hybrid, let lifted {
            return UITargetedDragPreview(view: lifted.view, parameters: parameters(lifted))
        }
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        // No shadow of its own either.
        parameters.shadowPath = UIBezierPath()
        return UITargetedDragPreview(view: nothing, parameters: parameters)
    }

    func dragInteraction(_ interaction: UIDragInteraction,
                         previewForCancelling item: UIDragItem, withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        if shows {
            FrameWatch.mark("handoff previewForCancelling")
            return retarget(defaultPreview, in: interaction.view)
        }
        return nil
    }

    // The lift starts: Firn's tile lifts at once and follows from here.
    func dragInteraction(_ interaction: UIDragInteraction,
                         willAnimateLiftWith animator: any UIDragAnimating, session: any UIDragSession) {
        #if DEBUG
        FrameWatch.mark("handoff willAnimateLift")
        #endif
        start(session, in: interaction)
        if shows, HandOffTrial.variant == 5 { endMenu() }
        // Lifted, then dropped back before a drag began: it lands.
        animator.addCompletion { [weak self] position in
            FrameWatch.mark("handoff lift animation done, at start: \(position == .start)")
            guard position == .start, let self else { return }
            if shows { _ = land(); settled() } else { finish() }
        }
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession) {
        #if DEBUG
        print("[handoff] iOS drag began")
        FrameWatch.mark("handoff sessionWillBegin, try \(HandOffTrial.variant)")
        if hybrid {
            // iOS's own preview goes; Firn's tile is already under it.
            for item in session.items { item.previewProvider = { nil } }
        }
        if shows, HandOffTrial.variant == 4, let lifted {
            let image = lifted.view.image
            let size = lifted.view.bounds.size
            let radius = lifted.cornerRadius
            session.items.first?.previewProvider = {
                let copy = UIImageView(image: image)
                copy.frame = CGRect(origin: .zero, size: size)
                let parameters = UIDragPreviewParameters()
                parameters.visiblePath = UIBezierPath(roundedRect: copy.bounds, cornerRadius: radius)
                parameters.backgroundColor = .clear
                return UIDragPreview(view: copy, parameters: parameters)
            }
        }
        #endif
        start(session, in: interaction)
    }

    // The finger lifted (or iOS cancelled): it lands now.
    func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession,
                         willEndWith operation: UIDropOperation) {
        #if DEBUG
        print("[handoff] iOS drag ending")
        FrameWatch.mark("handoff willEndWith \(operation.rawValue)")
        #endif
        if shows { _ = land(); return }
        finish()
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession,
                         didEndWith operation: UIDropOperation) {
        #if DEBUG
        FrameWatch.mark("handoff didEndWith")
        #endif
        if shows {
            if !animating { settled() }
            return
        }
        finish()
        nothing.removeFromSuperview()
    }

    func dragInteraction(_ interaction: UIDragInteraction, item: UIDragItem,
                         willAnimateCancelWith animator: any UIDragAnimating) {
        FrameWatch.mark("handoff willAnimateCancel")
        if shows { animating = true; revealSoon() }
        animator.addCompletion { [weak self] _ in
            FrameWatch.mark("handoff cancel animation done")
            if self?.shows == true { self?.settled() }
        }
    }

    private func start(_ session: any UIDragSession, in interaction: UIDragInteraction) {
        if carrying == nil {
            guard let id = offered else { return }
            carrying = id
            offered = nil
            started()
        }
        self.session = session
        view = interaction.view
        if ticker == nil {
            let ticker = CADisplayLink(target: self, selector: #selector(tick))
            ticker.add(to: .main, forMode: .common)
            self.ticker = ticker
        }
        tick()
    }

    /// Where the finger is, in the window, for Firn's own drag.
    @objc private func tick() {
        guard let id = carrying, let session, let view else { return }
        moved(id, view.convert(session.location(in: view), to: nil))
    }

    private func finish() {
        if hybrid {
            lifted?.view.removeFromSuperview()
            lifted = nil
        }
        ticker?.invalidate()
        ticker = nil
        session = nil
        offered = nil
        guard carrying != nil else { return }
        carrying = nil
        _ = ended()
    }
}

/// Step 3b's trials: which hand-off is tried. Trial 2 unless the app is
/// launched with `-handoff 0` (as before) or `-handoff 1`. Remove when done.
@MainActor enum HandOffTrial {
    static let number = UserDefaults.standard.object(forKey: "handoff") == nil
        ? 6 : UserDefaults.standard.integer(forKey: "handoff")
    /// Within trial 2, three tries at the preview iOS rebuilds when the
    /// menu's own ending finishes; each gets two drags, then the next:
    /// 3: the menu is given no dismissal preview during a hand-off;
    /// 4: the drag is given its final preview as it begins;
    /// 5: the menu is ended at once as the lift starts.
    static var drags = 0
    // Try 5 crashed UIKit (taking the menu's interaction off mid hand-off);
    // it's out of the rotation.
    static var variant: Int { [3, 4][(drags / 2) % 2] }
    private static let label = UILabel()

    static func show(in view: UIView?) {
        guard let window = view?.window else { return }
        label.text = " try \(variant) "
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .systemRed
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 8, y: window.safeAreaInsets.top + 2)
        if label.superview !== window { window.addSubview(label) }
    }
}

/// Step 3b, route B's question: does a plain recognizer still hear the
/// finger once iOS's menu is open? Logs only; never recognizes.
final class TouchProbe: UIGestureRecognizer {
    private var moves = 0
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        moves = 0
        FrameWatch.mark("probe began")
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        moves += 1
        if moves % 15 == 1 { FrameWatch.mark("probe moved \(moves)") }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        FrameWatch.mark("probe ended after \(moves) moves")
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        FrameWatch.mark("probe cancelled after \(moves) moves")
        state = .failed
    }
}

#if DEBUG

/// Debug only, for step 3b's landing: logs frames that came late (more
/// than 25ms apart) for 0.6s after a let-go. Remove when the step is done.
@MainActor final class FrameWatch: NSObject {
    static let shared = FrameWatch()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var until: CFTimeInterval = 0
    private var label = ""

    static func mark(_ text: String) {
        print("[landing] \(String(format: "%.3f", CACurrentMediaTime())) \(text)")
    }

    func watch(_ label: String) {
        self.label = label
        last = CACurrentMediaTime()
        until = last + 0.6
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if now - last > 0.025 {
            Self.mark("\(label): frame gap \(Int((now - last) * 1000))ms")
        }
        last = now
        if now > until {
            Self.mark("\(label): watch done")
            link.invalidate()
            self.link = nil
        }
    }
}
#else
enum FrameWatch { static func mark(_ text: String) {} }
#endif
