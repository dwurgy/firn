import FirnCore
import Observation
import UIKit

/// Lets pages out of sight sleep, so many open tabs stay light on a phone.
/// iOS is much stricter about memory than the Mac (it ends an app that uses
/// too much), so beyond the tab on screen only the two seen most recently
/// stay awake (`BrowserStore.sleepIdleTabs(keepingRecent:)`). A sleeping tab
/// keeps its place and back history, and pages playing sound or holding
/// unsent text never sleep. It checks a moment after the tab on screen
/// changes, and at once when iOS says memory is short; nothing runs on a
/// timer.
@MainActor
final class TabSleeper {
    static let keepAwake = 2

    private let store: BrowserStore
    private var check: Task<Void, Never>?
    /// A short-of-memory check asked for while another was running.
    private var memoryIsShortAgain = false
    private var warning: (any NSObjectProtocol)?

    init(store: BrowserStore) {
        self.store = store
    }

    func start() {
        watchTabOnScreen()
        warning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepIdleTabs(memoryIsShort: true) }
        }
    }

    private func watchTabOnScreen() {
        withObservationTracking {
            _ = store.activeTabID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.watchTabOnScreen()
                self?.sleepIdleTabs(memoryIsShort: false)
            }
        }
    }

    private func sleepIdleTabs(memoryIsShort: Bool) {
        guard check == nil else {
            memoryIsShortAgain = memoryIsShortAgain || memoryIsShort
            return
        }
        check = Task { @MainActor in
            if memoryIsShort {
                await store.sleepIdleTabs(memoryIsShort: true)
            } else {
                // After the switch has settled, so it's never slowed.
                try? await Task.sleep(for: .seconds(2))
                await store.sleepIdleTabs(keepingRecent: Self.keepAwake)
            }
            check = nil
            if memoryIsShortAgain {
                memoryIsShortAgain = false
                sleepIdleTabs(memoryIsShort: true)
            }
        }
    }
}
