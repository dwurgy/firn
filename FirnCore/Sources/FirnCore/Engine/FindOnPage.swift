import Foundation

/// Find on page (⌘F): what's searched for, and how the bar says what it found.
/// The words searched for stay in the window, never saved.
public enum FindOnPage {
    /// Which match to go to.
    public enum Direction: Sendable {
        /// The first match from where the last one was: as the words are typed,
        /// so a match that still fits stays chosen.
        case fromHere
        case next
        case previous
    }

    /// Matches are counted up to here, so a huge page can't keep Firn busy.
    public static let countLimit = 1000
    /// Longer than anyone types; also how much of a page's selection ⌘E takes.
    public static let maxLength = 200

    /// The words to look for: at most `maxLength` characters, on one line.
    public static func query(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(line.prefix(maxLength))
    }

    /// What the bar shows: "No matches", "1 match", "12 matches", or
    /// "1,000+ matches" once counting stopped.
    public static func label(count: Int) -> String {
        switch count {
        case ..<1: return "No matches"
        case 1: return "1 match"
        case countLimit...: return "\(countLimit.formatted())+ matches"
        default: return "\(count.formatted()) matches"
        }
    }

    /// Counts the words in the page's visible text, ignoring case, as WebKit's
    /// find does. Run in Firn's own world with `query` passed as a value, so
    /// what's typed is never read as code. Returns a number, nothing else.
    static let countScript = """
    const text = document.body ? document.body.innerText.toLocaleLowerCase() : "";
    const needle = String(query).toLocaleLowerCase();
    if (!needle) return 0;
    let count = 0, at = text.indexOf(needle);
    while (at !== -1 && count < limit) { count++; at = text.indexOf(needle, at + needle.length); }
    return count;
    """

    /// Moves the page's selection to the start of the match on screen, so
    /// searching on from it finds that match again if it still fits.
    static let collapseScript = """
    const selection = window.getSelection();
    if (selection && selection.rangeCount) selection.collapseToStart();
    """

    /// The page's selected text, for Use Selection for Find (⌘E).
    static let selectionScript = """
    const selection = window.getSelection();
    return selection ? String(selection).slice(0, limit) : "";
    """
}
