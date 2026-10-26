import FirnCore
import SwiftUI

/// Firn's settings, kept in the app's own preferences (inside its sandbox).
/// They're about how Firn behaves, not what's open, so they live apart
/// from the session file.
enum Preference {
    static let newTabPlacement = "newTabPlacement"
    static let driftAfter = "driftAfter"
    static let blocksContent = "blocksContent"
    static let searchEngine = "searchEngine"
    /// Whether typing in the command bar asks the search engine for
    /// suggestions. Off until someone says yes: it's the one place typing
    /// goes over the network.
    static let searchSuggestions = "searchSuggestions"
    /// Saved now; the "At the top" look that reads it is a later step.
    static let addressBar = "addressBar"
    /// Set once the welcome has been finished or skipped.
    static let welcomed = "welcomed"

    /// The "Block ads and trackers" setting before any view has read it (on by default).
    static var blocksContentAtLaunch: Bool {
        UserDefaults.standard.object(forKey: blocksContent) as? Bool ?? true
    }
}

/// The Settings window (⌘, or Firn › Settings…): a few plain choices, and
/// the saved passwords, in panes picked from a sidebar on the left, as in
/// Dia (David, 2026-10-25), rather than Safari's row of tabs.
struct SettingsView: View {
    let window: WindowModel

    /// Every pane is the same size, so the window never jumps between them.
    static let size = CGSize(width: 720, height: 520)

    private static var keepsToolbarTall: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
    }

    /// The pane open last time.
    @AppStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        NavigationSplitView {
            // A list selection can be empty; Settings always shows a pane.
            List(SettingsPane.allCases, selection: Binding { pane } set: { pane = $0 ?? pane }) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    // Glacier, not the system's blue (the selected row's
                    // highlight is already Firn's accent).
                    Image(systemName: pane.symbol)
                        .foregroundStyle(pane == self.pane ? Color.white : Theme.accent)
                }
            }
            .navigationSplitViewColumnWidth(190)
            // Warmed by the frame's color, as the browser's sidebar is.
            .scrollContentBackground(.hidden)
            .background(Theme.frameWash.ignoresSafeArea())
            // Settings always shows its sidebar: there's nothing to hide it for.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralSettings(window: window)
                case .tabs: TabsSettings()
                case .spaces: SpacesSettings(window: window)
                case .privacy: PrivacySettings()
                case .passwords: PasswordsSettings(store: window.store)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page.ignoresSafeArea())
            .modifier(FrauncesWindowTitle(title: pane.title))
            // An empty toolbar shrinks to a thin title bar, with the traffic
            // lights in the corner; one invisible item keeps it full height,
            // as the History window's search field does there.
            .toolbar {
                if #available(macOS 26, *) {
                    // No glass capsule around it, which would show as a sliver.
                    ToolbarItem(placement: .primaryAction) { Self.keepsToolbarTall }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) { Self.keepsToolbarTall }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The History window's look: Firn's page color, under the toolbar too.
        .modifier(PageBackground())
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, tabs, spaces, privacy, passwords

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .tabs: "Tabs"
        case .spaces: "Spaces"
        case .privacy: "Privacy"
        case .passwords: "Passwords"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .spaces: "square.stack"
        case .privacy: "hand.raised"
        case .passwords: "key"
        }
    }
}

/// The small muted line under a setting that says what it does.
struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings › General: search, updates, and bringing things over from Arc.
private struct GeneralSettings: View {
    let window: WindowModel
    @State private var startingArcImport = false
    @Bindable private var updater = Updater.shared
    @AppStorage(Preference.searchEngine) private var searchEngine = SearchEngine.default
    @AppStorage(Preference.searchSuggestions) private var searchSuggestions = false

    var body: some View {
        Form {
            // The address bar's place ("In the sidebar" or "At the top") comes
            // back here, and in the welcome, once the "At the top" look exists
            // (David, 2026-10-23); until then the choice would change nothing.
            Section {
                Picker("Search with", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show suggestions as you type", isOn: $searchSuggestions)
            } footer: {
                SettingsFootnote("With suggestions on, your search engine sees what you type.")
            }
            Section {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
            } footer: {
                SettingsFootnote("Once a day, Firn asks firnbrowser.com whether a new version is out. Only Firn's version number goes along, nothing about your browsing.")
            }
            Section {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Arc")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                        Text("Brings over Arc's spaces, favorites, and pinned tabs, as new spaces.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 12)
                    Button("Import…") { startingArcImport = true }
                        .accessibilityLabel("Import from Arc")
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .modifier(ArcImportFlow(starting: $startingArcImport, window: window))
    }
}

/// Settings › Tabs: where new tabs go, and when idle ones are tidied away.
private struct TabsSettings: View {
    @AppStorage(Preference.newTabPlacement) private var newTabPlacement = NewTabPlacement.bottom
    @AppStorage(Preference.driftAfter) private var driftAfter = DriftAfter.sevenDays

    var body: some View {
        Form {
            Section {
                Picker("New tabs open", selection: $newTabPlacement) {
                    Text("At the top").tag(NewTabPlacement.top)
                    Text("At the bottom").tag(NewTabPlacement.bottom)
                }
                .pickerStyle(.radioGroup)
                // Radio buttons draw in the system's blue unless tinted.
                .tint(Theme.accent)
            } footer: {
                SettingsFootnote("The New tab button sits there too. Tabs taken out of a group arrive there as well.")
            }
            Section {
                Picker("Tidy away tabs after", selection: $driftAfter) {
                    Text("1 day").tag(DriftAfter.oneDay)
                    Text("7 days").tag(DriftAfter.sevenDays)
                    Text("30 days").tag(DriftAfter.thirtyDays)
                    Text("Never").tag(DriftAfter.never)
                }
            } footer: {
                SettingsFootnote("Tabs you haven't looked at in a while are tidied away into a box that appears by your spaces, and deleted 30 days later. Only days you use Firn count. Basecamp and grouped tabs stay put.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings › Privacy: blocking ads and trackers.
private struct PrivacySettings: View {
    @AppStorage(Preference.blocksContent) private var blocksContent = true

    var body: some View {
        Form {
            Section {
                Toggle("Block ads and trackers", isOn: $blocksContent)
            } footer: {
                SettingsFootnote("Uses the EasyList and EasyPrivacy lists, which come with Firn. To let one site show its ads, open it and choose Stop Blocking from the View menu; each space keeps its own choices.")
            }
        }
        .formStyle(.grouped)
    }
}

/// A card in Settings: Firn's frost, as the Basecamp tiles and group cards
/// have it (a soft fill, a light rim along the top, a warm hairline), on
/// the page color, in place of the system's grey grouped box.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(Theme.tileFill) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
    }
}

/// One line in a settings card: a label on the left, its control after it.
struct SettingsCardRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Theme.tabFont)
                .foregroundStyle(Theme.ink)
                .frame(width: 80, alignment: .leading)
                .accessibilityHidden(true)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A text field drawn as the New space card's: a warm wash, the frost ring
/// while typing in it.
struct FirnTextField: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.tabFont)
            .foregroundStyle(Theme.ink)
            .focused(focused)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).fill(Theme.hover)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                    .strokeBorder(focused.wrappedValue ? Theme.frost : .clear, lineWidth: 2)
            }
    }
}
