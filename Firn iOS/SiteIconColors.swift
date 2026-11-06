import FirnCore
import UIKit

/// The iOS twin of the Mac's `siteIconColors` (Firn/SiteIconView.swift),
/// which Shared/Theme.swift needs: a site icon's own calmed colors, or nil
/// for black, white, or grey icons. Worked out once per icon.
@MainActor func siteIconColors(_ png: Data) -> IconColor.Colors? {
    let key = png as NSData
    if let known = foundColors.object(forKey: key) { return known.colors }
    let color = IconColor.from(png: png)
    foundColors.setObject(FoundColors(color), forKey: key)
    return color
}

/// NSCache keeps objects, and "no color" is worth remembering too.
private final class FoundColors {
    let colors: IconColor.Colors?
    init(_ colors: IconColor.Colors?) { self.colors = colors }
}

@MainActor private let foundColors: NSCache<NSData, FoundColors> = {
    let cache = NSCache<NSData, FoundColors>()
    cache.countLimit = 200
    return cache
}()
