import Foundation
import NaturalLanguage

/// Translating pages, step 2: reading the page's text and writing
/// translations back (plan in `docs/HISTORY.md`, "Plan: translating pages").
///
/// The page side is `Scripts/PageText.js`, run in Firn's own content world
/// on the main frame. It reads the page in *units*: stretches of a block to
/// translate whole, each a list of runs, plain text or a numbered *piece*
/// (an inline element: a link, bold). A translation is the same kind of list
/// in the new order; the script moves each piece's element there and writes
/// every word as plain text, never HTML. The originals stay the page's own
/// nodes, so Show Original puts back exactly what was there.
///
/// Everything here came from a web page: shapes are checked and sizes capped.
public enum PageText {
    /// One stretch of a unit's text.
    public struct Run: Equatable, Sendable {
        /// Which of the unit's pieces this is; nil for plain text.
        public var piece: Int?
        public var text: String
        /// A piece kept as it is (code, `translate="no"`, or an element
        /// with formatting inside): the translator leaves its words alone.
        public var isFixed: Bool

        public init(piece: Int? = nil, text: String, isFixed: Bool = false) {
            self.piece = piece
            self.text = text
            self.isFixed = isFixed
        }
    }

    /// One stretch of a block to translate whole.
    public struct Unit: Equatable, Sendable {
        public let id: Int
        /// Where it sits on the page, in points from the top, so what's on
        /// screen can go first.
        public let top: Double
        public let runs: [Run]
        /// The language its block says it's in, when that isn't the page's
        /// (a German quote on an English page); nil for the page's own.
        public var declaredLanguage: String? = nil

        public var text: String { runs.map(\.text).joined() }
        public var pieces: [Int] { runs.compactMap(\.piece) }
    }

    /// The part of the page on screen, in points from the top.
    public struct View: Equatable, Sendable {
        public var top: Double
        public var height: Double

        public init(top: Double = 0, height: Double = 0) {
            self.top = top
            self.height = height
        }

        var bottom: Double { top + height }
    }

    /// Text the page added since the last look, and where it's scrolled to.
    public struct More: Equatable, Sendable {
        public let view: View
        public let units: [Unit]

        public init(view: View, units: [Unit]) {
            self.view = view
            self.units = units
        }
    }

    /// What the page holds to translate.
    public struct Snapshot: Equatable, Sendable {
        /// The page's own `lang`, if it has a sensible one.
        public let declaredLanguage: String?
        public let title: String
        /// Some of its text, for language detection.
        public let sample: String
        public let units: [Unit]
        /// The part of the page on screen as it was read.
        public var view = View()

        /// The page's language: its `lang`, checked against its text.
        public var language: Locale.Language? {
            PageLanguage.detect(declared: declaredLanguage, sample: sample)
        }
    }

    /// A unit's translation, to write back.
    public struct Translation: Equatable, Sendable {
        public let id: Int
        public let runs: [Run]

        public init(id: Int, runs: [Run]) {
            self.id = id
            self.runs = runs
        }
    }

    // MARK: Limits (the script has the same)

    static let maxUnits = 4000
    static let maxRuns = 100
    static let maxRunCharacters = 4000

    /// Units are split by sentence to about this many characters: longer
    /// inputs can make the model loop (step 1's findings).
    public static let sentenceLimit = 600

    // MARK: Reading the script's answer

    /// Reads the script's `read()` answer, or nil if it isn't the shape
    /// expected. Units that aren't are dropped one by one.
    static func snapshot(from result: Any?) -> Snapshot? {
        guard let fields = result as? [String: Any], let rawUnits = fields["units"] as? [Any],
              rawUnits.count <= maxUnits else { return nil }
        var units: [Unit] = []
        for raw in rawUnits {
            guard let unit = Self.unit(from: raw) else { continue }
            units.append(unit)
        }
        let declared = (fields["lang"] as? String).flatMap(languageTag)
        let title = ReaderArticle.line(fields["title"], limit: 1000) ?? ""
        let sample = String(((fields["sample"] as? String) ?? "").prefix(3000))
        return Snapshot(declaredLanguage: declared, title: title, sample: sample, units: units,
                        view: view(from: fields["view"]))
    }

    /// Reads the script's `more()` answer, or nil if it isn't the shape
    /// expected.
    static func more(from result: Any?) -> More? {
        guard let fields = result as? [String: Any], let rawUnits = fields["units"] as? [Any],
              rawUnits.count <= maxUnits else { return nil }
        return More(view: view(from: fields["view"]), units: rawUnits.compactMap(unit(from:)))
    }

    private static func view(from raw: Any?) -> View {
        guard let fields = raw as? [String: Any] else { return View() }
        func number(_ key: String) -> Double {
            guard let value = (fields[key] as? NSNumber)?.doubleValue, value.isFinite else { return 0 }
            return min(max(value, 0), 10_000_000)
        }
        return View(top: number("top"), height: number("height"))
    }

    private static func unit(from raw: Any) -> Unit? {
        guard let fields = raw as? [String: Any], let id = (fields["id"] as? NSNumber)?.intValue,
              id >= 0, id < maxUnits, let rawRuns = fields["runs"] as? [Any],
              !rawRuns.isEmpty, rawRuns.count <= maxRuns else { return nil }
        let top = (fields["top"] as? NSNumber)?.doubleValue ?? 0
        var runs: [Run] = []
        var next = 0
        for raw in rawRuns {
            guard let run = raw as? [String: Any], let text = run["t"] as? String,
                  text.count <= maxRunCharacters, let k = (run["k"] as? NSNumber)?.intValue else { return nil }
            let fixed = (run["fixed"] as? NSNumber)?.boolValue == true
            if k == -1 {
                runs.append(Run(text: collapsed(text)))
            } else {
                // Pieces are numbered in order, from zero.
                guard k == next else { return nil }
                next += 1
                runs.append(Run(piece: k, text: fixed ? text : collapsed(text), isFixed: fixed))
            }
        }
        let lang = (fields["lang"] as? String).flatMap(languageTag)
        return Unit(id: id, top: top.isFinite ? top : 0, runs: runs, declaredLanguage: lang)
    }

    /// Whitespace runs become one space, as the page shows them.
    static func collapsed(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(character)
                lastWasSpace = false
            }
        }
        return out
    }

    /// A language tag, or nil if it isn't one ("en", "pt-BR", "zh-Hant").
    static func languageTag(_ raw: String) -> String? {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, tag.count <= 35,
              tag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              Locale.Language(identifier: tag).languageCode != nil else { return nil }
        return tag
    }

    // MARK: Checking a translation

    /// Whether `runs` can stand in for `unit`: every one of its pieces
    /// exactly once (a translation that drops or repeats a link isn't
    /// written), and nothing oversized.
    public static func fits(_ runs: [Run], _ unit: Unit) -> Bool {
        guard !runs.isEmpty, runs.count <= maxRuns * 2 else { return false }
        let pieces = runs.compactMap(\.piece)
        guard pieces.count == Set(pieces).count, Set(pieces) == Set(unit.pieces) else { return false }
        return runs.allSatisfy { $0.text.count <= maxRunCharacters * 3 }
    }

    /// Whether a translation ran away from its input (the model looping):
    /// over about twice as long. Counted in UTF-8 bytes, so a change of
    /// script (Chinese to English) doesn't look like one.
    public static func isRunaway(input: String, output: String) -> Bool {
        output.utf8.count > input.utf8.count * 2 + 64
    }

    // MARK: Shaping

    /// Moves the spaces at a piece's edges out beside it: the translator
    /// gives back "[here ]to continue", and the page wants "[here] to
    /// continue", so a link isn't underlined into the next word. Plain runs
    /// side by side are joined.
    public static func movingEdgeSpaces(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        func addPlain(_ text: String) {
            guard !text.isEmpty else { return }
            if let last = out.last, last.piece == nil { out[out.count - 1].text += text } else { out.append(Run(text: text)) }
        }
        for run in runs {
            guard run.piece != nil, !run.isFixed else {
                if run.piece == nil { addPlain(run.text) } else { out.append(run) }
                continue
            }
            let leading = run.text.prefix { $0.isWhitespace }
            let rest = run.text.dropFirst(leading.count)
            let trailing = rest.reversed().prefix { $0.isWhitespace }
            let middle = rest.dropLast(trailing.count)
            addPlain(leading.isEmpty ? "" : " ")
            out.append(Run(piece: run.piece, text: String(middle), isFixed: false))
            if !trailing.isEmpty { out.append(Run(text: " ")) }
        }
        return out
    }

    /// The unit cut by sentence into parts of about `limit` characters,
    /// never through a piece, to translate one at a time and join back. A
    /// short unit, or one sentence, is one part.
    public static func parts(of unit: Unit, limit: Int = sentenceLimit) -> [[Run]] {
        let text = unit.text as NSString
        guard text.length > limit else { return [unit.runs] }
        // Where each piece sits, in UTF-16 offsets; no cut falls inside one.
        var spans: [Range<Int>] = []
        var offset = 0
        for run in unit.runs {
            let length = (run.text as NSString).length
            if run.piece != nil { spans.append(offset..<(offset + length)) }
            offset += length
        }
        let tokenizer = NLTokenizer(unit: .sentence)
        let whole = unit.text
        tokenizer.string = whole
        var ends: [Int] = []
        tokenizer.enumerateTokens(in: whole.startIndex..<whole.endIndex) { range, _ in
            let end = NSRange(range, in: whole).upperBound
            if end < text.length, !spans.contains(where: { $0.lowerBound < end && end < $0.upperBound }) {
                ends.append(end)
            }
            return true
        }
        var cuts: [Int] = []
        var start = 0
        var previous: Int?
        for end in ends {
            if end - start > limit, let cut = previous, cut > start {
                cuts.append(cut)
                start = cut
            }
            previous = end
        }
        if text.length - start > limit, let cut = previous, cut > start { cuts.append(cut) }
        guard !cuts.isEmpty else { return [unit.runs] }

        var parts: [[Run]] = [[]]
        var position = 0
        var pending = cuts[...]
        for run in unit.runs {
            var rest = run.text as NSString
            var at = position
            var placed = false
            // A cut lands inside plain text only, or at a piece's edge.
            while let cut = pending.first, cut <= at + rest.length {
                let head = rest.substring(to: cut - at)
                if !head.isEmpty {
                    parts[parts.count - 1].append(Run(piece: run.piece, text: head, isFixed: run.isFixed))
                    placed = true
                }
                rest = rest.substring(from: cut - at) as NSString
                at = cut
                parts.append([])
                pending = pending.dropFirst()
            }
            if rest.length > 0 || (run.piece != nil && !placed) {
                parts[parts.count - 1].append(Run(piece: run.piece, text: rest as String, isFixed: run.isFixed))
            }
            position += (run.text as NSString).length
        }
        return parts.filter { !$0.isEmpty }
    }

    // MARK: Script

    /// `Scripts/PageText.js`, ending with a call to `action`, its one
    /// argument `input`.
    static func script(_ action: String) -> String? {
        source.map { $0 + "\nreturn firnPageText.\(action)(input);" }
    }

    private static let source: String? = {
        guard let url = Bundle.module.url(forResource: "PageText", withExtension: "js", subdirectory: "Scripts")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// A translation as the script takes it.
    static func argument(_ translations: [Translation], language: String, title: String?) -> [String: Any] {
        var input: [String: Any] = [
            "lang": languageTag(language) ?? "",
            "units": translations.map { translation in
                ["id": translation.id,
                 "runs": translation.runs.map { ["k": $0.piece ?? -1, "t": $0.text] as [String: Any] }] as [String: Any]
            },
        ]
        if let title { input["title"] = title }
        return input
    }
}

/// Which language a page is in, and whether to offer translating it.
public enum PageLanguage {
    /// The page's language: its `lang`, unless Apple's on-device detection
    /// is sure its text says otherwise (pages often keep a template's "en").
    /// Nil if neither says.
    public static func detect(declared: String?, sample: String) -> Locale.Language? {
        let declaredLanguage = declared.flatMap(PageText.languageTag).map(Locale.Language.init(identifier:))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample.prefix(3000)))
        guard let (guess, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              sample.count >= 20 else { return declaredLanguage }
        let detected = Locale.Language(identifier: guess.rawValue)
        if let declaredLanguage, declaredLanguage.languageCode == detected.languageCode { return declaredLanguage }
        if confidence >= 0.8 { return detected }
        return declaredLanguage ?? (confidence >= 0.5 ? detected : nil)
    }

    /// The language to offer translating `page` into, or nil for no offer:
    /// never a language the person reads (any of `preferred`), and only
    /// between languages the translator `supported`. The offer is the first
    /// preferred language it supports, in the closest form it has.
    public static func offer(
        page: Locale.Language, preferred: [String] = Locale.preferredLanguages, supported: [Locale.Language]
    ) -> Locale.Language? {
        guard let code = page.languageCode, supported.contains(where: { $0.languageCode == code }) else { return nil }
        let reads = preferred.map(Locale.Language.init(identifier:))
        guard !reads.contains(where: { $0.languageCode == code }) else { return nil }
        for language in reads {
            let same = supported.filter { $0.languageCode == language.languageCode }
            guard let first = same.first else { continue }
            return same.first { $0.region != nil && $0.region == language.region }
                ?? same.first { $0.script != nil && $0.script == language.script }
                ?? first
        }
        return nil
    }
}
