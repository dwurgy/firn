import QuartzCore
import WebKit

/// How Reader comes and goes, on the Mac and the iPhone alike (David,
/// 2026-11-25): a straight edge scrolls down the page, uncovering the
/// reader, and back up on the way out, uncovering the page. Neither page
/// moves; only a mask does, on Core Animation. The same unhurried speed
/// both ways. Reduce Motion: a plain cross-fade.
@MainActor
enum ReaderSweep {
    /// How long the edge takes to cross the page, either way.
    static let duration: CFTimeInterval = 0.4
    /// A soft start and a longer, softer end.
    static let curve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.15, 1)
    /// How long the way in waits, at most, for the reader's first drawn
    /// frame (`waitUntilDrawn`): sweeping in an empty page is the very cut
    /// this replaces, but a press never goes unanswered.
    static let wait: TimeInterval = 2.5
    /// On the way out the page comes in a touch darker, clearing behind the edge.
    static let dim: CGFloat = 0.25
    static let dimDelay: TimeInterval = 0.1
    static let dimDuration: TimeInterval = 0.25

    /// Comes back once the reader's article is there and has had a frame to
    /// draw. Asked in Firn's own world (the reader runs no scripts of its
    /// own). Not its load's end, which waits for every picture, nor its
    /// first size, which an empty page can have too.
    static func waitUntilDrawn(_ reader: WKWebView) async {
        while !Task.isCancelled {
            let drawn = try? await reader.callAsyncJavaScript(
                """
                if (!document.body || !document.body.firstElementChild) return false;
                await new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)));
                return true;
                """, in: nil, contentWorld: WebKitPageController.firnWorld)
            if drawn as? Bool == true { return }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Moves the mask's bottom edge from one height to the other, its top
    /// staying put. Call inside a transaction whose completion ends it.
    static func move(_ mask: CALayer, from: CGFloat, to: CGFloat) {
        let edge = CABasicAnimation(keyPath: "bounds.size.height")
        edge.fromValue = from
        edge.toValue = to
        edge.duration = duration
        edge.timingFunction = curve
        mask.bounds.size.height = to
        mask.add(edge, forKey: "sweep")
    }
}
