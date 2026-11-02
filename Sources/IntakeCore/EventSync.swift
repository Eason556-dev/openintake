import Foundation

@MainActor public protocol NutritionHealthStore {
    func authorize(_ nutrients: [Nutrient]) async throws
    func write(_ event: IntakeEvent) async throws
    func delete(_ event: IntakeEvent) async throws
}
@MainActor public protocol NutritionHealthReceiptStore {
    func sampleIDs(for eventID: UUID) -> [UUID]
}
@MainActor public enum EventSync {
    /// Caller must persist the pending event/tombstone first, then persist completion.
    public static func perform(_ event: IntakeEvent, using backend: any NutritionHealthStore) async throws {
        switch event.state {
        case .pending:
            try event.product.validate()
            let samples = try event.healthSamples
            let old = event.replacedHealthSamples ?? []
            try IntakeEvent.validateSamples(old)
            guard !samples.isEmpty || !old.isEmpty else { return }
            try await backend.authorize(Array(Set((samples + old).map(\.nutrient))))
            // A cancelled deletion may already have removed only some samples. Reconcile our
            // exact event IDs before restoring, also after a crash or a partial restore failure.
            if event.syncVersion > 1 { try await backend.delete(deletionPlan(event)) }
            if !samples.isEmpty { try await backend.write(event) }
        case .deletionPending:
            _ = try event.healthSamples
            try IntakeEvent.validateSamples(event.replacedHealthSamples ?? [])
            let plan = deletionPlan(event)
            if try !plan.healthSamples.isEmpty { try await backend.delete(plan) }
        case .deleted, .synced, .localOnly: break
        }
    }
    private static func deletionPlan(_ event: IntakeEvent) -> IntakeEvent {
        var plan = event
        var values: [Nutrient:NutrientAmount] = [:]
        for amount in (try? event.healthSamples) ?? [] { values[amount.nutrient] = amount }
        for amount in event.replacedHealthSamples ?? [] { values[amount.nutrient] = amount }
        plan.healthWriteSnapshot = Nutrient.allCases.compactMap { values[$0] }
        return plan
    }
}
