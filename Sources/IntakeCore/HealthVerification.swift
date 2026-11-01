import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public struct HealthSampleEvidence: Sendable {
    public var nutrient: Nutrient
    public var canonicalValue: Double
    public var date: Date
    public var syncID: String
    public var isOwnSource: Bool
    public init(nutrient: Nutrient, canonicalValue: Double, date: Date, syncID: String, isOwnSource: Bool) {
        self.nutrient = nutrient; self.canonicalValue = canonicalValue; self.date = date; self.syncID = syncID; self.isOwnSource = isOwnSource
    }
}
public enum HealthVerificationError: LocalizedError {
    case mismatch, deletionIncomplete
    public var errorDescription: String? {
        switch self {
        case .mismatch: L10n.tr("Apple 健康保存后核验未通过，尚未标记同步成功。请查看同步状态并重试。")
        case .deletionIncomplete: L10n.tr("Apple 健康中仍能查询到本次样本，撤销尚未完成，请重试。")
        }
    }
}
public enum HealthVerification {
    public static func validate(_ found: [HealthSampleEvidence], event: IntakeEvent) throws {
        let expected = try event.healthSamples
        guard found.count == expected.count else { throw HealthVerificationError.mismatch }
        for amount in expected {
            let matches = found.filter { $0.nutrient == amount.nutrient && $0.syncID == event.syncID(for: amount.nutrient) && $0.isOwnSource }
            let value = event.canonicalValue(for: amount)
            guard matches.count == 1, let sample = matches.first,
                  sample.canonicalValue.isFinite,
                  abs(sample.canonicalValue - value) <= max(1e-10, abs(value) * 1e-9),
                  abs(sample.date.timeIntervalSince(event.date)) <= 0.001 else { throw HealthVerificationError.mismatch }
        }
    }
}

/// Per-feature status must use the frozen write plan and actual post-save verification,
/// never infer external success from local totals or authorization alone.
public struct NutritionSyncStatus: Sendable {
    public var verified = 0
    public var pending = 0
    public var deleting = 0
    public var submittedUnverified = 0
    public init(events: [IntakeEvent], nutrients: Set<Nutrient>, date: Date = Date(), calendar: Calendar = .current) {
        for event in events where calendar.isDate(event.date, inSameDayAs: date) {
            guard let plan = try? event.healthSamples, plan.contains(where: { nutrients.contains($0.nutrient) }) else { continue }
            switch event.state {
            case .synced:
                if event.healthVerifiedAt != nil { verified += 1 } else { submittedUnverified += 1 }
            case .pending: pending += 1
            case .deletionPending: deleting += 1
            case .localOnly, .deleted: break
            }
        }
    }
}
