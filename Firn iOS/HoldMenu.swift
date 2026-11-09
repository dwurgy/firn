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
    /// along.
    func holdMenu(cornerRadius: CGFloat, outset: CGFloat = 0, base: Color,
                  sections: @escaping @MainActor () -> [[HoldMenuItem]]) -> some View {
        HoldMenuHost(content: self, cornerRadius: cornerRadius, outset: outset,
                     base: UIColor(base), sections: sections)
    }
}

/// Hosts the view in UIKit so the menu's interaction can sit on it; taps
/// still reach the SwiftUI view inside.
private struct HoldMenuHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let cornerRadius: CGFloat
    let outset: CGFloat
    let base: UIColor
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
    }
}

private final class HoldMenuController<Content: View>: UIHostingController<Content>,
                                                       UIContextMenuInteractionDelegate {
    var cornerRadius: CGFloat = 0
    var outset: CGFloat = 0
    var base: UIColor = .clear
    var sections: @MainActor () -> [[HoldMenuItem]] = { [] }

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
        view.addInteraction(UIContextMenuInteraction(delegate: self))
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
    /// iOS's hold menu for the tiles in a scrolling list, each lifted on a
    /// solid base, as `holdMenu` does for one view.
    ///
    /// Why not `holdMenu` on each tile: it hosts the tile in UIKit, and
    /// SwiftUI's glides inside (a card shrinking to a row, a group folding)
    /// don't reliably cross into a separate host. Instead one interaction
    /// sits on the list's scroll view, as SwiftUI's own `.contextMenu` does
    /// underneath, and lifts a picture of the tile taken from the screen at
    /// the start of the hold: exactly what was there, glass and all, on a
    /// solid base so iOS's shadow can't darken it. `held` hides the real
    /// tile while the menu is open (the lifted picture may move to make
    /// room for the menu) and shows it again once the picture has landed.
    ///
    /// `target` finds what's under a point and `frame` where a target is
    /// now (both in global points, nil: nothing there).
    func listHoldMenu(base: Color,
                      target: @escaping @MainActor (CGPoint) -> HoldMenuTarget?,
                      frame: @escaping @MainActor (UUID) -> CGRect?,
                      held: @escaping @MainActor (UUID?) -> Void) -> some View {
        background(ListHoldMenu(base: UIColor(base), target: target, frame: frame, held: held))
    }
}

private struct ListHoldMenu: UIViewRepresentable {
    let base: UIColor
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
        delegate.base = base
        delegate.target = target
        delegate.frame = frame
        delegate.held = held
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
    }
}

@MainActor final class ListHoldMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    var base: UIColor = .clear
    var target: @MainActor (CGPoint) -> HoldMenuTarget? = { _ in nil }
    var frame: @MainActor (UUID) -> CGRect? = { _ in nil }
    var held: @MainActor (UUID?) -> Void = { _ in }

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

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        preview(in: interaction)
    }

    // Back to where the tile is now; nil (a fade) if it's gone, as after Close Tab.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configuration: UIContextMenuConfiguration,
                                dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        preview(in: interaction)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        held(current?.id)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        let done = { [weak self] in
            guard let self else { return }
            self.picture?.removeFromSuperview()
            self.picture = nil
            self.current = nil
            self.held(nil)
        }
        if let animator { animator.addCompletion(done) } else { done() }
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
        // Solid, so iOS's shadow can't show through the glass.
        parameters.backgroundColor = base.resolvedColor(with: view.traitCollection)
        return UITargetedPreview(view: picture, parameters: parameters)
    }
}
