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
    func listHoldMenu(dragging: Bool,
                      target: @escaping @MainActor (CGPoint) -> HoldMenuTarget?,
                      frame: @escaping @MainActor (UUID) -> CGRect?,
                      held: @escaping @MainActor (UUID?) -> Void) -> some View {
        background(ListHoldMenu(dragging: dragging, target: target,
                                frame: frame, held: held))
    }
}

private struct ListHoldMenu: UIViewRepresentable {
    let dragging: Bool
    let target: @MainActor (CGPoint) -> HoldMenuTarget?
    let frame: @MainActor (UUID) -> CGRect?
    let held: @MainActor (UUID?) -> Void

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
        if dragging { delegate.cancel() }
    }
}

/// An invisible view in the list that puts the menu's interaction on the
/// scroll view holding it, so a hold anywhere on the list reaches it.
@MainActor final class ListHoldMenuAnchor: UIView {
    weak var delegate: ListHoldMenuDelegate?
    private weak var host: UIView?
    private var interaction: UIContextMenuInteraction?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let interaction { host?.removeInteraction(interaction) }
        interaction = nil
        host = nil
        guard window != nil, let delegate else { return }
        var view = superview
        while let candidate = view, !(candidate is UIScrollView) { view = candidate.superview }
        guard let scroll = view else { return }
        let new = UIContextMenuInteraction(delegate: delegate)
        scroll.addInteraction(new)
        host = scroll
        interaction = new
        delegate.interaction = new
    }
}

@MainActor final class ListHoldMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    var target: @MainActor (CGPoint) -> HoldMenuTarget? = { _ in nil }
    var frame: @MainActor (UUID) -> CGRect? = { _ in nil }
    var held: @MainActor (UUID?) -> Void = { _ in }
    weak var interaction: UIContextMenuInteraction?

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

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        let done = { [weak self] in self?.land(); return }
        if let animator { animator.addCompletion(done) } else { done() }
    }

    /// The tile shows again first; the picture over it leaves a moment
    /// later, once the tile has been drawn, so nothing blinks or shifts.
    private func land() {
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
        guard current != nil else { return }
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
        return UITargetedPreview(view: picture, parameters: parameters)
    }
}
