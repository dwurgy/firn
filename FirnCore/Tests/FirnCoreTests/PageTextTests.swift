import Foundation
import Testing
import WebKit
@testable import FirnCore

/// Translating pages, step 2: the logic around the page's text (`PageText`).
struct PageTextTests {
    private typealias Run = PageText.Run

    private func unit(_ runs: [Run]) -> PageText.Unit {
        PageText.Unit(id: 0, top: 0, runs: runs)
    }

    @Test func readsTheScriptsAnswer() throws {
        let answer: [String: Any] = [
            "lang": " es ", "title": "Hola\n mundo", "sample": "Hola",
            "units": [
                ["id": 0, "top": 12, "runs": [["k": -1, "t": "Haz\n  clic "], ["k": 0, "t": "aquí"],
                                               ["k": 1, "t": "x  =  1", "fixed": true]]],
                ["id": 1, "runs": [["k": 1, "t": "skips a number"]]],
                ["id": 2, "runs": [["k": -1, "t": 5]]],
                "nonsense",
            ],
        ]
        let snapshot = try #require(PageText.snapshot(from: answer))
        #expect(snapshot.declaredLanguage == "es")
        #expect(snapshot.title == "Hola mundo")
        #expect(snapshot.units.count == 1)
        let runs = try #require(snapshot.units.first?.runs)
        #expect(runs == [Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(piece: 1, text: "x  =  1", isFixed: true)])
        #expect(PageText.snapshot(from: "units") == nil)
        #expect(PageText.snapshot(from: ["units": "none"]) == nil)
        #expect(PageText.snapshot(from: ["lang": "<script>", "units": []])?.declaredLanguage == nil)
    }

    @Test func aTranslationMustKeepEveryPieceOnce() {
        let original = unit([Run(text: "Haz clic "), Run(piece: 0, text: "aquí"), Run(text: " para "),
                             Run(piece: 1, text: "continuar"), Run(text: ".")])
        let moved = [Run(piece: 1, text: "Continue"), Run(text: " by clicking "), Run(piece: 0, text: "here"), Run(text: ".")]
        #expect(PageText.fits(moved, original))
        #expect(!PageText.fits([Run(text: "Click here to continue.")], original))
        #expect(!PageText.fits(moved + [Run(piece: 0, text: "again")], original))
        #expect(!PageText.fits([Run(piece: 0, text: "a"), Run(piece: 1, text: "b"), Run(piece: 2, text: "c")], original))
        #expect(!PageText.fits([], original))
    }

    @Test func movesEdgeSpacesOutOfPieces() {
        let back = [Run(text: "Click"), Run(piece: 0, text: " here "), Run(text: "to continue"),
                    Run(piece: 1, text: "x ", isFixed: true)]
        #expect(PageText.movingEdgeSpaces(back) == [
            Run(text: "Click "), Run(piece: 0, text: "here"), Run(text: " to continue"),
            Run(piece: 1, text: "x ", isFixed: true),
        ])
    }

    @Test func cutsLongUnitsBySentenceButNeverThroughAPiece() {
        let sentence = "Esta es una frase bastante larga sobre la nieve que cae despacio en la montaña. "
        let runs = [Run(text: String(repeating: sentence, count: 6)),
                    Run(piece: 0, text: "Un enlace que cruza. Dos frases dentro."),
                    Run(text: " " + String(repeating: sentence, count: 6))]
        let whole = unit(runs)
        let parts = PageText.parts(of: whole, limit: 200)
        #expect(parts.count > 3)
        #expect(parts.flatMap { $0 }.map(\.text).joined() == whole.text)
        #expect(parts.flatMap { $0 }.compactMap(\.piece) == [0])
        #expect(parts.allSatisfy { $0.map(\.text).joined().utf16.count <= 260 })
        let withPiece = parts.first { $0.contains { $0.piece == 0 } }
        #expect(withPiece?.first { $0.piece == 0 }?.text == "Un enlace que cruza. Dos frases dentro.")
        // Short units stay whole.
        #expect(PageText.parts(of: unit([Run(text: sentence)])) == [[Run(text: sentence)]])
    }

    @Test func spotsARunaway() {
        let input = String(repeating: "Nieve tranquila. ", count: 40)
        #expect(!PageText.isRunaway(input: input, output: String(repeating: "Quiet snow. ", count: 45)))
        #expect(PageText.isRunaway(input: input, output: String(repeating: "Quiet snow. ", count: 200)))
        // Chinese to English isn't one, though it has more letters.
        #expect(!PageText.isRunaway(input: "安静的雪落在山上", output: "Quiet snow falls on the mountain"))
    }

    // MARK: Language

    private let spanish = "La nieve cae despacio sobre la montaña y el pueblo duerme tranquilo hasta la mañana."

    @Test func detectsThePagesLanguage() {
        #expect(PageLanguage.detect(declared: "es-MX", sample: spanish)?.minimalIdentifier == "es-MX")
        // A template's "en" over Spanish text.
        #expect(PageLanguage.detect(declared: "en", sample: spanish)?.languageCode == "es")
        #expect(PageLanguage.detect(declared: nil, sample: spanish)?.languageCode == "es")
        #expect(PageLanguage.detect(declared: "de", sample: "OK")?.languageCode == "de")
        #expect(PageLanguage.detect(declared: nil, sample: "OK") == nil)
    }

    @Test func offersOnlyALanguageThePersonDoesntRead() {
        let supported = ["en", "en-GB", "es", "de", "fr"].map(Locale.Language.init(identifier:))
        let spanish = Locale.Language(identifier: "es-ES")
        #expect(PageLanguage.offer(page: spanish, preferred: ["en-US", "es-MX"], supported: supported) == nil)
        #expect(PageLanguage.offer(page: spanish, preferred: ["en-US"], supported: supported)?.minimalIdentifier == "en")
        #expect(PageLanguage.offer(page: spanish, preferred: ["en-GB"], supported: supported)?.maximalIdentifier
                == Locale.Language(identifier: "en-GB").maximalIdentifier)
        #expect(PageLanguage.offer(page: spanish, preferred: ["xx", "fr-CA"], supported: supported)?.languageCode == "fr")
        #expect(PageLanguage.offer(page: Locale.Language(identifier: "ja"), preferred: ["en"], supported: supported) == nil)
        #expect(PageLanguage.offer(page: spanish, preferred: ["xx"], supported: supported) == nil)
        // The device's list starts with a regional English: someone in the
        // US or Zimbabwe is offered plain English, not English (India).
        let device = ["en-IN", "es-CL", "en-CA", "es", "en-GB", "en", "zh-HK", "zh"].map(Locale.Language.init(identifier:))
        #expect(PageLanguage.offer(page: spanish, preferred: ["en-US"], supported: device)?.minimalIdentifier == "en")
        #expect(PageLanguage.offer(page: spanish, preferred: ["en-ZW"], supported: device)?.minimalIdentifier == "en")
        #expect(PageLanguage.offer(page: spanish, preferred: ["en-CA"], supported: device)?.region?.identifier == "CA")
    }
}

/// The page script itself, in a real web view.
@MainActor
struct PageTextPageTests {
    private static let page = """
        <!doctype html><html lang="es"><head><title>Hola mundo</title></head><body>
        <h1 id="h">Una mañana tranquila</h1>
        <p id="p">Haz clic <a id="l" href="/mas" onclick="window.clicked = 1">aquí</a> para <b>continuar</b>.</p>
        <p id="n">Ver <a href="/x">el <b>informe</b></a> hoy.</p>
        <p id="br">Línea uno<br>Línea dos</p>
        <pre>no tocar el texto</pre><code>x = 1</code>
        <p translate="no">Nombre propio</p>
        <p class="notranslate">Otro nombre</p>
        <div contenteditable="true">texto editable</div>
        <form><input value="valor"><textarea>texto del área</textarea><button>Enviar ahora</button></form>
        <script>var s = "texto del script";</script>
        </body></html>
        """

    private func load(_ html: String) async throws -> (WebKitPageController, UUID) {
        let id = UUID()
        let page = try #require(BrowserEngine.makePage(dataStoreID: id) as? WebKitPageController)
        page.webView.loadHTMLString(html, baseURL: URL(string: "https://translate.test/page")!)
        for _ in 0..<100 where page.url == nil || page.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
        return (page, id)
    }

    private func inPage(_ script: String, _ page: WebKitPageController) async throws -> Any? {
        try await page.webView.callAsyncJavaScript(script, contentWorld: .page)
    }

    @Test func readsOnlyWhatShouldBeTranslated() async throws {
        let (page, id) = try await load(Self.page)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        let snapshot = try #require(await page.readPageText())
        #expect(snapshot.declaredLanguage == "es")
        #expect(snapshot.title == "Hola mundo")
        #expect(snapshot.language?.languageCode == "es")
        let texts = snapshot.units.map { $0.text.trimmingCharacters(in: .whitespaces) }
        for wanted in ["Una mañana tranquila", "Haz clic aquí para continuar.", "Ver el informe hoy.",
                       "Línea uno", "Línea dos", "Enviar ahora"] {
            #expect(texts.contains(wanted), "\(wanted) wasn't read")
        }
        for text in texts {
            for banned in ["no tocar", "x = 1", "Nombre propio", "Otro nombre", "editable", "valor", "área", "script"] {
                #expect(!text.contains(banned), "\(banned) was read")
            }
        }
        // The link and the bold are pieces; bold inside a link travels whole.
        let link = try #require(snapshot.units.first { $0.text.contains("Haz clic") })
        #expect(link.runs.filter { $0.piece != nil }.map(\.text) == ["aquí", "continuar"])
        let nested = try #require(snapshot.units.first { $0.text.contains("Ver el") })
        #expect(nested.runs.first { $0.piece != nil } == Run(piece: 0, text: "el informe", isFixed: true))
        // Firn's script is nowhere the page can reach.
        #expect(try await inPage("return typeof firnPageText", page) as? String == "undefined")
    }

    private typealias Run = PageText.Run

    @Test func readsThePagesLanguageWithoutChangingIt() async throws {
        let (page, id) = try await load(Self.page)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        let before = try #require(try await inPage("return document.body.innerHTML", page) as? String)
        let script = try #require(PageText.script("language"))
        let result = try await page.webView.callAsyncJavaScript(
            script, arguments: ["input": NSNull()], in: nil, contentWorld: WebKitPageController.firnWorld)
        let found = try #require(PageText.language(from: result))
        #expect(found.declared == "es")
        #expect(found.sample.contains("Una mañana tranquila"))
        for banned in ["no tocar", "x = 1", "texto del script", "texto del área"] {
            #expect(!found.sample.contains(banned), "\(banned) was sampled")
        }
        #expect(PageLanguage.detect(declared: found.declared, sample: found.sample)?.languageCode == "es")
        #expect(try await inPage("return document.body.innerHTML", page) as? String == before)
        #expect(PageText.language(from: ["lang": 5]) == nil)
    }

    @Test func aNewPageStartsWithNothingOffered() async throws {
        let (page, id) = try await load(Self.page)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        let translator = try #require(page.translator)
        translator.pageChanged()
        #expect(translator.state == .none)
        #expect(translator.target == nil)
        translator.translate()
        #expect(translator.state == .none)
    }

    @Test func writesPlainTextAndPutsTheOriginalBack() async throws {
        let (page, id) = try await load(Self.page)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        let before = try #require(try await inPage("return document.body.innerHTML", page) as? String)
        _ = try await inPage("window.savedLink = document.getElementById('l'); return 0", page)
        let snapshot = try #require(await page.readPageText())
        let link = try #require(snapshot.units.first { $0.text.contains("Haz clic") })
        let heading = try #require(snapshot.units.first { $0.text.contains("mañana") })
        let nested = try #require(snapshot.units.first { $0.text.contains("Ver el") })

        let written = await page.writePageText([
            // The order moves: "continue" first, then the link.
            .init(id: link.id, runs: [Run(piece: 1, text: "Continue"), Run(text: " by clicking "),
                                      Run(piece: 0, text: "here"), Run(text: ".")]),
            // Markup in a translation stays text.
            .init(id: heading.id, runs: [Run(text: "A calm <img src=x onerror=\"window.hit=1\"> morning")]),
            // Drops its piece: not written.
            .init(id: nested.id, runs: [Run(text: "See the report today.")]),
        ], language: "en", title: "Hello world")
        #expect(written == 2)

        let paragraph = try await inPage("return document.getElementById('p').innerHTML", page) as? String
        #expect(paragraph == "<b>Continue</b> by clicking <a id=\"l\" href=\"/mas\" onclick=\"window.clicked = 1\">here</a>.")
        #expect(try await inPage("return document.getElementById('l') === window.savedLink", page) as? Bool == true)
        #expect(try await inPage("return document.getElementById('p').getAttribute('lang')", page) as? String == "en")
        #expect(try await inPage("return document.querySelectorAll('img').length", page) as? Int == 0)
        #expect(try await inPage("return document.getElementById('h').textContent", page) as? String
                == "A calm <img src=x onerror=\"window.hit=1\"> morning")
        #expect(try await inPage("return document.getElementById('n').textContent", page) as? String == "Ver el informe hoy.")
        #expect(try await inPage("return document.title", page) as? String == "Hello world")

        await page.restorePageText()
        #expect(try await inPage("return document.body.innerHTML", page) as? String == before)
        #expect(try await inPage("return document.title", page) as? String == "Hola mundo")
        #expect(try await inPage("return document.getElementById('l') === window.savedLink", page) as? Bool == true)
    }

    @Test func refusesHostileShapes() async throws {
        let (page, id) = try await load(Self.page)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) } }
        let before = try #require(try await inPage("return document.body.innerHTML", page) as? String)
        _ = try #require(await page.readPageText())
        let script = try #require(PageText.script("write"))
        for input: Any in [NSNull(), "units", ["units": "x"], ["units": [["id": 9999, "runs": []]]],
                           ["units": [["id": 0, "runs": [["k": 7, "t": "x"]]]]],
                           ["units": [["id": 0, "runs": [["k": -1, "t": 5]]]]],
                           ["lang": "\"><script>", "units": [] as [Any]]] {
            let count = try await page.webView.callAsyncJavaScript(
                script, arguments: ["input": input], in: nil, contentWorld: WebKitPageController.firnWorld)
            #expect((count as? Int) == 0)
        }
        #expect(try await inPage("return document.body.innerHTML", page) as? String == before)
    }
}
