import Foundation

/// The lists that ship inside Firn. They're refreshed by replacing the files in
/// `Blocking/Lists` (see the README there); Firn never downloads them.
public enum BlockList: String, CaseIterable, Sendable {
    case ads = "easylist"
    case trackers = "easyprivacy"

    /// The list's text, as shipped.
    public func text() -> String? {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "txt", subdirectory: "Lists") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
