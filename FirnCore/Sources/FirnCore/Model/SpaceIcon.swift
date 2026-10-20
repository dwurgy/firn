import Foundation

/// Firn's own space icons (CLAUDE.md: never emoji). A space stores one by its
/// raw name; the app draws it. Each has a plain name for VoiceOver that's
/// never shown on screen.
public enum SpaceIcon: String, CaseIterable, Sendable {
    case home, work, reading, family, shopping, pets, coffee, music
    case creative, photos, travel, outdoors, leaf, forest, sun, star

    /// The first one, home: the first space's icon.
    public static let `default` = SpaceIcon.home

    /// The icon a space stored, or home if the name isn't one Firn knows
    /// (a hand-edited session file).
    public init(stored name: String) {
        self = SpaceIcon(rawValue: name) ?? .default
    }

    /// The icon the New space sheet starts on: the first one no space uses
    /// yet, in order (so home, then work, then reading…), the same way the
    /// next color is picked. With all sixteen in use, it goes round again.
    public static func next(after taken: [String]) -> SpaceIcon {
        let used = Set(taken)
        return allCases.first { !used.contains($0.rawValue) } ?? allCases[taken.count % allCases.count]
    }

    /// What VoiceOver says for this icon.
    public var spokenName: String {
        switch self {
        case .home: "Home"
        case .work: "Work"
        case .reading: "Reading"
        case .family: "Family"
        case .shopping: "Shopping"
        case .pets: "Pets"
        case .coffee: "Coffee"
        case .music: "Music"
        case .creative: "Creative"
        case .photos: "Photos"
        case .travel: "Travel"
        case .outdoors: "Outdoors"
        case .leaf: "Nature"
        case .forest: "Forest"
        case .sun: "Sun"
        case .star: "Star"
        }
    }
}
