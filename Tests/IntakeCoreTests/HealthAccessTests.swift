import XCTest
@testable import IntakeCore

final class HealthAccessTests: XCTestCase {
    func testVitaminAndMineralAuthorizationIsNotLimitedToWater() async throws {
        let p = Product(name: "Synthetic multi", serving: "1 tablet", nutrients: [.init(.vitaminC, 500, .mg), .init(.calcium, 250, .mg)], confirmedAt: Date())
        XCTAssertEqual(Set(HealthAccessPlan.suggested(products: [p], events: [])), [.vitaminC, .calcium])
        let event = try IntakeEvent(product: p, servings: 1)
        let backend = await FakeHealth()
        try await EventSync.perform(event, using: backend)
        let types = await backend.authorizedNutrients
        XCTAssertEqual(Set(types), [.vitaminC, .calcium])
        let count = await backend.samples.count
        XCTAssertEqual(count, 2)
    }
    func testBroadMappingNeedsConsentAndAuthorizationAloneDoesNotChangeProduct() throws {
        var p = Product(name: "Synthetic omega", serving: "1 capsule", confirmedAt: Date())
        p.ingredients = [Ingredient(name: "Omega-3", value: 500, unit: "mg")]
        XCTAssertTrue(HealthAccessPlan.suggested(products: [p], events: []).isEmpty)
        XCTAssertTrue(HealthAccessPlan.explanation(for: p).contains("尚未启用"))
        p.allowBroadMapping = true
        XCTAssertEqual(HealthAccessPlan.suggested(products: [p], events: []), [.fatPolyunsaturated])
    }
    func testPendingSnapshotStillSuggestsItsTypesAfterProductEdit() throws {
        var p = Product(name: "Synthetic", serving: "1", nutrients: [.init(.iron, 10, .mg)], confirmedAt: Date())
        let old = try IntakeEvent(product: p, servings: 1)
        p.nutrients = [.init(.vitaminC, 500, .mg)]
        XCTAssertEqual(Set(HealthAccessPlan.suggested(products: [p], events: [old])), [.iron, .vitaminC])
        var deleted = old; deleted.state = .deleted
        XCTAssertEqual(HealthAccessPlan.suggested(products: [p], events: [deleted]), [.vitaminC])
    }
    func testUnconfirmedAndUnknownIngredientsDoNotInventPermissions() {
        let unconfirmed = Product(name: "Draft", serving: "1", nutrients: [.init(.vitaminD, 25, .mcg)])
        var unknown = Product(name: "Unknown", serving: "1", confirmedAt: Date())
        unknown.ingredients = [Ingredient(name: "Turmeric Extract", value: 20, unit: "mg")]
        XCTAssertTrue(HealthAccessPlan.suggested(products: [unconfirmed, unknown], events: []).isEmpty)
        var review = unknown
        var item = Ingredient(name: "Vitamin C", value: 500, unit: "mg"); item.reviewReasons = ["需核对"]
        review.ingredients = [item]
        XCTAssertTrue(HealthAccessPlan.explanation(for: review).contains("待确认"))
    }
}
