import Sparkle
import SwiftUI

/// Firn's updates, through Sparkle. A check is one plain request for
/// firnbrowser.com/appcast.xml (no system profile), and Sparkle installs an
/// update only if it's signed with Firn's key. Sparkle asks on the second
/// launch whether to check automatically; Settings › General can change it.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    /// False while a check is already running, so the menu item waits.
    private(set) var canCheck = false

    var checksAutomatically: Bool {
        get { automatic }
        set {
            automatic = newValue
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private var automatic = false
    // Sparkle's standard controller: its own window for a found update.
    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    @ObservationIgnored private var watching: [NSKeyValueObservation] = []

    private init() {
        let updater = controller.updater
        automatic = updater.automaticallyChecksForUpdates
        // Sparkle changes these itself (its second-launch question, a running
        // check); follow along so the menu and Settings stay true.
        watching = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automatic = updater.automaticallyChecksForUpdates }
            },
        ]
    }

    /// Firn › Check for Updates…: shows Sparkle's window either way, so a
    /// person always sees an answer.
    func checkNow() {
        controller.checkForUpdates(nil)
    }
}
