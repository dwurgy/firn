import Foundation
import WebKit

/// Blocks ads and trackers in every page with the lists that ship inside Firn
/// (`BlockList`). Each list is converted and compiled once per version, in the
/// background, and WebKit keeps the compiled rules between launches.
///
/// Pages never wait for this: one made before the rules are ready gets them
/// the moment they are, so on the very first launch (or after a list
/// update) the first pages may load unblocked.
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker(store: .default())

    /// Raise when the converter changes what it writes, so lists compile again.
    nonisolated static let converterVersion = 1
    nonisolated static let identifierPrefix = "firn-"

    private let store: WKContentRuleListStore
    private(set) var lists: [WKContentRuleList] = []
    /// Every page's content controller, so rules that arrive later reach it.
    /// Weak: a closed page's controller simply drops out.
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private var started = false

    init(store: WKContentRuleListStore) {
        self.store = store
    }

    /// Gives a new page the rules, now or once they're ready.
    func attach(_ controller: WKUserContentController) {
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        for list in lists { controller.add(list) }
    }

    /// Finds or compiles each list, then removes compiled lists no longer used.
    func start(_ blockLists: [BlockList] = BlockList.allCases) async {
        guard !started else { return }
        started = true
        var current: Set<String> = []
        for blockList in blockLists {
            guard let text = await Task.detached(operation: { blockList.text() }).value else { continue }
            let identifier = await Task.detached { Self.identifier(for: blockList, text: text) }.value
            current.insert(identifier)
            if let found = await store.lookUp(identifier) {
                add(found)
                continue
            }
            let json = await Task.detached { BlockListConverter.convert(text).json }.value
            if let compiled = try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) {
                add(compiled)
            }
        }
        for old in await store.availableIdentifiers() where old.hasPrefix(Self.identifierPrefix) && !current.contains(old) {
            await store.remove(old)
        }
    }

    private func add(_ list: WKContentRuleList) {
        lists.append(list)
        for controller in controllers.allObjects { controller.add(list) }
    }

    /// "firn-easylist-…": the list's name and a fingerprint of its text and
    /// the converter, so a new list or converter compiles afresh.
    nonisolated static func identifier(for list: BlockList, text: String) -> String {
        // FNV-1a: stable across launches, unlike Swift's own hashing.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return "\(identifierPrefix)\(list.rawValue)-\(converterVersion)-\(String(hash, radix: 16))"
    }
}

/// Callback calls WebKit doesn't offer as async.
private extension WKContentRuleListStore {
    func lookUp(_ identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            lookUpContentRuleList(forIdentifier: identifier) { list, _ in continuation.resume(returning: list) }
        }
    }

    func remove(_ identifier: String) async {
        await withCheckedContinuation { continuation in
            removeContentRuleList(forIdentifier: identifier) { _ in continuation.resume() }
        }
    }

    func availableIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
    }
}
