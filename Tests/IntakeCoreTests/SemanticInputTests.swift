import XCTest
@testable import IntakeCore

final class SemanticInputTests: XCTestCase {
    func testBilingualInputPreservesAllEvidenceAndIsSmallerThanVerbosePrompt() throws {
        let doc = OCRDocument(text: SemanticPipelineTests.english + "\n" + SemanticPipelineTests.french)
        let batches = SemanticInput.batches(doc)
        XCTAssertFalse(batches.isEmpty)
        for block in doc.blocks where !block.text.isEmpty {
            XCTAssertTrue(batches.contains { $0.contains(block.id) })
            let lines = batches.flatMap { $0.components(separatedBy: "\n") }
            let found = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }.first { $0["id"] as? String == block.id }
            XCTAssertEqual(found?["text"] as? String, block.text)
        }
        XCTAssertLessThan(batches.joined().count, doc.promptText.count)
    }
    func testBatchBoundaryRetainsNamesAndNumbersAndTablePositions() throws {
        let blocks = (0..<30).map { i in OCRBlock(id: "id-\(i)", text: i % 2 == 0 ? "Vitamin C" : "100 mg", box: .init(x: 0.123456789, y: 0.7, width: 0.2, height: 0.03), table: "table", row: i / 2, column: i % 2) }
        let batches = SemanticInput.batches(.init(blocks: blocks), limit: 600)
        XCTAssertGreaterThan(batches.count, 1)
        for block in blocks { XCTAssertTrue(batches.contains { $0.contains(block.id) }) }
        XCTAssertTrue(batches.allSatisfy { $0.contains("table") && $0.contains("box") })
        for index in 1..<batches.count {
            let previous = batches[index - 1].components(separatedBy: "\n")
            XCTAssertTrue(batches[index].hasPrefix(previous.suffix(2).joined(separator: "\n")))
        }
    }
    func testChunkKeysAreNamespacedAndBilingualGraphValidatedOnce() throws {
        let english = OCRDocument(text: SemanticPipelineTests.english)
        var french = OCRDocument(text: SemanticPipelineTests.french)
        for i in french.blocks.indices { french.blocks[i].id = "fr-\(i)" }
        let full = OCRDocument(blocks: english.blocks + french.blocks)
        let proposal = SemanticInput.join([OfflineSemanticProvider.draft(english), OfflineSemanticProvider.draft(french)])
        XCTAssertEqual(Set(proposal.ingredients.map(\.key)).count, proposal.ingredients.count)
        let label = SemanticValidator.validate(proposal, document: full, provider: "appleFoundationModels")
        XCTAssertEqual(label.ingredients.count, 6)
        let p = SemanticPipelineTests().product(label)
        XCTAssertEqual(try HealthPlan.samples(for: p).map(\.value), [500])
    }
    func testTransitionWordsAndDoseNeverBecomeComponents() {
        let document = OCRDocument(text: SemanticPipelineTests.english + "\n" + SemanticPipelineTests.french + "\nProviding: 500 mg\nDont: 500 mg\nApportant 500 mg")
        let parsed = SemanticValidator.validate(OfflineSemanticProvider.draft(document), document: document, provider: "offlineRules")
        XCTAssertEqual(parsed.ingredients.count, 6)
        XCTAssertFalse(parsed.ingredients.contains { LabelEvidence.isConnector($0.originalName ?? $0.name) || LabelEvidence.isInstruction($0.originalName ?? $0.name) })
    }
    func testConnectorPrefixKeepsRealIngredientButNotStandaloneConnector() {
        let doc = OCRDocument(text: "Each softgel contains:\nFish Oil 834 mg\nFournissant Oméga-3 500 mg\nProviding EPA 300 mg\nDHA 200 mg\nProviding the following 500 mg")
        let result = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "offlineRules")
        XCTAssertEqual(result.ingredients.count, 4)
        XCTAssertEqual(result.ingredients.first { $0.canonicalID == "omega3" }?.value, 500)
        XCTAssertEqual(result.ingredients.first { $0.canonicalID == "epa" }?.value, 300)
    }
    func testSupplementReminderIdentityAndTimeValidation() throws {
        let id = UUID(), plan = SupplementReminder(productID: UUID(), hour: 23, minute: 59)
        try plan.validate()
        let a = SupplementReminder(productID: id, hour: 8, minute: 0)
        let b = SupplementReminder(productID: id, hour: 9, minute: 30)
        XCTAssertEqual(a.identifier, b.identifier)
        XCTAssertNotEqual(a.identifier, plan.identifier)
        XCTAssertEqual(try JSONDecoder().decode(SupplementReminder.self, from: JSONEncoder().encode(a)), a)
        XCTAssertThrowsError(try SupplementReminder(productID: id, hour: 24, minute: 0).validate())
        XCTAssertThrowsError(try SupplementReminder(productID: id, hour: 0, minute: -1).validate())
    }
}
