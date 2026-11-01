import XCTest
@testable import IntakeCore

final class HealthCatalogTests: XCTestCase {
    func testEveryMassCategoryMapsByHumanNameAndIdentifierIsUnique() {
        XCTAssertEqual(Nutrient.allCases.count, 39)
        XCTAssertEqual(Set(Nutrient.allCases.map(\.healthKitIdentifier)).count, 39)
        for nutrient in Nutrient.allCases {
            let item = Ingredient(name: nutrient.title, value: 1, unit: nutrient.dimension == .mass ? "mg" : nutrient.dimension == .volume ? "mL" : "kcal")
            XCTAssertEqual(item.mapping.kind, .exact, nutrient.title)
            XCTAssertEqual(item.mapping.nutrient, nutrient, nutrient.title)
        }
        for name in ["EPA", "DHA", "鱼油", "姜黄提取物"] {
            XCTAssertEqual(Ingredient(name: name, value: 1, unit: "mg").mapping.kind, .localOnly)
        }
    }
    func testPreviouslyMissingTypesRecognizedFromLabel() throws {
        let draft = SupplementParser.parse("Each capsule contains:\nPhosphorus 100 mg\nChloride 200 mg\nProtein 1 g\nDietary fiber 500 mg\nMonounsaturated fat 50 mg")
        var product = Product(name: "Synthetic", serving: draft.serving, confirmedAt: Date())
        product.ingredients = draft.ingredients
        try product.validate()
        XCTAssertEqual(try HealthPlan.samples(for: product).map(\.nutrient), [.phosphorus, .chloride, .protein, .fiber, .fatMonounsaturated])
    }
    func testAppleFatHierarchyPreservesDistinctCategoriesWithoutSumming() throws {
        let fat = Ingredient(name: "总脂肪", value: 834, unit: "mg")
        let omega = Ingredient(name: "Omega-3", value: 500, unit: "mg", parentID: fat.id)
        let epa = Ingredient(name: "EPA", value: 300, unit: "mg", parentID: omega.id)
        var product = Product(name: "Synthetic", serving: "1 粒", confirmedAt: Date())
        product.ingredients = [fat, omega, epa]; product.allowBroadMapping = true
        try product.validate()
        let event = try IntakeEvent(product: product, servings: 3)
        let samples = try event.healthSamples
        XCTAssertEqual(samples.map(\.nutrient), [.fatTotal, .fatPolyunsaturated])
        XCTAssertEqual(event.grams(for: samples[0]), 2.502, accuracy: 1e-12)
        XCTAssertEqual(event.grams(for: samples[1]), 1.5, accuracy: 1e-12)
    }
    func testUnapprovedMappingIsNotPresentedAsUnsupported() throws {
        let draft = SupplementParser.parse(SupplementTests.label)
        var product = Product(name: "Jamieson", serving: draft.serving, confirmedAt: Date())
        product.ingredients = draft.ingredients
        XCTAssertTrue(MappingPresentation.needsBroadConsent(product))
        XCTAssertTrue(MappingPresentation.localReason(product).contains("确认宽泛映射"))
        let old = try IntakeEvent(product: product, servings: 1)
        product.allowBroadMapping = true
        XCTAssertFalse(MappingPresentation.needsBroadConsent(product))
        XCTAssertTrue(try old.healthSamples.isEmpty)
        XCTAssertEqual(try IntakeEvent(product: product, servings: 1).healthSamples.map(\.nutrient), [.fatPolyunsaturated])
    }
}
