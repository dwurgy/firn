import QuartzCore
import SwiftUI

/// One move of the address bar between its full size and its small pill, as
/// Safari's on iOS 27 (David's recordings, 2026-11-23; `docs/IOS-PLAN.md`,
/// section 11): first the bar follows the finger a little of the way
/// (`lead`), then it lets go and finishes on its own, on a spring that
/// carries on at the finger's speed. A slow scroll starts it slowly and a
/// flick starts it fast, where one fixed glide had a single speed.
///
/// A class, read by `BarGlide` on every frame: the scroll moves `lead`
/// without SwiftUI working anything out again. Only ever touched on the
/// main thread (the page's scrolling and SwiftUI's animations both run
/// there), which is why it may call itself `Sendable`.
final class BarRun: @unchecked Sendable {
    /// How much of the way the bar has gone while it follows the finger.
    private var lead: CGFloat = 0
    private var leadTime: CFTimeInterval = 0
    /// The finger's speed, in shares of the way a second.
    private var speed: CGFloat = 0
    /// Let go: when, from how far along, and how fast.
    private var release: (at: CFTimeInterval, from: CGFloat, speed: CGFloat)?

    /// The finish: the bar's glide before it followed anything.
    static let spring = Spring(duration: 0.32, bounce: 0)

    /// A move that follows the finger until `finish`.
    init() {}

    /// A move with no finger behind it (a tap on the small pill, a new
    /// page, a flick past the whole way): the plain glide.
    static func onItsOwn() -> BarRun {
        let run = BarRun()
        run.finish()
        return run
    }

    var following: Bool { release == nil }

    func follow(_ lead: CGFloat) {
        let now = CACurrentMediaTime()
        let passed = now - leadTime
        if leadTime > 0, passed > 0.001, passed < 0.1 {
            // Smoothed a little: one frame's scroll is a rough measure.
            speed = speed * 0.4 + (lead - self.lead) / passed * 0.6
        } else {
            speed = 0
        }
        self.lead = lead
        leadTime = now
    }

    /// Lets go: the rest of the way on the spring.
    func finish() {
        guard release == nil else { return }
        let stale = CACurrentMediaTime() - leadTime > 0.1
        release = (CACurrentMediaTime(), lead, stale ? 0 : min(max(speed, 0), 12))
    }

    /// How much of the move has been made, 0 to 1; nil once it's over.
    func amount(at now: CFTimeInterval) -> Double? {
        guard let release else { return lead }
        let time = now - release.at
        guard time < Self.spring.settlingDuration else { return nil }
        let rest = 1 - Double(release.from)
        return Double(release.from) + Self.spring.value(target: rest, initialVelocity: Double(release.speed), time: time)
    }
}

/// The bar's animation: wherever `run` says the move is. Everything the
/// bar animates as it changes size (its glass, its width, the name, the
/// buttons) follows the one run, so they keep together under the finger.
struct BarGlide: CustomAnimation {
    let run: BarRun

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard let amount = run.amount(at: CACurrentMediaTime()) else { return nil }
        return value.scaled(by: amount)
    }

    static func == (a: BarGlide, b: BarGlide) -> Bool { a.run === b.run }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(run)) }
}

/// Fades with the bar's move instead of on a clock: gone once the bar is
/// `gone` of the way to its small pill, and back the same way. On a clock,
/// Back and Reload vanished as the bar began to follow a slow finger.
struct FadesWithTheBar: ViewModifier, Animatable {
    /// 0 at the full bar, 1 at the small pill.
    var amount: CGFloat
    let gone: CGFloat

    nonisolated var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(min(max(1 - amount / gone, 0), 1))
    }
}
