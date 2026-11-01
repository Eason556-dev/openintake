import XCTest
@testable import IntakeCore

final class LabelRecognitionRegressionTests: XCTestCase {
    // Exact failed OCR supplied by the user, including the shared bilingual letter and line breaks.
    static let vitaminC = """
    Each tablet contains/Chaque comprimé
    contient :
    Vitamin/Vitamine C ..
    500 mg
    (Ascorbic acid, Sodium ascorbate/
    acide ascorbique, ascorbate de sodium)
    """
    func recognize(_ text: String) -> Product {
        var session = LabelRecognitionSession(); session.begin(OCRDocument(text: text))
        return session.applying(to: Product(name: "", confirmedAt: Date()))
    }
    func assertVitaminC(_ product: Product, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(product.ingredients?.count, 1, file: file, line: line)
        let ingredient = try XCTUnwrap(product.ingredients?.first, file: file, line: line)
        XCTAssertEqual(ingredient.canonicalID, "vitaminC", file: file, line: line)
        XCTAssertEqual(ingredient.value, 500, file: file, line: line)
        XCTAssertEqual(ingredient.unit, "mg", file: file, line: line)
        XCTAssertEqual(product.unitsPerServing, 1, file: file, line: line)
        XCTAssertEqual(ingredient.mapping.nutrient, .vitaminC, file: file, line: line)
        XCTAssertTrue((ingredient.reviewReasons ?? []).isEmpty, "\(ingredient.reviewReasons ?? [])", file: file, line: line)
        for dose in [1.0, 2] {
            let event = try IntakeEvent(product: product, servings: product.servings(forUnits: dose))
            XCTAssertEqual(try event.healthSamples.count, 1, file: file, line: line)
            XCTAssertEqual(event.canonicalValue(for: try XCTUnwrap(event.healthSamples.first)), dose * 0.5, accuracy: 1e-10, file: file, line: line)
        }
    }
    func testDuplicateVisionParagraphAndTableEvidenceCoalesceWithoutTextLoss() {
        var doc = OCRDocument(blocks: [])
        let box = OCRBox(x:0.1,y:0.7,width:0.4,height:0.04)
        doc.appendEvidence(.init(id:"paragraph",text:"Vitamin/Vitamine C",confidence:0.95,box:box))
        doc.appendEvidence(.init(id:"table",text:"Vitamin/Vitamine C",confidence:0.9,box:box,table:"t",row:0,column:0))
        XCTAssertEqual(doc.blocks.count,1)
        XCTAssertEqual(doc.blocks[0].id,"paragraph")
        XCTAssertEqual(doc.blocks[0].table,"t")
        XCTAssertEqual(doc.blocks[0].confidence,0.9)
        XCTAssertTrue(doc.rawText.contains("Vitamin/Vitamine C"))
        doc.appendEvidence(.init(id:"other-page",page:1,text:"Vitamin/Vitamine C",box:box))
        XCTAssertEqual(doc.blocks.count,2)
    }
    func testT01SingleLine() throws { try assertVitaminC(recognize("Each tablet contains:\nVitamin C 500 mg")) }
    func testT02SharedBilingualSuffixAndOtherVitamins() throws {
        try assertVitaminC(recognize("Each tablet contains:\nVitamin/Vitamine C 500 mg"))
        for (name, id) in [("Vitamin / Vitamine B12", "vitaminB12"), ("Vitamin/Vitamine A", "vitaminA"), ("Vitamin/Vitamina B1", "thiamin")] {
            XCTAssertEqual(IngredientCatalog.resolve(name), id)
            let p = recognize("Each tablet contains:\n\(name) 500 mcg")
            XCTAssertEqual(p.ingredients?.first?.canonicalID, id)
            XCTAssertEqual(p.ingredients?.first?.value, 500)
        }
        XCTAssertNil(IngredientCatalog.resolve("Vitamin/Vitamine Calcium carbonate"))
    }
    func testT03AdjacentPastedLineGrammarNotArbitraryDistance() throws {
        try assertVitaminC(recognize("Each tablet contains:\nVitamin C\n500 mg"))
        let p = recognize("Each tablet contains:\nVitamin C\nZinc\n500 mg")
        XCTAssertNil(p.ingredients?.first { $0.canonicalID == "vitaminC" }?.value)
        let camera = OCRDocument(blocks: [.init(id:"b",text:"Each tablet contains:"),.init(id:"n",text:"Vitamin C"),.init(id:"v",text:"500 mg")],engine:"Vision.VNRecognizeTextRequest")
        XCTAssertNil(SemanticValidator.validate(OfflineSemanticProvider.draft(camera), document: camera, provider: "offlineRules").ingredients.first?.value)
    }
    func testT04ExactRealFailure() throws { try assertVitaminC(recognize(Self.vitaminC)) }
    func testT05ChemicalSourcesAreMetadataAndBilingualDeduplicated() throws {
        let p = recognize(Self.vitaminC)
        XCTAssertEqual(p.ingredients?.first?.chemicalSources?.map(\.canonicalID), ["ascorbicAcid", "sodiumAscorbate"])
        XCTAssertTrue(p.ingredients?.first?.sourceText.contains("acide ascorbique") == true)
        XCTAssertEqual(p.ingredients?.first?.evidenceIDs, ["text-2", "text-3", "text-4", "text-5"])
        XCTAssertTrue(recognize("Each tablet contains:\n(Ascorbic acid / Sodium ascorbate)").ingredients?.isEmpty == true)
    }
    func testT06VitaminD3IU() throws {
        let p = recognize("Each tablet contains:\nVitamin D3 1000 IU")
        XCTAssertEqual(p.ingredients?.first?.value, 1000)
        XCTAssertEqual(p.ingredients?.first?.chemicalForm, "D3")
        XCTAssertEqual(try HealthPlan.samples(for: p).first?.value, 25)
        XCTAssertEqual(try HealthPlan.samples(for: p).first?.unit, .mcg)
    }
    func testT07IndependentMultipleNutrients() throws {
        let p = recognize("Each tablet contains:\nVitamin C 500 mg + Zinc 10 mg")
        let plan = try HealthPlan.samples(for: p)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.first { $0.nutrient == .vitaminC }?.value, 500)
        XCTAssertEqual(plan.first { $0.nutrient == .zinc }?.value, 10)
    }
    func testT08SourcesNeverBecomeAnotherVitaminOrSodiumDose() throws {
        for line in ["Vitamin C 500 mg (Sodium ascorbate)", "Vitamin C (as Ascorbic acid, Sodium ascorbate) 500 mg"] {
            try assertVitaminC(recognize("Each tablet contains:\n" + line))
        }
        XCTAssertTrue(try HealthPlan.samples(for: recognize("Each tablet contains:\nSodium ascorbate 500 mg")).isEmpty)
        XCTAssertTrue(try HealthPlan.samples(for: recognize("Each tablet contains:\nCalcium carbonate 500 mg")).isEmpty)
    }
    func testT09MissingAmountStaysUnknown() {
        let item = recognize("Each tablet contains:\nVitamin C").ingredients?.first
        XCTAssertEqual(item?.canonicalID, "vitaminC"); XCTAssertNil(item?.value); XCTAssertNil(item?.healthAmount)
    }
    func testT10UnknownIngredientNotMapped() throws {
        let p = recognize("Each tablet contains:\nBotanical XYZ 250 mg")
        XCTAssertEqual(p.ingredients?.first?.value, 250)
        XCTAssertNil(p.ingredients?.first?.canonicalID)
        XCTAssertTrue(try HealthPlan.samples(for: p).isEmpty)
    }
    func correctAI() -> SemanticProposal {
        .init(basisQuote: "Each tablet contains/Chaque comprimé", ingredients: [.init(key:"c", name:"Vitamin C", chemicalForm:"Ascorbic acid, Sodium ascorbate", amount:"500",unit:"mg", evidenceIDs:["text-2","text-3","text-4","text-5"],nameQuote:"Vitamin C",amountQuote:"500 mg")])
    }
    func testT11NormalizedAINameGroundedToVerbatimEvidence() throws {
        let doc = OCRDocument(text: Self.vitaminC)
        let checked = SemanticValidator.validate(correctAI(), document: doc, provider: "fakeAI")
        XCTAssertEqual(checked.ingredients.first?.originalName, "Vitamin/Vitamine C")
        XCTAssertEqual(checked.ingredients.first?.value, 500)
        var session = LabelRecognitionSession(); let token = session.begin(doc)
        XCTAssertTrue(session.receive(correctAI(), generation: token))
        try assertVitaminC(session.applying(to: Product(name:"",confirmedAt:Date())))
        var forged = correctAI(); forged.ingredients[0].nameQuote = "Zinc"
        XCTAssertTrue(SemanticValidator.validate(forged, document: doc, provider:"fakeAI").ingredients.isEmpty)
    }
    func testT12RejectedParentDoesNotPromoteSourceOrOrphanDose() throws {
        var ai = correctAI(); ai.ingredients[0].nameQuote = "Invented vitamin"
        ai.ingredients.append(.init(key:"s",name:"(Ascorbic acid, Sodium ascorbate/",parentKey:"c", evidenceIDs:["text-4"],nameQuote:"(Ascorbic acid, Sodium ascorbate/"))
        XCTAssertTrue(SemanticValidator.validate(ai, document: .init(text:Self.vitaminC), provider:"fakeAI").ingredients.isEmpty)
        let doc = OCRDocument(text:"Each softgel contains:\nEPA 300 mg")
        let orphan = SemanticProposal(basisQuote:"Each softgel contains:",ingredients:[.init(key:"e",name:"EPA",amount:"300",unit:"mg",parentKey:"missing",evidenceIDs:["text-1"],nameQuote:"EPA",amountQuote:"300 mg")])
        XCTAssertNil(SemanticValidator.validate(orphan, document:doc, provider:"fakeAI").ingredients.first?.value)
    }
    func testT13RepeatedFinalSnapshotAndRetryAreDeterministic() throws {
        var session = LabelRecognitionSession(); let token = session.begin(.init(text:Self.vitaminC))
        XCTAssertTrue(session.receive(correctAI(),generation:token))
        let a = session.applying(to:Product(name:"",confirmedAt:Date()))
        XCTAssertFalse(session.receive(correctAI(),generation:token))
        let b = session.applying(to:a)
        XCTAssertEqual(a.ingredients,b.ingredients)
        let token2 = session.begin(.init(text:Self.vitaminC)); XCTAssertTrue(session.receive(correctAI(),generation:token2))
        try assertVitaminC(session.applying(to:a))
    }
    func testT14RapidScansCancelAndEmptyResultCannotRetainPreviousIngredients() {
        var session = LabelRecognitionSession(); let old = session.begin(.init(text:Self.vitaminC))
        let product = session.applying(to:Product(name:"",confirmedAt:Date()))
        let fresh = session.begin(.init(text:"Unrecognized package"))
        XCTAssertFalse(session.receive(correctAI(),generation:old))
        XCTAssertTrue(session.applying(to:product).ingredients?.isEmpty == true)
        session.cancel(); XCTAssertFalse(session.receive(correctAI(),generation:fresh))
    }
    func testT15SaveReloadPreservesStructuredDataWithoutIngestion() throws {
        let p = recognize(Self.vitaminC); try p.validate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let repository = LibraryRepository(url:folder.appendingPathComponent("library.json"))
        var library = Library(); library.products = [p]; try repository.save(library)
        let restored = try repository.load()
        XCTAssertEqual(restored.products[0].ingredients,p.ingredients)
        XCTAssertEqual(restored.products[0].ocrDocument,p.ocrDocument)
        XCTAssertTrue(restored.events.isEmpty)
        try assertVitaminC(restored.products[0])
    }
}
