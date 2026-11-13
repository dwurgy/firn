import Foundation
import Security

/// The key sync seals records with (`SyncSeal`), one per iCloud account,
/// kept in iCloud Keychain so every device signed into that account has it,
/// end to end (docs/SYNC-PLAN.md). The Mac app and the iPhone app share a
/// bundle id, so they share the Keychain group the item lives in.
///
/// If two devices each make a key before iCloud Keychain carries the first
/// across, iCloud Keychain ends up keeping one; the engine notices a record
/// sealed with another key, reads the Keychain again, and a device whose key
/// changed seals and sends everything again.
///
/// Calls block on the Keychain: keep them off the main thread.
public enum SyncKeychain {
    private static let service = "com.firnbrowser.firn.sync"
    private static let account = "sync-key"

    /// The key in iCloud Keychain, or nil if there's none yet.
    public static func read() throws -> Data? {
        var search = base
        search[kSecMatchLimit] = kSecMatchLimitOne
        search[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = result as? Data, data.count == SyncSeal.keySize else { throw Failure(status: errSecDecode) }
        return data
    }

    /// The key, made and saved first if this iCloud account has none.
    public static func key() throws -> Data {
        if let key = try read() { return key }
        var item = base
        item[kSecValueData] = SyncSeal.makeKeyData()
        // Synced, so it can't be "this device only"; readable once the
        // device has been unlocked after starting, so sync can run then.
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrLabel] = "Firn sync key"
        let status = SecItemAdd(item as CFDictionary, nil)
        // Another of Firn's calls made one first: that one is the key.
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure(status: status) }
        guard let key = try read() else { throw Failure(status: errSecItemNotFound) }
        return key
    }

    /// Only the Keychain's error number, never anything about the key.
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    private static var base: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: true,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
