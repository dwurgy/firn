import Observation
import StoreKit
import SwiftUI

/// The tip jar: the David Wurgler apps' one shared jar (three consumable
/// tips, $2.99, $4.99, and $9.99, the same words in every app). Tips unlock
/// nothing; a tip is only finished, so the App Store knows it was delivered.
///
/// Only the App Store app has it: the Mac's Firn is sold outside the Mac App
/// Store, where in-app purchases don't work, so the Mac's jar is Ko-fi.
@MainActor @Observable
final class TipJar {
    /// Smallest first. The same pattern in every app: `<bundle ID>.tip.<size>`.
    static let productIDs = ["com.firnbrowser.firn.tip.small",
                             "com.firnbrowser.firn.tip.medium",
                             "com.firnbrowser.firn.tip.large"]

    enum State: Equatable { case loading, ready, unavailable }

    private(set) var tips: [Product] = []
    private(set) var state = State.loading
    /// A tip went through: the thank-you shows in the tips' place.
    private(set) var thanked = false
    /// The tip whose purchase is open, so its row can say so.
    private(set) var buying: Product.ID?

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        // Tips that finish later (Ask to Buy approved, or a purchase
        // interrupted by a crash) arrive here; finishing them is all a tip needs.
        updates = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
            }
        }
    }

    func load() async {
        guard tips.isEmpty else { return }
        do {
            let products = try await Product.products(for: Self.productIDs)
            tips = products.sorted { $0.price < $1.price }
            state = tips.isEmpty ? .unavailable : .ready
        } catch {
            // Offline, or the App Store can't be reached: say so quietly.
            state = .unavailable
        }
    }

    /// Buys one tip through SwiftUI's purchase action, which shows the App
    /// Store's own sheet over the screen it came from.
    func buy(_ tip: Product, with purchase: PurchaseAction) async {
        guard buying == nil else { return }
        buying = tip.id
        defer { buying = nil }
        do {
            let result = try await purchase(tip)
            if case .success(let verification) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                thanked = true
            }
            // .pending (Ask to Buy) and .userCancelled need nothing.
        } catch {
            // The App Store's sheet already told the person what went wrong.
        }
    }
}
