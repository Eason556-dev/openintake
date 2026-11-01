import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public enum WatchIntakeError: String, Error { case invalid, changedProduct, conflictingID, duplicate }
public enum WatchIntake {
    public static func catalog(_ products: [Product]) -> [WatchProduct] {
        products.compactMap { p in
            guard (try? QuickIntake.resolve(productID: p.id, quantity: p.defaultIntakeQuantity, products: products)) != nil else { return nil }
            return WatchProduct(id: p.id, revision: p.revision, name: p.name, unit: p.intakeUnitTitle,
                                quantity: p.manualNutrition?.packageQuantity ?? p.defaultIntakeQuantity)
        }
    }
    /// Returns nil for an already persisted request, including a revoked event. Never resurrect on replay.
    public static func apply(_ request: WatchIntakeRequest, to library: inout Library, now: Date = Date()) throws -> UUID? {
        guard request.schema == 1, request.quantity.isFinite, request.quantity > 0,
              request.date.timeIntervalSince1970.isFinite, request.date <= now.addingTimeInterval(300) else { throw WatchIntakeError.invalid }
        if let event = library.events.first(where: { $0.id == request.id }) {
            guard event.watchRequest == request else { throw WatchIntakeError.conflictingID }
            return nil
        }
        if let id = request.productID {
            guard let product = library.products.first(where: { $0.id == id }), product.revision == request.revision else { throw WatchIntakeError.changedProduct }
        } else {
            guard request.revision == nil, request.unit == "mL" else { throw WatchIntakeError.invalid }
        }
        let (product, quantity) = try QuickIntake.resolve(productID: request.productID, quantity: request.quantity, products: library.products, expectedUnit: request.unit)
        var event = try IntakeEvent(product: product, servings: product.servings(forUnits: quantity), date: request.date)
        event.id = request.id; event.watchRequest = request
        // Independent taps are not silently coalesced: existing near-duplicate rules require review.
        do { try library.enqueue(event) } catch IntakeError.duplicate { throw WatchIntakeError.duplicate }
        return event.id
    }
}
