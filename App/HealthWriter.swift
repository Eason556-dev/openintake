import HealthKit
import UIKit
import Foundation

@MainActor
final class HealthWriter: NutritionHealthStore, NutritionHealthReceiptStore {
    private var receipts: [UUID: [UUID]] = [:]
    func sampleIDs(for eventID: UUID) -> [UUID] { receipts[eventID] ?? [] }
    private let store = HKHealthStore()
    var allowsAuthorizationUI = true
    static func unit(for nutrient: Nutrient) -> HKUnit {
        switch nutrient.dimension { case .mass: .gram(); case .volume: .literUnit(with: .milli); case .energy: .kilocalorie() }
    }
    func type(_ nutrient: Nutrient) throws -> HKQuantityType {
        guard let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: nutrient.healthKitIdentifier)) else { throw IntakeError.invalidProduct }
        return type
    }
    func authorization(for nutrient: Nutrient) -> HKAuthorizationStatus? {
        guard HKHealthStore.isHealthDataAvailable(), let type = try? type(nutrient) else { return nil }
        return store.authorizationStatus(for: type)
    }
    /// Permission-only operation: neither creates events nor saves health samples.
    func requestStatus(_ nutrients: [Nutrient]) async throws -> HKAuthorizationRequestStatus {
        guard HKHealthStore.isHealthDataAvailable() else { throw IntakeError.permission }
        let types = try Set(nutrients.map { try type($0) })
        return try await store.statusForAuthorizationRequest(toShare: types, read: [])
    }
    func requestAccess(_ nutrients: [Nutrient]) async throws {
        guard !nutrients.isEmpty else { return }
        guard HKHealthStore.isHealthDataAvailable() else { throw IntakeError.permission }
        let types = try Set(nutrients.map { try type($0) })
        try await store.requestAuthorization(toShare: types, read: [])
    }
    func authorize(_ nutrients: [Nutrient]) async throws {
        let types = try Set(nutrients.map { try type($0) })
        if !types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) {
            guard allowsAuthorizationUI, UIApplication.shared.applicationState == .active else { throw IntakeError.permission }
            try await requestAccess(nutrients)
        }
        guard types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else { throw IntakeError.permission }
    }
    func write(_ event: IntakeEvent) async throws {
        let samples = try event.healthSamples.map { amount in
            let type = try type(amount.nutrient)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { throw IntakeError.permission }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: Self.unit(for: amount.nutrient), doubleValue: event.canonicalValue(for: amount)), start: event.date, end: event.date,
                metadata: [HKMetadataKeySyncIdentifier: event.syncID(for: amount.nutrient), HKMetadataKeySyncVersion: event.syncVersion,
                    HKMetadataKeyWasUserEntered: true, "org.openintake.product": event.product.id.uuidString,
                    "org.openintake.productName": event.product.name, "org.openintake.entryDevice": event.watchRequest == nil ? "iPhone" : "Apple Watch", "org.openintake.revision": event.product.revision.uuidString, "org.openintake.origin": amount.origin.rawValue,
                    "org.openintake.event": event.id.uuidString,
                    "org.openintake.nutrientCoverage": coverage(event, nutrient: amount.nutrient),
                    "org.openintake.foodReferences": (event.product.mealDetails ?? []).compactMap(\.referenceFoodID).joined(separator: ","),
                    "org.openintake.confirmedAt": event.product.confirmedAt!.timeIntervalSince1970])
        }
        try await store.save(samples)
        // Query only our own exact sync IDs; do not request access to other sources.
        var evidence: [HealthSampleEvidence] = []
        var sampleIDs: [UUID] = []
        for amount in try event.healthSamples {
            for sample in try await ownSamples(event, nutrient: amount.nutrient) {
                sampleIDs.append(sample.uuid)
                evidence.append(.init(nutrient: amount.nutrient,
                    canonicalValue: sample.quantity.doubleValue(for: Self.unit(for: amount.nutrient)),
                    date: sample.startDate,
                    syncID: sample.metadata?[HKMetadataKeySyncIdentifier] as? String ?? "",
                    isOwnSource: sample.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier))
            }
        }
        try HealthVerification.validate(evidence, event: event)
        receipts[event.id] = sampleIDs
    }
    private func coverage(_ event: IntakeEvent, nutrient: Nutrient) -> String {
        guard let items = event.product.mealDetails else { return "provided" }
        if event.product.mealOverrides?.contains(where: { $0.nutrient == nutrient }) == true { return "manual-total" }
        return "\(items.filter { $0.nutrientsPer100.contains { $0.nutrient == nutrient } }.count)/\(items.count)"
    }
    func delete(_ event: IntakeEvent) async throws {
        for amount in try event.healthSamples {
            let quantityType = try type(amount.nutrient)
            guard store.authorizationStatus(for: quantityType) == .sharingAuthorized else { throw IntakeError.permission }
            let predicate = ownPredicate(event, nutrient: amount.nutrient)
            // HealthKit restricts deletion to objects written by this app. No broad Health reads.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.deleteObjects(of: quantityType, predicate: predicate) { success, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: IntakeError.permission) }
                }
            }
            guard try await ownSamples(event, nutrient: amount.nutrient).isEmpty else { throw HealthVerificationError.deletionIncomplete }
        }
    }
    private func ownPredicate(_ event: IntakeEvent, nutrient: Nutrient) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [event.syncID(for: nutrient)]),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
    }
    private func ownSamples(_ event: IntakeEvent, nutrient: Nutrient) async throws -> [HKQuantitySample] {
        let type = try type(nutrient)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: ownPredicate(event, nutrient: nutrient), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.compactMap { $0 as? HKQuantitySample } ?? []) }
            }
            store.execute(query)
        }
    }
}
