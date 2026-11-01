import XCTest
@testable import IntakeCore

final class IntakeCoreTests: XCTestCase {
    func product() -> Product { Product(name: "D + Calcium", serving: "2 capsules", nutrients: [NutrientAmount(.vitaminD, 25, .mcg), NutrientAmount(.calcium, 250, .mg)], confirmedAt: Date()) }
    func testMassConversionAndFractionalServings() throws {
        let e = try IntakeEvent(product: product(), servings: 0.5)
        XCTAssertEqual(e.grams(for: e.product.nutrients[0]), 0.0000125, accuracy: 1e-12)
        XCTAssertEqual(e.grams(for: e.product.nutrients[1]), 0.125, accuracy: 1e-12)
    }
    func testUnknownIsAbsentAndScanCannotLogUnconfirmedProduct() throws {
        let values = LabelParser.parse("Vitamin D 25 mcg\nZinc unknown")
        XCTAssertEqual(values.count, 1); XCTAssertFalse(values.contains { $0.nutrient == .zinc })
        XCTAssertThrowsError(try IntakeEvent(product: Product(name: "Draft", serving: "1 capsule", nutrients: values), servings: 1))
    }
    func testRejectMedicationInvalidAndRepeatedValues() {
        var p = product(); p.kind = .medication
        XCTAssertThrowsError(try p.validate())
        p = product(); p.nutrients.append(p.nutrients[0]); XCTAssertThrowsError(try p.validate())
        for bad in [Double.nan, .infinity, -1] {
            p = product(); p.nutrients[0].value = bad; XCTAssertThrowsError(try p.validate())
        }
        for bad in [Double.nan, .infinity, -1, 0] { XCTAssertThrowsError(try IntakeEvent(product: product(), servings: bad)) }
    }
    func testConservativeParser() {
        let values = LabelParser.parse("Vitamin D 25 μg 125%\nCalcium 250 mg\n维生素C 100 毫克\nVitamin A 1000 IU\nIron <2 mg\nZinc 1 mg / 2 mg\nSelenium 1,000 mcg")
        XCTAssertEqual(values.map(\.nutrient), [.vitaminD, .calcium, .vitaminC])
        XCTAssertEqual(values[0].origin, .labelOCR)
        XCTAssertTrue(LabelParser.parse("Vitamin D 25 mcg\nVitamin D 50 mcg").isEmpty)
        XCTAssertTrue(LabelParser.parse("Iron -2 mg\nMagnesium citrate 500 mg\nFolate 600 mcg DFE").isEmpty)
        XCTAssertEqual(LabelParser.suggestedServing("Supplement Facts\nServing Size: 2 capsules"), "2 capsules")
        XCTAssertEqual(LabelParser.suggestedName("Example D\nSupplement Facts"), "Example D")
        XCTAssertTrue(LabelParser.parse("Vitamin B12 5 mcg\nVitamin B6 2 mg").count == 2)
    }
    func testDuplicateWindowAndRevocationStateMachine() throws {
        var lib = Library(); let p = product(); let date = Date(timeIntervalSince1970: 1000)
        let first = try IntakeEvent(product: p, servings: 1, date: date); try lib.enqueue(first)
        XCTAssertThrowsError(try lib.enqueue(IntakeEvent(product: p, servings: 1, date: date.addingTimeInterval(59))))
        try lib.enqueue(IntakeEvent(product: p, servings: 1, date: date.addingTimeInterval(60)))
        lib.completeSync(first.id); XCTAssertEqual(lib.events.last?.state, .synced)
        try lib.revoke(first.id); XCTAssertEqual(lib.events.last?.state, .deletionPending)
        lib.completeSync(first.id); XCTAssertEqual(lib.events.last?.state, .deleted)
        lib.completeSync(first.id); XCTAssertEqual(lib.events.last?.state, .deleted)
    }
    func testEventSnapshotAndStableSyncIdentifiers() throws {
        var p = product(); let e = try IntakeEvent(product: p, servings: 1)
        p.nutrients[0].value = 100; p.revision = UUID()
        XCTAssertEqual(e.product.nutrients[0].value, 25)
        let restored = try JSONDecoder().decode(IntakeEvent.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(e.syncID(for: .vitaminD), restored.syncID(for: .vitaminD))
        XCTAssertNotEqual(e.syncID(for: .vitaminD), e.syncID(for: .calcium))
    }
    func testRepositoryRestoresOutboxAndTombstone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = LibraryRepository(url: directory.appendingPathComponent("library.json"))
        XCTAssertTrue(try repo.load().events.isEmpty)
        var lib = Library(); lib.products = [product()]
        let event = try IntakeEvent(product: lib.products[0], servings: 1); try lib.enqueue(event)
        try repo.save(lib); XCTAssertEqual(try repo.load().events[0].state, .pending)
        try lib.revoke(event.id); try repo.save(lib)
        XCTAssertEqual(try repo.load().events[0].state, .deletionPending)
    }
    func testUnreadableLibraryIsNotAnEmptyLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A directory at the file path is an I/O error, not an absent library.
        let repo = LibraryRepository(url: directory)
        XCTAssertThrowsError(try repo.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }
    func testCorruptionAndFutureSchemaAreNotSilentlyReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = LibraryRepository(url: directory.appendingPathComponent("library.json"))
        var lib = Library(); lib.schemaVersion = 99; try repo.save(lib)
        XCTAssertThrowsError(try repo.load())
        try Data("broken".utf8).write(to: repo.url)
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(try String(contentsOf: repo.url, encoding: .utf8), "broken")
    }
}
