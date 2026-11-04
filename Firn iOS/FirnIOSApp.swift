import FirnCore
import SwiftUI

/// Firn for iPhone and iPad. Phase 1: one space, one tab, and a plain field
/// for addresses (see docs/IOS-PLAN.md).
@main
struct FirnIOSApp: App {
    /// Made once the screen first appears, never in `init`: a web view made
    /// while iOS is still starting the app gets its touch handling wired up
    /// wrong, and the first scrolls or taps on the page crash inside UIKit
    /// (`-[UIGestureRecognizer _delayTouchesForEvent:inPhase:]`, found
    /// 2026-11-03). Restoring the session makes the page's web view, so it
    /// waits too.
    @State private var browser: Browser?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let browser {
                    BrowserScreen(store: browser.store, pictures: browser.pictures)
                } else {
                    Theme.page.ignoresSafeArea()
                }
            }
            .onAppear {
                if browser == nil { browser = Browser() }
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase != .active, let browser else { return }
            // A fresh picture of the page on screen, for the overview
            // after a restart (taken before iOS dims the app away).
            if let tab = browser.store.activeTab { browser.pictures.capture(tab) }
            browser.saver.saveNow()
        }
    }
}

/// The browser behind the screen: the restored session and its saver.
@MainActor
final class Browser {
    let store: BrowserStore
    let saver: SessionSaver
    let sleeper: TabSleeper
    let pictures: PagePictures

    /// Picks up where the last session left off, then saves as things change
    /// and whenever Firn leaves the screen (iOS may end it after that without
    /// a word).
    init() {
        let file = SessionFile.standard
        let session = file.load()
        let placesFile = PagePlacesFile.standard
        let store = BrowserStore(
            restoring: session, pagePlaces: placesFile.load(), defaultSpaces: [FirstSpace.make()],
            makePage: BrowserEngine.makePage,
            removeData: { BrowserEngine.removeData(for: $0) }
        )
        let snapshot: @MainActor () -> Session = { store.session(sidebarWidth: 260, sidebarCollapsed: false) }
        // The first space's data store is new: save it at once, so a quit
        // within the first seconds doesn't leave it nameless and forgotten.
        if session == nil { try? file.save(snapshot()) }
        self.store = store
        // Each tab's back history goes with the session, and whenever Firn
        // leaves the screen; closed tabs' pictures go after each save.
        let pictureStore = PagePictureStore.standard
        pictures = PagePictures(store: pictureStore)
        saver = SessionSaver(file: file, placesFile: placesFile, snapshot: snapshot,
                             places: { store.pagePlaces() }, pictures: pictureStore)
        saver.start()
        sleeper = TabSleeper(store: store)
        sleeper.start()
    }
}

/// The space Firn starts with on a new iPhone or iPad: its own data store,
/// never .default(). Made once, then kept in the saved session.
enum FirstSpace {
    static func make() -> Space {
        Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID())
    }
}
