import Foundation

/// A link preview floating over the tab on screen. Its page uses the space's
/// own data store, so it's signed in wherever the space is. It's never
/// saved: it goes away when closed, on quit, or on switching space, and
/// becomes a tab only if kept.
@MainActor
public struct Lookout: Identifiable {
    public let id = UUID()
    public let spaceID: UUID
    public let page: any PageController
    /// The address it opened with, where a kept tab rests if its page never
    /// committed one.
    let openedURL: URL
}
