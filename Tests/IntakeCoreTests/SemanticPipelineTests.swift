import XCTest
@testable import IntakeCore

final class SemanticPipelineTests: XCTestCase {
    static let english = """
    Jamieson Omega-3 + Turmeric
    Each softgel contains:
    Fish Oil 834 mg
    Omega-3 500 mg
    EPA 300 mg
    DHA 200 mg
    Turmeric Extract 20 mg (50:1)
    Equivalent to dried herb 1,000 mg
    Recommended dose – Adults: Take 2 softgels daily
    """
    static let french = """
    Chaque gélule contient:
    Huile de poisson 834 mg
    Oméga-3 500 mg
    EPA 300 mg
    DHA 200 mg
    Extrait de curcuma 20 mg (50:1)
    Équivalent en herbe sèche 1 000 mg
    Posologie – Adultes: Prendre 2 gélules
    Fournissant 500 mg
    """
    static let chinese = """
    Jamieson Omega-3 + Turmeric
    每粒含有：
    鱼油 834 毫克，其中欧米伽3 500 毫克，EPA 300 毫克，DHA 200 毫克
    姜黄提取物 20 毫克（50:1），相当于干燥草本 1,000 毫克
    建议服用：成人每天两粒
    """
    func parsed(_ text: String) -> ValidatedLabel {
        let doc = OCRDocument(text: text)
        return SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "offlineRules")
    }
    func product(_ label: ValidatedLabel, consent: Bool = true) -> Product {
        var p = Product(name: "Synthetic Jamieson", serving: label.serving, confirmedAt: Date())
        p.ingredients = label.ingredients; p.unitsPerServing = label.unitsPerServing; p.labelBasis = label.basis; p.allowBroadMapping = consent
        return p
    }
    func testEnglishChineseBilingualAndMixedHaveSameDoseGraph() throws {
        for text in [Self.english, Self.chinese, Self.english + "\n" + Self.french, Self.chinese + "\n" + Self.french] {
            let label = parsed(text)
            XCTAssertEqual(label.ingredients.count, 6, "\(text)\n\(label.warnings)")
            let ids = Dictionary(uniqueKeysWithValues: label.ingredients.compactMap { item in item.canonicalID.map { ($0, item) } })
            XCTAssertEqual(ids["fishOil"]?.value, 834)
            XCTAssertEqual(ids["omega3"]?.value, 500, "\(text)\n\(label.ingredients)")
            XCTAssertEqual(ids["epa"]?.parentID, ids["omega3"]?.id)
            XCTAssertEqual(ids["dha"]?.parentID, ids["omega3"]?.id)
            XCTAssertEqual(ids["omega3"]?.parentID, ids["fishOil"]?.id)
            XCTAssertEqual(ids["dryHerbEquivalent"]?.relation, .equivalent)
            XCTAssertEqual(ids["dryHerbEquivalent"]?.value, 1000)
            XCTAssertEqual(ids["turmericExtract"]?.value, 20)
            XCTAssertEqual(ids["turmericExtract"]?.extractRatio, "50:1")
            XCTAssertEqual(label.unitsPerServing, 1)
            XCTAssertFalse(label.recommendations.isEmpty)
            for count in [1.0, 2, 3] {
                let p = product(label); try p.validate()
                let event = try IntakeEvent(product: p, servings: p.servings(forUnits: count))
                let samples = try event.healthSamples
                XCTAssertEqual(samples.map(\.nutrient), [.fatPolyunsaturated])
                XCTAssertEqual(event.canonicalValue(for: try XCTUnwrap(samples.first)), count * 0.5, accuracy: 1e-12)
                XCTAssertEqual(ids["turmericExtract"]?.amount(forServings: count), 20 * count)
            }
            XCTAssertTrue(try HealthPlan.samples(for: product(label, consent: false)).isEmpty)
        }
    }
    func testServingSizeNormalizesButRecommendedDoseDoesNot() throws {
        let label = parsed("Serving size: 2 capsules\nVitamin D 1000 IU\nRecommended dose: Take 4 capsules daily")
        XCTAssertEqual(label.ingredients.first?.value, 500)
        XCTAssertEqual(label.unitsPerServing, 1)
        let p = product(label)
        let event = try IntakeEvent(product: p, servings: p.servings(forUnits: 2))
        let amount = try XCTUnwrap(event.healthSamples.first)
        XCTAssertEqual(event.canonicalValue(for: amount), 0.000025, accuracy: 1e-12)
        let daily = parsed("1日当たり 2錠\nビタミンD 1000 IU")
        XCTAssertEqual(daily.ingredients.first?.value, 500)
    }
    func testAliasesAreLanguageIndependentButFormsRemainSeparate() {
        for alias in ["Vitamin B1", "Thiamin", "维生素B1", "硫胺素", "Vitamine B1"] { XCTAssertEqual(IngredientCatalog.resolve(alias), "thiamin") }
        for alias in ["Fish Oil", "Huile de poisson", "鱼油", "フィッシュオイル", "어유", "Aceite de pescado", "Fischöl"] { XCTAssertEqual(IngredientCatalog.resolve(alias), "fishOil") }
        XCTAssertNil(IngredientCatalog.resolve("Calcium carbonate"))
        XCTAssertNil(IngredientCatalog.resolve("Thiamine hydrochloride"))
        let item = Ingredient(name: "Huile de poisson", value: 834, unit: "mg")
        XCTAssertEqual(item.displayName(language: "zh"), "鱼油")
        XCTAssertEqual(item.displayName(language: "en"), "Fish Oil")
    }
    func testSwappedAmountsHallucinationsAndInstructionsAreRejected() {
        let doc = OCRDocument(text: "Each capsule contains:\nVitamin D 10 mcg; Calcium 200 mg\nPosologie – Adultes: Prendre 2 gélules")
        let proposal = SemanticProposal(basisQuote: "Each capsule contains:", ingredients: [
            .init(key: "d", name: "Vitamin D", canonicalID: "vitaminD", amount: "200", unit: "mg", evidenceIDs: ["text-1"], nameQuote: "Vitamin D", amountQuote: "200 mg"),
            .init(key: "x", name: "Vitamin C", amount: "10", unit: "mg", evidenceIDs: ["text-1"], nameQuote: "Vitamin C", amountQuote: "10 mg"),
            .init(key: "dose", name: "Posologie", amount: "2", unit: "g", evidenceIDs: ["text-2"], nameQuote: "Posologie")
        ])
        let result = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
        XCTAssertEqual(result.ingredients.count, 1)
        XCTAssertNil(result.ingredients.first?.value)
        XCTAssertEqual(result.ingredients.first?.mapping.kind, .localOnly)
    }
    func testLowConfidenceErrorsInequalitiesAndConflictingDuplicatesStayUnknown() {
        var doc = OCRDocument(text: "Each capsule contains:\nVitamin D 10 mcg")
        doc.blocks[1].confidence = 0.4
        let low = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "fakeAI")
        XCTAssertNil(low.ingredients.first?.value)
        for line in ["Vitamin D 1O mcg", "Vitamin D <10 mcg", "Vitamin D -10 mcg", "Vitamin D unknown"] { XCTAssertNil(parsed("Each capsule contains:\n" + line).ingredients.first?.value, line) }
        let conflict = parsed(Self.english + "\nHuile de poisson 835 mg")
        XCTAssertNil(conflict.ingredients.first { $0.canonicalID == "fishOil" }?.value)
        XCTAssertFalse(conflict.warnings.isEmpty)
    }
    func testUnknownBasisNeverProducesWritableNutrition() throws {
        for heading in ["Recommended dose: 2 capsules", "1日当たり", ""] {
            let result = parsed(heading + "\nVitamin D 10 mcg")
            XCTAssertNil(result.ingredients.first?.value)
            XCTAssertTrue(try HealthPlan.samples(for: product(result)).isEmpty)
        }
    }
    func testCrossLineGeometryTableAndDifferentAngles() {
        for x in [0.1, 0.14, 0.2] { // rectified page positions after camera perspective correction
            let doc = OCRDocument(blocks: [
                .init(id: "basis", text: "Each capsule contains:"),
                .init(id: "name", text: "Vitamin D", box: .init(x: x, y: 0.7, width: 0.3, height: 0.04)),
                .init(id: "value", text: "10 mcg", box: .init(x: x + 0.01, y: 0.65, width: 0.2, height: 0.04))])
            let result = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "offlineRules")
            XCTAssertEqual(result.ingredients.first?.value, 10)
            var bad = doc; bad.blocks[2].box?.x = 0.8
            XCTAssertNil(SemanticValidator.validate(OfflineSemanticProvider.draft(bad), document: bad, provider: "fakeAI").ingredients.first?.value)
        }
        let table = OCRDocument(blocks: [.init(id: "basis", text: "Each capsule contains:"), .init(id: "n", text: "Vitamin D", table: "t", row: 0, column: 0), .init(id: "v", text: "10 mcg", table: "t", row: 0, column: 1)])
        XCTAssertEqual(SemanticValidator.validate(OfflineSemanticProvider.draft(table), document: table, provider: "fakeAI").ingredients.first?.value, 10)
    }
    func testSpecialUnitsWaterEnergyAndMassConversion() throws {
        let result = parsed("Each capsule contains:\nVitamin D 1000 IU\nVitamin A 600 mcg RAE\nFolate 400 mcg DFE\nVitamin E 10 IU\nWater 0.25 L\nEnergy 4.184 kJ\nCalcium 0.2 g\nVitamin B1 1000 μg")
        let p = product(result)
        let event = try IntakeEvent(product: p, servings: 2)
        let samples = try event.healthSamples
        let values = Dictionary(uniqueKeysWithValues: samples.map { ($0.nutrient, event.canonicalValue(for: $0)) })
        XCTAssertEqual(values[.vitaminD] ?? -1, 0.00005, accuracy: 1e-12)
        XCTAssertEqual(values[.water], 500)
        XCTAssertEqual(values[.energyConsumed] ?? -1, 2, accuracy: 1e-12)
        XCTAssertEqual(values[.calcium], 0.4)
        XCTAssertEqual(values[.thiamin], 0.002)
        XCTAssertNil(values[.vitaminA]); XCTAssertNil(values[.folate]); XCTAssertNil(values[.vitaminE])
    }
    func testInvalidGraphAndCompoundMassNeverEnterHealthPlan() throws {
        let doc = OCRDocument(text: "Each softgel contains:\nFish Oil 834 mg\nOmega-3 500 mg\nEPA 600 mg\nDHA 200 mg\nCalcium carbonate 100 mg")
        let result = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "fakeAI")
        XCTAssertTrue(try HealthPlan.samples(for: product(result)).isEmpty)
        XCTAssertTrue(result.ingredients.filter { ["omega3", "epa", "dha"].contains($0.canonicalID ?? "") }.allSatisfy { $0.mapping.kind == .localOnly })
    }
    func testDocumentAndSemanticProposalRoundTripDoesNotCreateEvents() throws {
        let doc = OCRDocument(text: Self.english + "\n" + Self.french)
        var p = product(parsed(doc.rawText)); p.ocrDocument = doc; p.semanticProposal = OfflineSemanticProvider.draft(doc)
        var library = Library(); library.products = [p]
        let copy = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(copy.products[0].ocrDocument, doc)
        XCTAssertEqual(copy.products[0].semanticProposal, p.semanticProposal)
        XCTAssertTrue(copy.events.isEmpty)
    }
    func testPer100gAndVolumeUseActualQuantityWithoutGuessingServingSize() throws {
        let label = parsed("Per 100 g\nProtein 20 g")
        let p = product(label)
        XCTAssertEqual(p.intakeUnitTitle, "g")
        let event = try IntakeEvent(product: p, servings: p.servings(forUnits: 25))
        XCTAssertEqual(event.consumedQuantity, 25)
        XCTAssertEqual(event.canonicalValue(for: try XCTUnwrap(event.healthSamples.first)), 5)
        let drink = product(parsed("Per 100 mL\nEnergy 10 kcal"))
        XCTAssertEqual(drink.intakeUnitTitle, "mL")
        let sip = try IntakeEvent(product: drink, servings: drink.servings(forUnits: 250))
        XCTAssertEqual(sip.canonicalValue(for: try XCTUnwrap(sip.healthSamples.first)), 25)
        let ambiguous = product(parsed("Per 100 g\nPer serving\nProtein 20 g"))
        XCTAssertTrue(try HealthPlan.samples(for: ambiguous).isEmpty)
    }
    func testUntrustedModelCannotMapCompoundMassToElement() throws {
        for (line, name, id) in [("Calcium carbonate 100 mg", "Calcium", "calcium"), ("氧化铁 100 mg", "铁", "iron")] {
            let doc = OCRDocument(text: "Each capsule contains:\n" + line)
            let proposal = SemanticProposal(basisQuote: "Each capsule contains:", ingredients: [.init(key: "c", name: name, canonicalID: id, amount: "100", unit: "mg", evidenceIDs: ["text-1"], nameQuote: name, amountQuote: "100 mg")])
            let label = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
            XCTAssertTrue(try HealthPlan.samples(for: product(label)).isEmpty)
        }
    }
    func testUnmappedIngredientsAreRetainedAndMalformedEvidenceIsRejected() {
        let label = parsed("Each capsule contains:\nCoenzyme Q10 100 mg\nLutein 10 mg")
        XCTAssertEqual(label.ingredients.count, 2)
        XCTAssertEqual(label.ingredients.map { $0.mapping.kind }, [.localOnly, .localOnly])
        var doc = OCRDocument(text: Self.english); doc.blocks[1].id = doc.blocks[0].id
        XCTAssertTrue(SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "fakeAI").ingredients.isEmpty)
    }

    func testSharedBilingualAmountIsOneIngredientNotTwoDoses() throws {
        let label = parsed("Each softgel contains:\nFish Oil / Huile de poisson 834 mg\nOmega-3 / Oméga-3 500 mg\nEPA 300 mg\nDHA 200 mg")
        XCTAssertEqual(label.ingredients.count, 4)
        XCTAssertEqual(label.ingredients.first { $0.canonicalID == "fishOil" }?.value, 834)
        XCTAssertEqual(try HealthPlan.samples(for: product(label)).first?.value, 500)
    }

    func testChineseOCRLostWhitespaceAndMisreadHeadingRemainSafe() throws {
        let label = parsed("每粒含有：\n鱼油834毫克\n欧米伽3500毫克\nEPA 300毫克\nDHA200毫克\n姜黄提取物20毫克（50:1）\n相当于干燥草本1,000毫克")
        XCTAssertEqual(label.ingredients.first { $0.canonicalID == "fishOil" }?.value, 834)
        XCTAssertEqual(try HealthPlan.samples(for: product(label)).first?.value, 500)
        XCTAssertEqual(label.ingredients.first { $0.canonicalID == "dha" }?.value, 200)
        let damaged = parsed("母粒含有：\n鱼油834毫克\n欧米伽3500毫克")
        XCTAssertTrue(try HealthPlan.samples(for: product(damaged)).isEmpty)
        XCTAssertFalse(damaged.warnings.isEmpty)
    }

    func testVolumeCanonicalUnitOverflowIsRejectedBeforeExternalWrite() {
        var p = Product(name: "Synthetic overflow", serving: "1 serving", confirmedAt: Date())
        p.ingredients = [Ingredient(name: "Water", value: 1e307, unit: "L")]
        XCTAssertThrowsError(try IntakeEvent(product: p, servings: 1))
    }

    func testModelOmittedNumericFieldsAreCompletedOnlyFromPrintedAssociatedQuantity() throws {
        let doc = OCRDocument(text: "Each softgel contains:\nFish Oil 834 mg\nOmega-3 500 mg\nEquivalent to dried herb 1,000 mg")
        let proposal = SemanticProposal(basisQuote: "Each softgel contains:", ingredients: [
            .init(key: "f", name: "Fish Oil", unit: "mg", evidenceIDs: ["text-1"], nameQuote: "Fish Oil", amountQuote: "834"),
            .init(key: "o", name: "Omega-3", unit: "mg", parentKey: "f", evidenceIDs: ["text-2"], nameQuote: "Omega-3", amountQuote: "500"),
            .init(key: "e", name: "Equivalent to dried herb", unit: "mg", relation: "equivalent", evidenceIDs: ["text-3"], nameQuote: "Equivalent to dried herb", amountQuote: "1000")])
        let label = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
        XCTAssertEqual(label.ingredients.map(\.value), [834, 500, 1000])
        XCTAssertEqual(try HealthPlan.samples(for: product(label)).first?.value, 500)
        var conflicting = proposal; conflicting.ingredients[0].amount = "500"
        XCTAssertNil(SemanticValidator.validate(conflicting, document: doc, provider: "fakeAI").ingredients.first?.value)
    }

    func testIndependentGroundingRestoresModelOmissionsWithoutHidingNumericConflicts() throws {
        let doc = OCRDocument(text: Self.english)
        let rules = parsed(Self.english)
        let proposal = SemanticProposal(basisQuote: "Each softgel contains:", ingredients: [.init(key: "o", name: "Omega-3", unit: "mg", evidenceIDs: ["text-3"], nameQuote: "Omega-3", amountQuote: "500")])
        let ai = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
        let merged = SemanticReconciliation.complete(ai, with: rules)
        XCTAssertEqual(merged.ingredients.count, 6)
        XCTAssertEqual(merged.ingredients.first { $0.canonicalID == "omega3" }?.parentID, merged.ingredients.first { $0.canonicalID == "fishOil" }?.id)
        try product(merged).validate()
        XCTAssertEqual(try HealthPlan.samples(for: product(merged)).first?.value, 500)
        XCTAssertTrue(merged.provider.contains("validatedRules"))
        var conflict = ai; conflict.ingredients[0].value = 600
        let rejected = SemanticReconciliation.complete(conflict, with: rules)
        XCTAssertNil(rejected.ingredients.first { $0.canonicalID == "omega3" }?.value)
        XCTAssertTrue(try HealthPlan.samples(for: product(rejected)).isEmpty)
    }

    func testModelNameContainingQuantityAndInventedFormDoNotCreateDuplicateIngredients() throws {
        let doc = OCRDocument(text: Self.english)
        let proposal = SemanticProposal(basisQuote: "Each softgel contains:", ingredients: [
            .init(key: "f", name: "Fish Oil", chemicalForm: "Fish Oil", unit: "mg", evidenceIDs: ["text-2"], nameQuote: "Fish Oil 834 mg", amountQuote: "834"),
            .init(key: "o", name: "Omega-3", chemicalForm: "invented form", unit: "mg", parentKey: "f", evidenceIDs: ["text-3"], nameQuote: "Omega-3 500", amountQuote: "500")])
        let ai = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
        let final = SemanticReconciliation.complete(ai, with: parsed(Self.english))
        XCTAssertEqual(final.ingredients.count, 6)
        XCTAssertEqual(try HealthPlan.samples(for: product(final)).first?.value, 500)
    }

    func testFalseEquivalentRelationshipCannotDuplicateKnownSubcomponents() throws {
        let doc = OCRDocument(text: Self.english)
        var proposal = OfflineSemanticProvider.draft(doc)
        for i in proposal.ingredients.indices where ["epa", "dha"].contains(proposal.ingredients[i].canonicalID) { proposal.ingredients[i].relation = "equivalent" }
        let ai = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
        let result = SemanticReconciliation.complete(ai, with: parsed(Self.english))
        XCTAssertEqual(result.ingredients.count, 6)
        XCTAssertEqual(result.ingredients.first { $0.canonicalID == "epa" }?.relation, .component)
        XCTAssertEqual(try HealthPlan.samples(for: product(result)).first?.value, 500)
    }
    func testUnknownChemicalFormRetainsOriginalEvidence() {
        let doc = OCRDocument(text: "Each capsule contains:\nBotanical X (root extract) 20 mg")
        let proposal = SemanticProposal(basisQuote: "Each capsule contains:", ingredients: [.init(key: "x", name: "Botanical X", chemicalForm: "root extract", amount: "20", unit: "mg", evidenceIDs: ["text-1"], nameQuote: "Botanical X", amountQuote: "20 mg")])
        let result = SemanticValidator.validate(proposal, document: doc, provider: "fakeAI")
        XCTAssertEqual(result.ingredients.first?.chemicalForm, "root extract")
        XCTAssertEqual(result.ingredients.first?.mapping.kind, .localOnly)
    }

}
