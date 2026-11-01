import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public enum DashboardBuilder {
    public static func build(events: [IntakeEvent], goals: [DashboardMetric: Double], language: String,
                             date: Date = Date(), calendar: Calendar = .current) -> DashboardSnapshot {
        let active = events.filter { calendar.isDate($0.date, inSameDayAs: date) && $0.state != .deleted && $0.state != .deletionPending }
        let mapping: [DashboardMetric: Nutrient] = [.water: .water, .energy: .energyConsumed, .protein: .protein, .sugar: .sugar, .sodium: .sodium]
        let values = DashboardMetric.allCases.map { metric in
            var total: Double?; var estimated = false
            for event in active {
                for amount in (try? event.healthSamples) ?? [] where amount.nutrient == mapping[metric] {
                    let value = event.canonicalValue(for: amount) * (metric == .sodium ? 1000 : 1)
                    guard value.isFinite, value >= 0 else { continue }
                    total = (total ?? 0) + value
                    estimated = estimated || amount.origin == .aiEstimate || amount.origin == .manualEstimate
                }
            }
            let goal = goals[metric].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            return DashboardValue(id: metric, value: total, goal: goal, estimated: estimated)
        }
        let pending = active.filter { $0.state == .pending }.count + events.filter { calendar.isDate($0.date, inSameDayAs: date) && $0.state == .deletionPending }.count
        return DashboardSnapshot(updatedAt: date, calendar: calendar, values: values, pendingCount: pending, language: language)
    }
}
