import Foundation

/// How big a page is drawn: Safari's steps, from half size to three times.
/// Kept per tab and forgotten on quit (David, 2026-10-23), so nothing about
/// which sites were zoomed is ever saved.
public enum PageZoom {
    public static let steps: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// The next step up from `zoom`, or nil at the largest.
    public static func larger(than zoom: Double) -> Double? {
        steps.first { $0 > zoom + 0.001 }
    }

    /// The next step down from `zoom`, or nil at the smallest.
    public static func smaller(than zoom: Double) -> Double? {
        steps.last { $0 < zoom - 0.001 }
    }

    public static func isActualSize(_ zoom: Double) -> Bool {
        abs(zoom - 1) < 0.001
    }

    /// "125%", for the address bar.
    public static func percent(_ zoom: Double) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }
}
