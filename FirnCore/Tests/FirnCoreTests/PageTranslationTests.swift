import Foundation
import Testing
import WebKit
@testable import FirnCore

private typealias Run = PageText.Run
private typealias Unit = PageText.Unit

/// A page as the translator sees it, with no WebKit.
@MainActor
private final class FakeTextPage: PageTextAccess {
    var url: URL? = URL(string: "https://translate.test/page")
    var snapshot: PageText.Snapshot
    var added: [Unit] = []
    var view = PageText.View(top: 0, height: 800)
    var writes: [PageText.Translation] = []
    var titles: [String] = []
    var restores = 0
    var onPageTextChange: (@MainActor () -> Void)?

    init(units: [Unit], title: String = "Hola mundo") {
        snapshot = PageText.Snapshot(declaredLanguage: "es", title: title, sample: "", units: units,
                                     view: PageText.View(top: 0, height: 800))
    }

    func readPageText() async -> PageText.Snapshot? { snapshot }
    func readMorePageText() async -> PageText.More? {
        defer { added = [] }
        return PageText.More(view: view, units: added)
    }
    func writePageText(_ translations: [PageText.Translation], language: String, title: String?) async -> Int {
        writes += translations
        if let title { titles.append(title) }
        return translations.count
    }
    func restorePageText() async { restores += 1 }
}

/// Words in, words out: each plain word gets a "~" (so it's visibly
/// translated), and pieces swap places when asked, as word order does.
@MainActor
private final class FakeTranslator: RunTranslating {
    var calls: [[Run]] = []
    var swapsPieces = false
    var fails = false
    var dropsPieces = false
    var runsAwayOver = Int.max
    var delay: Duration = .zero
    var cancelled = false
    /// The quick way misses any part with a piece; the careful way doesn't.
    var missesPieces = false
    var carefulCalls = 0

    func translateCarefully(_ runs: [Run]) async throws -> [Run] {
        carefulCalls += 1
        let misses = missesPieces
        missesPieces = false
        defer { missesPieces = misses }
        return try await translate(runs)
    }

    func translate(_ runs: [Run]) async throws -> [Run] {
        calls.append(runs)
        if missesPieces, runs.contains(where: { $0.piece != nil }) { throw PiecesMissed() }
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw URLError(.cannotFindHost) }
        if runs.map(\.text).joined().count > runsAwayOver {
            return [Run(text: String(repeating: "loop ", count: 400))]
        }
        var out = runs.map { run in
            Run(piece: run.piece, text: run.isFixed ? "CHANGED" : "~" + run.text + " ", isFixed: false)
        }
        if dropsPieces { out = out.filter { $0.piece == nil } }
        if swapsPieces {
            let pieces = out.indices.filter { out[$0].piece != nil }
            if pieces.count == 2 { out.swapAt(pieces[0], pieces[1]) }
        }
        return out
    }

    func cancel() { cancelled = true }
}

@MainActor
struct PageTranslationTests {
    private let es = Locale.Language(identifier: "es")
    private let en = Locale.Language(identifier: "en")

    private func unit(_ id: Int, top: Double = 0, _ runs: [Run], lang: String? = nil) -> Unit {
        Unit(id: id, top: top, runs: runs, declaredLanguage: lang)
    }

    private func translate(_ page: FakeTextPage, _ translator: FakeTranslator) async throws -> PageTranslation {
        let translation = PageTranslation(page: page, source: es, target: en) { _ in translator }
        translation.start()
        for _ in 0..<200 where translation.phase == .translating {
            try await Task.sleep(for: .milliseconds(10))
        }
        return translation
    }

    @Test func leavesPartsTheQuickWayMissedForTheCarefulWayLast() async throws {
        let page = FakeTextPage(units: [
            unit(0, [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: ". Y luego espera.")]),
            unit(1, top: 50, [Run(text: "Una mañana tranquila")]),
            unit(2, top: 100, [Run(text: "Otra más")]),
        ])
        let translator = FakeTranslator()
        translator.missesPieces = true
        let translation = try await translate(page, translator)
        #expect(translation.phase == .translated)
        // The rest of the page first; the missed unit carefully, once.
        #expect(page.writes.map(\.id) == [1, 2, 0])
        #expect(page.writes.last?.runs.compactMap(\.piece) == [0])
        #expect(translator.carefulCalls == 1)
    }

    @Test func ordersWhatsOnScreenFirstThenBelowThenAbove() {
        let units = [unit(0, top: 100, [Run(text: "a")]), unit(1, top: 2000, [Run(text: "b")]),
                     unit(2, top: 1100, [Run(text: "c")]), unit(3, top: 1500, [Run(text: "d")]),
                     unit(4, top: 3000, [Run(text: "e")]), unit(5, top: 990, [Run(text: "f")])]
        let order = PageTranslation.ordered(units, view: PageText.View(top: 1000, height: 800))
        #expect(order.map(\.id) == [5, 2, 3, 1, 4, 0])
    }

    @Test func translatesEveryUnitAndTheTitle() async throws {
        let page = FakeTextPage(units: [
            unit(0, [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: " para "),
                     Run(piece: 1, text: "continuar"), Run(text: ".")]),
            unit(1, top: 50, [Run(text: "Una mañana tranquila")]),
        ])
        let translator = FakeTranslator()
        translator.swapsPieces = true
        let translation = try await translate(page, translator)
        #expect(translation.phase == .translated)
        #expect(translation.progress == 1)
        #expect(page.titles == ["~Hola mundo"])
        #expect(page.writes.map(\.id) == [0, 1])
        // The pieces moved with the sentence, and their edge spaces moved out.
        let first = try #require(page.writes.first)
        #expect(first.runs.compactMap(\.piece) == [1, 0])
        #expect(first.runs.first { $0.piece == 1 }?.text == "~continuar")
        #expect(PageText.fits(first.runs, page.snapshot.units[0]))
    }

    @Test func keepsKeptPiecesAndEmptyOnesAsTheyWere() {
        let part = [Run(piece: 0, text: ""), Run(text: "Usa "), Run(piece: 1, text: "git", isFixed: true), Run(text: " hoy")]
        let back = [Run(text: "~Usa "), Run(piece: 1, text: "CHANGED"), Run(text: " ~hoy")]
        let settled = PageTranslation.settled(back, from: part)
        #expect(settled.first == Run(piece: 0, text: ""))
        #expect(settled.first { $0.piece == 1 } == Run(piece: 1, text: "git", isFixed: true))
    }

    @Test func leavesAUnitAlreadyInTheTargetLanguage() async throws {
        let page = FakeTextPage(units: [
            unit(0, [Run(text: "Un párrafo en español, como el resto de la página.")]),
            unit(1, [Run(text: "A quote that the page marks as English, so it stays as it is.")], lang: "en"),
            unit(2, [Run(text: "This paragraph is plainly English, though the page says it's Spanish throughout.")]),
        ])
        let translator = FakeTranslator()
        _ = try await translate(page, translator)
        #expect(page.writes.map(\.id) == [0])
    }

    @Test func translatesABlockFromItsOwnLanguage() async throws {
        let page = FakeTextPage(units: [
            unit(0, [Run(text: "Ein Zitat auf Deutsch, mitten auf einer spanischen Seite.")], lang: "de"),
        ])
        var asked: [String] = []
        let translator = FakeTranslator()
        let translation = PageTranslation(page: page, source: es, target: en) { language in
            asked.append(language.languageCode?.identifier ?? "")
            return translator
        }
        translation.start()
        for _ in 0..<200 where translation.phase == .translating { try await Task.sleep(for: .milliseconds(10)) }
        #expect(asked.contains("de"))
        #expect(page.writes.map(\.id) == [0])
    }

    @Test func neverWritesATranslationThatLostAPiece() async throws {
        let page = FakeTextPage(units: [unit(0, [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: ".")])])
        let translator = FakeTranslator()
        translator.dropsPieces = true
        let translation = try await translate(page, translator)
        #expect(page.writes.isEmpty)
        #expect(translation.phase == .translated)
    }

    @Test func aRunawayTriesSentenceBySentence() async throws {
        let sentence = "Esta es una frase corta de prueba. "
        let page = FakeTextPage(units: [unit(0, [Run(text: String(repeating: sentence, count: 4))])], title: "")
        let translator = FakeTranslator()
        // Whole, it loops; one sentence at a time, it doesn't.
        translator.runsAwayOver = sentence.count + 5
        _ = try await translate(page, translator)
        let written = try #require(page.writes.first)
        #expect(written.runs.map(\.text).joined().components(separatedBy: "~Esta").count == 5)
        #expect(translator.calls.count == 5)
    }

    @Test func givesUpWhenNothingTranslates() async throws {
        let units = (0..<6).map { unit($0, [Run(text: "Párrafo número \($0) de la página.")]) }
        let page = FakeTextPage(units: units, title: "")
        let translator = FakeTranslator()
        translator.fails = true
        let translation = try await translate(page, translator)
        #expect(translation.phase == .failed)
        #expect(translator.calls.count == PageTranslation.failureLimit)
        #expect(page.writes.isEmpty)
        #expect(page.onPageTextChange == nil)
    }

    @Test func showOriginalStopsAndPutsThePageBack() async throws {
        let units = (0..<8).map { unit($0, top: Double($0) * 100, [Run(text: "Párrafo \($0).")]) }
        let page = FakeTextPage(units: units, title: "")
        let translator = FakeTranslator()
        translator.delay = .milliseconds(30)
        let translation = PageTranslation(page: page, source: es, target: en) { _ in translator }
        translation.start()
        try await Task.sleep(for: .milliseconds(80))
        await translation.showOriginal()
        let writes = page.writes.count
        try await Task.sleep(for: .milliseconds(150))
        #expect(translation.phase == .original)
        #expect(page.restores == 1)
        #expect(translator.cancelled)
        #expect(page.writes.count == writes)
        #expect(writes < units.count)
        #expect(page.onPageTextChange == nil)
    }

    @Test func leavingThePageStopsButAJumpWithinItDoesnt() async throws {
        #expect(PageTranslation.samePage(URL(string: "https://a.test/p#one"), URL(string: "https://a.test/p")))
        #expect(!PageTranslation.samePage(URL(string: "https://a.test/q"), URL(string: "https://a.test/p")))
        let units = (0..<8).map { unit($0, [Run(text: "Párrafo \($0).")]) }
        let page = FakeTextPage(units: units, title: "")
        let translator = FakeTranslator()
        translator.delay = .milliseconds(30)
        let translation = PageTranslation(page: page, source: es, target: en) { _ in translator }
        translation.start()
        try await Task.sleep(for: .milliseconds(80))
        page.url = URL(string: "https://translate.test/other")
        try await Task.sleep(for: .milliseconds(100))
        #expect(translation.phase == .original)
        #expect(page.writes.count < units.count)
    }

    @Test func translatesTextThePageAddsLater() async throws {
        let page = FakeTextPage(units: [unit(0, [Run(text: "Primero.")])], title: "")
        let translator = FakeTranslator()
        let translation = try await translate(page, translator)
        #expect(translation.phase == .translated)
        page.added = [unit(1, [Run(text: "Después.")])]
        page.onPageTextChange?()
        for _ in 0..<100 where page.writes.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(page.writes.map(\.id) == [0, 1])
        #expect(translation.phase == .translated)
    }

    @Test func joinsPartsWithASpaceOnlyWhereTheLanguageHasOne() {
        let a = [Run(text: "One.")], b = [Run(text: "Two.")]
        #expect(PageTranslation.joined(a, b, spaced: true).map(\.text).joined() == "One. Two.")
        #expect(PageTranslation.joined(a, b, spaced: false).map(\.text).joined() == "One.Two.")
        #expect(PageTranslation.joined([Run(text: "One. ")], b, spaced: true).map(\.text).joined() == "One. Two.")
    }

    @Test func marksPiecesForTheFrameworkAndReadsThemBack() throws {
        guard #available(macOS 26.4, iOS 26.4, *) else { return }
        let runs = [Run(text: "Usa "), Run(piece: 0, text: "git", isFixed: true), Run(text: " y "),
                    Run(piece: 1, text: "aquí")]
        let attributed = SystemRunTranslator.attributed(runs)
        #expect(String(attributed.characters) == "Usa git y aquí")
        #expect(SystemRunTranslator.runs(from: attributed).map(\.text) == runs.map(\.text))
        #expect(SystemRunTranslator.runs(from: attributed).map(\.piece) == runs.map(\.piece))
    }

    @Test func tagsPiecesForTheFastModelAndReadsThemBack() throws {
        let runs = [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: " para leer "),
                    Run(piece: 1, text: "git log", isFixed: true), Run(text: ".")]
        #expect(TaggedRuns.encode(runs) == "Haz clic <a0>aquí</a0> para leer <x1/>.")
        // The sentence's order may move; a kept piece keeps its own words.
        let out = try #require(TaggedRuns.decode("Read <x1/> by clicking <a0>here</a0>.", from: runs))
        #expect(out == [Run(text: "Read "), Run(piece: 1, text: "git log", isFixed: true),
                        Run(text: " by clicking "), Run(piece: 0, text: "here"), Run(text: ".")])
        // No pieces: plain text both ways.
        #expect(TaggedRuns.decode("Hello.", from: [Run(text: "Hola.")]) == [Run(text: "Hello.")])
    }

    @Test func refusesTagsThatDontComeBackExactly() {
        let runs = [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: " o "), Run(piece: 1, text: "allí")]
        for bad in ["Click <a0>here</a0> or there",                 // lost
                    "Click <a0>here</a0> or <a1>there</a1> <a1>x</a1>", // repeated
                    "Click <a0>here <a1>or</a1></a0> there",        // nested
                    "Click <a0>here</a0> or <a1>there",             // unclosed
                    "Click <a0>here</a0> or <a7>there</a7>",        // unknown
                    "Click <a0>here</a0> or <x1/>",                 // kept, but it isn't
                    "Click <a0>here</a0> or < a1 >there</a1>"] {    // mangled
            #expect(TaggedRuns.decode(bad, from: runs) == nil, "\(bad)")
        }
        // A piece with no words (an empty anchor) may go missing.
        let empty = [Run(piece: 0, text: ""), Run(text: "Hola")]
        #expect(TaggedRuns.decode("Hello", from: empty) == [Run(text: "Hello")])
    }

    @Test func doesntTagTextThatLooksLikeATag() {
        #expect(TaggedRuns.encode([Run(text: "Escribe <a1> aquí")]) == nil)
        #expect(TaggedRuns.encode([Run(text: "x "), Run(piece: 0, text: "</ A2>")]) == nil)
        #expect(TaggedRuns.encode([Run(text: "5 < 3 y a > 2")]) == "5 < 3 y a > 2")
    }

    /// Only where Spanish to English is already on this Mac.
    @Test func translatesWithTheRealFramework() async throws {
        guard #available(macOS 26.4, iOS 26.4, *),
              await PageTranslationSupport.isInstalled(from: es, to: en) else { return }
        let translator = SystemRunTranslator(installedSource: es, target: en)
        let runs = [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: " para continuar.")]
        let out = PageText.movingEdgeSpaces(try await translator.translate(runs))
        #expect(out.compactMap(\.piece) == [0])
        #expect(out.map(\.text).joined().lowercased().contains("click"))
        let kept = [Run(text: "Ejecuta "), Run(piece: 0, text: "git log", isFixed: true), Run(text: " en la terminal.")]
        #expect(try await translator.translate(kept).contains(kept[1]))
    }
}

/// The script's half of translating later text, in a real web view.
@MainActor
struct PageTranslationPageTests {
    @Test func noticesTextThePageAddsAndReadsOnlyThat() async throws {
        let html = """
            <!doctype html><html lang="es"><head><title>Hola</title></head><body>
            <p id="a">Primer párrafo de la página.</p>
            <blockquote lang="de"><p>Ein Zitat auf Deutsch.</p></blockquote>
            <div id="feed"></div>
            </body></html>
            """
        let id = UUID()
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        let page = try #require(BrowserEngine.makePage(dataStoreID: id) as? WebKitPageController)
        page.webView.loadHTMLString(html, baseURL: URL(string: "https://translate.test/page")!)
        for _ in 0..<100 where page.url == nil || page.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(200))

        var heard = 0
        page.onPageTextChange = { heard += 1 }
        let snapshot = try #require(await page.readPageText())
        #expect(snapshot.view.height > 0)
        #expect(snapshot.units.first { $0.text.contains("Zitat") }?.declaredLanguage == "de")
        #expect(snapshot.units.first { $0.text.contains("Primer") }?.declaredLanguage == nil)
        let first = try #require(snapshot.units.first { $0.text.contains("Primer") })

        // Firn's own write isn't the page adding text.
        #expect(await page.writePageText([.init(id: first.id, runs: [Run(text: "First paragraph.")])],
                                         language: "en", title: nil) == 1)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(heard == 0)
        #expect(await page.readMorePageText()?.units.isEmpty == true)

        // The page adds two paragraphs: Firn hears once, and reads just those.
        _ = try await page.webView.callAsyncJavaScript("""
            const feed = document.getElementById('feed');
            for (const t of ['Nuevo párrafo uno.', 'Nuevo párrafo dos.']) {
                const p = document.createElement('p'); p.textContent = t; feed.appendChild(p);
            }
            """, contentWorld: .page)
        for _ in 0..<40 where heard == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(heard == 1)
        let more = try #require(await page.readMorePageText())
        #expect(more.units.map(\.text) == ["Nuevo párrafo uno.", "Nuevo párrafo dos."])
        #expect(Set(more.units.map(\.id)).isDisjoint(with: snapshot.units.map(\.id)))

        // The page can't post to Firn's channel from its own world.
        _ = try? await page.webView.callAsyncJavaScript("""
            window.webkit.messageHandlers.firnPageTextChanged.postMessage('changed');
            """, contentWorld: .page)
        // After Show Original, nothing more is heard.
        await page.restorePageText()
        _ = try await page.webView.callAsyncJavaScript(
            "document.getElementById('feed').appendChild(document.createElement('p')).textContent = 'Otro más.';",
            contentWorld: .page)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(heard == 1)
    }
}
