import Foundation
import NaturalLanguage
import Observation
#if canImport(Translation)
import Translation
#endif

/// Translating pages, step 3: the translator (plan in `docs/HISTORY.md`,
/// "Plan: translating pages"). Reads the page (`PageText`), translates it
/// a unit at a time, nearest the part on screen first, and writes each one
/// back as it's done; then keeps translating text the page adds, until
/// Show Original or the page moves on. Everything happens on the device:
/// the words go to Apple's Translation framework and nowhere else, and
/// nothing is stored or logged.

/// What a translation needs of a page; `PageController` has it.
@MainActor
public protocol PageTextAccess: AnyObject {
    /// The committed address.
    var url: URL? { get }
    /// The page's text to translate, read in Firn's world (`PageText`);
    /// nil if it isn't a loaded web page. Puts back any translation first,
    /// and starts noticing text the page adds.
    func readPageText() async -> PageText.Snapshot?
    /// Text the page added since the last read or look, while translated,
    /// and where it's scrolled to; nil if the page isn't there to ask.
    func readMorePageText() async -> PageText.More?
    /// Writes translations of the units last read, as plain text, marked
    /// as `language`, and the tab's title if given; how many went in.
    func writePageText(_ translations: [PageText.Translation], language: String, title: String?) async -> Int
    /// Show Original: the page's own words and title back, exactly; stops
    /// noticing text the page adds.
    func restorePageText() async
    /// Called, at most about once a second, when a translated page adds text.
    var onPageTextChange: (@MainActor () -> Void)? { get set }
}

/// Turns one part of a unit into another language: Apple's Translation
/// framework in the apps (`SystemRunTranslator`), a fake in tests.
@MainActor
public protocol RunTranslating: AnyObject {
    /// `runs` in the target language, each piece where the sentence puts
    /// it. Throws if it can't (the language isn't on the device, say).
    func translate(_ runs: [PageText.Run]) async throws -> [PageText.Run]
    /// Stops whatever it's doing.
    func cancel()
}

/// One page being translated. Made for a page and its two languages,
/// started once, and over at Show Original or when the page moves on;
/// translating again is a new one.
@MainActor
@Observable
public final class PageTranslation {
    public enum Phase: Equatable, Sendable {
        /// Working through the page.
        case translating
        /// Done, and translating text the page adds.
        case translated
        /// Nothing could be translated (the language isn't on the device,
        /// say); the page is as it was.
        case failed
        /// Show Original, or the page moved on: the page's own words.
        case original
    }

    public private(set) var phase: Phase = .translating
    /// How far through the units found so far, from 0 to 1.
    public private(set) var progress = 0.0
    public let source: Locale.Language
    public let target: Locale.Language

    /// Units translated at a time between looks at where the page is
    /// scrolled, so translating follows the reader down the page.
    static let batch = 4
    /// Failures in a row, with nothing written yet, before giving up.
    static let failureLimit = 3

    /// Held weakly: the page's controller holds this (through its
    /// `PageTranslator`), so a closed tab's page goes; once it has, this
    /// sees a page that's gone (no address), and stops.
    @ObservationIgnored private weak var heldPage: (any PageTextAccess)?
    private var page: any PageTextAccess { heldPage ?? GonePage.shared }
    @ObservationIgnored private let makeTranslator: @MainActor (Locale.Language) -> (any RunTranslating)?
    /// Made so far, by source language code; nil once one couldn't work.
    @ObservationIgnored private var translators: [String: (any RunTranslating)?] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var queue: [PageText.Unit] = []
    @ObservationIgnored private var view = PageText.View()
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var changed = false
    @ObservationIgnored private var title: String?
    @ObservationIgnored private var found = 0
    @ObservationIgnored private var handled = 0
    @ObservationIgnored private var written = 0
    @ObservationIgnored private var failures = 0

    /// `translator` makes a translator from a source language into
    /// `target`, or nil if it can't; it's asked once per language.
    public init(
        page: any PageTextAccess, source: Locale.Language, target: Locale.Language,
        translator: @escaping @MainActor (Locale.Language) -> (any RunTranslating)?
    ) {
        self.heldPage = page
        self.source = source
        self.target = target
        self.makeTranslator = translator
    }

    /// Translation on the device, with languages already downloaded (the
    /// app asks the system to download them first); nil before macOS 26.4
    /// and iOS 26.4, where translation is simply absent.
    public static func onDevice(page: any PageTextAccess, source: Locale.Language, target: Locale.Language) -> PageTranslation? {
        #if canImport(Translation)
        if #available(macOS 26.4, iOS 26.4, *) {
            return PageTranslation(page: page, source: source, target: target) { from in
                SystemRunTranslator(installedSource: from, target: target)
            }
        }
        #endif
        return nil
    }

    /// Starts translating. Once only.
    public func start() {
        guard task == nil, phase == .translating, pageURL == nil else { return }
        pageURL = page.url
        page.onPageTextChange = { [weak self] in self?.pageAddedText() }
        task = Task { [weak self] in await self?.run(reading: true) }
    }

    /// Show Original: stops, and puts the page's own words and title back.
    public func showOriginal() async {
        guard phase != .original else { return }
        stop()
        await page.restorePageText()
    }

    /// Stops without touching the page (its tab is closing).
    public func stop() {
        task?.cancel()
        task = nil
        for case let translator? in translators.values { translator.cancel() }
        if page.onPageTextChange != nil { page.onPageTextChange = nil }
        phase = .original
    }

    // MARK: The work

    private var stillOnPage: Bool {
        Self.samePage(page.url, pageURL)
    }

    /// The same page, ignoring a jump within it (#section).
    static func samePage(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        func bare(_ url: URL) -> String {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.fragment = nil
            return parts?.string ?? url.absoluteString
        }
        return bare(a) == bare(b)
    }

    private func pageAddedText() {
        guard phase == .translating || phase == .translated else { return }
        if task != nil {
            changed = true
        } else {
            task = Task { [weak self] in await self?.run(reading: false) }
        }
    }

    private func run(reading: Bool) async {
        if reading {
            guard let snapshot = await page.readPageText(), !Task.isCancelled else { return finishRun() }
            guard stillOnPage else { return leave() }
            queue = snapshot.units
            view = snapshot.view
            found = queue.count
            title = await translatedTitle(snapshot.title)
        }
        while !Task.isCancelled {
            guard stillOnPage else { return leave() }
            // Each batch: anything the page added, and where it's scrolled.
            changed = false
            if let more = await page.readMorePageText() {
                view = more.view
                queue += more.units
                found += more.units.count
            }
            guard !Task.isCancelled else { return }
            guard !queue.isEmpty else {
                if changed { continue }
                break
            }
            let next = Self.ordered(queue, view: view).prefix(Self.batch)
            let ids = Set(next.map(\.id))
            queue.removeAll { ids.contains($0.id) }
            for unit in next {
                let runs = await translation(of: unit)
                guard !Task.isCancelled else { return }
                guard stillOnPage else { return leave() }
                if let runs {
                    // Checked just before writing, with nothing in between:
                    // Show Original can't be overtaken by a late write.
                    let count = await page.writePageText(
                        [PageText.Translation(id: unit.id, runs: runs)], language: tag, title: title)
                    if count > 0 { written += 1; title = nil }
                }
                handled += 1
                progress = found == 0 ? 1 : min(1, Double(handled) / Double(found))
                if written == 0, failures >= Self.failureLimit {
                    task = nil
                    phase = .failed
                    if page.onPageTextChange != nil { page.onPageTextChange = nil }
                    await page.restorePageText()
                    return
                }
            }
        }
        guard !Task.isCancelled else { return }
        // A title translated on a page whose units couldn't be written.
        if let title, stillOnPage {
            _ = await page.writePageText([], language: tag, title: title)
            self.title = nil
        }
        finishRun()
    }

    private func finishRun() {
        task = nil
        guard phase == .translating || phase == .translated else { return }
        progress = 1
        phase = written == 0 && failures > 0 ? .failed : .translated
        if phase == .failed, page.onPageTextChange != nil { page.onPageTextChange = nil }
    }

    /// The page moved on: whatever's there now is its own.
    private func leave() {
        stop()
        Task { await page.restorePageText() }
    }

    private var tag: String { target.minimalIdentifier }

    /// The units in the order to translate them: those on screen, from the
    /// top; then those below, nearest first (where the reader is going);
    /// then those above.
    static func ordered(_ units: [PageText.Unit], view: PageText.View) -> [PageText.Unit] {
        // A little above the top counts as on screen: a paragraph cut by it.
        let top = view.top - 40
        func key(_ unit: PageText.Unit) -> (Int, Double) {
            if unit.top >= top, unit.top <= view.bottom { return (0, unit.top) }
            if unit.top > view.bottom { return (1, unit.top - view.bottom) }
            return (2, top - unit.top)
        }
        return units.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Languages

    /// The language a unit is in: its block's `lang` (checked against its
    /// text), else the page's, unless the text is long enough to be sure
    /// it's another (an English paragraph on a German page).
    static func language(of unit: PageText.Unit, page: Locale.Language) -> Locale.Language {
        if let declared = unit.declaredLanguage {
            return PageLanguage.detect(declared: declared, sample: unit.text) ?? page
        }
        let text = unit.runs.filter { !$0.isFixed }.map(\.text).joined()
        guard text.count >= 40 else { return page }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (guess, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.9 else { return page }
        let detected = Locale.Language(identifier: guess.rawValue)
        return detected.languageCode == page.languageCode ? page : detected
    }

    private func translator(from language: Locale.Language) -> (any RunTranslating)? {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        if let made = translators[code] { return made }
        let made = makeTranslator(language)
        translators[code] = .some(made)
        return made
    }

    private func dropTranslator(for language: Locale.Language) {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        translators[code] = .some(nil)
    }

    // MARK: Translating a unit

    /// A unit's translation, ready to write, or nil to leave it as it is:
    /// already in the target language, no translator for its language, or
    /// a translation that lost a piece or ran away.
    private func translation(of unit: PageText.Unit) async -> [PageText.Run]? {
        let from = Self.language(of: unit, page: source)
        guard from.languageCode != target.languageCode, let translator = translator(from: from) else { return nil }
        do {
            var out: [PageText.Run] = []
            for part in PageText.parts(of: unit) {
                guard let runs = try await translated(part, with: translator) else { return nil }
                out = Self.joined(out, runs, spaced: spacesSentences)
            }
            out = PageText.movingEdgeSpaces(out)
            failures = 0
            return PageText.fits(out, unit) ? out : nil
        } catch is CancellationError {
            return nil
        } catch {
            // Another language than the page's that isn't on the device:
            // its units stay as they are. The page's own counts as a failure.
            if from.languageCode != source.languageCode { dropTranslator(for: from) } else { failures += 1 }
            return nil
        }
    }

    /// One part, whole; if that runs away or loses a piece, sentence by
    /// sentence; nil if that doesn't work either.
    private func translated(_ part: [PageText.Run], with translator: any RunTranslating) async throws -> [PageText.Run]? {
        if let runs = try await attempt(part, with: translator) { return runs }
        let sentences = PageText.parts(of: PageText.Unit(id: 0, top: 0, runs: part), limit: 1)
        guard sentences.count > 1 else { return nil }
        var out: [PageText.Run] = []
        for sentence in sentences {
            guard let runs = try await attempt(sentence, with: translator) else { return nil }
            out = Self.joined(out, runs, spaced: spacesSentences)
        }
        return out
    }

    private func attempt(_ part: [PageText.Run], with translator: any RunTranslating) async throws -> [PageText.Run]? {
        // Nothing to translate in a part of only kept pieces and spaces.
        guard part.contains(where: { !$0.isFixed && $0.text.contains(where: \.isLetter) }) else { return part }
        let raw = try await translator.translate(part)
        try Task.checkCancellation()
        let runs = PageText.movingEdgeSpaces(Self.settled(raw, from: part))
        let input = part.map(\.text).joined(), output = runs.map(\.text).joined()
        guard !PageText.isRunaway(input: input, output: output),
              PageText.fits(runs, PageText.Unit(id: 0, top: 0, runs: part)) else { return nil }
        return runs
    }

    /// The translator's runs made whole again: kept pieces with their own
    /// words, and pieces with no words (an empty anchor) that the
    /// translator dropped put back where they were, at the start or end.
    static func settled(_ runs: [PageText.Run], from part: [PageText.Run]) -> [PageText.Run] {
        var byPiece: [Int: PageText.Run] = [:]
        for run in part { if let piece = run.piece { byPiece[piece] = run } }
        var out = runs.map { run -> PageText.Run in
            guard let piece = run.piece, let original = byPiece[piece] else { return PageText.Run(text: run.text) }
            return original.isFixed ? original : PageText.Run(piece: piece, text: run.text)
        }
        let present = Set(out.compactMap(\.piece))
        for (index, run) in part.enumerated() {
            guard let piece = run.piece, !present.contains(piece),
                  !run.text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            if index == 0 { out.insert(run, at: 0) } else { out.append(run) }
        }
        return out
    }

    /// Whether the target language puts a space between sentences (not
    /// Chinese, Japanese, Thai, and the like).
    private var spacesSentences: Bool {
        !["zh", "ja", "th", "lo", "km", "my", "yue"].contains(target.languageCode?.identifier ?? "")
    }

    /// Two parts' translations as one, with a space between sentences
    /// where the translator trimmed it.
    static func joined(_ a: [PageText.Run], _ b: [PageText.Run], spaced: Bool) -> [PageText.Run] {
        guard let last = a.last?.text.last, let first = b.first?.text.first else { return a + b }
        guard spaced, !last.isWhitespace, !first.isWhitespace else { return a + b }
        return a + [PageText.Run(text: " ")] + b
    }

    /// The tab's title in the target language, or nil to keep it.
    private func translatedTitle(_ title: String) async -> String? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: \.isLetter), text.count <= 1000 else { return nil }
        let unit = PageText.Unit(id: 0, top: 0, runs: [PageText.Run(text: text)])
        guard let runs = await translation(of: unit) else { return nil }
        let out = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty || out.count > 1000 ? nil : out
    }
}

/// A page that has closed: no address, nothing to read or write.
@MainActor
private final class GonePage: PageTextAccess {
    static let shared = GonePage()
    var url: URL? { nil }
    func readPageText() async -> PageText.Snapshot? { nil }
    func readMorePageText() async -> PageText.More? { nil }
    func writePageText(_ translations: [PageText.Translation], language: String, title: String?) async -> Int { 0 }
    func restorePageText() async {}
    var onPageTextChange: (@MainActor () -> Void)? {
        get { nil }
        set {}
    }
}

/// Whether page translation is here, and which languages it has.
public enum PageTranslationSupport {
    /// macOS 26.4 and iOS 26.4 or later: before that, links can't stay in
    /// place, so translation is simply absent (David, 2026-11-27).
    public static var isAvailable: Bool {
        #if canImport(Translation)
        if #available(macOS 26.4, iOS 26.4, *) { return true }
        #endif
        return false
    }

    /// The languages the translator knows, downloaded or not; none where
    /// it's absent.
    public static func supportedLanguages() async -> [Locale.Language] {
        #if canImport(Translation)
        if #available(macOS 26.4, iOS 26.4, *) { return await LanguageAvailability().supportedLanguages }
        #endif
        return []
    }

    /// Whether `source` to `target` is already on the device, so it can
    /// start at once; otherwise the app asks the system to download it.
    /// The fast model counts (it has its own download), unless it has no
    /// such pair.
    public static func isInstalled(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        #if canImport(Translation)
        if #available(macOS 26.4, iOS 26.4, *) {
            let fast = await LanguageAvailability(preferredStrategy: .lowLatency).status(from: source, to: target)
            if fast != .unsupported { return fast == .installed }
            return await LanguageAvailability().status(from: source, to: target) == .installed
        }
        #endif
        return false
    }

    /// Whether to ask the system for the fast model when downloading:
    /// yes, unless it has no such pair (then the careful one).
    public static func downloadsFastModel(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        #if canImport(Translation)
        if #available(macOS 26.4, iOS 26.4, *) {
            return await LanguageAvailability(preferredStrategy: .lowLatency).status(from: source, to: target) != .unsupported
        }
        #endif
        return false
    }
}

#if canImport(Translation)
/// Apple's Translation framework, one source and target language.
///
/// Fast first (2026-11-28): Apple's fast model with the pieces marked by
/// tags in the text (`TaggedRuns`), about 13 times quicker than the careful
/// model, which took about 2s a paragraph however it was asked. A part
/// whose tags don't come back exactly goes to the careful model, with the
/// pieces marked as runs (marked with their number as a `link`, kept
/// pieces also marked to skip), which come back around the right words,
/// even when the sentence's order moves (step 1's findings). Where the
/// fast model isn't on the device or has no such pair, it's careful only.
@available(macOS 26.4, iOS 26.4, *)
@MainActor
public final class SystemRunTranslator: RunTranslating {
    // The framework's sessions aren't marked Sendable, though their calls
    // run off the main thread. Firn uses each from one translation, one
    // call at a time (the translator's loop awaits each), so neither is
    // ever shared.
    nonisolated(unsafe) private var fast: TranslationSession?
    nonisolated(unsafe) private var carefulSession: TranslationSession?
    private let makeCareful: () -> TranslationSession

    /// A session from SwiftUI's `translationTask`, say: careful only.
    public init(session: TranslationSession) {
        self.makeCareful = { session }
    }

    /// For languages already downloaded; translating throws otherwise.
    public init(installedSource source: Locale.Language, target: Locale.Language) {
        self.fast = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        self.makeCareful = { TranslationSession(installedSource: source, target: target) }
    }

    public func translate(_ runs: [PageText.Run]) async throws -> [PageText.Run] {
        if let fast, let tagged = TaggedRuns.encode(runs) {
            do {
                nonisolated(unsafe) let session = fast
                let response = try await session.translate(tagged)
                if let out = TaggedRuns.decode(response.targetText, from: runs) { return out }
            } catch let error where TranslationError.notInstalled ~= error
                || TranslationError.unsupportedLanguagePairing ~= error {
                self.fast = nil
            }
            try Task.checkCancellation()
        }
        return try await careful(runs)
    }

    private func careful(_ runs: [PageText.Run]) async throws -> [PageText.Run] {
        nonisolated(unsafe) let session = carefulSession ?? makeCareful()
        carefulSession = session
        let response = try await session.translate(Self.attributed(runs))
        if let text = response.attributedTargetText { return Self.runs(from: text) }
        // Without its marks the pieces are lost: only plain text will do.
        guard !runs.contains(where: { $0.piece != nil }) else { throw Lost() }
        return [PageText.Run(text: response.targetText)]
    }

    public func cancel() {
        fast?.cancel()
        carefulSession?.cancel()
    }

    struct Lost: Error {}

    private static let scheme = "firn-piece"

    static func attributed(_ runs: [PageText.Run]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            if let piece = run.piece {
                part.link = URL(string: "\(scheme):\(piece)")
                if run.isFixed { part[AttributeScopes.TranslationAttributes.SkipTranslationAttribute.self] = true }
            }
            out += part
        }
        return out
    }

    static func runs(from text: AttributedString) -> [PageText.Run] {
        var out: [PageText.Run] = []
        for run in text.runs {
            let words = String(text[run.range].characters)
            var piece: Int?
            if let link = run.link, link.scheme == scheme {
                piece = Int(link.absoluteString.dropFirst(scheme.count + 1))
            }
            // A piece split over runs (other marks inside it) is one piece.
            if let last = out.last, last.piece == piece {
                out[out.count - 1].text += words
            } else {
                out.append(PageText.Run(piece: piece, text: words))
            }
        }
        return out
    }
}
#endif
