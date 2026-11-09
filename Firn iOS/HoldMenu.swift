import SwiftUI
import UIKit

/// One choice in a hold menu: plain words and an SF Symbol.
struct HoldMenuItem {
    let title: String
    let systemImage: String
    let action: @MainActor () -> Void
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
        let sections = sections().filter { !$0.isEmpty }
        guard !sections.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: sections.map { items in
                UIMenu(options: .displayInline, children: items.map { item in
                    UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { _ in
                        item.action()
                    }
                })
            })
        }
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
