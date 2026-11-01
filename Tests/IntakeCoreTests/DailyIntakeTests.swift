import XCTest
@testable import IntakeCore

final class DailyIntakeTests: XCTestCase {
    func testSplitColumnsFindValuesWithoutDependingOnReadingOrder() throws {
        let doc = OCRDocument(blocks: [
            OCRBlock(id: "basis", text: "Each softgel contains"),
            OCRBlock(id: "a", text: "Vitamin C", box: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.04)),
            OCRBlock(id: "b", text: "Vitamin D", box: .init(x: 0.1, y: 0.6, width: 0.3, height: 0.04)),
            OCRBlock(id: "v2", text: "25 mcg", box: .init(x: 0.7, y: 0.6, width: 0.2, height: 0.04)),
            OCRBlock(id: "v1", text: "500 mg", box: .init(x: 0.7, y: 0.7, width: 0.2, height: 0.04))
        ])
        let label = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "offlineRules")
        XCTAssertEqual(label.ingredients.first { $0.canonicalID == "vitaminC" }?.value, 500)
        XCTAssertEqual(label.ingredients.first { $0.canonicalID == "vitaminD" }?.value, 25)
    }
    func testMultipleColumnsAreNotAutomaticallySelected() {
        let name = OCRBlock(id: "n", text: "Vitamin C", box: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.04))
        let doc = OCRDocument(blocks: [name,
            OCRBlock(id: "a", text: "500 mg", box: .init(x: 0.6, y: 0.7, width: 0.1, height: 0.04)),
            OCRBlock(id: "b", text: "1000 mg", box: .init(x: 0.8, y: 0.7, width: 0.1, height: 0.04))])
        XCTAssertNil(OCRLayout.rightHandAmount(for: name, in: doc))
    }
    func testCrossPageAndPercentColumnsAreNotAmounts() {
        let name = OCRBlock(id: "n", text: "Vitamin C", box: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.04))
        for amount in [OCRBlock(id: "a", page: 1, text: "500 mg", box: .init(x: 0.7, y: 0.7, width: 0.1, height: 0.04)), OCRBlock(id: "a", text: "500 mg 50%", box: .init(x: 0.7, y: 0.7, width: 0.1, height: 0.04))] {
            XCTAssertNil(OCRLayout.rightHandAmount(for: name, in: .init(blocks: [name, amount])))
        }
    }
    func testDotLeadersAndSeparatorsKeepIngredientIdentities() {
        for text in ["Vitamin C .... 500 mg", "Vitamin C | 500 mg", "Vitamin C — 500 mg", "Vitamin C: 500 mg"] {
            let doc = OCRDocument(text: "Each tablet contains\n" + text)
            let label = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "offlineRules")
            XCTAssertEqual(label.ingredients.first?.canonicalID, "vitaminC", text)
            XCTAssertEqual(label.ingredients.first?.value, 500, text)
        }
    }
    func testPromptIncludesLayoutAndConfidence() {
        let doc = OCRDocument(blocks: [.init(id: "a", text: "Synthetic", confidence: 0.8, box: .init(x: 0, y: 0, width: 1, height: 1), column: 2)])
        XCTAssertTrue(doc.promptText.contains("bounds")); XCTAssertTrue(doc.promptText.contains("confidence")); XCTAssertTrue(doc.promptText.contains("column"))
    }
    func testWaterUnitsDuplicateGuardAndSyncSnapshot() throws {
        let product = HydrationProgress.product()
        let a = try IntakeEvent(product: product, servings: product.servings(forUnits: 250))
        let b = try IntakeEvent(product: HydrationProgress.product(), servings: 2.5, date: a.date)
        XCTAssertTrue(a.duplicates(b))
        XCTAssertEqual(a.canonicalValue(for: try XCTUnwrap(a.healthSamples.first)), 250)
        XCTAssertEqual(a.product.kind, .water)
    }
    func testWaterRingCountsLocalPendingButExcludesRevokedAndYesterday() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let p = HydrationProgress.product()
        var events = try (0..<5).map { _ in try IntakeEvent(product: p, servings: 2.5, date: now) }
        events[0].state = .synced; events[1].state = .pending; events[2].state = .deleted; events[3].state = .deletionPending
        events[4].date = calendar.date(byAdding: .day, value: -1, to: now)!
        let progress = HydrationProgress(events: events, goal: 1000, date: now, calendar: calendar)
        XCTAssertEqual(progress.milliliters, 500); XCTAssertEqual(progress.fraction, 0.5)
        XCTAssertEqual(HydrationProgress(events: events, goal: .nan, date: now, calendar: calendar).goal, 2000)
    }
    func testWaterGoalSaturatesAndNoOtherNutrientCounts() throws {
        let e = try IntakeEvent(product: HydrationProgress.product(), servings: 30)
        XCTAssertEqual(HydrationProgress(events: [e], goal: 2000).fraction, 1)
        var p = Product(name: "Synthetic food", serving: "1", nutrients: [.init(.protein, 10, .g)], confirmedAt: Date()); p.kind = .food
        let food = try IntakeEvent(product: p, servings: 1)
        XCTAssertEqual(HydrationProgress(events: [food], goal: 2000).milliliters, 0)
    }
    func testReminderPlanBoundaries() throws {
        XCTAssertEqual(try WaterReminderPlan.hours(start: 8, end: 20, interval: 2), [8,10,12,14,16,18,20])
        XCTAssertEqual(try WaterReminderPlan.hours(start: 23, end: 23, interval: 1), [23])
        for tuple in [(20,8,2),(-1,20,2),(8,24,2),(8,20,0)] { XCTAssertThrowsError(try WaterReminderPlan.hours(start: tuple.0, end: tuple.1, interval: tuple.2)) }
    }
    func testMealNeedsActualPortionAndExplicitConfirmation() throws {
        let item = MealPortion(name: "Synthetic rice", per100g: [.init(.carbohydrates, 28, .g, origin: .aiEstimate)])
        XCTAssertThrowsError(try MealValidation.product([item], confirmed: true))
        var weighed = item; weighed.grams = 150
        XCTAssertThrowsError(try MealValidation.product([weighed], confirmed: false))
        XCTAssertEqual(try MealValidation.product([weighed], confirmed: true).nutrients.first?.value, 42)
    }
    func testMealUnknownsAreOmittedAndSeparateFoodsSumOnce() throws {
        let a = MealPortion(name: "A", grams: 150, per100g: [.init(.protein, 10, .g, origin: .aiEstimate), .init(.energyConsumed, 100, .kcal, origin: .aiEstimate)])
        let b = MealPortion(name: "B", grams: 50, per100g: [.init(.protein, 20, .g, origin: .aiEstimate)])
        let p = try MealValidation.product([a,b], confirmed: true)
        XCTAssertEqual(p.nutrients.count, 2); XCTAssertNil(p.nutrients.first { $0.nutrient == .sodium })
        XCTAssertEqual(p.nutrients.first { $0.nutrient == .protein }?.value, 25)
        XCTAssertEqual(p.nutrients.first { $0.nutrient == .energyConsumed }?.value, 150)
        XCTAssertEqual(p.mealDetails?.count, 2); XCTAssertEqual(p.kind, .food)
        XCTAssertTrue(p.nutrients.allSatisfy { $0.origin == .aiEstimate })
    }
    func testMealRejectsImpossibleOrWrongDimensionOrDuplicateEstimates() {
        for amounts in [[NutrientAmount(.protein, 120, .g, origin: .aiEstimate)], [.init(.energyConsumed, 10, .mg, origin: .aiEstimate)], [.init(.water, 100, .mL, origin: .aiEstimate)], [.init(.protein, .nan, .g, origin: .aiEstimate)], [.init(.protein, 0, .g, origin: .aiEstimate)], [.init(.protein, 10, .g, origin: .aiEstimate), .init(.protein, 20, .g, origin: .aiEstimate)]] {
            XCTAssertThrowsError(try MealValidation.validate(.init(name: "Synthetic", per100g: amounts)))
        }
        XCTAssertThrowsError(try MealValidation.product([.init(name: "Unknown", grams: 100)], confirmed: true))
    }
    func testMealSnapshotAndWaterAreBackwardsCompatible() throws {
        let p = try MealValidation.product([.init(name: "Synthetic", grams: 100, per100g: [.init(.protein, 1, .g, origin: .aiEstimate)])], confirmed: true)
        var library = Library(); library.events = [try IntakeEvent(product: p, servings: 1), try IntakeEvent(product: HydrationProgress.product(), servings: 2.5)]
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.events[0].product.mealDetails?.first?.grams, 100)
        XCTAssertEqual(restored.events[1].product.kind, .water)
        let old = Product(name: "Old", serving: "1", nutrients: [.init(.vitaminC, 1, .mg)], confirmedAt: Date())
        XCTAssertNil(try JSONDecoder().decode(Product.self, from: JSONEncoder().encode(old)).mealDetails)
    }
    func testSyncSummarySeparatesLocalAndDeletion() throws {
        var events = try (0..<5).map { _ in try IntakeEvent(product: HydrationProgress.product(), servings: 1) }
        let states: [SyncState] = [.synced,.pending,.localOnly,.deletionPending,.deleted]
        for i in events.indices { events[i].state = states[i] }
        let s = SyncSummary(events: events)
        XCTAssertEqual(s.synced,1); XCTAssertEqual(s.pending,1); XCTAssertEqual(s.local,1); XCTAssertEqual(s.deleting,1); XCTAssertTrue(s.needsSync)
    }
    func testMealRejectsExcessMacroMassAndPreservesManualOrigins() throws {
        let excess = MealPortion(name: "Synthetic", grams: 100, per100g: [.init(.protein, 60, .g, origin: .aiEstimate), .init(.carbohydrates, 60, .g, origin: .aiEstimate)])
        XCTAssertThrowsError(try MealValidation.product([excess], confirmed: true))
        let manual = MealPortion(name: "Manual", grams: 100, per100g: [.init(.protein, 10, .g, origin: .manual)])
        XCTAssertEqual(try MealValidation.product([manual], confirmed: true).nutrients.first?.origin, .manual)
    }
    func testAmbiguousTableColumnsCannotGroundAnAIChoice() {
        let doc = OCRDocument(blocks: [.init(id: "h", text: "Each tablet contains"),
            .init(id: "n", text: "Vitamin C", table: "t", row: 0, column: 0),
            .init(id: "a", text: "500 mg", table: "t", row: 0, column: 1),
            .init(id: "b", text: "1000 mg", table: "t", row: 0, column: 2)])
        let proposal = SemanticProposal(basisQuote: "Each tablet contains", ingredients: [.init(key: "c", name: "Vitamin C", amount: "500", unit: "mg", evidenceIDs: ["n","a"], nameQuote: "Vitamin C", amountQuote: "500 mg")])
        let label = SemanticValidator.validate(proposal, document: doc, provider: "appleFoundationModels")
        XCTAssertNil(label.ingredients.first?.value)
    }

}
