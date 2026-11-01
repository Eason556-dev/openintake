import XCTest
@testable import IntakeCore

final class TextMealTests: XCTestCase {
    let rice = NutrientAmount(.carbohydrates, 28, .g, origin: .aiEstimate)
    func testMultiFoodEvidenceMassAndConfirmedNutritionTotals() throws {
        let source = "米饭150g、鸡肉100g、苹果80g"
        let draft = try TextMealValidation.build([
            .init(nameQuote: "米饭", sourceQuote: "米饭150g", quantityQuote: "150g", estimates: [rice]),
            .init(nameQuote: "鸡肉", sourceQuote: "鸡肉100g", quantityQuote: "100g", estimates: [.init(.protein, 25, .g, origin: .aiEstimate)]),
            .init(nameQuote: "苹果", sourceQuote: "苹果80g", quantityQuote: "80g", estimates: [.init(.sugar, 10, .g, origin: .aiEstimate)])
        ], source: source)
        XCTAssertEqual(draft.items.count, 3)
        XCTAssertEqual(draft.items[0].grams, 150)
        XCTAssertThrowsError(try MealValidation.product(draft.items, confirmed: false))
        let product = try MealValidation.product(draft.items, confirmed: true)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .carbohydrates }?.value, 42)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .protein }?.value, 25)
        XCTAssertEqual(product.nutrients.first { $0.nutrient == .sugar }?.value, 8)
        XCTAssertFalse(product.nutrients.contains { $0.nutrient == .water })
        XCTAssertTrue(product.nutrients.allSatisfy { $0.origin == .aiEstimate })
    }
    func testUnknownPortionsVolumeAndInventedMassNeverAutoFill() throws {
        let source = "一碗米饭、牛奶250mL、鸡肉0.1kg"
        let draft = try TextMealValidation.build([
            .init(nameQuote: "米饭", sourceQuote: "一碗米饭", quantityQuote: "150g", estimates: [rice]),
            .init(nameQuote: "牛奶", sourceQuote: "牛奶250mL", quantityQuote: "250mL"),
            .init(nameQuote: "鸡肉", sourceQuote: "鸡肉0.1kg", quantityQuote: "0.1kg")
        ], source: source)
        XCTAssertNil(draft.items[0].grams); XCTAssertNil(draft.items[1].grams)
        XCTAssertEqual(draft.items[2].grams, 100)
        XCTAssertThrowsError(try MealValidation.product(draft.items, confirmed: true))
    }
    func testInventedNameBadNutrientsAndRepeatedModelRows() throws {
        let source = "rice 150g"
        let draft = try TextMealValidation.build([
            .init(nameQuote: "rice", sourceQuote: source, quantityQuote: "150g", estimates: [.init(.water, 100, .mL, origin: .aiEstimate)]),
            .init(nameQuote: "rice", sourceQuote: source, quantityQuote: "150g", estimates: [rice]),
            .init(nameQuote: "fish", sourceQuote: "fish100g", quantityQuote: "100g", estimates: [rice])
        ], source: source)
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertTrue(draft.items[0].per100g.isEmpty)
        XCTAssertFalse(draft.warnings.isEmpty)
        XCTAssertThrowsError(try MealValidation.product(draft.items, confirmed: true))
    }
    func testRepeatedActualPortionsNotMergedAndAmbiguousMassRequiresReview() throws {
        let source = "苹果50g、苹果50g、米饭150g鸡肉100g"
        let apple = TextFoodProposal(nameQuote: "苹果", sourceQuote: "苹果50g", quantityQuote: "50g")
        let draft = try TextMealValidation.build([apple, apple, apple,
            .init(nameQuote: "米饭", sourceQuote: "米饭150g鸡肉100g", quantityQuote: "100g")], source: source)
        XCTAssertEqual(draft.items.count, 3)
        XCTAssertEqual(draft.items[0].grams, 50); XCTAssertEqual(draft.items[1].grams, 50)
        XCTAssertNil(draft.items[2].grams)
    }
    func testFallbackAndInputBoundsNeverInventNutrition() throws {
        let draft = try TextMealValidation.fallback("米饭150克、鸡肉100g；一杯奶")
        XCTAssertEqual(draft.items.count, 3)
        XCTAssertEqual(draft.items[0].grams, 150)
        XCTAssertNil(draft.items[2].grams)
        XCTAssertTrue(draft.items.allSatisfy { $0.per100g.isEmpty })
        XCTAssertThrowsError(try TextMealValidation.fallback(Array(repeating: "rice", count: 31).joined(separator: ";")))
        XCTAssertThrowsError(try TextMealValidation.validateInput("  "))
        XCTAssertThrowsError(try TextMealValidation.validateInput(String(repeating: "x", count: 4001)))
        let rejected = try TextMealValidation.build([.init(nameQuote: "fish", sourceQuote: "rice")], source: "rice")
        XCTAssertEqual(rejected.items.map(\.name), ["rice"])
        XCTAssertTrue(rejected.items[0].nutrientsPer100.isEmpty) // Preserve source, never the invented name.
    }
    func testUnknownZeroDoesNotEraseOtherValidEstimatesButContradictoryMacrosFail() throws {
        let draft = try TextMealValidation.build([.init(nameQuote: "rice", sourceQuote: "rice 150g", quantityQuote: "150g", estimates: [rice, .init(.sugar, 0, .g, origin: .aiEstimate)])], source: "rice 150g")
        XCTAssertEqual(draft.items[0].per100g, [rice])
        let invalid = try TextMealValidation.build([.init(nameQuote: "rice", sourceQuote: "rice 150g", quantityQuote: "150g", estimates: [.init(.protein, 80, .g, origin: .aiEstimate), .init(.fatTotal, 80, .g, origin: .aiEstimate)])], source: "rice 150g")
        XCTAssertTrue(invalid.items[0].per100g.isEmpty)
    }
    @MainActor func testTextMealConfirmationUsesSameHealthRetryAndDeletion() async throws {
        let draft = try TextMealValidation.build([.init(nameQuote: "rice", sourceQuote: "rice 150g", quantityQuote: "150g", estimates: [rice])], source: "rice 150g")
        let product = try MealValidation.product(draft.items, confirmed: true)
        let event = try IntakeEvent(product: product, servings: 1)
        var library = Library(); try library.enqueue(event)
        let backend = FakeHealth(); backend.granted = false
        do { try await EventSync.perform(event, using: backend); XCTFail("Denied") } catch { }
        XCTAssertEqual(library.events[0].state, .pending)
        XCTAssertTrue(backend.samples.isEmpty)
        backend.granted = true
        try await EventSync.perform(event, using: backend); library.completeSync(event.id)
        XCTAssertEqual(backend.samples[event.syncID(for: .carbohydrates)], 42)
        try library.revoke(event.id)
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
    }
}
