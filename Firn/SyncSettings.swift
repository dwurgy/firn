import CloudKit
import SwiftUI

/// Settings › Sync (docs/SYNC-PLAN.md, step 3, part 3): one switch, "Sync
/// with iCloud", off until the person turns it on. The Passwords switch
/// joins it in step 8, once it would do something.
///
/// The switch reads the saved setting, so it also goes off by itself when
/// the engine turns sync off (signed out of iCloud, another account, or
/// Firn's data deleted in iCloud's settings).
struct SyncSettings: View {
    let sync: ICloudSync

    @AppStorage(ICloudSync.enabledKey) private var isOn = false
    @State private var availability = ICloudSync.Availability.available

    var body: some View {
        SettingsPage {
            SettingsGroup(footer: footer) {
                SettingsLine("Sync with iCloud", caption: caption) {
                    SettingsSwitch("Sync with iCloud", isOn: Binding(
                        get: { isOn && canSync },
                        set: { $0 ? sync.turnOn() : sync.turnOff() }
                    ))
                    .disabled(!canSync)
                }
            }
        }
        .task { await refresh() }
        // Signed in or out of iCloud while Settings is open.
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await refresh() }
        }
    }

    private var canSync: Bool { availability == .available && !DemoMode.isOn }

    /// Why the switch can't be used, when it can't.
    private var caption: String? {
        if DemoMode.isOn { return "Not in demo mode." }
        switch availability {
        case .available: return nil
        case .signedOut: return "Sign in to iCloud in System Settings to use sync."
        case .unavailable: return "iCloud isn’t available on this Mac."
        }
    }

    private var footer: String {
        "Keeps your spaces the same on your Mac, iPhone, and iPad, through your own iCloud. They’re encrypted on this Mac, so only your devices can read them. Sign-ins stay on each device, so a separate space starts signed out on the others."
    }

    private func refresh() async {
        guard !DemoMode.isOn else { return }
        availability = await ICloudSync.availability()
    }
}
