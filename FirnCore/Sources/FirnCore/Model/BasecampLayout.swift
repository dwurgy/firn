/// How Basecamp's square tiles are arranged: as few rows as fit, rows
/// balanced (5 tiles are 3 + 2, never 4 + 1), and tiles never too small.
public struct BasecampLayout: Equatable, Sendable {
    /// Tiles in each row, top to bottom; the longest row comes first.
    public let rows: [Int]
    /// The side of every tile, in points.
    public let tileSize: Double

    public static let gap = 8.0
    /// Tiles never shrink below this; narrower sidebars use fewer columns.
    public static let minimumTile = 48.0
    /// Nor grow past this, so one or two tiles stay tile-sized.
    public static let maximumTile = 72.0
    public static let maximumColumns = 4

    public init(rows: [Int], tileSize: Double) {
        self.rows = rows
        self.tileSize = tileSize
    }

    /// The layout for `count` tiles in `width` points.
    public static func make(count: Int, width: Double) -> BasecampLayout {
        guard count > 0, width > 0 else { return BasecampLayout(rows: [], tileSize: 0) }
        let fitting = Int((width + gap) / (minimumTile + gap))
        let widest = min(max(fitting, 1), maximumColumns)
        let rowCount = (count + widest - 1) / widest
        // Spread the tiles evenly: rows differ by at most one.
        let base = count / rowCount
        let extra = count % rowCount
        let rows = (0..<rowCount).map { base + ($0 < extra ? 1 : 0) }
        let columns = Double(rows[0])
        let tile = (width - (columns - 1) * gap) / columns
        return BasecampLayout(rows: rows, tileSize: min(tile, maximumTile).rounded(.down))
    }
}
