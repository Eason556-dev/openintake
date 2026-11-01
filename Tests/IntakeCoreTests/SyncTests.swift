import XCTest
@testable import IntakeCore

@MainActor final class FakeHealth: NutritionHealthStore {
    var failWrite = false
    var failDelete = false
    var granted = true
    var samples: [String: Double] = [:]
    var writes = 0
    var authorizations = 0
    var authorizedNutrients: [Nutrient] = []
    func authorize(_ nutrients: [Nutrient]) async throws { authorizations += 1; authorizedNutrients = nutrients; if !granted { throw IntakeError.permission } }
    func write(_ event: IntakeEvent) async throws {
        writes += 1
        // Model a crash/error after a partial external write.
        for amount in try event.healthSamples {
            samples[event.syncID(for: amount.nutrient)] = event.canonicalValue(for: amount)
            if failWrite { throw IntakeError.busy }
        }
    }
    func delete(_ event: IntakeEvent) async throws {
        for amount in try event.healthSamples {
            samples.removeValue(forKey: event.syncID(for: amount.nutrient))
            if failDelete { throw IntakeError.busy }
        }
    }
}
final class SyncTests: XCTestCase {
    @MainActor func testPartialWriteRetryAndPartialDeleteRetry() async throws {
        let p = Product(name: "Test", serving: "1 capsule", nutrients: [NutrientAmount(.vitaminD, 25, .mcg), NutrientAmount(.calcium, 250, .mg)], confirmedAt: Date())
        let event = try IntakeEvent(product: p, servings: 1)
        let backend = FakeHealth(); var lib = Library(); try lib.enqueue(event)
        backend.failWrite = true
        do { try await EventSync.perform(lib.events[0], using: backend); XCTFail("Should fail") } catch {}
        XCTAssertEqual(lib.events[0].state, .pending)
        backend.failWrite = false; try await EventSync.perform(lib.events[0], using: backend); lib.completeSync(event.id)
        XCTAssertEqual(backend.samples.count, 2)
        try lib.revoke(event.id); backend.failDelete = true
        do { try await EventSync.perform(lib.events[0], using: backend); XCTFail("Should fail") } catch {}
        XCTAssertEqual(lib.events[0].state, .deletionPending)
        backend.failDelete = false; try await EventSync.perform(lib.events[0], using: backend); lib.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
        let writes = backend.writes
        try await EventSync.perform(lib.events[0], using: backend)
        XCTAssertEqual(backend.writes, writes)
    }
    @MainActor func testDeniedPermissionDoesNotWrite() async throws {
        let event = try IntakeEvent(product: Product(name: "Test", serving: "1 tablet", nutrients: [NutrientAmount(.iron, 2, .mg)], confirmedAt: Date()), servings: 1)
        let backend = FakeHealth(); backend.granted = false
        do { try await EventSync.perform(event, using: backend); XCTFail("Should fail") } catch {}
        XCTAssertEqual(backend.writes, 0)
    }
    @MainActor func testSemanticJamiesonOutboxSurvivesFailureRelaunchRetryAndUndo() async throws {
        let doc = OCRDocument(text: SemanticPipelineTests.english + "\n" + SemanticPipelineTests.french)
        let label = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "fakeAI")
        var p = Product(name: "Synthetic Jamieson", serving: label.serving, confirmedAt: Date())
        p.ingredients = label.ingredients; p.unitsPerServing = label.unitsPerServing; p.allowBroadMapping = true
        let event = try IntakeEvent(product: p, servings: p.servings(forUnits: 2))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LibraryRepository(url: url)
        var library = Library(); try library.enqueue(event); try repository.save(library)
        let backend = FakeHealth(); backend.failWrite = true
        do { try await EventSync.perform(event, using: backend); XCTFail("Expected partial failure") } catch {}
        library = try repository.load()
        XCTAssertEqual(library.events[0].state, .pending)
        XCTAssertEqual(library.events[0].product.ingredients?.count, 6)
        backend.failWrite = false
        try await EventSync.perform(library.events[0], using: backend)
        library.completeSync(event.id); try repository.save(library)
        XCTAssertEqual(backend.samples, [event.syncID(for: .fatPolyunsaturated): 1])
        try library.revoke(event.id); try repository.save(library)
        library = try repository.load()
        try await EventSync.perform(library.events[0], using: backend)
        library.completeSync(event.id); try repository.save(library)
        XCTAssertEqual(try repository.load().events[0].state, .deleted)
        XCTAssertTrue(backend.samples.isEmpty)
    }

    private func restorationEvent() throws -> IntakeEvent {
        try IntakeEvent(product: Product(name: "Restoration fixture", serving: "1 tablet",
            nutrients: [NutrientAmount(.vitaminC, 500, .mg), NutrientAmount(.zinc, 10, .mg)],
            confirmedAt: Date()), servings: 2, date: Date(timeIntervalSince1970: 1_700_000_000))
    }
    @MainActor func testRestoreDeletedPreservesSnapshotTimeAndIdentity() async throws {
        let event = try restorationEvent(); let backend = FakeHealth()
        var library = Library(); try library.enqueue(event)
        try await EventSync.perform(event, using: backend); library.completeSync(event.id)
        try library.revoke(event.id)
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
        library.events[0].healthVerifiedAt = Date()
        try library.restore(event.id)
        let restored = library.events[0]
        XCTAssertEqual(restored.id, event.id); XCTAssertEqual(restored.date, event.date)
        XCTAssertEqual(restored.servings, 2); XCTAssertEqual(restored.product.revision, event.product.revision)
        XCTAssertEqual(try restored.healthSamples, try event.healthSamples)
        XCTAssertNil(restored.healthVerifiedAt); XCTAssertEqual(restored.syncVersion, 2)
        try await EventSync.perform(restored, using: backend); library.completeSync(event.id)
        XCTAssertEqual(library.events.count, 1); XCTAssertEqual(library.events[0].state, .synced)
        XCTAssertEqual(backend.samples.count, 2)
        XCTAssertEqual(backend.samples[event.syncID(for: .vitaminC)], 1)
        // Restoring an already active row is a no-op, not another revision/event.
        try library.restore(event.id); XCTAssertEqual(library.events[0].syncVersion, 2)
    }
    @MainActor func testCancelPartialDeletionAndRetryPartialRestoration() async throws {
        let event = try restorationEvent(); let backend = FakeHealth()
        var library = Library(); try library.enqueue(event)
        try await EventSync.perform(event, using: backend); library.completeSync(event.id)
        try library.revoke(event.id); backend.failDelete = true
        do { try await EventSync.perform(library.events[0], using: backend); XCTFail() } catch {}
        XCTAssertEqual(backend.samples.count, 1)
        try library.restore(event.id)
        // Cleanup failure must not write an incomplete replacement.
        let writes = backend.writes
        do { try await EventSync.perform(library.events[0], using: backend); XCTFail() } catch {}
        XCTAssertEqual(backend.writes, writes); XCTAssertEqual(library.events[0].state, .pending)
        backend.failDelete = false; backend.failWrite = true
        do { try await EventSync.perform(library.events[0], using: backend); XCTFail() } catch {}
        XCTAssertEqual(backend.samples.count, 1)
        backend.failWrite = false
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertEqual(backend.samples.count, 2)
        try library.revoke(event.id)
        try await EventSync.perform(library.events[0], using: backend); library.completeSync(event.id)
        XCTAssertTrue(backend.samples.isEmpty)
        try library.restore(event.id); XCTAssertEqual(library.events[0].syncVersion, 3)
    }
    @MainActor func testRestorationDeniedPermissionRemainsRetryable() async throws {
        let event = try restorationEvent(); var library = Library(); try library.enqueue(event)
        try library.revoke(event.id); library.completeSync(event.id); try library.restore(event.id)
        let backend = FakeHealth(); backend.granted = false
        do { try await EventSync.perform(library.events[0], using: backend); XCTFail() } catch {}
        XCTAssertEqual(library.events[0].state, .pending); XCTAssertEqual(backend.writes, 0)
        backend.granted = true; try await EventSync.perform(library.events[0], using: backend)
        library.completeSync(event.id); XCTAssertEqual(library.events[0].state, .synced)
    }
    func testRestoreRejectsReplacementDuplicate() throws {
        let original = try restorationEvent(); var library = Library(); try library.enqueue(original)
        try library.revoke(original.id)
        let replacement = try IntakeEvent(product: original.product, servings: original.servings, date: original.date)
        try library.enqueue(replacement)
        XCTAssertThrowsError(try library.restore(original.id))
        XCTAssertEqual(library.events.first(where: { $0.id == original.id })?.state, .deletionPending)
    }
    @MainActor func testLocalOnlyRestoreAndPersistenceCompatibility() async throws {
        var product = Product(name: "Local fixture", serving: "1 capsule", confirmedAt: Date())
        product.ingredients = [Ingredient(name: "Turmeric", value: 20, unit: "mg")]
        let event = try IntakeEvent(product: product, servings: 1)
        var library = Library(); try library.enqueue(event)
        try library.revoke(event.id); library.completeSync(event.id); try library.restore(event.id)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LibraryRepository(url: url); try repository.save(library)
        library = try repository.load(); XCTAssertEqual(library.events[0].syncVersion, 2)
        let backend = FakeHealth(); try await EventSync.perform(library.events[0], using: backend)
        library.completeSync(event.id)
        XCTAssertEqual(library.events[0].state, .localOnly); XCTAssertEqual(backend.authorizations, 0)
        XCTAssertEqual(backend.writes, 0)
        let old = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(IntakeEvent.self, from: old).syncVersion, 1)
    }

}
