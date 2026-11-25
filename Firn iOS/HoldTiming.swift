import Foundation

/// How far a held field or pill sinks before its menu opens (as iOS's
/// items do).
let pressedScale: CGFloat = 0.97

/// The timing of Firn's own holds (the address field, the space's name): a
/// finger held still for `hold` starts to sink, and at `menuHold` its menu
/// opens. Cards, groups, and Basecamp's tiles are held by iOS, from the
/// overview's grid (`OverviewGridCards.swift`).
enum HoldThenMove {
    static let hold: TimeInterval = 0.15
    static let menuHold: TimeInterval = 0.5
}
