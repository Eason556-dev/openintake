import XCTest
@testable import IntakeCore

final class QuickIntakeTests: XCTestCase {
    func drink() throws -> Product {
        try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100, packageQuantity: 330,
            amounts: [.init(.sugar, 10, .g), .init(.sodium, 20, .mg)]).product(name: "Synthetic beverage")
    }
    func testWaterActionHasStableIdentityAndRejectsInvalidQuantity() throws {
        let (a, quantity) = try QuickIntake.resolve(productID: nil, quantity: 250, products: [])
        let (b, _) = try QuickIntake.resolve(productID: nil, quantity: 150, products: [])
        XCTAssertEqual(a.id, b.id)
        let event = try IntakeEvent(product: a, servings: a.servings(forUnits: quantity))
        XCTAssertEqual(event.canonicalValue(for: try event.healthSamples[0]), 250)
        for amount in [0, -1, Double.nan, Double.infinity, 10001] {
            XCTAssertThrowsError(try QuickIntake.resolve(productID: nil, quantity: amount, products: []))
        }
    }
    func testProductActionResolvesLatestLabelNotCachedWidgetValues() throws {
        var product = try drink()
        let id = product.id
        product = try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100,
            amounts: [.init(.sugar, 8, .g)]).product(name: "Updated synthetic beverage")
        product.id = id
        let (current, quantity) = try QuickIntake.resolve(productID: id, quantity: 330, products: [product])
        let event = try IntakeEvent(product: current, servings: current.servings(forUnits: quantity))
        XCTAssertEqual(event.canonicalValue(for: try event.healthSamples[0]), 26.4, accuracy: 1e-9)
        XCTAssertThrowsError(try QuickIntake.resolve(productID: id, quantity: 330, products: [product], expectedUnit: "g"))
        XCTAssertNoThrow(try QuickIntake.resolve(productID: id, quantity: 330, products: [product], expectedUnit: "mL"))
        XCTAssertThrowsError(try QuickIntake.resolve(productID: id, quantity: 330, products: []))
        product.confirmedAt = nil
        XCTAssertThrowsError(try QuickIntake.resolve(productID: id, quantity: 330, products: [product]))
    }
    func testSupplementUnitsAndMedicationExclusion() throws {
        var p = Product(name: "Synthetic C", serving: "2 tablets", nutrients: [.init(.vitaminC, 1000, .mg)], confirmedAt: Date())
        p.unitsPerServing = 2
        let (current, units) = try QuickIntake.resolve(productID: p.id, quantity: 1, products: [p])
        let event = try IntakeEvent(product: current, servings: current.servings(forUnits: units))
        XCTAssertEqual(event.canonicalValue(for: try event.healthSamples[0]), 0.5)
        p.kind = .medication
        XCTAssertThrowsError(try QuickIntake.resolve(productID: p.id, quantity: 1, products: [p]))
    }
    func testWidgetSelectionDefaultExplicitDeletionAndChangedUnits() throws {
        let product = try drink()
        let automatic = QuickIntake.widgetSelection(products: [product], preferredID: nil, quantity: nil, expectedUnit: nil)
        XCTAssertEqual(automatic?.1, 330)
        XCTAssertNil(QuickIntake.widgetSelection(products: [product], preferredID: UUID(), quantity: 1, expectedUnit: "mL"))
        XCTAssertEqual(QuickIntake.widgetSelection(products: [product], preferredID: product.id, quantity: 165, expectedUnit: "mL")?.1, 165)
        XCTAssertEqual(QuickIntake.widgetSelection(products: [product], preferredID: product.id, quantity: 165, expectedUnit: "g")?.1, 330)
        XCTAssertEqual(QuickIntake.widgetSelection(products: [product], preferredID: product.id, quantity: .nan, expectedUnit: "mL")?.1, 330)
        var unconfirmed = product; unconfirmed.confirmedAt = nil
        XCTAssertNil(QuickIntake.widgetSelection(products: [unconfirmed], preferredID: nil, quantity: nil, expectedUnit: nil))
    }
    @MainActor func testSystemEntryUsesExistingDurableOutboxRetryUndoAndRestore() async throws {
        let product = try drink()
        let (current, units) = try QuickIntake.resolve(productID: product.id, quantity: 330, products: [product])
        let event = try IntakeEvent(product: current, servings: current.servings(forUnits: units))
        var library = Library(); try library.enqueue(event)
        XCTAssertThrowsError(try library.enqueue(IntakeEvent(product: current, servings: current.servings(forUnits: units), date: event.date)))
        let backend = FakeHealth(); backend.granted = false
        do { try await EventSync.perform(library.events[0], using: backend); XCTFail("Denied") } catch { }
        XCTAssertEqual(library.events[0].state, .pending); XCTAssertEqual(backend.writes, 0)
        backend.granted = true
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertEqual(backend.samples[event.syncID(for: .sugar)]!, 33, accuracy: 1e-9)
        XCTAssertEqual(backend.samples[event.syncID(for: .sodium)]!, 0.066, accuracy: 1e-9)
        try library.revoke(event.id)
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
        try library.restore(event.id)
        try await EventSync.perform(library.events[0], using: backend)
        XCTAssertEqual(backend.samples.count, 2)
        XCTAssertEqual(library.events[0].date, event.date)
    }
}
