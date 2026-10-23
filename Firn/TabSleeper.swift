import Dispatch
import FirnCore
import Observation

/// Lets pages out of sight for a while sleep (`BrowserStore.sleepIdleTabs`),
/// so many open tabs stay light. It checks a moment after the tab on screen
/// changes, and at once when the Mac says memory is running short; nothing
/// runs on a timer.
@MainActor
final class TabSleeper {
    private let store: BrowserStore
    private var pressure: DispatchSourceMemoryPressure?
    private var check: Task<Void, Never>?
    /// A short-of-memory check asked for while another was running.
    private var memoryIsShortAgain = false

    init(store: BrowserStore) {
        self.store = store
    }

    func start() {
        watchTabOnScreen()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.sleepIdleTabs(memoryIsShort: true) }
        }
        source.resume()
        pressure = source
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
            // After the switch has settled, so it's never slowed.
            if !memoryIsShort { try? await Task.sleep(for: .seconds(2)) }
            await store.sleepIdleTabs(memoryIsShort: memoryIsShort)
            check = nil
            if memoryIsShortAgain {
                memoryIsShortAgain = false
                sleepIdleTabs(memoryIsShort: true)
            }
        }
    }
}
