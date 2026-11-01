import Foundation

@MainActor public protocol NutritionHealthStore {
    func authorize(_ nutrients: [Nutrient]) async throws
    func write(_ event: IntakeEvent) async throws
    func delete(_ event: IntakeEvent) async throws
}
@MainActor public enum EventSync {
    /// Caller must persist the pending event/tombstone first, then persist completion.
    public static func perform(_ event: IntakeEvent, using backend: any NutritionHealthStore) async throws {
        switch event.state {
        case .pending:
            try event.product.validate()
            let samples = try event.healthSamples
            guard !samples.isEmpty else { return }
            try await backend.authorize(samples.map(\.nutrient))
            // A cancelled deletion may already have removed only some samples. Reconcile our
            // exact event IDs before restoring, also after a crash or a partial restore failure.
            if event.syncVersion > 1 { try await backend.delete(event) }
            try await backend.write(event)
        case .deletionPending:
            if try !event.healthSamples.isEmpty { try await backend.delete(event) }
        case .deleted, .synced, .localOnly: break
        }
    }
}
