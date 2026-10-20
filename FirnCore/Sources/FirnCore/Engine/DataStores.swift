import Foundation
import os
import WebKit

/// Erasing a space's website data: its cookies, sign-ins, and site data.
extension BrowserEngine {
    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "data")

    /// Erases a data store no space uses any more. WebKit refuses while a
    /// page still holds the store, so this waits a moment for the deleted
    /// space's pages to let go; if it's still refused, `removeUnusedData`
    /// erases it at the next launch.
    public static func removeData(for dataStoreID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: dataStoreID)
            } catch {
                log.notice("A deleted space's data is still in use; it will be erased at next launch")
            }
        }
    }

    /// Erases every data store that isn't in `keeping`: what's left of
    /// spaces deleted while their pages were still open. Call it only with
    /// the spaces of a session that really loaded, never a fresh start
    /// after a damaged file, or it would erase spaces that still exist.
    public static func removeUnusedData(keeping: Set<UUID>) {
        Task { @MainActor in
            let unused = await WKWebsiteDataStore.allDataStoreIdentifiers.filter { !keeping.contains($0) }
            for id in unused {
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: id)
                } catch {
                    log.notice("Couldn't erase an unused space's data; will try again at next launch")
                }
            }
        }
    }
}
