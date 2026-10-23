import FirnCore
import SwiftUI

/// Firn's settings, kept in the app's own preferences (inside its sandbox).
/// They're about how Firn behaves, not what's open, so they live apart
/// from the session file.
enum Preference {
    static let newTabPlacement = "newTabPlacement"
    static let driftAfter = "driftAfter"
    static let blocksContent = "blocksContent"

    /// The "Block ads and trackers" setting before any view has read it (on by default).
    static var blocksContentAtLaunch: Bool {
        UserDefaults.standard.object(forKey: blocksContent) as? Bool ?? true
    }
}

/// The Settings window (⌘, or Firn › Settings…): a few plain choices, no more.
struct SettingsView: View {
    @AppStorage(Preference.newTabPlacement) private var newTabPlacement = NewTabPlacement.bottom
    @AppStorage(Preference.driftAfter) private var driftAfter = DriftAfter.sevenDays
    @AppStorage(Preference.blocksContent) private var blocksContent = true

    var body: some View {
        Form {
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
                Text("Tabs you haven't looked at in a while are tidied away into the clock button by your spaces, and deleted 30 days later. Only days you use Firn count. Basecamp and grouped tabs stay put.")
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
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
