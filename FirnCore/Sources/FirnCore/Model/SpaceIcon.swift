import Foundation

/// Firn's own space icons (CLAUDE.md: never emoji). A space stores one by its
/// raw name; the app draws it. Each has a plain name for VoiceOver that's
/// never shown on screen.
public enum SpaceIcon: String, CaseIterable, Sendable {
    case home, work, reading, family, shopping, pets, coffee, music
    case creative, photos, travel, outdoors, leaf, forest, sun, star

    /// The leaf: what a new space starts with.
    public static let `default` = SpaceIcon.leaf

    /// The icon a space stored, or the leaf if the name isn't one Firn knows
    /// (an older or hand-edited session file).
    public init(stored name: String) {
        self = SpaceIcon(rawValue: name) ?? .default
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
