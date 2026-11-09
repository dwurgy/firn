import SwiftUI
import UIKit

/// One choice in a hold menu: plain words and an SF Symbol, or a
/// sub-menu of choices (Move to Group).
struct HoldMenuItem {
    let title: String
    let systemImage: String?
    let action: @MainActor () -> Void
    let children: [HoldMenuItem]

    init(title: String, systemImage: String?, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
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
                      handOffEnded: @escaping @MainActor () -> Void) -> some View {
        background(ListHoldMenu(dragging: dragging, target: target,
                                frame: frame, held: held,
                                handOff: handOff, handOffEnded: handOffEnded))
    }
}

private struct ListHoldMenu: UIViewRepresentable {
    let dragging: Bool
    let target: @MainActor (CGPoint) -> HoldMenuTarget?
    let frame: @MainActor (UUID) -> CGRect?
    let held: @MainActor (UUID?) -> Void
    let handOff: @MainActor (UUID, CGPoint) -> Void
    let handOffEnded: @MainActor () -> Void

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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let interaction { host?.removeInteraction(interaction) }
        if let drag { host?.removeInteraction(drag) }
        interaction = nil
        drag = nil
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
        preview(in: interaction)
    }

    // Only now may iOS's drag start: the menu is showing (see MenuHandOff).
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        handOffs.showing = current?.id
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        handOffs.showing = nil
        let done = { [weak self] in self?.land(); return }
        if let animator { animator.addCompletion(done) } else { done() }
    }

    /// The tile shows again first; the picture over it leaves a moment
    /// later, once the tile has been drawn, so nothing blinks or shifts.
    private func land() {
        handingOff = false
        guard current != nil else { return }
        held(nil)
        current = nil
        let landed = picture
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
@MainActor final class MenuHandOff: NSObject, UIDragInteractionDelegate {
    /// The tile whose menu is showing now; nil: no drag may start.
    var showing: UUID?
    var moved: @MainActor (UUID, CGPoint) -> Void = { _, _ in }
    var ended: @MainActor () -> Void = {}
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
        guard let id = showing, let view = interaction.view else { return [] }
        offered = id
        nothing.backgroundColor = .clear
        nothing.isUserInteractionEnabled = false
        nothing.center = session.location(in: view)
        view.addSubview(nothing)
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.previewProvider = { [nothing] in UIDragPreview(view: nothing) }
        return [item]
    }

    // Never offered to another app.
    func dragInteraction(_ interaction: UIDragInteraction,
                         sessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { true }

    func dragInteraction(_ interaction: UIDragInteraction,
                         previewForLifting item: UIDragItem, session: any UIDragSession) -> UITargetedDragPreview? {
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        // No shadow of its own either.
        parameters.shadowPath = UIBezierPath()
        return UITargetedDragPreview(view: nothing, parameters: parameters)
    }

    func dragInteraction(_ interaction: UIDragInteraction,
                         previewForCancelling item: UIDragItem, withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        nil
    }

    // The lift starts: Firn's tile lifts at once and follows from here.
    func dragInteraction(_ interaction: UIDragInteraction,
                         willAnimateLiftWith animator: any UIDragAnimating, session: any UIDragSession) {
        start(session, in: interaction)
        // Lifted, then dropped back before a drag began: it lands.
        animator.addCompletion { [weak self] position in
            if position == .start { self?.finish() }
        }
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession) {
        #if DEBUG
        print("[handoff] iOS drag began")
        #endif
        start(session, in: interaction)
    }

    // The finger lifted (or iOS cancelled): it lands now.
    func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession,
                         willEndWith operation: UIDropOperation) {
        #if DEBUG
        print("[handoff] iOS drag ending")
        FrameWatch.mark("handoff willEndWith")
        #endif
        finish()
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession,
                         didEndWith operation: UIDropOperation) {
        #if DEBUG
        FrameWatch.mark("handoff didEndWith")
        #endif
        finish()
        nothing.removeFromSuperview()
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
        ticker?.invalidate()
        ticker = nil
        session = nil
        offered = nil
        guard carrying != nil else { return }
        carrying = nil
        ended()
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
#endif
