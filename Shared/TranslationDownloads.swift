import FirnCore
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Translating pages: when a tab asks to translate into languages not yet
/// on the device (`PageTranslator.download`), the system's own sheet asks
/// to download them (SwiftUI's `translationTask`, the only way an app can
/// start that download). Its wording, look, and buttons are Apple's. The
/// tab hears how it went: translating starts, or nothing changes.
/// Nothing before macOS 26.4 and iOS 26.4, where translation is absent.
struct TranslationDownloads: ViewModifier {
    let translator: PageTranslator?

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 26.4, iOS 26.4, *) {
            content.modifier(DownloadPrompt(translator: translator))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func translationDownloads(for translator: PageTranslator?) -> some View {
        modifier(TranslationDownloads(translator: translator))
    }
}

#if canImport(Translation)
@available(macOS 26.4, iOS 26.4, *)
private struct DownloadPrompt: ViewModifier {
    let translator: PageTranslator?
    @State private var configuration: TranslationSession.Configuration?
    /// The tab that asked, so switching tabs while the sheet is up still
    /// answers the right one.
    @State private var asking: PageTranslator?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                // The framework's session isn't marked Sendable, though it
                // runs its own work; it's used only here, once.
                nonisolated(unsafe) let session = session
                try? await session.prepareTranslation()
                guard let asking, let download = asking.download else { return }
                // Declining the sheet doesn't always throw: the languages
                // being there is the answer.
                let ready = await PageTranslationSupport.isInstalled(from: download.source, to: download.target)
                asking.downloaded(ready)
                self.asking = nil
            }
            .onChange(of: translator?.download, initial: true) {
                guard let translator, let download = translator.download else { return }
                asking = translator
                Task {
                    // The fast model has its own download; it's the one
                    // Firn translates with, where it has the pair.
                    let fast = await PageTranslationSupport.downloadsFastModel(from: download.source, to: download.target)
                    guard asking === translator, translator.download == download else { return }
                    let strategy: TranslationSession.Strategy = fast ? .lowLatency : .highFidelity
                    if configuration?.source == download.source, configuration?.target == download.target,
                       configuration?.preferredStrategy == strategy {
                        configuration?.invalidate()
                    } else {
                        configuration = .init(source: download.source, target: download.target, preferredStrategy: strategy)
                    }
                }
            }
    }
}
#endif
