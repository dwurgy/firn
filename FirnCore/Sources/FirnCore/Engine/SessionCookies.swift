import Foundation
import WebKit

/// Keeps people signed in across a quit (David, 2026-11-25). WebKit drops
/// every session cookie (the kind a site marks "until the browser closes")
/// when Firn quits, so sites that sign people in with those signed them out
/// each time. Firn brings tabs back, so it brings these back too, as
/// browsers that restore tabs do.
///
/// Per data store, and only its own: a separate space's never reach another.
/// Put back before the store's first page loads; kept, sealed on this Mac
/// (`SessionCookieFiles`), as they change and at quit. A store that wasn't
/// opened this time is never written, so its file stays as it was.
@MainActor
final class SessionCookies: NSObject, WKHTTPCookieStoreObserver {
    /// Off until `BrowserEngine.keepSignIns` starts it (never in a demo).
    static var shared: SessionCookies?

    private enum State {
        /// Its cookies are on their way back; loads wait here (nil once
        /// they've waited long enough, and just go).
        case opening(waiting: [() -> Void]?)
        case open(canSave: Bool)
    }

    private let files: SessionCookieFiles
    private var states: [UUID: State] = [:]
    /// The open stores, held while they're watched, and let go as soon as
    /// their space is deleted (WebKit won't erase a store in use).
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var lastSaved: [UUID: [SavedCookie]] = [:]
    private var pending: [UUID: Task<Void, Never>] = [:]

    /// Pages wait this long at most for their cookies.
    private static let patience: Duration = .seconds(2)
    private static let saveDelay: Duration = .seconds(2)

    init(files: SessionCookieFiles) {
        self.files = files
    }

    // MARK: Back in

    /// A page is about to use this store. The first time, its cookies start
    /// coming back.
    func willUse(_ store: WKWebsiteDataStore) {
        guard let id = store.identifier, states[id] == nil else { return }
        states[id] = .opening(waiting: [])
        stores[id] = store
        Task {
            let (saved, canSave) = await files.load(id)
            guard stores[id] === store else { return }
            for cookie in saved.compactMap(\.cookie) { await store.httpCookieStore.setCookie(cookie) }
            guard stores[id] === store else { return }
            if canSave {
                lastSaved[id] = saved
                store.httpCookieStore.add(self)
            }
            finishOpening(id, canSave: canSave)
        }
        Task {
            try? await Task.sleep(for: Self.patience)
            // The loads go on; saving still waits until every cookie is in.
            runWaiting(id)
        }
    }

    /// Runs `load` now, or once the store's cookies are in.
    func whenReady(_ store: WKWebsiteDataStore, _ load: @escaping () -> Void) {
        guard let id = store.identifier, case let .opening(waiting?) = states[id] else { return load() }
        states[id] = .opening(waiting: waiting + [load])
    }

    private func runWaiting(_ id: UUID) {
        guard case let .opening(waiting?) = states[id] else { return }
        states[id] = .opening(waiting: nil)
        for load in waiting { load() }
    }

    private func finishOpening(_ id: UUID, canSave: Bool) {
        guard case let .opening(waiting) = states[id] else { return }
        states[id] = .open(canSave: canSave)
        for load in waiting ?? [] { load() }
    }

    // MARK: Kept

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        MainActor.assumeIsolated {
            guard let id = stores.first(where: { $0.value.httpCookieStore === cookieStore })?.key,
                  pending[id] == nil else { return }
            pending[id] = Task {
                try? await Task.sleep(for: Self.saveDelay)
                guard !Task.isCancelled else { return }
                pending[id] = nil
                guard let store = stores[id] else { return }
                let cookies = await store.httpCookieStore.allCookies()
                save(cookies, for: id, wait: false)
            }
        }
    }

    private func save(_ cookies: [HTTPCookie], for id: UUID, wait: Bool) {
        guard case .open(canSave: true) = states[id] else { return }
        let kept = cookies.compactMap(SavedCookie.init)
            .sorted { ($0.domain, $0.path, $0.name, $0.value) < ($1.domain, $1.path, $1.name, $1.value) }
        guard wait || kept != lastSaved[id] else { return }
        lastSaved[id] = kept
        files.save(kept, for: id, wait: wait)
    }

    /// At quit: every open store once more. WebKit answers through the run
    /// loop, so this turns it, for a second at most.
    func saveNow() {
        for task in pending.values { task.cancel() }
        pending = [:]
        var left = 0
        for (id, state) in states {
            guard case .open(canSave: true) = state, let store = stores[id] else { continue }
            left += 1
            store.httpCookieStore.getAllCookies { [weak self] cookies in
                MainActor.assumeIsolated {
                    self?.save(cookies, for: id, wait: true)
                    left -= 1
                }
            }
        }
        let end = Date().addingTimeInterval(1)
        while left > 0, Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: Gone

    /// No space uses the store any more: it's let go, and its file erased.
    func erase(_ id: UUID) {
        pending.removeValue(forKey: id)?.cancel()
        if let store = stores.removeValue(forKey: id) { store.httpCookieStore.remove(self) }
        lastSaved[id] = nil
        // Whatever still waited goes on without cookies.
        finishOpening(id, canSave: false)
        files.erase(id)
    }

    func removeUnused(keeping: Set<UUID>) {
        files.removeUnused(keeping: keeping)
    }
}

extension BrowserEngine {
    /// Keeps people signed in across a quit (`SessionCookies`). Call once at
    /// launch, before any page is made; never in a demo.
    @MainActor public static func keepSignIns() {
        guard SessionCookies.shared == nil else { return }
        SessionCookies.shared = SessionCookies(files: SessionCookieFiles(
            directory: URL.applicationSupportDirectory.appending(path: "Firn/Session Cookies", directoryHint: .isDirectory),
            key: KeychainSessionCookieKey()))
    }

    /// At quit.
    @MainActor public static func saveSignIns() {
        SessionCookies.shared?.saveNow()
    }
}
