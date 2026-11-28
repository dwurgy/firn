import Foundation

/// A unit's runs as one plain string with its pieces marked by small tags,
/// for Apple's fast translation model (2026-11-28, `docs/HISTORY.md`,
/// "Plan: translating pages", step 6e). The fast model throws away the
/// framework's own attributed marks, but keeps tags in the text around the
/// right words: "Haz clic <a0>aquí</a0> para leer <x1/>" comes back as
/// "Click <a0>here</a0> to read <x1/>". A piece is `<aN>words</aN>`; a
/// kept piece (code, `translate="no"`) is `<xN/>`, its words left out so
/// the model can't touch them.
///
/// The page's words are hostile input: a page whose own text looks like a
/// tag isn't tagged at all, and a translation whose tags don't come back
/// exactly (lost, repeated, nested, or unknown) isn't used.
enum TaggedRuns {
    /// The runs as tagged text, or nil if the text already holds something
    /// that looks like one of the tags.
    static func encode(_ runs: [PageText.Run]) -> String? {
        var out = ""
        for run in runs {
            guard !looksLikeTag(run.text) else { return nil }
            switch (run.piece, run.isFixed) {
            case (nil, _): out += run.text
            case (let piece?, true): out += "<x\(piece)/>"
            case (let piece?, false): out += "<a\(piece)>\(run.text)</a\(piece)>"
            }
        }
        return out
    }

    /// A tagged translation read back into runs, or nil if its tags don't
    /// match `part`'s pieces exactly. A piece with no words (an empty
    /// anchor) may go missing; the translator puts it back.
    static func decode(_ text: String, from part: [PageText.Run]) -> [PageText.Run]? {
        var byPiece: [Int: PageText.Run] = [:]
        for run in part { if let piece = run.piece { byPiece[piece] = run } }
        var out: [PageText.Run] = []
        var seen = Set<Int>()
        var open: (piece: Int, start: String.Index)?
        var plainStart = text.startIndex
        for match in text.matches(of: tag) {
            let (_, kind, number, slash) = match.output
            guard let piece = Int(number), let original = byPiece[piece] else { return nil }
            switch (String(kind), slash != nil) {
            case ("a", false):
                guard open == nil, !original.isFixed else { return nil }
                out.append(PageText.Run(text: String(text[plainStart..<match.range.lowerBound])))
                open = (piece, match.range.upperBound)
            case ("/a", false):
                guard let current = open, current.piece == piece, seen.insert(piece).inserted else { return nil }
                out.append(PageText.Run(piece: piece, text: String(text[current.start..<match.range.lowerBound])))
                open = nil
                plainStart = match.range.upperBound
            case ("x", true):
                guard open == nil, original.isFixed, seen.insert(piece).inserted else { return nil }
                out.append(PageText.Run(text: String(text[plainStart..<match.range.lowerBound])))
                out.append(original)
                plainStart = match.range.upperBound
            default:
                return nil
            }
        }
        guard open == nil else { return nil }
        out.append(PageText.Run(text: String(text[plainStart...])))
        for (piece, run) in byPiece where !seen.contains(piece) {
            guard !run.text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        }
        // A tag the model mangled ("< a0 >") would show on the page.
        guard !out.contains(where: { $0.piece == nil && looksLikeTag($0.text) }) else { return nil }
        // Plain runs side by side, and empty ones, as one.
        var merged: [PageText.Run] = []
        for run in out where !(run.piece == nil && run.text.isEmpty) {
            if run.piece == nil, let last = merged.last, last.piece == nil {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    // `<a3>`, `</a3>`, or `<x3/>`.
    nonisolated(unsafe) private static let tag = /<(\/?[ax])(\d{1,4})(\/)?>/

    /// Anything resembling a tag, spaced or not: "<a1", "</ a1", "<x 1".
    private static func looksLikeTag(_ text: String) -> Bool {
        text.contains(/<\s*\/?\s*[axAX]\s*\d/)
    }
}
