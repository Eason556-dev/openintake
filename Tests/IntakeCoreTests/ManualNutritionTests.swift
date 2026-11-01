import XCTest
@testable import IntakeCore

final class ManualNutritionTests: XCTestCase {
    func beverage(reference: Double = 100, sugar: Double = 10) throws -> Product {
        try ManualNutritionTemplate(category: .beverage, referenceQuantity: reference, packageQuantity: 330,
            amounts: [.init(.sugar, sugar, .g), .init(.sodium, 20, .mg)]).product(name: "Synthetic drink")
    }
    func testDrinkActualVolumeAndBottleBasis() throws {
        let product = try beverage()
        let event = try IntakeEvent(product: product, servings: product.servings(forUnits: 330))
        XCTAssertEqual(event.consumedQuantity, 330)
        XCTAssertEqual(event.canonicalValue(for: try event.healthSamples.first { $0.nutrient == .sugar }!), 33, accuracy: 1e-9)
        let half = try IntakeEvent(product: product, servings: product.servings(forUnits: 165))
        XCTAssertEqual(half.canonicalValue(for: try half.healthSamples.first { $0.nutrient == .sugar }!), 16.5, accuracy: 1e-9)
        let bottle = try beverage(reference: 330, sugar: 33)
        let bottleEvent = try IntakeEvent(product: bottle, servings: bottle.servings(forUnits: 330))
        XCTAssertEqual(bottleEvent.canonicalValue(for: try bottleEvent.healthSamples.first { $0.nutrient == .sugar }!), 33, accuracy: 1e-9)
    }
    func testTemplateCannotSilentlyDivergeFromItsOriginalLabel() throws {
        var product = try beverage()
        product.nutrients[0].value = 1
        XCTAssertThrowsError(try product.validate())
        product = try beverage(); product.labelBasis = .init(kind: .per100g)
        XCTAssertThrowsError(try product.validate())
    }
    func testFoodMassAndSodiumUnitConversion() throws {
        let product = try ManualNutritionTemplate(category: .food, referenceQuantity: 15,
            amounts: [.init(.sodium, 900, .mg)]).product(name: "Synthetic sauce")
        let event = try IntakeEvent(product: product, servings: product.servings(forUnits: 5))
        XCTAssertEqual(event.consumedQuantity, 5)
        XCTAssertEqual(event.canonicalValue(for: try event.healthSamples[0]), 0.3, accuracy: 1e-9)
        XCTAssertFalse(try event.healthSamples.contains { $0.nutrient == .sugar })
    }
    func testUnknownNutritionStaysLocalAndDoesNotCountAsWater() throws {
        let product = try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100, amounts: []).product(name: "Unknown drink")
        let event = try IntakeEvent(product: product, servings: product.servings(forUnits: 330))
        XCTAssertTrue(try event.healthSamples.isEmpty)
        XCTAssertEqual(event.consumedQuantity, 330)
        let summary = DailyNutritionSummary(events: [event])
        XCTAssertNil(summary.sugarGrams); XCTAssertNil(summary.sodiumMilligrams)
        XCTAssertEqual(HydrationProgress(events: [event], goal: 2000).milliliters, 0)
    }
    func testExplicitZeroDiffersFromUnknownAndSugarIsNotCarbs() throws {
        let product = try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100,
            amounts: [.init(.sugar, 0, .g)]).product(name: "Label zero")
        let event = try IntakeEvent(product: product, servings: 1)
        let summary = DailyNutritionSummary(events: [event])
        XCTAssertEqual(summary.sugarGrams, 0); XCTAssertNil(summary.sodiumMilligrams)
        let carbs = try ManualNutritionTemplate(category: .food, referenceQuantity: 100,
            amounts: [.init(.carbohydrates, 20, .g)]).product(name: "Carbs only")
        XCTAssertNil(DailyNutritionSummary(events: [try IntakeEvent(product: carbs, servings: 1)]).sugarGrams)
    }
    func testInvalidManualInputsRejected() {
        for reference in [0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try ManualNutritionTemplate(category: .food, referenceQuantity: reference, amounts: []).product(name: "Test"))
        }
        for value in [-1, Double.nan, .infinity] {
            XCTAssertThrowsError(try ManualNutritionTemplate(category: .food, referenceQuantity: 100, amounts: [.init(.sugar, value, .g)]).product(name: "Test"))
        }
        XCTAssertThrowsError(try ManualNutritionTemplate(category: .food, referenceQuantity: 100, amounts: [.init(.sugar, 30, .g), .init(.carbohydrates, 20, .g)]).product(name: "Test"))
        XCTAssertThrowsError(try ManualNutritionTemplate(category: .food, referenceQuantity: 100, amounts: [.init(.sodium, 101, .g)]).product(name: "Test"))
        XCTAssertThrowsError(try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100, amounts: [.init(.sugar, 1, .g), .init(.sugar, 2, .g)]).product(name: "Test"))
        XCTAssertThrowsError(try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100, amounts: [.init(.water, 100, .mL)]).product(name: "Test"))
    }
    func testOrdinarySaltPersonalShareAndConfirmation() throws {
        let consumed = try OrdinarySalt.consumedGrams(saltGrams: 5, fraction: 0.25)
        XCTAssertEqual(consumed, 1.25)
        let product = try OrdinarySalt.product(saltGrams: 5, fraction: 0.25, confirmed: true)
        let event = try IntakeEvent(product: product, servings: product.servings(forUnits: consumed))
        XCTAssertEqual(event.canonicalValue(for: try event.healthSamples[0]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try event.healthSamples[0].origin, .manualEstimate)
        XCTAssertTrue(DailyNutritionSummary(events: [event]).estimated)
        XCTAssertThrowsError(try OrdinarySalt.product(saltGrams: 5, fraction: 1, confirmed: false))
        for fraction in [0, -1, 1.01, Double.nan, .infinity] { XCTAssertThrowsError(try OrdinarySalt.consumedGrams(saltGrams: 5, fraction: fraction)) }
    }
    func testDailySummaryExcludesUndoAndOtherDayIncludesPendingAndRestore() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let product = try beverage()
        var event = try IntakeEvent(product: product, servings: 3.3, date: date)
        var library = Library(); try library.enqueue(event)
        XCTAssertEqual(DailyNutritionSummary(events: library.events, date: date).sugarGrams!, 33, accuracy: 1e-9)
        try library.revoke(event.id)
        XCTAssertNil(DailyNutritionSummary(events: library.events, date: date).sugarGrams)
        library.completeSync(event.id); try library.restore(event.id)
        XCTAssertEqual(DailyNutritionSummary(events: library.events, date: date).sodiumMilligrams!, 66, accuracy: 1e-9)
        event.date = date.addingTimeInterval(-86400 * 3)
        XCTAssertNil(DailyNutritionSummary(events: [event], date: date).sugarGrams)
    }
    @MainActor func testManualTemplatePersistenceFrozenMappingSyncAndUndo() async throws {
        var product = try beverage()
        let event = try IntakeEvent(product: product, servings: product.servings(forUnits: 330))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = LibraryRepository(url: url); var library = Library(); library.products = [product]
        try repo.save(library); XCTAssertTrue(try repo.load().events.isEmpty)
        try library.enqueue(event); XCTAssertThrowsError(try library.enqueue(event))
        try repo.save(library); library = try repo.load()
        XCTAssertEqual(library.products[0].manualNutrition?.packageQuantity, 330)
        product.nutrients = [.init(.sugar, 1, .g)]
        XCTAssertEqual(try library.events[0].healthSamples.first { $0.nutrient == .sugar }?.value, 10)
        let backend = FakeHealth(); try await EventSync.perform(library.events[0], using: backend)
        XCTAssertEqual(Set(backend.authorizedNutrients), [.sugar, .sodium])
        XCTAssertEqual(backend.samples[event.syncID(for: .sugar)]!, 33, accuracy: 1e-9)
        XCTAssertEqual(backend.samples[event.syncID(for: .sodium)]!, 0.066, accuracy: 1e-9)
        library.completeSync(event.id); try library.revoke(event.id)
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
        try library.restore(event.id); try await EventSync.perform(library.events[0], using: backend)
        XCTAssertEqual(backend.samples.count, 2)
    }
}
