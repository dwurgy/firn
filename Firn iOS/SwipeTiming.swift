import Foundation
import QuartzCore
import UIKit
import os

/// Measures the wait between a swipe up (or the tabs button) and the page
/// moving (`docs/IOS-PLAN.md`, "The swipe up's delay", step 1). Debug
/// builds only; it logs milliseconds and step names, never an address or
/// a title. Read it in Xcode's console, filtered to "swipe timing".
///
/// What it logs, each from the finger's grab: the overview's card for the
/// tab laid out, WebKit's picture arriving, the picture set on screen, and
/// every frame that took longer than 20ms to come (the main thread held
/// up) during the first 1.5s.
@MainActor
enum SwipeTiming {
    #if DEBUG
    private static let log = Logger(subsystem: "com.firnbrowser.Firn", category: "swipe timing")
    private static var start: CFTimeInterval?
    private static var watched: UUID?
    private static var sawSpot = false
    private static var ticker: Ticker?

    /// The finger grabbed the page (or the tabs button was tapped).
    static func begin(_ kind: String, tab: UUID) {
        ticker?.stop()
        start = CACurrentMediaTime()
        watched = tab
        sawSpot = false
        log.notice("— \(kind, privacy: .public): grab")
        ticker = Ticker()
    }

    /// A step along the way, in milliseconds since the grab.
    static func mark(_ step: String) {
        guard let start else { return }
        let ms = (CACurrentMediaTime() - start) * 1000
        log.notice("  \(step, privacy: .public): \(ms, format: .fixed(precision: 0), privacy: .public)ms")
    }

    /// The overview recorded card spots; logs once, when the watched tab's
    /// own spot first appears.
    static func sawSpots(_ frames: [UUID: CGRect]) {
        guard start != nil, !sawSpot, let watched, frames[watched] != nil else { return }
        sawSpot = true
        mark("overview laid out (card's spot known)")
    }

    /// Lists every layer SwiftUI draws with the CPU (its `CGDrawingLayer`),
    /// with its size and place on screen: the profile showed most of the
    /// glide's time spent drawing those (2026-11-10).
    static func listCPUDrawnLayers() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        var found = 0
        func walk(_ layer: CALayer, depth: Int) {
            let name = String(describing: type(of: layer))
            if name.contains("Drawing"), layer.bounds.width * layer.bounds.height > 2000 {
                found += 1
                let frame = layer.convert(layer.bounds, to: window.layer)
                let size = "\(Int(frame.width))×\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY))"
                var chain: [String] = []
                var up = layer.superlayer
                while let l = up, chain.count < 4 {
                    chain.append(String(describing: type(of: l)) + (l.delegate.map { "(\(type(of: $0)))" } ?? ""))
                    up = l.superlayer
                }
                log.notice("  CPU layer \(name, privacy: .public) \(size, privacy: .public) opacity \(layer.opacity, privacy: .public) sublayers \(layer.sublayers?.count ?? 0, privacy: .public) ← \(chain.joined(separator: " ← "), privacy: .public)")
            }
            for sub in layer.sublayers ?? [] { walk(sub, depth: depth + 1) }
        }
        walk(window.layer, depth: 0)
        log.notice("  CPU-drawn layers: \(found, privacy: .public)")
    }

    fileprivate static func finish() {
        mark("timer stops")
        start = nil
        watched = nil
        ticker = nil
    }

    /// Watches each frame for 1.5s and logs the slow ones.
    @MainActor private final class Ticker: NSObject {
        private var link: CADisplayLink?
        private var last: CFTimeInterval?
        private var listed = 0
        private static let listAt: [CFTimeInterval] = [0.2, 0.42, 0.65]

        override init() {
            super.init()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            if last == nil { SwipeTiming.mark("first frame") }
            if let last, now - last > 0.020 {
                SwipeTiming.mark("slow frame (\(Int((now - last) * 1000))ms gap)")
            }
            last = now
            if let start = SwipeTiming.start, listed < Self.listAt.count,
               CACurrentMediaTime() - start > Self.listAt[listed] {
                listed += 1
                SwipeTiming.listCPUDrawnLayers()
            }
            if let start = SwipeTiming.start, CACurrentMediaTime() - start > 1.5 {
                stop()
                SwipeTiming.finish()
            }
        }
    }
    #else
    @inline(__always) static func begin(_ kind: String, tab: UUID) {}
    @inline(__always) static func mark(_ step: String) {}
    @inline(__always) static func sawSpots(_ frames: [UUID: CGRect]) {}
    @inline(__always) static func listCPUDrawnLayers() {}
    #endif
}
