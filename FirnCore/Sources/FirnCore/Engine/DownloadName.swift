import Foundation

/// The name a downloaded file is saved under. The name comes from the site,
/// so it's hostile input: it may try to climb out of the Downloads folder
/// ("../../x"), hide itself (".x"), or disguise its type with invisible
/// characters ("photo\u{202E}gpj.app" reads as "photoppa.jpg").
public enum DownloadName {
    /// Leaves room under the file system's 255-byte limit for " 99".
    static let maxBytes = 200

    /// A safe file name: one plain name, no folders, nothing invisible, not
    /// hidden, and not too long. `fallback` when nothing usable is left.
    public static func clean(_ suggested: String, fallback: String = "Download") -> String {
        var name = String(String.UnicodeScalarView(suggested.unicodeScalars.compactMap { scalar in
            switch scalar.properties.generalCategory {
            // Control and formatting characters (direction overrides,
            // zero-width marks) and line or paragraph breaks.
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                return nil
            default:
                // Folder separators (":" is one to Finder) can't name folders.
                return "/\\:".unicodeScalars.contains(scalar) ? "-" : scalar
            }
        }))
        // No hidden files, and no trailing dots or spaces (some disks refuse them).
        name = String(name.drop(while: { $0 == "." || $0.isWhitespace }))
        while let last = name.last, last == "." || last.isWhitespace { name.removeLast() }
        name = shortened(name)
        return name.isEmpty ? fallback : name
    }

    /// `name`, or "name 2.pdf", "name 3.pdf", and so on, whichever isn't
    /// taken yet.
    public static func unique(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let (stem, ext) = split(name)
        for number in 2... {
            let candidate = "\(stem) \(number)\(ext)"
            if !isTaken(candidate) { return candidate }
        }
        return name
    }

    /// The name and its extension (with its dot), keeping two-part ones
    /// like ".tar.gz" together.
    static func split(_ name: String) -> (stem: String, ext: String) {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return (name, "") }
        let keep = parts.count > 2 && parts[parts.count - 2].lowercased() == "tar" ? 2 : 1
        let ext = "." + parts.suffix(keep).joined(separator: ".")
        // An extension is short and plain; anything else is part of the name.
        guard ext.count <= 16, !ext.contains(" ") else { return (name, "") }
        return (String(name.dropLast(ext.count)), ext)
    }

    /// Cut to `maxBytes`, keeping the extension and whole characters.
    private static func shortened(_ name: String) -> String {
        guard name.utf8.count > maxBytes else { return name }
        var (stem, ext) = split(name)
        if ext.utf8.count > maxBytes / 2 { (stem, ext) = (name, "") }
        while !stem.isEmpty, stem.utf8.count + ext.utf8.count > maxBytes { stem.removeLast() }
        while let last = stem.last, last == "." || last.isWhitespace { stem.removeLast() }
        return stem + ext
    }
}
