import XCTest
@testable import IntakeCore
import IntakeShared

final class WatchIntakeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_670_400)
    func request(_ ml: Double = 250, id: UUID = UUID()) -> WatchIntakeRequest { .init(id: id, quantity: ml, date: now) }
    func total(_ library: Library) -> Double {
        library.events.filter { $0.state != .deleted && $0.state != .deletionPending }.reduce(0) { total, event in
            total + ((try? event.healthSamples) ?? []).filter { $0.nutrient == .water }.reduce(0) { $0 + event.canonicalValue(for: $1) }
        }
    }
    func testLiveAndBackgroundRetransmissionRecords250OnlyOnce() throws {
        var library = Library(); let r = request()
        XCTAssertEqual(try WatchIntake.apply(r, to: &library, now: now), r.id)
        for _ in 0..<20 { XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now)) }
        XCTAssertEqual(library.events.count, 1); XCTAssertEqual(total(library), 250)
        XCTAssertTrue(library.events[0].syncID(for: .water).contains(r.id.uuidString))
    }
    func testRestartAndLostAcknowledgementDoNotDuplicate() throws {
        var library = Library(); let r = request()
        _ = try WatchIntake.apply(r, to: &library, now: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = LibraryRepository(url: directory.appendingPathComponent("library.json"))
        try repo.save(library); var recovered = try repo.load()
        XCTAssertNil(try WatchIntake.apply(r, to: &recovered, now: now))
        XCTAssertEqual(total(recovered), 250)
    }
    func testLateReplayAfterUndoNeverResurrects() throws {
        var library = Library(); let r = request()
        _ = try WatchIntake.apply(r, to: &library, now: now)
        try library.revoke(r.id)
        XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now)); XCTAssertEqual(total(library), 0)
        library.completeSync(r.id)
        XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now)); XCTAssertEqual(library.events[0].state, .deleted)
        try library.restore(r.id)
        XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now)); XCTAssertEqual(total(library), 250)
    }
    func testConflictingPayloadCannotReuseAnEventID() throws {
        var library = Library(); let r = request()
        _ = try WatchIntake.apply(r, to: &library, now: now)
        XCTAssertThrowsError(try WatchIntake.apply(request(500, id: r.id), to: &library, now: now))
        XCTAssertEqual(total(library), 250)
    }
    func testIndependentPhoneAndWatchRecordsAreNotOverwritten() throws {
        var library = Library()
        let phone = try IntakeEvent(product: HydrationProgress.product(), servings: 1, date: now)
        try library.enqueue(phone)
        _ = try WatchIntake.apply(request(), to: &library, now: now)
        XCTAssertEqual(library.events.count, 2); XCTAssertEqual(total(library), 350)
    }
    func testNearDuplicateTapGetsExplicitRejectionRatherThanSilentMerge() throws {
        var library = Library()
        _ = try WatchIntake.apply(request(), to: &library, now: now)
        XCTAssertThrowsError(try WatchIntake.apply(request(), to: &library, now: now)) { XCTAssertEqual($0 as? WatchIntakeError, .duplicate) }
        XCTAssertEqual(total(library), 250)
    }
    func testTwoSeparateValidEventsAccumulateExactlyOnce() throws {
        var library = Library(); let first = request(); var second = request(); second.date = now.addingTimeInterval(120)
        _ = try WatchIntake.apply(second, to: &library, now: second.date)
        _ = try WatchIntake.apply(first, to: &library, now: second.date)
        _ = try WatchIntake.apply(second, to: &library, now: second.date)
        XCTAssertEqual(total(library), 500)
    }
    func testChangedOrRemovedRecipeRejectedButAcceptedReplaySurvivesEdit() throws {
        var library = Library()
        var product = Product(name: "Test supplement", serving: "1 tablet", nutrients: [.init(.vitaminC, 500, .mg)], confirmedAt: now)
        product.unitsPerServing = 1
        library.products = [product]
        let r = WatchIntakeRequest(productID: product.id, revision: product.revision, unit: product.intakeUnitTitle, quantity: 2, date: now)
        _ = try WatchIntake.apply(r, to: &library, now: now)
        XCTAssertEqual(try library.events[0].healthSamples.first!.value, 500)
        XCTAssertEqual(library.events[0].servings, 2)
        library.products[0].revision = UUID()
        XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now))
        var fresh = r; fresh.id = UUID()
        XCTAssertThrowsError(try WatchIntake.apply(fresh, to: &library, now: now))
        library.products = []
        XCTAssertThrowsError(try WatchIntake.apply(fresh, to: &library, now: now))
        XCTAssertEqual(library.events.count, 1)
    }
    func testInvalidRequestsDoNotMutateLedger() throws {
        for quantity in [0, -1, Double.nan, Double.infinity, 10001] {
            var library = Library()
            XCTAssertThrowsError(try WatchIntake.apply(request(quantity), to: &library, now: now))
            XCTAssertTrue(library.events.isEmpty)
        }
        var library = Library(); var bad = request(); bad.unit = "g"
        XCTAssertThrowsError(try WatchIntake.apply(bad, to: &library, now: now))
        bad = request(); bad.date = now.addingTimeInterval(3600)
        XCTAssertThrowsError(try WatchIntake.apply(bad, to: &library, now: now))
    }
    func testOutboxPersistsUntilDurableAckAndHandlesOutOfOrderReceipts() throws {
        let r = request(); var queue = WatchOutbox()
        queue.add(.init(request: r, name: "Water")); queue.add(.init(request: r, name: "Water"))
        XCTAssertEqual(queue.items.count, 1)
        queue = try JSONDecoder().decode(WatchOutbox.self, from: JSONEncoder().encode(queue))
        queue.receive(.init(id: r.id, outcome: .retry)); XCTAssertEqual(queue.items.count, 1)
        queue.receive(.init(id: UUID(), outcome: .accepted)); XCTAssertEqual(queue.items.count, 1)
        queue.receive(.init(id: r.id, outcome: .accepted)); XCTAssertTrue(queue.items.isEmpty)
        queue.receive(.init(id: r.id, outcome: .rejected, reason: "late")); XCTAssertTrue(queue.items.isEmpty)
    }
    func testRejectedRequestIsVisibleRatherThanLostOrCounted() {
        let r = request(); var queue = WatchOutbox(); queue.add(.init(request: r, name: "Water"))
        queue.receive(.init(id: r.id, outcome: .rejected, reason: "duplicate"))
        XCTAssertEqual(queue.items[0].rejection, "duplicate")
    }
    func testConfiguredFoodAndDrinkUseTheirOriginalQuantityBasis() throws {
        for category in [ManualFoodCategory.beverage, .food] {
            let product = try ManualNutritionTemplate(category: category, referenceQuantity: 100, amounts: [.init(.sugar, 5, .g)]).product(name: "Synthetic food")
            var library = Library(); library.products = [product]
            let r = WatchIntakeRequest(productID: product.id, revision: product.revision, unit: category.unit, quantity: 250, date: now)
            _ = try WatchIntake.apply(r, to: &library, now: now)
            XCTAssertEqual(library.events[0].servings, 2.5)
            XCTAssertEqual(library.events[0].canonicalValue(for: try library.events[0].healthSamples[0]), 12.5)
            XCTAssertFalse(try library.events[0].healthSamples.contains { $0.nutrient == .sodium })
        }
    }
    @MainActor func testWatchSharedHealthOutboxDenialPartialWriteRetryUndoAndRestore() async throws {
        var library = Library(); let r = request()
        _ = try WatchIntake.apply(r, to: &library, now: now)
        let health = FakeHealth(); health.granted = false
        do { try await EventSync.perform(library.events[0], using: health); XCTFail("Expected denial") } catch {}
        XCTAssertEqual(library.events.count, 1); XCTAssertTrue(health.samples.isEmpty)
        health.granted = true; health.failWrite = true
        do { try await EventSync.perform(library.events[0], using: health); XCTFail("Expected partial failure") } catch {}
        XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now))
        health.failWrite = false
        try await EventSync.perform(library.events[0], using: health); library.completeSync(r.id)
        XCTAssertEqual(health.samples.count, 1); XCTAssertEqual(health.samples.values.first, 250)
        try library.revoke(r.id)
        try await EventSync.perform(library.events[0], using: health); library.completeSync(r.id)
        XCTAssertTrue(health.samples.isEmpty)
        XCTAssertNil(try WatchIntake.apply(r, to: &library, now: now))
        try library.restore(r.id)
        try await EventSync.perform(library.events[0], using: health); library.completeSync(r.id)
        XCTAssertEqual(health.samples.count, 1); XCTAssertEqual(health.samples.values.first, 250)
    }

}
