import XCTest
@testable import IntakeCore

final class HealthVerificationTests: XCTestCase {
    func event() throws -> IntakeEvent {
        try IntakeEvent(product: .init(name: "Synthetic", serving: "1", nutrients: [.init(.vitaminC, 500, .mg), .init(.calcium, 250, .mg)], confirmedAt: Date()), servings: 2)
    }
    func evidence(_ event: IntakeEvent) throws -> [HealthSampleEvidence] {
        try event.healthSamples.map { .init(nutrient: $0.nutrient, canonicalValue: event.canonicalValue(for: $0), date: event.date, syncID: event.syncID(for: $0.nutrient), isOwnSource: true) }
    }
    func testCorrectSavedValuesTimeAndSourcePass() throws {
        let e = try event(); try HealthVerification.validate(evidence(e), event: e)
    }
    func testMissingAndDuplicateSamplesCannotBeSuccessful() throws {
        let e = try event(); let found = try evidence(e)
        XCTAssertThrowsError(try HealthVerification.validate([], event: e))
        XCTAssertThrowsError(try HealthVerification.validate([found[0]], event: e))
        XCTAssertThrowsError(try HealthVerification.validate([found[0],found[0]], event: e))
        XCTAssertThrowsError(try HealthVerification.validate(found + [found[0]], event: e))
    }
    func testWrongDoseTimeSourceAndSyncIDFailIndependently() throws {
        let e = try event()
        for field in 0..<5 {
            var found = try evidence(e)
            switch field {
            case 0: found[0].canonicalValue *= 1000
            case 1: found[0].date.addTimeInterval(10)
            case 2: found[0].isOwnSource = false
            case 3: found[0].syncID = "unrelated-event"
            default: found[0].canonicalValue = .nan
            }
            XCTAssertThrowsError(try HealthVerification.validate(found, event: e))
        }
    }
    func testOldEventsDoNotAcquireVerificationByDecoding() throws {
        let e = try event()
        XCTAssertNil(try JSONDecoder().decode(IntakeEvent.self, from: JSONEncoder().encode(e)).healthVerifiedAt)
    }
    func testSugarSodiumMassUnitsAndActualSampleEvidenceRequired() throws {
        let product = try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100,
            amounts: [.init(.sugar, 10, .g), .init(.sodium, 20, .mg)]).product(name: "Synthetic drink")
        let event = try IntakeEvent(product: product, servings: product.servings(forUnits: 330))
        let found = try evidence(event)
        XCTAssertEqual(found.first { $0.nutrient == .sugar }!.canonicalValue, 33, accuracy: 1e-9)
        XCTAssertEqual(found.first { $0.nutrient == .sodium }!.canonicalValue, 0.066, accuracy: 1e-9)
        try HealthVerification.validate(found, event: event)
        XCTAssertThrowsError(try HealthVerification.validate([], event: event))
        XCTAssertThrowsError(try HealthVerification.validate(found.filter { $0.nutrient == .sugar }, event: event))
        var wrongUnits = found
        let index = wrongUnits.firstIndex { $0.nutrient == .sodium }!
        wrongUnits[index].canonicalValue = 66
        XCTAssertThrowsError(try HealthVerification.validate(wrongUnits, event: event))
        XCTAssertEqual(Nutrient.sugar.healthKitIdentifier, "HKQuantityTypeIdentifierDietarySugar")
        XCTAssertEqual(Nutrient.sodium.healthKitIdentifier, "HKQuantityTypeIdentifierDietarySodium")
    }
    func testPerFeatureSyncStatusDoesNotInferHealthSuccessFromLocalTotals() throws {
        let date = Date()
        let product = try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100,
            amounts: [.init(.sugar, 10, .g), .init(.sodium, 20, .mg)]).product(name: "Synthetic drink")
        var event = try IntakeEvent(product: product, servings: 1, date: date)
        func status(_ event: IntakeEvent) -> NutritionSyncStatus { .init(events: [event], nutrients: [.sugar, .sodium], date: date) }
        XCTAssertEqual(status(event).pending, 1); XCTAssertEqual(status(event).verified, 0)
        event.state = .synced
        XCTAssertEqual(status(event).submittedUnverified, 1); XCTAssertEqual(status(event).verified, 0)
        event.healthVerifiedAt = date
        XCTAssertEqual(status(event).verified, 1)
        // Current product edits cannot hide the frozen historical write plan.
        event.product.nutrients = [.init(.iron, 1, .mg)]
        XCTAssertEqual(status(event).verified, 1)
        event.state = .deletionPending
        XCTAssertEqual(status(event).deleting, 1); XCTAssertEqual(status(event).verified, 0)
        event.state = .deleted; XCTAssertEqual(status(event).deleting, 0)
        event.state = .synced; event.date = date.addingTimeInterval(-3 * 86400)
        XCTAssertEqual(status(event).verified, 0)
    }
    @MainActor func testSugarSodiumDeniedPermissionDoesNotWriteAndRetryUsesBothTypes() async throws {
        let product = try ManualNutritionTemplate(category: .beverage, referenceQuantity: 100,
            amounts: [.init(.sugar, 10, .g), .init(.sodium, 20, .mg)]).product(name: "Synthetic drink")
        let event = try IntakeEvent(product: product, servings: 3.3)
        let backend = FakeHealth(); backend.granted = false
        do { try await EventSync.perform(event, using: backend); XCTFail("Permission should be denied") } catch {}
        XCTAssertEqual(backend.writes, 0)
        XCTAssertEqual(Set(backend.authorizedNutrients), [.sugar, .sodium])
        backend.granted = true
        try await EventSync.perform(event, using: backend)
        XCTAssertEqual(backend.samples.count, 2)
        XCTAssertEqual(backend.samples[event.syncID(for: .sodium)]!, 0.066, accuracy: 1e-9)
    }

}
