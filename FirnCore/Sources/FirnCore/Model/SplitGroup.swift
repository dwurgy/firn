import Foundation

/// Split view: two everyday tabs shown side by side, one row in the
/// sidebar. Its tabs sit next to each other in the tab list (left first),
/// in the same group if they're in one, and never drift. Ending it leaves
/// two ordinary tabs.
public struct SplitGroup: Identifiable, Hashable, Sendable {
    /// Neither page gets narrower than this share of the page area.
    public static let fractionRange: ClosedRange<Double> = 0.3...0.7

    public let id: UUID
    public let spaceID: UUID
    /// The left page's share of the width.
    public internal(set) var leftFraction: Double

    init(id: UUID = UUID(), spaceID: UUID, leftFraction: Double = 0.5) {
        self.id = id
        self.spaceID = spaceID
        self.leftFraction = Self.clamped(leftFraction)
    }

    /// A share both pages can live with, whatever was asked for.
    static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0.5 }
        return min(max(fraction, fractionRange.lowerBound), fractionRange.upperBound)
    }
}

/// Which half of a split a tab goes on.
public enum SplitSide: Sendable {
    case left, right
}
