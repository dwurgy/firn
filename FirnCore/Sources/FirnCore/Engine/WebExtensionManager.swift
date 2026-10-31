#if os(macOS)
import AppKit
import Foundation
import Observation
import WebKit

@MainActor @Observable @available(macOS 15.4, *)
public final class WebExtensionManager: NSObject, WKWebExtensionControllerDelegate {
    public static let shared: WebExtensionManager = {
        let manager = WebExtensionManager(library: .shared)
        manager.isSharedManager = true
        return manager
    }()
    public let library: WebExtensionLibrary
    public private(set) var errors: [UUID: String] = [:]

    @ObservationIgnored fileprivate weak var store: BrowserStore?
    @ObservationIgnored private var controllers: [UUID: WKWebExtensionController] = [:]
    @ObservationIgnored private var contexts: [UUID: [UUID: WKWebExtensionContext]] = [:]
    @ObservationIgnored fileprivate var windows: [UUID: ExtensionWindow] = [:]
    @ObservationIgnored private var tabs: [UUID: ExtensionTab] = [:]
    @ObservationIgnored private var loading = Set<String>()
    @ObservationIgnored private var revisions: [UUID: Int] = [:]
    @ObservationIgnored private var knownMemberships: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var cleaningRemovals = Set<UUID>()
    @ObservationIgnored private var popupRequest: (storeID: UUID, context: WKWebExtensionContext, anchor: NSView)?
    @ObservationIgnored private weak var visiblePopup: NSPopover?
    @ObservationIgnored private var isSharedManager = false

    public init(library: WebExtensionLibrary) {
        self.library = library
        super.init()
    }

    public func connect(to store: BrowserStore) {
        guard BrowserEngine.mayUseExtensions else { return }
        if isSharedManager { BrowserEngine.didUseExtensionManager() }
        self.store = store
        knownMemberships = Dictionary(uniqueKeysWithValues: library.extensions.map { ($0.id, $0.enabledDataStoreIDs) })
        library.onChange = { [weak self] in self?.reconcile() }
        reconcile()
        watchStore()
    }

    func disable() {
        for id in controllers.keys { revisions[id, default: 0] += 1 }
        popupRequest = nil
        visiblePopup?.close()
        for (storeID, entries) in contexts {
            guard let controller = controllers[storeID] else { continue }
            for context in entries.values { try? controller.unload(context) }
        }
        contexts.removeAll()
        controllers.removeAll()
        windows.removeAll()
        tabs.removeAll()
    }

    func controller(for dataStoreID: UUID) -> WKWebExtensionController? {
        guard BrowserEngine.mayUseExtensions else { return nil }
        if isSharedManager { BrowserEngine.didUseExtensionManager() }
        if let existing = controllers[dataStoreID] { return existing }
        let dataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        let configuration = WKWebExtensionController.Configuration(identifier: dataStoreID)
        configuration.defaultWebsiteDataStore = dataStore
        configuration.webViewConfiguration.websiteDataStore = dataStore
        configuration.webViewConfiguration.userContentController.addUserScript(WKUserScript(
            source: WebExtensionCompatibility.source, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = self
        controllers[dataStoreID] = controller
        windows[dataStoreID] = ExtensionWindow(dataStoreID: dataStoreID, manager: self)
        controller.didOpenWindow(windows[dataStoreID]!)
        reconcile()
        return controller
    }

    private func reconcile() {
        guard BrowserEngine.mayUseExtensions else { return }
        let current = Dictionary(uniqueKeysWithValues: library.extensions.map { ($0.id, $0.enabledDataStoreIDs) })
        for (id, pendingStores) in library.pendingRemovals where !cleaningRemovals.contains(id) {
            cleaningRemovals.insert(id)
            let priorStores = pendingStores.union(knownMemberships[id] ?? [])
            Task { [weak self] in
                guard let self else { return }
                defer { cleaningRemovals.remove(id) }
                let stores = Set(await WKWebsiteDataStore.allDataStoreIdentifiers).union(priorStores)
                var completed = true
                for storeID in stores {
                    if !(await removeOwnedData(for: id, in: storeID)) { completed = false }
                }
                if completed {
                    do { try library.completeRemoval(id: id); knownMemberships[id] = nil }
                    catch { errors[id] = "Extension data removal will be retried next time Firn opens." }
                }
            }
        }
        for (id, stores) in current { knownMemberships[id, default: []].formUnion(stores) }
        for (storeID, controller) in controllers {
            revisions[storeID, default: 0] += 1
            let desired = library.extensions.filter { $0.enabledDataStoreIDs.contains(storeID) }
            let desiredIDs = Set(desired.map(\.id))
            for (id, context) in contexts[storeID] ?? [:] where !desiredIDs.contains(id) {
                if popupRequest?.context === context { popupRequest = nil; visiblePopup?.close() }
                do { try controller.unload(context) }
                catch { errors[id] = "Extension data could not be removed."; continue }
                contexts[storeID]?[id] = nil
            }
            for record in desired where contexts[storeID]?[record.id] == nil && !loading.contains("\(storeID):\(record.id)") {
                loading.insert("\(storeID):\(record.id)")
                Task { [weak self] in await self?.load(record, in: storeID, controller: controller) }
            }
        }
    }

    private func load(_ record: InstalledWebExtension, in storeID: UUID, controller: WKWebExtensionController) async {
        let revision = revisions[storeID, default: 0]
        defer {
            loading.remove("\(storeID):\(record.id)")
            if revisions[storeID, default: 0] != revision { reconcile() }
        }
        guard BrowserEngine.mayUseExtensions, controllers[storeID] === controller else { return }
        guard library.extensions.contains(where: { $0.id == record.id && $0.enabledDataStoreIDs.contains(storeID) }) else { return }
        do {
            let ext = try await WKWebExtension(resourceBaseURL: library.archiveURL(for: record.id))
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = record.id.uuidString
            context.baseURL = URL(string: "webkit-extension://\(record.id.uuidString.lowercased())/")!
            context.unsupportedAPIs = ["browser.runtime.connectNative", "browser.runtime.sendNativeMessage", "browser.notifications"]
            var grants: [WKWebExtension.Permission: Date] = [:]
            for permission in record.permissions where permission != "nativeMessaging" && permission != "notifications" {
                grants[WKWebExtension.Permission(rawValue: permission)] = .distantFuture
            }
            context.grantedPermissions = grants
            var hosts: [WKWebExtension.MatchPattern: Date] = [:]
            for pattern in record.hostPatterns {
                for safe in Self.webPatterns(for: pattern) {
                    if let parsed = try? WKWebExtension.MatchPattern(string: safe) { hosts[parsed] = .distantFuture }
                }
            }
            context.grantedPermissionMatchPatterns = hosts
            guard BrowserEngine.mayUseExtensions, controllers[storeID] === controller,
                  revisions[storeID, default: 0] == revision,
                  library.extensions.contains(where: { $0.id == record.id && $0.enabledDataStoreIDs.contains(storeID) }) else { return }
            contexts[storeID, default: [:]][record.id] = context
            do { try controller.load(context) } catch {
                contexts[storeID]?[record.id] = nil
                throw error
            }
            errors[record.id] = nil
            refreshTabs(in: storeID)
        } catch { errors[record.id] = "The extension could not be loaded in this space." }
    }

    private static func webPatterns(for pattern: String) -> [String] {
        if pattern == "<all_urls>" { return ["http://*/*", "https://*/*"] }
        if pattern.hasPrefix("*://") { return ["http://" + pattern.dropFirst(4), "https://" + pattern.dropFirst(4)] }
        return pattern.hasPrefix("http://") || pattern.hasPrefix("https://") ? [pattern] : []
    }

    func allowsExtensionNavigation(_ target: URL, from source: URL?, in storeID: UUID) -> Bool {
        guard ownsExtensionURL(target, in: storeID),
              let controller = controllers[storeID], let context = controller.extensionContext(for: target) else { return false }
        // A top-level extension page may navigate within its own context. External
        // pages cannot manufacture extension URLs, even if they know the ID.
        return source.flatMap { controller.extensionContext(for: $0) } === context
    }

    func ownsExtensionURL(_ url: URL, in storeID: UUID) -> Bool {
        guard BrowserEngine.mayUseExtensions, url.scheme == "webkit-extension",
              let context = controllers[storeID]?.extensionContext(for: url) else { return false }
        return contexts[storeID]?.values.contains(where: { $0 === context }) == true
    }

    private func extensionPage(_ url: URL, in storeID: UUID) -> WebKitPageController? {
        guard let controller = controllers[storeID], ownsExtensionURL(url, in: storeID) else { return nil }
        guard let context = controller.extensionContext(for: url),
              let configuration = context.webViewConfiguration,
              configuration.webExtensionController === controller,
              configuration.websiteDataStore.identifier == storeID else { return nil }
        return WebKitPageController(configuration: configuration, isPopup: false)
    }

    private func cleanupController(for storeID: UUID) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(identifier: storeID)
        let dataStore = WKWebsiteDataStore(forIdentifier: storeID)
        configuration.defaultWebsiteDataStore = dataStore
        configuration.webViewConfiguration.websiteDataStore = dataStore
        return WKWebExtensionController(configuration: configuration)
    }

    public func performAction(id: UUID, in dataStoreID: UUID, for page: (any PageController)?, anchor: NSView) {
        guard BrowserEngine.mayUseExtensions, let store = store,
              store.spaces.contains(where: { $0.dataStoreID == dataStoreID }),
              let context = contexts[dataStoreID]?[id], context.isLoaded else { return }
        let tab = page.flatMap { page in tabs.values.first { $0.dataStoreID == dataStoreID && $0.page === page } }
        guard page == nil || tab != nil else { return }
        popupRequest = (dataStoreID, context, anchor)
        if let tab { context.userGesturePerformed(in: tab) }
        context.performAction(for: tab)
    }

    @discardableResult public func removeData(for dataStoreID: UUID) async -> Bool {
        revisions[dataStoreID, default: 0] += 1
        do { try library.removeData(for: dataStoreID) }
        catch { errors[dataStoreID] = "Extension data could not be removed from this space."; return false }
        let controller = controllers[dataStoreID] ?? cleanupController(for: dataStoreID)
        var unloaded = true
        for context in contexts[dataStoreID]?.values ?? Dictionary<UUID, WKWebExtensionContext>().values {
            do { try controller.unload(context) } catch { unloaded = false }
        }
        guard unloaded else {
            errors[dataStoreID] = "Extension data could not be removed from this space."
            return false
        }
        let records = await controller.dataRecords(ofTypes: WKWebExtensionController.allExtensionDataTypes)
        let ids = Set(records.map(\.uniqueIdentifier))
            .union(library.extensions.map { $0.id.uuidString })
            .union(library.pendingRemovals.keys.map(\.uuidString))
        let removed = await removeOwnedData(identifiers: ids, from: controller)
        contexts[dataStoreID] = nil
        controllers[dataStoreID] = nil
        windows[dataStoreID] = nil
        if !removed { errors[dataStoreID] = "Extension data could not be removed from this space." }
        return removed
    }

    private func removeOwnedData(for extensionID: UUID, in storeID: UUID) async -> Bool {
        let controller = controllers[storeID] ?? cleanupController(for: storeID)
        if let context = contexts[storeID]?[extensionID] {
            do { try controller.unload(context) }
            catch { errors[extensionID] = "Extension data could not be removed."; return false }
            contexts[storeID]?[extensionID] = nil
        }
        let removed = await removeOwnedData(identifiers: [extensionID.uuidString], from: controller)
        if !removed { errors[extensionID] = "Extension data could not be removed." }
        return removed
    }

    static func isOwnedWebsiteRecordName(_ displayName: String, hosts: Set<String>) -> Bool {
        let name = displayName.lowercased()
        // A bare UUID can also be an ordinary website hostname. Without an
        // explicit extension scheme, the public record has no origin provenance.
        guard let url = URLComponents(string: name), url.scheme == "webkit-extension",
              let host = url.host, let id = UUID(uuidString: host) else { return false }
        return hosts.contains(id.uuidString.lowercased())
    }

    private func removeOwnedData(identifiers: Set<String>, from controller: WKWebExtensionController) async -> Bool {
        let ownedHosts = Set(identifiers.compactMap { UUID(uuidString: $0)?.uuidString.lowercased() })
        guard !ownedHosts.isEmpty else { return true }
        let records = await controller.dataRecords(ofTypes: WKWebExtensionController.allExtensionDataTypes)
            .filter { identifiers.contains($0.uniqueIdentifier) }
        if !records.isEmpty {
            await withCheckedContinuation { continuation in
                controller.removeData(ofTypes: WKWebExtensionController.allExtensionDataTypes, from: records) {
                    continuation.resume()
                }
            }
        }
        let apiDataRemoved = records.allSatisfy { $0.errors.isEmpty }
        guard let dataStore = controller.configuration.defaultWebsiteDataStore else { return false }
        let websiteRecords = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let ownedRecords = websiteRecords.filter { Self.isOwnedWebsiteRecordName($0.displayName, hosts: ownedHosts) }
        if !ownedRecords.isEmpty {
            await withCheckedContinuation { continuation in
                dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: ownedRecords) {
                    continuation.resume()
                }
            }
        }
        let remaining = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        return apiDataRemoved && !remaining.contains { Self.isOwnedWebsiteRecordName($0.displayName, hosts: ownedHosts) }
    }

    private func watchStore() {
        guard let store else { return }
        withObservationTracking {
            _ = store.tabs.map { ($0.id, $0.page?.url, $0.page?.title) }
            _ = store.activeTabID
            _ = store.activeSpaceID
            _ = store.spaces.map { ($0.id, $0.dataStoreID) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshTabs()
                self?.watchStore()
            }
        }
        refreshTabs()
    }

    fileprivate func visibleTabs(in storeID: UUID) -> [ExtensionTab] {
        guard let store else { return [] }
        return store.tabs.compactMap { tab in
            guard store.spaces.contains(where: { $0.id == tab.spaceID && $0.dataStoreID == storeID }),
                  tab.place != .drifted, let page = tab.page as? WebKitPageController,
                  page.webView.configuration.websiteDataStore.identifier == storeID,
                  page.webView.configuration.webExtensionController === controllers[storeID] else { return nil }
            if let adapter = tabs[tab.id] {
                if adapter.dataStoreID == storeID && adapter.tab === tab { return adapter }
                controllers[adapter.dataStoreID]?.didCloseTab(adapter, windowIsClosing: false)
                tabs[tab.id] = nil
            }
            let adapter = ExtensionTab(tab: tab, dataStoreID: storeID, manager: self)
            tabs[tab.id] = adapter
            return adapter
        }
    }

    private func refreshTabs(in onlyStore: UUID? = nil) {
        if let request = popupRequest, store?.activeSpace.dataStoreID != request.storeID { popupRequest = nil; visiblePopup?.close() }
        for (storeID, controller) in controllers where onlyStore == nil || onlyStore == storeID {
            let current = visibleTabs(in: storeID)
            let ids = Set(current.compactMap { $0.tab?.id })
            for (id, adapter) in tabs where adapter.dataStoreID == storeID && !ids.contains(id) {
                controller.didCloseTab(adapter, windowIsClosing: false)
                tabs[id] = nil
            }
            for adapter in current where !adapter.announced {
                adapter.announced = true
                controller.didOpenTab(adapter)
            }
            for adapter in current { controller.didChangeTabProperties([.URL, .title, .loading], for: adapter) }
            if let context = contexts[storeID]?.values.first, let active = windows[storeID]?.activeTab(for: context) {
                controller.didActivateTab(active, previousActiveTab: nil)
            }
        }
    }

    private func storeID(for controller: WKWebExtensionController) -> UUID? {
        controllers.first { $0.value === controller }?.key
    }
    private func error(_ text: String) -> NSError { NSError(domain: "FirnWebExtensions", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }

    private func validStore(_ controller: WKWebExtensionController, _ context: WKWebExtensionContext) -> UUID? {
        guard let id = storeID(for: controller), contexts[id]?.values.contains(where: { $0 === context }) == true,
              store?.spaces.contains(where: { $0.dataStoreID == id }) == true else { return nil }
        return id
    }

    fileprivate func liveTab(_ adapter: ExtensionTab, for context: WKWebExtensionContext) -> Tab? {
        guard let controller = controllers[adapter.dataStoreID],
              validStore(controller, context) == adapter.dataStoreID,
              let tab = adapter.tab, tabs[tab.id] === adapter,
              visibleTabs(in: adapter.dataStoreID).contains(where: { $0 === adapter }) else { return nil }
        return tab
    }
    fileprivate func owns(_ url: URL, for context: WKWebExtensionContext, in storeID: UUID) -> Bool {
        ownsExtensionURL(url, in: storeID) && controllers[storeID]?.extensionContext(for: url) === context
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void) {
        guard let id = validStore(controller, context), let store,
              let url = configuration.url,
              url.scheme == "https" || url.scheme == "http" || controller.extensionContext(for: url) === context else {
            return completionHandler(nil, error("Extension tab request was denied."))
        }
        // Never use the active space as a fallback: it may belong to another store.
        guard let space = store.spaces.first(where: { $0.dataStoreID == id && $0.id == store.activeSpaceID })
                ?? store.spaces.first(where: { $0.dataStoreID == id }) else { return completionHandler(nil, error("Extension space is unavailable.")) }
        let active = configuration.shouldBeActive && store.activeSpace.dataStoreID == id
        let tab: Tab
        if url.scheme == "webkit-extension" {
            guard let page = extensionPage(url, in: id) else { return completionHandler(nil, error("Extension page could not be opened.")) }
            guard let opened = store.openExtensionTab(url, in: space.id, page: page, inBackground: !active) else { return completionHandler(nil, error("Extension tab could not be opened.")) }
            tab = opened
            page.loadExtensionPage(url, in: id)
        } else {
            guard let opened = store.openExtensionTab(url, in: space.id, inBackground: !active) else { return completionHandler(nil, error("Extension tab could not be opened.")) }
            tab = opened
            store.instantiateExtensionPage(for: tab)
        }
        refreshTabs(in: id)
        completionHandler(tabs[tab.id], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionWindow)?, Error?) -> Void) {
        guard let id = validStore(controller, context), let window = windows[id],
              !configuration.shouldBePrivate else { return completionHandler(nil, error("Extension window request was denied.")) }
        let urls = configuration.tabURLs
        guard urls.allSatisfy({ $0.scheme == "https" || $0.scheme == "http" || controller.extensionContext(for: $0) === context }) else {
            return completionHandler(nil, error("Extension window address was denied."))
        }
        guard let store, let space = store.spaces.first(where: { $0.dataStoreID == id }) else { return completionHandler(nil, error("Extension space is unavailable.")) }
        let active = configuration.shouldBeFocused && store.activeSpace.dataStoreID == id
        for url in urls {
            if url.scheme == "webkit-extension" {
                guard let page = extensionPage(url, in: id) else { continue }
                guard store.openExtensionTab(url, in: space.id, page: page, inBackground: !active) != nil else { continue }
                page.loadExtensionPage(url, in: id)
            } else {
                if let tab = store.openExtensionTab(url, in: space.id, inBackground: !active) {
                    store.instantiateExtensionPage(for: tab)
                }
            }
        }
        refreshTabs(in: id)
        completionHandler(window, nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let id = validStore(controller, context), let url = context.optionsPageURL, let store,
              let space = store.spaces.first(where: { $0.dataStoreID == id }) else { return completionHandler(error("Extension space is unavailable.")) }
        guard let page = extensionPage(url, in: id) else { return completionHandler(error("Extension page could not be opened.")) }
        guard store.openExtensionTab(url, in: space.id, page: page, inBackground: store.activeSpace.dataStoreID != id) != nil else { return completionHandler(error("Extension page could not be opened.")) }
        page.loadExtensionPage(url, in: id)
        completionHandler(nil)
    }

    private func ask(_ detail: String, context: WKWebExtensionContext, controller: WKWebExtensionController, answer: @escaping (Bool) -> Void) {
        guard let id = validStore(controller, context),
              let name = library.extensions.first(where: { contexts[id]?[$0.id] === context })?.name,
              let space = store?.spaces.first(where: { $0.dataStoreID == id }),
              let window = NSApp.keyWindow else { return answer(false) }
        let alert = NSAlert()
        alert.messageText = "Allow \(name) in \(space.name)?"
        alert.informativeText = detail
        alert.addButton(withTitle: "Don't Allow")
        alert.addButton(withTitle: "Allow")
        alert.beginSheetModal(for: window) { [weak self] result in
            answer(result == .alertSecondButtonReturn && self?.validStore(controller, context) == id && context.isLoaded)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let requested = permissions.filter { $0.rawValue != "nativeMessaging" && $0.rawValue != "notifications" }
        guard !requested.isEmpty else { return completionHandler([], nil) }
        ask("Requested permissions: " + requested.map(\.rawValue).sorted().joined(separator: ", "), context: context, controller: controller) { allowed in
            completionHandler(allowed ? Set(requested) : [], nil)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let safe = Set(patterns.flatMap { Self.webPatterns(for: $0.string) }.compactMap { try? WKWebExtension.MatchPattern(string: $0) })
        guard !safe.isEmpty else { return completionHandler([], nil) }
        ask("Requested website access: " + safe.map(\.string).sorted().joined(separator: ", "), context: context, controller: controller) { allowed in
            completionHandler(allowed ? safe : [], nil)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext, completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let safe = urls.filter { $0.scheme == "https" || $0.scheme == "http" }
        ask("Requested website access: " + safe.map(\.absoluteString).sorted().joined(separator: "\n"), context: context, controller: controller) { allowed in
            completionHandler(allowed ? Set(safe) : [], nil)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        guard let id = storeID(for: controller), contexts[id]?.values.contains(where: { $0 === context }) == true,
              let window = windows[id] else { return [] }
        return [window]
    }
    public func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        webExtensionController(controller, openWindowsFor: context).first
    }
    public func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let request = popupRequest, validStore(controller, context) == request.storeID,
              request.context === context, store?.activeSpace.dataStoreID == request.storeID,
              let popover = action.popupPopover else { return completionHandler(error("Extension popup is unavailable.")) }
        popupRequest = nil
        let anchor = request.anchor
        visiblePopup = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        completionHandler(nil)
    }
    public func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier identifier: String?, for context: WKWebExtensionContext, replyHandler: @escaping (Any?, Error?) -> Void) {
        replyHandler(nil, error("Native messaging is unsupported in Firn."))
    }
    public func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(error("Native messaging is unsupported in Firn."))
    }
}

@MainActor @available(macOS 15.4, *)
private final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    let dataStoreID: UUID
    weak var manager: WebExtensionManager?
    init(dataStoreID: UUID, manager: WebExtensionManager) { self.dataStoreID = dataStoreID; self.manager = manager }
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { manager?.visibleTabs(in: dataStoreID) ?? [] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let manager, let store = manager.store, store.activeSpace.dataStoreID == dataStoreID,
              let id = store.activeTabID else { return nil }
        return manager.visibleTabs(in: dataStoreID).first { $0.tab?.id == id }
    }
}

@MainActor @available(macOS 15.4, *)
private final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var tab: Tab?
    let dataStoreID: UUID
    weak var manager: WebExtensionManager?
    var announced = false
    var page: (any PageController)? { tab?.page }
    init(tab: Tab, dataStoreID: UUID, manager: WebExtensionManager) { self.tab = tab; self.dataStoreID = dataStoreID; self.manager = manager }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { manager?.windows[dataStoreID] }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { manager?.visibleTabs(in: dataStoreID).firstIndex { $0 === self } ?? NSNotFound }
    func parentTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let manager, let tab = manager.liveTab(self, for: context), let opener = tab.openerTabID else { return nil }
        return manager.visibleTabs(in: dataStoreID).first { $0.tab?.id == opener }
    }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { (tab?.page as? WebKitPageController)?.webView }
    func title(for context: WKWebExtensionContext) -> String? { tab?.page?.title ?? tab?.title }
    func url(for context: WKWebExtensionContext) -> URL? { tab?.page?.url ?? tab?.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(tab?.page?.isLoading ?? false) }
    func isSelected(for context: WKWebExtensionContext) -> Bool { manager?.store?.activeTabID == tab?.id && manager?.store?.activeSpace.dataStoreID == dataStoreID }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { false }
    func shouldBypassPermissions(for context: WKWebExtensionContext) -> Bool { false }
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let manager, let tab = manager.liveTab(self, for: context),
              url.scheme == "http" || url.scheme == "https" || manager.ownsExtensionURL(url, in: dataStoreID),
              url.scheme != "webkit-extension" || manager.owns(url, for: context, in: dataStoreID),
              let page = tab.page as? WebKitPageController else {
            return completionHandler(NSError(domain: "FirnWebExtensions", code: 1))
        }
        if url.scheme == "webkit-extension" { page.loadExtensionPage(url, in: dataStoreID) }
        else { page.load(url) }
        completionHandler(nil)
    }
    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let manager, let tab = manager.liveTab(self, for: context),
              let store = manager.store, store.activeSpace.dataStoreID == dataStoreID else {
            return completionHandler(NSError(domain: "FirnWebExtensions", code: 1))
        }
        store.select(tab)
        completionHandler(nil)
    }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        guard let manager, let tab = manager.liveTab(self, for: context), let store = manager.store else {
            return completionHandler(NSError(domain: "FirnWebExtensions", code: 1))
        }
        store.close(tab)
        completionHandler(nil)
    }
}
#endif
