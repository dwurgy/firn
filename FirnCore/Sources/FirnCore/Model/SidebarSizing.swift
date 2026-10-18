/// How wide the sidebar may be, and what dragging its edge does.
///
/// Pulling narrower stops at `minimum` (the sidebar "hits a wall"); pulling
/// on past `snapDistance` more lets go and hides the sidebar.
public enum SidebarSizing {
    public static let minimum = 200.0
    public static let maximum = 360.0
    public static let standard = 260.0
    /// How far past the minimum the edge must be pulled before the sidebar hides.
    public static let snapDistance = 60.0

    public enum Outcome: Equatable, Sendable {
        case width(Double)
        case collapse
    }

    /// What a drag to `proposedWidth` should do.
    public static func outcome(forProposedWidth proposedWidth: Double) -> Outcome {
        if proposedWidth < minimum - snapDistance { return .collapse }
        return .width(min(max(proposedWidth, minimum), maximum))
    }
}
