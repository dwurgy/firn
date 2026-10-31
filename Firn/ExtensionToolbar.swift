import AppKit
import FirnCore
import SwiftUI

/// An AppKit button supplies WebKit with the actual view that anchors a popup.
@available(macOS 15.4, *)
struct ExtensionToolbar: View {
    let store: BrowserStore
    let window: WindowModel
    @State private var library = WebExtensionLibrary.shared

    private var enabled: [InstalledWebExtension] {
        library.extensions.filter { $0.enabledDataStoreIDs.contains(store.activeSpace.dataStoreID) }
    }

    var body: some View {
        if !enabled.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(enabled) { item in
                        ExtensionActionButton(name: item.name, isAvailable: store.lookout == nil) { anchor in
                            WebExtensionManager.shared.performAction(
                                id: item.id,
                                in: store.activeSpace.dataStoreID,
                                for: window.frontPage,
                                anchor: anchor
                            )
                        }
                        .frame(width: 28, height: 28)
                    }
                }
            }
            .frame(maxWidth: 86)
            .accessibilityLabel("Extensions")
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionActionButton: NSViewRepresentable {
    let name: String
    let isAvailable: Bool
    let action: (NSView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(Theme.muted)
        button.toolTip = isAvailable ? name : "Extensions are unavailable in link previews"
        button.isEnabled = isAvailable
        button.setAccessibilityLabel("Open \(name) extension")
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.toolTip = isAvailable ? name : "Extensions are unavailable in link previews"
        button.isEnabled = isAvailable
        button.setAccessibilityLabel("Open \(name) extension")
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: (NSView) -> Void
        init(action: @escaping (NSView) -> Void) { self.action = action }

        @objc func clicked(_ sender: NSButton) { action(sender) }
    }
}
