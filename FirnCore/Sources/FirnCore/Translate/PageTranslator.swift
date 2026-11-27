import Foundation
import Observation

/// Translating pages, step 4: one tab's translating, for the apps' mark,
/// menus, and command bar (plan in `docs/HISTORY.md`, "Plan: translating
/// pages"). Each page controller has one. As a page finishes loading it
/// looks at the page's language and decides whether to offer translating
/// it (`PageLanguage.offer`); it holds the page's translation while the
/// page is open, never across a restart.
///
/// Languages not yet on the device go through the app: `download` asks it
/// to show the system's own download sheet (SwiftUI's `translationTask`),
/// and the app answers with `downloaded(_:)`.
@MainActor
@Observable
public final class PageTranslator {
    /// What the mark and the menus show.
    public enum State: Equatable, Sendable {
        /// Not offered: the page is in a language the person reads, one the
        /// translator doesn't know, or not a web page. Nothing shows.
        case none
        /// "Translate to [target]".
        case offered
        /// Waiting for the system's download sheet, or translating.
        case translating
        /// "Show Original".
        case translated
        /// The last try couldn't translate anything; offered again.
        case failed
    }

    /// The page's language, once checked; nil if not offered.
    public private(set) var source: Locale.Language?
    /// The language offered, the first of the person's that the translator
    /// knows; nil if not offered.
    public private(set) var target: Locale.Language?
    /// The page's translation, while it's on (or just failed).
    public private(set) var translation: PageTranslation?
    /// Languages the app should ask the system to download, then answer
    /// with `downloaded(_:)`. Nil when nothing's waiting.
    public private(set) var download: Download?
    /// The system's download was declined, or translation isn't here.
    private var failedDownload = false

    public struct Download: Equatable, Sendable {
        public let source: Locale.Language
        public let target: Locale.Language
    }

    @ObservationIgnored private weak var page: (any PageTextAccess)?
    @ObservationIgnored private var check: Task<Void, Never>?
    @ObservationIgnored private var starting: Task<Void, Never>?
    /// The address the offer was made for.
    @ObservationIgnored private var checkedURL: URL?

    public init(page: any PageTextAccess) {
        self.page = page
    }

    public var state: State {
        if failedDownload { return target == nil ? .none : .failed }
        if download != nil || starting != nil { return .translating }
        switch translation?.phase {
        case .translating: return .translating
        case .translated: return .translated
        case .failed: return target == nil ? .none : .failed
        case .original, nil: return target == nil ? .none : .offered
        }
    }

    /// The language offered, in the person's own language ("English").
    public var targetName: String? { target.map(Self.name) }
    /// The page's language, in the person's own language ("Spanish").
    public var sourceName: String? { source.map(Self.name) }

    public static func name(_ language: Locale.Language) -> String {
        let id = language.minimalIdentifier
        return Locale.current.localizedString(forIdentifier: id)
            ?? Locale.current.localizedString(forLanguageCode: language.languageCode?.identifier ?? id)
            ?? id
    }

    /// The language's name in that language ("español"), for the command bar.
    public static func ownName(_ language: Locale.Language) -> String? {
        let id = language.minimalIdentifier
        return Locale(identifier: id).localizedString(forLanguageCode: language.languageCode?.identifier ?? id)
    }

    // MARK: The page

    /// A new page came in: nothing offered or translated until it's checked.
    /// The old page's translation goes with it (its words went with the page).
    public func pageChanged() {
        check?.cancel()
        check = nil
        starting?.cancel()
        starting = nil
        translation?.stop()
        translation = nil
        download = nil
        failedDownload = false
        source = nil
        target = nil
        checkedURL = nil
    }

    /// The page finished loading (or changed without loading): `language`
    /// reads its declared language and a sample of its text, in Firn's
    /// world. Checked after `delay` seconds, once per address; nothing
    /// before macOS 26.4 and iOS 26.4.
    public func pageLoaded(after delay: Double = 0, language: @escaping @MainActor () async -> (declared: String?, sample: String)?) {
        guard PageTranslationSupport.isAvailable, let url = page?.url, WebAddress.isWebURL(url) else { return }
        if checkedURL.map({ PageTranslation.samePage($0, url) }) == true, target != nil { return }
        check?.cancel()
        check = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            // A translated page that loads again in place (a #jump) keeps it.
            // Looked at after the wait: a site changing pages without loading
            // (pushState) has just had Show Original, which ends the old
            // translation a moment later, and the new page is checked.
            if let translation = self?.translation, translation.phase == .translating || translation.phase == .translated { return }
            guard !Task.isCancelled, let self, self.page?.url == url,
                  let found = await language(), !Task.isCancelled, self.page?.url == url else { return }
            let supported = await Self.supported()
            guard !Task.isCancelled, self.page?.url == url else { return }
            self.checkedURL = url
            guard let pageLanguage = PageLanguage.detect(declared: found.declared, sample: found.sample),
                  let offer = PageLanguage.offer(page: pageLanguage, supported: supported) else {
                self.source = nil
                self.target = nil
                return
            }
            // The translator's own form of the page's language ("es", not "es-419").
            self.source = supported.first { $0.languageCode == pageLanguage.languageCode } ?? pageLanguage
            self.target = offer
        }
    }

    // MARK: Translating

    /// Translate to the offered language: at once if it's on the device,
    /// after the system's download sheet otherwise.
    public func translate() {
        guard let source, let target, state == .offered || state == .failed else { return }
        failedDownload = false
        translation = nil
        starting = Task { [weak self] in
            let installed = await PageTranslationSupport.isInstalled(from: source, to: target)
            guard let self, !Task.isCancelled else { return }
            self.starting = nil
            if installed {
                self.begin()
            } else {
                self.download = Download(source: source, target: target)
            }
        }
    }

    /// The app's answer to `download`: whether the languages are now on
    /// the device. If not (the person declined), nothing changes.
    public func downloaded(_ ready: Bool) {
        guard download != nil else { return }
        download = nil
        if ready { begin() } else { failedDownload = true }
    }

    /// Show Original: the page's own words and title back.
    public func showOriginal() {
        starting?.cancel()
        starting = nil
        download = nil
        failedDownload = false
        guard let translation else { return }
        Task { await translation.showOriginal() }
    }

    /// The tab is closing: stop, leaving the page alone.
    public func close() {
        check?.cancel()
        starting?.cancel()
        translation?.stop()
    }

    private func begin() {
        guard let page, let source, let target,
              let made = PageTranslation.onDevice(page: page, source: source, target: target) else {
            failedDownload = true
            return
        }
        translation = made
        made.start()
    }

    // MARK: Languages

    private static var supportedCache: [Locale.Language]?

    /// The translator's languages, asked once.
    private static func supported() async -> [Locale.Language] {
        if let supportedCache { return supportedCache }
        let found = await PageTranslationSupport.supportedLanguages()
        if !found.isEmpty { supportedCache = found }
        return found
    }
}
