import Foundation

/// A group: a name and a flat set of everyday tabs, kept together in the
/// sidebar above the loose tabs. Its tabs are ordinary tabs that never
/// archive. Groups are ordered by their place in `BrowserStore.groups`.
public struct TabGroup: Identifiable, Hashable, Sendable {
    public static let defaultName = "New Group"
    /// Longer names are cut to this many characters.
    public static let nameLimit = 100

    public let id: UUID
    public let spaceID: UUID
    public internal(set) var name: String
    public internal(set) var folded: Bool

    init(id: UUID = UUID(), spaceID: UUID, name: String = defaultName, folded: Bool = false) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.folded = folded
    }

    /// A name fit to show: one line, trimmed, and not too long; nil if
    /// nothing's left.
    static func cleanName(_ name: String) -> String? {
        let line = name.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
    }
}
