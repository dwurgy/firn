import FirnCore
import SwiftUI

/// Firn's settings, kept in the app's own preferences (inside its sandbox).
/// They're about how Firn behaves, not what's open, so they live apart
/// from the session file.
enum Preference {
    static let newTabPlacement = "newTabPlacement"
}

/// The Settings window (⌘, or Firn › Settings…): a few plain choices, no more.
struct SettingsView: View {
    @AppStorage(Preference.newTabPlacement) private var newTabPlacement = NewTabPlacement.bottom

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
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
