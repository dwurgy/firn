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
/// the saved passwords.
struct SettingsView: View {
    let window: WindowModel

    /// Every tab is the same size, so the window never jumps between them.
    static let size = CGSize(width: 540, height: 500)

    var body: some View {
        TabView {
            GeneralSettings(window: window)
                .tabItem { Label("General", systemImage: "gearshape") }
            PasswordsSettings(store: window.store)
                .tabItem { Label("Passwords", systemImage: "key") }
        }
    }
}

/// Settings › General: a few plain choices, no more.
private struct GeneralSettings: View {
    let window: WindowModel
    @State private var startingArcImport = false
    @Bindable private var updater = Updater.shared
    @AppStorage(Preference.newTabPlacement) private var newTabPlacement = NewTabPlacement.bottom
    @AppStorage(Preference.driftAfter) private var driftAfter = DriftAfter.sevenDays
    @AppStorage(Preference.blocksContent) private var blocksContent = true
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
                Text("With suggestions on, your search engine sees what you type.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Picker("New tabs open", selection: $newTabPlacement) {
                    Text("At the top").tag(NewTabPlacement.top)
                    Text("At the bottom").tag(NewTabPlacement.bottom)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("The New tab button sits there too. Tabs taken out of a group arrive there as well.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Picker("Tidy away tabs after", selection: $driftAfter) {
                    Text("1 day").tag(DriftAfter.oneDay)
                    Text("7 days").tag(DriftAfter.sevenDays)
                    Text("30 days").tag(DriftAfter.thirtyDays)
                    Text("Never").tag(DriftAfter.never)
                }
            } footer: {
                Text("Tabs you haven't looked at in a while are tidied away into a box that appears by your spaces, and deleted 30 days later. Only days you use Firn count. Basecamp and grouped tabs stay put.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Block ads and trackers", isOn: $blocksContent)
            } footer: {
                Text("Uses the EasyList and EasyPrivacy lists, which come with Firn. To let one site show its ads, open it and choose Stop Blocking from the View menu; each space keeps its own choices.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
            } footer: {
                Text("Once a day, Firn asks firnbrowser.com whether a new version is out. Only Firn's version number goes along, nothing about your browsing.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: SettingsView.size.width, height: SettingsView.size.height)
        .modifier(ArcImportFlow(starting: $startingArcImport, window: window))
    }
}
