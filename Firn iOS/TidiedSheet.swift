import FirnCore
import SwiftUI
import UIKit

// Tidied away on the iPhone (docs/IOS-PLAN.md, "Plan: tidying away"; look
// from docs/tidy-ios-design.html): the list, from the space menu's row. The
// moment the tabs go is `Tidying`.

extension EnvironmentValues {
    /// Opens the Tidied Away sheet (`BrowserScreen` shows it): the space
    /// menu's row, or the pill while it speaks.
    @Entry var showTidied: SheetAction? = nil
}

/// "Tidy away tabs after": this device's own choice, kept as the Mac keeps
/// its own.
enum TidySetting {
    static let key = "driftAfter"
    static var saved: DriftAfter {
        UserDefaults.standard.string(forKey: key).flatMap(DriftAfter.init) ?? .sevenDays
    }
}

/// The space on screen's tidied-away tabs, as iOS's own list, as History's.
/// A tap brings a tab back and shows it at once; a swipe left closes it, and
/// holding it gives iOS's menu. Restore All brings them all back where new
/// tabs go. The Mac's words (`Firn/Overflow.swift`).
struct TidiedSheet: View {
    let store: BrowserStore
    /// Shows a tab and puts this sheet away.
    let open: (FirnCore.Tab) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The site's icon grows with the text, as History's does.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.driftedTabs) { row($0) }
                } footer: {
                    Text("Tabs you haven’t looked at in a while. They’re deleted after 30 days.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tidied Away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restore All") {
                        dismiss()
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.restoreAllDrifted() }
                    }
                    .tint(Theme.ink)
                    .accessibilityHint("Brings these tabs back.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                        .tint(Theme.ink)
                }
            }
        }
        .tint(Theme.ink)
        .presentationDetents([.large])
        .onAppear { store.markTidiedSeen() }
        // The last one closed: nothing left to show.
        .onChange(of: store.driftedTabs.isEmpty) { _, empty in if empty { dismiss() } }
    }

    private func row(_ tab: FirnCore.Tab) -> some View {
        let large = typeSize.isAccessibilitySize
        let site = WebAddress.site(of: tab.url)
        return Button { open(tab) } label: {
            HStack(spacing: 12) {
                SiteIconView(icon: tab.icon, size: iconSize) { LetterMark(site: site) }
                VStack(alignment: .leading, spacing: 2) {
                    // `Color`, not `.primary`: inside a list's button the
                    // style would follow the tint.
                    Text(tab.title.isEmpty ? site : tab.title)
                        .foregroundStyle(Color.primary)
                        .lineLimit(large ? 2 : 1)
                    Text(site)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .truncationMode(.tail)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Brings this tab back and shows it.")
        .contextMenu {
            if let url = tab.url {
                Button("Copy Link", systemImage: "link") { UIPasteboard.general.url = url }
                Divider()
            }
            Button("Close Tab", systemImage: "xmark", role: .destructive) { close(tab) }
        }
        .swipeActions(edge: .trailing) {
            // iOS's red, said outright: the sheet's ink tint would take it.
            Button("Close", systemImage: "xmark", role: .destructive) { close(tab) }
                .tint(.red)
        }
    }

    private func close(_ tab: FirnCore.Tab) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { store.close(tab) }
    }
}
