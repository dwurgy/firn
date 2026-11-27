import FirnCore
import SwiftUI
import UIKit

/// Tidying away on the iPhone (docs/IOS-PLAN.md, "Plan: tidying away";
/// approved from docs/tidy-ios-design.html, David, 2026-11-25: "Sink into
/// pill"). The overview has opened and come to rest: after a beat, the space
/// on screen's idle cards sink one after another into the space's pill,
/// frosting as they go, the grid closes up, and the pill frosts over in the
/// space's color, says "Tidied away 4 tabs", and thaws back to its name.
/// Where they went is the space menu's Tidied Away row (`TidiedSheet`).
///
/// Cards out of view just go, the grid staying put under the eye, and the
/// pill speaks. Reduce Motion: cards and pill fade, nothing flies.
@MainActor @Observable
final class Tidying {
    /// The pill: its name, frosted over, or saying how many were tidied.
    enum Pill { case rest, frosted, speaking }
    private(set) var pill = Pill.rest
    private(set) var said = ""
    /// Cards about to go: their X and shadow fade first, as a held card's.
    private(set) var leaving: Set<UUID> = []
    /// Cards go with nothing to see: the grid takes the change at once
    /// (`GridCards.still`).
    private(set) var quiet = false
    /// Set by the bar: its menu is open, and where its pill is (global).
    @ObservationIgnored var menuOpen = false
    @ObservationIgnored var pillFrame: CGRect = .zero
    /// Where the cards fly, over the grid and under the bar.
    @ObservationIgnored fileprivate weak var air: UIView?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Being tidied and not yet gone, for a moment cut short.
    @ObservationIgnored private var pending: [FirnCore.Tab] = []
    @ObservationIgnored private weak var store: BrowserStore?
    /// Tidied, but the moment was cut short before the pill said so: told
    /// the next time the space's overview comes to rest, so nothing goes
    /// without a word.
    @ObservationIgnored private var untold: [UUID: Int] = [:]
    /// The space and tabs of the moment under way, until it's told.
    @ObservationIgnored private var telling: (space: UUID, tabs: [FirnCore.Tab])?

    /// What a moment needs from the overview.
    struct Scene {
        let store: BrowserStore
        let pictures: PagePictures
        let reduceMotion: Bool
        /// At rest, with nothing held, open, or moving.
        let ready: @MainActor () -> Bool
        /// Still on screen.
        let shown: @MainActor () -> Bool
        /// The part of the screen cards are seen in (global).
        let view: @MainActor () -> CGRect
        /// Whether the cards in view can all stay where they are on screen
        /// once these tabs are gone (the list scrolling as much as it got
        /// shorter above them).
        let holds: @MainActor (Set<UUID>) -> Bool
        /// Scrolls the list by this much, at once.
        let scrollBy: @MainActor (CGFloat) -> Void
    }

    /// The beat before anything moves, as the Mac's.
    private static let beat: Duration = .milliseconds(600)
    /// One card's way down, and how far apart they start.
    fileprivate static let sink: CFTimeInterval = 0.9
    private static let apart: Duration = .milliseconds(150)

    /// The overview has come to rest: tidies after a beat, if there's
    /// anything idle in the space on screen.
    func soon(_ scene: Scene) {
        guard pending.isEmpty, pill == .rest else { return }
        task?.cancel()
        guard !Self.idle(scene.store).isEmpty || untold[scene.store.activeSpaceID] != nil else { return }
        task = Task { [weak self] in
            repeat {
                try? await Task.sleep(for: Self.beat)
                guard !Task.isCancelled, scene.shown() else { return }
            } while !scene.ready()
            let idle = Self.idle(scene.store)
            guard let self, !idle.isEmpty || untold[scene.store.activeSpaceID] != nil else { return }
            await tidy(idle, scene)
        }
    }

    /// Cut short (the overview hides, another space): what was going goes
    /// at once, unseen, and the pill is its name again.
    func stop() {
        #if TIDY_TEST
        Self.testedThisTime = false
        #endif
        task?.cancel()
        task = nil
        for card in air?.subviews ?? [] { card.removeFromSuperview() }
        if !pending.isEmpty, let store {
            quiet = true
            for tab in pending { store.drift(tab) }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                quiet = false
            }
        }
        if let telling {
            let count = telling.tabs.count { $0.place == .drifted }
            if count > 0 { untold[telling.space, default: 0] += count }
        }
        telling = nil
        settle()
        if pill != .rest {
            var atOnce = Transaction()
            atOnce.disablesAnimations = true
            withTransaction(atOnce) { pill = .rest }
        }
    }

    #if TIDY_TEST
    /// Once each time the overview opens: the pill's thaw is a new rest,
    /// and the next four tabs went, and the next.
    private static var testedThisTime = false
    #endif

    private static func idle(_ store: BrowserStore) -> [FirnCore.Tab] {
        #if TIDY_TEST
        // For trying the moment without waiting a week; never in a build
        // that ships (docs/IOS-PLAN.md).
        if store.driftAfter != .never {
            if testedThisTime { return [] }
            return Array(store.looseTabs.filter { $0.id != store.activeTabID }.prefix(4))
        }
        #endif
        return store.idleTabs(in: store.activeSpaceID)
    }

    private func settle() {
        pending = []
        if !leaving.isEmpty {
            for cell in GridCards.cells(leaving).values { cell.unsink() }
            leaving = []
        }
    }

    private func tidy(_ idle: [FirnCore.Tab], _ scene: Scene) async {
        #if TIDY_TEST
        Self.testedThisTime = true
        #endif
        store = scene.store
        pending = idle
        let space = scene.store.activeSpaceID
        telling = (space, idle)
        defer { if !Task.isCancelled { settle() } }
        let view = scene.view()
        let frames = GridCards.framesOnScreen()
        // Reduce Motion: all of them go as those out of view do, in one fade.
        let seen = scene.reduceMotion ? [] : idle.filter { frames[$0.id].map { $0.intersects(view) } ?? false }
        let seenIDs = Set(seen.map(\.id))
        let unseen = idle.filter { !seenIDs.contains($0.id) }
        if !unseen.isEmpty {
            await leaveQuietly(unseen, frames: frames, scene)
            guard !Task.isCancelled else { return }
        }
        if !seen.isEmpty {
            await sink(seen, scene)
            guard !Task.isCancelled else { return }
        }
        // Fewer than were counted, if some have been brought back since.
        let count = min(idle.count { $0.place == .drifted } + (untold.removeValue(forKey: space) ?? 0),
                        scene.store.driftedTabs.count)
        telling = nil
        settle()
        guard count > 0 else {
            withAnimation(.easeOut(duration: 0.25)) { pill = .rest }
            return
        }
        await speak(count, scene)
    }

    /// Cards sink into the pill one after another; once the last is nearly
    /// there the pill frosts and the grid closes up.
    private func sink(_ tabs: [FirnCore.Tab], _ scene: Scene) async {
        withAnimation(.easeOut(duration: 0.15)) { leaving = Set(tabs.map(\.id)) }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        for (index, tab) in tabs.enumerated() {
            if index > 0 { try? await Task.sleep(for: Self.apart) }
            guard !Task.isCancelled else { return }
            // Picked meanwhile: it stays.
            guard tab.id != scene.store.activeTabID, let cell = GridCards.cells([tab.id])[tab.id] else { continue }
            fly(tab, from: OverviewRow.gridWindow(in: cell.convert(cell.bounds, to: nil)), scene)
            cell.sink()
        }
        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { pill = .frosted }
        try? await Task.sleep(for: .milliseconds(380))
        guard !Task.isCancelled else { return }
        // Near the list's end, the cards in view stay put and others come
        // in above: they fade in. Let glide, they dipped and came back, the
        // grid closing up and the list getting shorter each at its own pace
        // (the Simulator, 2026-11-25).
        if scene.holds(Set(tabs.map(\.id))) {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            await leaveQuietly(tabs, frames: GridCards.framesOnScreen(), scene)
        } else {
            withAnimation(.smooth(duration: 0.25)) { for tab in tabs { scene.store.drift(tab) } }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Cards out of view go with nothing to see: what is on screen stays
    /// where it is (the list scrolls as much as it got shorter). Where the
    /// grid has to take them in (a card changes column), it cross-fades:
    /// the screen's picture holds over it until it has settled.
    private func leaveQuietly(_ tabs: [FirnCore.Tab], frames: [UUID: CGRect], _ scene: Scene) async {
        let gone = Set(tabs.map(\.id))
        let view = scene.view()
        let stays = frames.filter { !gone.contains($0.key) && $0.value.intersects(view) }
        let anchor = scene.store.activeTabID.flatMap { stays[$0] == nil ? nil : $0 }
            ?? stays.min { $0.value.minY < $1.value.minY }?.key
        let window = air?.window
        let cover = window?.snapshotView(afterScreenUpdates: false)
        cover?.isUserInteractionEnabled = false
        if let window, let cover { window.addSubview(cover) }
        var atOnce = Transaction()
        atOnce.disablesAnimations = true
        withTransaction(atOnce) {
            quiet = true
            for tab in tabs { scene.store.drift(tab) }
        }
        defer { quiet = false }
        pending.removeAll { gone.contains($0.id) }
        if let anchor, let top = frames[anchor]?.minY {
            // A frame at a time, until the list has settled: still for a
            // few frames, where it was or as near as its ends allow. The
            // list takes the shorter height and the scroll some frames
            // after they're asked for (the Simulator, 2026-11-25).
            var last: CGFloat?
            var still = 0
            for _ in 0..<24 where still < 4 {
                try? await Task.sleep(for: .milliseconds(16))
                guard let now = GridCards.framesOnScreen()[anchor]?.minY else { continue }
                still = last.map { abs($0 - now) < 0.5 } ?? false ? still + 1 : 0
                last = now
                if abs(now - top) > 0.5 { scene.scrollBy(now - top) }
            }
        }
        guard let cover else { return }
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) { cover.alpha = 0 } completion: { _ in
            cover.removeFromSuperview()
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    private func speak(_ count: Int, _ scene: Scene) async {
        let text = count == 1 ? "Tidied away 1 tab" : "Tidied away \(count) tabs"
        said = text
        AccessibilityNotification.Announcement(text).post()
        let calm = scene.reduceMotion
        if pill == .rest, !calm {
            withAnimation(.easeOut(duration: 0.3)) { pill = .frosted }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        withAnimation(calm ? .easeOut(duration: 0.3) : .smooth(duration: 0.38)) { pill = .speaking }
        try? await Task.sleep(for: .milliseconds(2800))
        guard !Task.isCancelled else { return }
        withAnimation(calm ? .easeOut(duration: 0.3) : .smooth(duration: 0.38)) { pill = calm ? .rest : .frosted }
        if calm { return }
        try? await Task.sleep(for: .milliseconds(330))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { pill = .rest }
    }

    /// Tapped while it speaks: the list opens, and the pill thaws.
    func heard() {
        task?.cancel()
        settle()
        withAnimation(.easeOut(duration: 0.25)) { pill = .rest }
    }

    /// One card's picture, flown down into the pill. UIKit's layers, not
    /// SwiftUI: the whole way is handed to the screen's own drawing at once,
    /// so the grid closing up meanwhile can't make it stutter.
    private func fly(_ tab: FirnCore.Tab, from frame: CGRect, _ scene: Scene) {
        guard let air, pillFrame.width > 0 else { return }
        let box = air.convert(frame, from: nil)
        let pill = air.convert(pillFrame, from: nil)
        let card = SinkingCard(size: box.size, dark: air.traitCollection,
                               color: scene.store.activeSpace.color)
        if let image = scene.pictures.cachedImage(for: tab.id), let picture = image.cgImage {
            card.show(picture, width: image.size.width, height: image.size.height,
                      skip: scene.pictures.headerDepth(for: tab.id))
        } else if let icon = tab.icon.flatMap(UIImage.init(data:)) {
            card.show(icon: icon)
        }
        air.addSubview(card)
        card.sink(from: CGPoint(x: box.midX, y: box.midY), to: CGPoint(x: pill.midX, y: pill.midY))
    }
}

/// A card's picture on its way into the pill: the card's corners, a frost
/// that gathers over it, and a soft shadow.
private final class SinkingCard: UIView {
    private let picture = CALayer()
    private let frost = CALayer()

    init(size: CGSize, dark traits: UITraitCollection, color: String) {
        super.init(frame: CGRect(origin: .zero, size: size))
        let radius = OverviewRow.gridCornerRadius
        picture.frame = bounds
        picture.cornerRadius = radius
        picture.cornerCurve = .continuous
        picture.masksToBounds = true
        picture.backgroundColor = UIColor(Theme.page).resolvedColor(with: traits).cgColor
        picture.minificationFilter = .trilinear
        frost.frame = bounds
        frost.backgroundColor = UIColor(Theme.tidyFrost(color)).resolvedColor(with: traits).cgColor
        frost.opacity = 0
        picture.addSublayer(frost)
        layer.addSublayer(picture)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        layer.shadowColor = UIColor(red: 0.24, green: 0.16, blue: 0.08, alpha: 1).cgColor
        layer.shadowRadius = 9
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowOpacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is never used") }

    /// As the card shows it (`OverviewRow.pictureView`): as wide as the
    /// card, from just below the page's header; a picture too short for
    /// that fills the card's height, centered.
    func show(_ image: CGImage, width: CGFloat, height: CGFloat, skip: CGFloat) {
        guard width > 0, height > 0 else { return }
        let scale = max(bounds.width / width, bounds.height / height)
        let seen = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let top = min(skip, max(height - seen.height, 0))
        picture.contents = image
        picture.contentsRect = CGRect(x: (width - seen.width) / 2 / width, y: top / height,
                                      width: seen.width / width, height: seen.height / height)
    }

    /// A card with no picture shows its site's icon.
    func show(icon: UIImage) {
        let mark = CALayer()
        mark.contents = icon.cgImage
        mark.contentsGravity = .resizeAspect
        mark.frame = CGRect(x: bounds.midX - 20, y: bounds.midY - 20, width: 40, height: 40)
        mark.cornerRadius = 9
        mark.masksToBounds = true
        picture.insertSublayer(mark, below: frost)
    }

    /// The way down, as the mockup's: across on an even ease, down a little
    /// late, as if it lets go, and smaller all the way; gone in the last
    /// seventh, behind the pill's glass.
    func sink(from start: CGPoint, to end: CGPoint) {
        let steps = 45
        var points: [CGPoint] = [], scales: [CGFloat] = [], fades: [Float] = []
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let even = t * t * (3 - 2 * t)
            let fall = pow(t, 2.1) * 0.55 + even * 0.45
            points.append(CGPoint(x: start.x + (end.x - start.x) * even, y: start.y + (end.y - start.y) * fall))
            scales.append(1 - 0.86 * (1 - pow(1 - t, 1.7)) * min(1, 0.35 + even * 0.65))
            fades.append(t < 0.86 ? 1 : Float(1 - (t - 0.86) / 0.14))
        }
        func keys(_ path: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.calculationMode = .linear
            return animation
        }
        let shade = CABasicAnimation(keyPath: "shadowOpacity")
        shade.fromValue = 0
        shade.toValue = 0.2
        shade.duration = 0.2
        shade.fillMode = .forwards
        let way = CAAnimationGroup()
        way.animations = [keys("position", points), keys("transform.scale", scales), keys("opacity", fades), shade]
        way.duration = Tidying.sink
        way.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        let gather = CABasicAnimation(keyPath: "opacity")
        gather.fromValue = 0
        gather.toValue = 1
        gather.duration = Tidying.sink
        gather.timingFunction = CAMediaTimingFunction(name: .easeIn)
        gather.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
        layer.position = end
        layer.opacity = 0
        frost.opacity = 1
        layer.add(way, forKey: "sink")
        frost.add(gather, forKey: "gather")
        CATransaction.commit()
    }
}

/// The air over the grid the cards sink through; never touched.
struct TidyAir: UIViewRepresentable {
    let tidying: Tidying

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        tidying.air = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        if tidying.air !== view { tidying.air = view }
    }
}
