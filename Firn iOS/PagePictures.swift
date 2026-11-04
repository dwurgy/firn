import FirnCore
import SwiftUI
import UIKit

/// The pictures of each tab's page that the overview's cards will show
/// (phase 2, step 4), and the glide into the overview will stand in for
/// the page with (step 3b). Taken as the overview opens and as Firn leaves
/// the screen, saved on the device (`PagePictureStore`) so they're still
/// there after iOS ends Firn in the background, and kept in memory once
/// shown. A tab's picture goes with the tab (the session saver prunes).
@MainActor @Observable
final class PagePictures {
    @ObservationIgnored private let store: PagePictureStore
    /// Pictures read or taken since launch. Dropped when memory is short;
    /// they come back from disk when next asked for.
    private var images: [UUID: UIImage] = [:]
    /// How wide the page is on screen, in points (set by the screen).
    @ObservationIgnored var pageWidth: CGFloat = 0
    /// The status bar's height, in points (set by the screen): where the
    /// page, and so its picture, starts on screen.
    @ObservationIgnored var topInset: CGFloat = 0
    @ObservationIgnored private var warning: (any NSObjectProtocol)?

    init(store: PagePictureStore) {
        self.store = store
        warning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.images.removeAll() }
        }
    }

    /// The tab's picture: from memory, else from disk, else nil.
    func image(for tabID: UUID) -> UIImage? {
        if let image = images[tabID] { return image }
        guard let picture = store.load(for: tabID) else { return nil }
        let image = UIImage(cgImage: picture, scale: 2, orientation: .up)
        images[tabID] = image
        return image
    }

    /// Takes a picture of the tab's page as it is now and saves it. A
    /// sleeping tab (no page) or a page that can't be pictured (nothing
    /// loaded, or a load error) keeps the picture it had. The task gives
    /// the new picture once it's in memory (saving goes on after), for the
    /// glide to stand in for the page with; nil if none was taken.
    @discardableResult
    func capture(_ tab: FirnCore.Tab) -> Task<UIImage?, Never>? {
        guard let page = tab.page, pageWidth > 0 else { return nil }
        let id = tab.id
        // Twice the page's width in pixels: sharp on a card a little
        // narrower than the screen, and a quarter of a 3x picture's size.
        let scale = UITraitCollection.current.displayScale
        let width = pageWidth * 2 / max(scale, 1)
        let store = store
        return Task {
            guard let picture = await page.snapshot(width: width) else { return nil }
            let image = UIImage(cgImage: picture, scale: 2, orientation: .up)
            images[id] = image
            // Encoding and writing happen off the main thread.
            Task.detached(priority: .utility) {
                do {
                    try store.save(picture, for: id)
                } catch {
                    // A locked phone can refuse; the picture in memory stays.
                }
            }
            return image
        }
    }
}
