import FirnCore
import Foundation

/// Demo mode, for the website's screenshots and videos: Firn started with
/// `--demo` runs on its own throwaway data, so nothing from David's real
/// browsing shows up and nothing in it is changed.
///
/// - The session and history live in `Application Support/Firn/Demo`,
///   wiped at every demo launch, then seeded with `DemoSession`'s three
///   spaces and two weeks of history, so each demo starts the same. Its
///   sites' icons are fetched at launch, and the welcome is skipped.
/// - Its spaces get new data stores (sign-ins, cookies); the real ones are
///   never erased or read. The last demo's stores are erased as the next
///   demo starts, and any left over at the next real launch.
/// - Saved passwords are kept in memory only; the Keychain isn't touched.
/// - Settings start empty: the real ones are set aside in a file and put
///   back at the next real launch (even if the demo crashed).
/// - No update checks.
enum DemoMode {
    static let isOn = ProcessInfo.processInfo.arguments.contains("--demo")

    private static let support = URL.applicationSupportDirectory.appending(path: "Firn")
    private static let folder = support.appending(path: "Demo")
    /// Outside `Demo`, so wiping a demo never loses the real settings.
    private static let savedSettings = support.appending(path: "settings-before-demo.plist")

    static var sessionFile: SessionFile {
        isOn ? SessionFile(url: folder.appending(path: "session.json")) : .standard
    }

    /// Where a screenshot's window number goes (`DemoShot`): the real
    /// Downloads folder, the one place outside Firn's sandbox it may write
    /// and the script may read. Hidden, and removed after each shot.
    static var shotReadyFile: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(filePath: home).appending(path: "Downloads/.firn-demo-shot")
    }

    static let history = isOn ? HistoryStore(directory: folder.appending(path: "History")) : .standard

    static let passwords = isOn ? PasswordStore(vault: MemoryVault()) : .keychain

    /// Call first thing at launch, before anything reads a setting.
    @MainActor static func prepare() {
        if isOn {
            startDemo()
            seed()
        } else {
            putBackRealSettings()
        }
    }

    @MainActor private static func startDemo() {
        // The last demo's spaces' website data, then its files.
        if let last = SessionFile(url: folder.appending(path: "session.json")).load() {
            for space in last.spaces { BrowserEngine.removeData(for: space.dataStoreID) }
        }
        try? FileManager.default.removeItem(at: folder)

        // Set the real settings aside (unless a demo already did: what's
        // there now are the demo's), then start with none.
        guard let domain = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        if !FileManager.default.fileExists(atPath: savedSettings.path(percentEncoded: false)) {
            let real = defaults.persistentDomain(forName: domain) ?? [:]
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            guard (try? PropertyListSerialization.data(fromPropertyList: real, format: .binary, options: 0)
                .write(to: savedSettings, options: .atomic)) != nil
            else {
                // Couldn't keep a copy, so don't touch them.
                return
            }
        }
        defaults.removePersistentDomain(forName: domain)
        // The welcome is skipped: the demo starts as someone's own Firn.
        defaults.set(true, forKey: Preference.welcomed)
    }

    /// Writes the demo's ready-made session, before the store loads it, and
    /// its history (in the background; it's there well before ⌘Y).
    @MainActor private static func seed() {
        let (session, visits) = DemoSession.make()
        try? SessionFile(url: folder.appending(path: "session.json")).save(session)
        Task.detached(priority: .utility) {
            for visit in visits {
                await history.record(visit.url, title: visit.title, at: visit.time, in: visit.dataStoreID)
            }
        }
    }

    /// Fetches the demo sites' icons, so tiles and resting tabs show them.
    @MainActor static func fetchIcons(for store: BrowserStore) {
        guard isOn else { return }
        Task { await DemoSession.fetchIcons(for: store) }
    }

    private static func putBackRealSettings() {
        guard let domain = Bundle.main.bundleIdentifier,
              let data = try? Data(contentsOf: savedSettings),
              let real = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        UserDefaults.standard.setPersistentDomain(real, forName: domain)
        try? FileManager.default.removeItem(at: savedSettings)
    }
}

/// The demo's saved passwords: a plain list in memory, gone at quit.
private final class MemoryVault: PasswordVault, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [SavedLogin] = []

    func save(_ login: SavedLogin) throws {
        lock.withLock {
            saved.removeAll { same($0, login) }
            saved.append(login)
        }
    }

    func logins(in dataStoreID: UUID, for site: PasswordSite?) throws -> [SavedLogin] {
        lock.withLock { saved.filter { $0.dataStoreID == dataStoreID && (site == nil || $0.site == site) } }
    }

    func delete(_ login: SavedLogin) throws {
        lock.withLock { saved.removeAll { same($0, login) } }
    }

    func deleteAll(in dataStoreID: UUID) throws {
        lock.withLock { saved.removeAll { $0.dataStoreID == dataStoreID } }
    }

    func dataStoreIDs() throws -> Set<UUID> {
        lock.withLock { Set(saved.map(\.dataStoreID)) }
    }

    private func same(_ a: SavedLogin, _ b: SavedLogin) -> Bool {
        a.dataStoreID == b.dataStoreID && a.site == b.site && a.username == b.username
    }
}
