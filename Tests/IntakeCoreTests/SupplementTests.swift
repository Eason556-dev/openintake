import XCTest
@testable import IntakeCore

final class SupplementTests: XCTestCase {
    static let label = """
    Jamieson Omega-3 + Turmeric
    Each softgel contains:
    Fish oil 834 mg
    Omega-3 500 mg
    EPA 300 mg
    DHA 200 mg
    Turmeric extract 20 mg (50:1, equivalent to dried herb 1,000 mg)
    """
    func product(broad: Bool = false, text: String = label) -> Product {
        let draft = SupplementParser.parse(text)
        var p = Product(name: "Jamieson Omega-3 + Turmeric", serving: draft.serving, confirmedAt: Date())
        p.ingredients = draft.ingredients; p.unitsPerServing = draft.unitsPerServing
        p.parsingWarnings = draft.warnings; p.allowBroadMapping = broad
        return p
    }
    func testJamiesonNamesQuantitiesAndHierarchy() throws {
        let p = product(); try p.validate()
        let items = try XCTUnwrap(p.ingredients)
        XCTAssertEqual(items.map(\.name), ["鱼油", "Omega-3", "EPA", "DHA", "姜黄提取物", "干燥草本等效量"])
        XCTAssertEqual(items.compactMap(\.value), [834, 500, 300, 200, 20, 1000])
        XCTAssertEqual(items.map(\.unit), Array(repeating: "mg", count: 6))
        XCTAssertEqual(items[1].parentID, items[0].id)
        XCTAssertEqual(items[2].parentID, items[1].id); XCTAssertEqual(items[3].parentID, items[1].id)
        XCTAssertEqual(items[5].parentID, items[4].id); XCTAssertEqual(items[5].relation, .equivalent)
        XCTAssertEqual(items[4].note, "提取比例 50:1")
        XCTAssertEqual(p.unitsPerServing, 1)
    }
    func testChineseSingleLineAndThousandsEquivalent() throws {
        let text = "Jamieson Omega-3 + Turmeric\n每粒鱼油 834 mg，其中 Omega-3 500 mg（EPA 300 mg、DHA 200 mg），另含姜黄提取物 20 mg（50:1，相当于干燥草本 1,000 mg）。"
        let p = product(broad: true, text: text); try p.validate()
        XCTAssertEqual(p.ingredients?.compactMap(\.value), [834, 500, 300, 200, 20, 1000])
        XCTAssertEqual(try HealthPlan.samples(for: p).map(\.nutrient), [.fatPolyunsaturated])
    }
    func testBroadMappingIsExplicitAndLocalIngredientsAreNotLost() throws {
        let p = product()
        XCTAssertTrue(try HealthPlan.samples(for: p).isEmpty)
        XCTAssertEqual(p.ingredients?[1].mapping.kind, .broader)
        XCTAssertEqual(p.ingredients?[1].mapping.nutrient, .fatPolyunsaturated)
        for i in [0,2,3,4,5] { XCTAssertEqual(p.ingredients?[i].mapping.kind, .localOnly) }
        XCTAssertEqual(try HealthPlan.samples(for: product(broad: true)).count, 1)
    }
    func testSingleAndMultipleCapsuleMathAndNoDoubleCounting() throws {
        let p = product(broad: true)
        for count in [1.0, 2, 3] {
            let event = try IntakeEvent(product: p, servings: count / (p.unitsPerServing ?? 1))
            let samples = try event.healthSamples
            XCTAssertEqual(samples.count, 1)
            XCTAssertEqual(samples[0].nutrient, .fatPolyunsaturated)
            XCTAssertEqual(event.grams(for: samples[0]), 0.5 * count, accuracy: 1e-12)
            let items = try XCTUnwrap(p.ingredients)
            XCTAssertEqual(items[0].amount(forServings: event.servings), 834 * count)
            XCTAssertEqual(items[2].amount(forServings: event.servings), 300 * count)
            XCTAssertEqual(items[3].amount(forServings: event.servings), 200 * count)
            XCTAssertEqual(items[4].amount(forServings: event.servings), 20 * count)
            XCTAssertEqual(items[5].amount(forServings: event.servings), 1000 * count)
        }
    }
    func testServingTwoCapsulesConvertsActualCount() throws {
        let p = product(broad: true, text: Self.label.replacingOccurrences(of: "Each softgel contains:", with: "Serving Size: 2 softgels"))
        XCTAssertEqual(p.unitsPerServing, 2)
        let event = try IntakeEvent(product: p, servings: try p.servings(forUnits: 1))
        XCTAssertEqual(event.consumedUnitCount, 1)
        XCTAssertEqual(try event.grams(for: event.healthSamples[0]), 0.25, accuracy: 1e-12)
    }
    func testExactMappingAndMassConversion() throws {
        let p = product(broad: true, text: "Each capsule contains:\nVitamin D 25 mcg\nOmega-3 0.5 g\nTurmeric extract 20 mg")
        XCTAssertEqual(p.ingredients?[0].mapping.kind, .exact)
        let event = try IntakeEvent(product: p, servings: 2)
        let samples = try event.healthSamples
        XCTAssertEqual(samples.map(\.nutrient), [.vitaminD, .fatPolyunsaturated])
        XCTAssertEqual(event.grams(for: samples[0]), 0.00005, accuracy: 1e-12)
        XCTAssertEqual(event.grams(for: samples[1]), 1, accuracy: 1e-12)
    }
    func testUnknownCustomAndSpecialUnitsUseNutrientSpecificRules() throws {
        let p = product(text: "Each capsule contains:\nCoenzyme Q10 100 mg\nVitamin D 1000 IU\nVitamin A 600 mcg RAE")
        try p.validate()
        XCTAssertEqual(p.ingredients?.count, 3)
        XCTAssertEqual(try HealthPlan.samples(for: p).map(\.nutrient), [.vitaminD])
        XCTAssertEqual(try HealthPlan.samples(for: p).first?.value, 25)
        XCTAssertEqual(p.ingredients?[0].name, "Coenzyme Q10")
        XCTAssertEqual(p.ingredients?[1].unit, "IU")
        XCTAssertEqual(p.ingredients?[2].unit, "mcg RAE")
    }
    func testUnknownAmountsAndCyclesCannotBecomeSamples() throws {
        var p = product(text: "Each capsule contains:\nOmega-3\nEPA 100 mg")
        XCTAssertNil(p.ingredients?[0].value)
        XCTAssertTrue(try HealthPlan.samples(for: p).isEmpty)
        guard p.ingredients?.count == 2 else { return XCTFail("Unknown Omega-3 must be preserved") }
        let childID = p.ingredients?[1].id
        p.ingredients?[0].parentID = childID
        XCTAssertThrowsError(try p.validate())
    }
    func testAmbiguousRepeatedTotalsAreRejectedNotSummed() {
        let p = product(broad: true, text: "Each capsule contains:\nOmega-3 500 mg\nOmega-3 700 mg")
        XCTAssertThrowsError(try p.validate())
    }
    func testParentSameTypeSuppressesDescendant() throws {
        var p = product(broad: true, text: "Each capsule contains:\nFish oil 834 mg\nOmega-3 500 mg")
        var exact = Ingredient(name: "多不饱和脂肪", value: 500, unit: "mg")
        exact.parentID = p.ingredients?[1].id
        p.ingredients?.append(exact)
        try p.validate()
        XCTAssertEqual(try HealthPlan.samples(for: p).count, 1)
        XCTAssertEqual(try HealthPlan.samples(for: p)[0].value, 500)
    }
    func testContradictoryHierarchyCannotBeConfirmed() {
        let p = product(broad: true, text: Self.label.replacingOccurrences(of: "EPA 300 mg", with: "EPA 400 mg"))
        XCTAssertThrowsError(try p.validate())
    }
    func testWriteSnapshotDoesNotRecomputeAfterProductChanges() throws {
        var event = try IntakeEvent(product: product(broad: true), servings: 1)
        event.product.allowBroadMapping = false
        XCTAssertEqual(try event.healthSamples.map(\.nutrient), [.fatPolyunsaturated])
        let decoded = try JSONDecoder().decode(IntakeEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(try decoded.healthSamples.map(\.nutrient), [.fatPolyunsaturated])
    }
    func testLegacyJSONWithoutIngredientFieldsStillLoads() throws {
        let old = Product(name: "Old", serving: "1 capsule", nutrients: [NutrientAmount(.vitaminD, 25, .mcg)], confirmedAt: Date())
        let data = try JSONEncoder().encode(old)
        let restored = try JSONDecoder().decode(Product.self, from: data)
        XCTAssertNil(restored.ingredients)
        XCTAssertEqual(try HealthPlan.samples(for: restored), old.nutrients)
    }
    @MainActor func testHealthBackendReceivesOnlyConsentedPUFAAndStableRetry() async throws {
        let backend = FakeHealth()
        let event = try IntakeEvent(product: product(broad: true), servings: 2)
        try await EventSync.perform(event, using: backend)
        try await EventSync.perform(event, using: backend)
        XCTAssertEqual(backend.authorizedNutrients, [.fatPolyunsaturated])
        XCTAssertEqual(backend.samples.count, 1)
        XCTAssertEqual(backend.samples[event.syncID(for: .fatPolyunsaturated)], 1)
    }
    @MainActor func testLocalOnlyRecordsNeverRequestHealthPermission() async throws {
        let backend = FakeHealth(); let event = try IntakeEvent(product: product(), servings: 1)
        var lib = Library(); try lib.enqueue(event)
        try await EventSync.perform(event, using: backend); lib.completeSync(event.id)
        XCTAssertEqual(backend.authorizations, 0); XCTAssertEqual(backend.writes, 0)
        XCTAssertEqual(lib.events[0].state, .localOnly)
        try lib.revoke(event.id); try await EventSync.perform(lib.events[0], using: backend); lib.completeSync(event.id)
        XCTAssertEqual(lib.events[0].state, .deleted)
    }
    @MainActor func testHealthFailureRetainsAllLocalIngredientsAndOutbox() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = LibraryRepository(url: directory.appendingPathComponent("library.json"))
        let event = try IntakeEvent(product: product(broad: true), servings: 3)
        var lib = Library(); lib.products = [event.product]; try lib.enqueue(event); try repo.save(lib)
        let backend = FakeHealth(); backend.failWrite = true
        do { try await EventSync.perform(event, using: backend); XCTFail("Should fail") } catch {}
        let restored = try repo.load()
        XCTAssertEqual(restored.events[0].state, .pending)
        XCTAssertEqual(restored.events[0].product.ingredients?.count, 6)
        XCTAssertEqual(restored.events[0].product.ingredients?[4].amount(forServings: 3), 60)
        backend.failWrite = false
        try await EventSync.perform(restored.events[0], using: backend)
        XCTAssertEqual(backend.samples.count, 1)
        XCTAssertEqual(backend.samples[event.syncID(for: .fatPolyunsaturated)], 1.5)
    }
}
