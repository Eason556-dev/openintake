import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public struct HydrationProgress: Equatable, Sendable {
    public var milliliters: Double
    public var goal: Double
    public var fraction: Double { min(1, milliliters / goal) }
    public init(events: [IntakeEvent], goal: Double, date: Date = Date(), calendar: Calendar = .current) {
        self.goal = goal.isFinite && goal > 0 ? goal : 2000
        milliliters = events.filter { calendar.isDate($0.date, inSameDayAs: date) && $0.state != .deleted && $0.state != .deletionPending }.reduce(0) { total, event in
            total + ((try? event.healthSamples)?.filter { $0.nutrient == .water }.reduce(0) { $0 + event.canonicalValue(for: $1) } ?? 0)
        }
    }
    public static func product() -> Product {
        var product = Product(name: "饮水", serving: "100 mL", nutrients: [.init(.water, 100, .mL)], confirmedAt: Date())
        // One stable template identity makes the normal duplicate guard work across taps/intents.
        product.id = UUID(uuidString: "BA6F7680-DC92-47EB-BCF2-656B4CAEF098")!
        product.kind = .water; product.labelBasis = .init(kind: .per100mL, evidence: "用户记录饮水毫升数")
        return product
    }
}
public struct SyncSummary: Equatable, Sendable {
    public var synced = 0, pending = 0, local = 0, deleting = 0
    public init(events: [IntakeEvent]) {
        for event in events {
            switch event.state { case .synced: synced += 1; case .pending: pending += 1; case .localOnly: local += 1; case .deletionPending: deleting += 1; case .deleted: break }
        }
    }
    public var needsSync: Bool { pending + deleting > 0 }
}
public enum WaterReminderPlan {
    public static func hours(start: Int, end: Int, interval: Int) throws -> [Int] {
        guard (0...23).contains(start), (0...23).contains(end), start <= end, (1...12).contains(interval) else { throw IntakeError.invalidQuantity }
        return Array(stride(from: start, through: end, by: interval))
    }
}

/// Explicit mass or volume basis. Unknowns are absent; no inferred volume-to-mass conversion.
public enum MealPortionUnit: String, Codable, CaseIterable, Sendable { case g, mL }
public struct MealPortion: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var grams: Double?
    public var per100g: [NutrientAmount]
    public var notes: String
    // Optional additions preserve decoding of existing meal snapshots.
    public var referenceFoodID: String?
    public var referenceOnlyNutrients: [ReferenceOnlyNutrient]?
    public var milliliters: Double?
    public var per100mL: [NutrientAmount]?
    public var portionUnit: MealPortionUnit { per100mL != nil || milliliters != nil ? .mL : .g }
    public var quantity: Double? {
        get { portionUnit == .mL ? milliliters : grams }
        set { if portionUnit == .mL { milliliters = newValue } else { grams = newValue } }
    }
    public var nutrientsPer100: [NutrientAmount] {
        get { portionUnit == .mL ? per100mL ?? [] : per100g }
        set { if portionUnit == .mL { per100mL = newValue } else { per100g = newValue } }
    }
    public mutating func rename(_ value: String) {
        if value != name, referenceFoodID != nil {
            referenceFoodID = nil; referenceOnlyNutrients = nil
            nutrientsPer100.removeAll { $0.origin == .database }
            notes = L10n.tr("名称已修改，请重新选择参考食物或手动填写营养。")
        }
        name = value
    }
    public mutating func changeUnit(to unit: MealPortionUnit) {
        guard unit != portionUnit else { return }
        referenceFoodID = nil; referenceOnlyNutrients = nil
        grams = nil; milliliters = nil; per100g = []; per100mL = unit == .mL ? [] : nil
    }
    public init(name: String, grams: Double? = nil, per100g: [NutrientAmount] = [], notes: String = "", milliliters: Double? = nil, per100mL: [NutrientAmount]? = nil) {
        self.milliliters = milliliters; self.per100mL = per100mL
        self.name = name; self.grams = grams; self.per100g = per100g; self.notes = notes
    }
}
public enum MealValidation {
    /// Structural/plausibility validation cannot establish factual accuracy from a photo.
    public static func validate(_ item: MealPortion) throws {
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(item.nutrientsPer100.map(\.nutrient)).count == item.nutrientsPer100.count else { throw IntakeError.invalidProduct }
        guard !(item.portionUnit == .mL && (item.grams != nil || !item.per100g.isEmpty)) else { throw IntakeError.invalidProduct }
        for amount in item.nutrientsPer100 {
            guard amount.origin == .aiEstimate || amount.origin == .manual || amount.origin == .database || amount.origin == .manualEstimate || amount.origin == .labelOCR,
                  amount.unit.dimension == amount.nutrient.dimension,
                  amount.value.isFinite, amount.value >= 0, (amount.origin != .aiEstimate || amount.value > 0), amount.nutrient != .water else { throw IntakeError.invalidProduct }
            let canonical = amount.value * amount.unit.canonicalMultiplier
            guard canonical.isFinite, canonical >= 0, canonical <= (amount.nutrient == .energyConsumed ? 1000 : 100) else { throw IntakeError.invalidQuantity }
        }
        func value(_ nutrient: Nutrient) -> Double? { item.nutrientsPer100.first { $0.nutrient == nutrient }.map { $0.value * $0.unit.canonicalMultiplier } }
        for (child,parent) in [(Nutrient.sugar,Nutrient.carbohydrates),(.fiber,.carbohydrates),(.fatSaturated,.fatTotal),(.fatMonounsaturated,.fatTotal),(.fatPolyunsaturated,.fatTotal)] {
            if let sub = value(child), let total = value(parent), sub > total + 0.1 { throw IntakeError.invalidHierarchy }
        }
        let macros = item.nutrientsPer100.filter { [.protein, .carbohydrates, .fatTotal].contains($0.nutrient) }.reduce(0.0) { $0 + $1.value * $1.unit.canonicalMultiplier }
        guard item.portionUnit != .g || macros <= 101 else { throw IntakeError.invalidQuantity }
    }
    public static func portionIssues(_ items: [MealPortion]) -> [String] {
        guard !items.isEmpty else { return ["请至少添加一项食物或饮料。"] }
        var issues: [String] = []
        if Set(items.map(\.id)).count != items.count { issues.append("存在重复的餐食条目，请删除重复项。") }
        for (index, item) in items.enumerated() {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = name.isEmpty ? L10n.tr("第 \(index + 1) 项") : name
            if name.isEmpty { issues.append("\(title)：请填写食物或饮料名称。") }
            if item.quantity.map({ $0.isFinite && $0 > 0 && $0 <= 10000 }) != true {
                issues.append("\(title)：请填写大于 0 且不超过 10000 \(item.portionUnit.rawValue) 的实际摄入量。")
            }
            if !name.isEmpty, (try? validate(item)) == nil { issues.append("\(title)：营养值、单位或计量基准无效，请核对每 100 \(item.portionUnit.rawValue) 的含量。") }
        }
        return issues
    }
    public static func submissionIssues(_ items: [MealPortion], confirmed: Bool) -> [String] {
        var issues = portionIssues(items)
        if !items.isEmpty && items.allSatisfy({ $0.nutrientsPer100.isEmpty }) {
            issues.append("本餐尚无可写入 Apple 健康的已知营养值；请补充至少一项，未知值不要填零。")
        }
        if !confirmed { issues.append("请先确认实际摄入量及填写的营养值。") }
        return issues
    }
    public static func product(_ items: [MealPortion], confirmed: Bool, allowLocalOnly: Bool = false) throws -> Product {
        let issues = allowLocalOnly ? portionIssues(items) + (confirmed ? [] : ["请先确认实际摄入量及填写的营养值。"]) : submissionIssues(items, confirmed: confirmed)
        guard issues.isEmpty else { throw MealReviewError.blocked(issues) }
        var totals: [Nutrient: Double] = [:]
        var origins: [Nutrient: DataOrigin] = [:]
        for item in items {
            try validate(item)
            guard let quantity = item.quantity, quantity.isFinite, quantity > 0, quantity <= 10000 else { throw IntakeError.invalidQuantity }
            for amount in item.nutrientsPer100 {
                let value = amount.value * amount.unit.canonicalMultiplier * quantity / 100
                guard value.isFinite else { throw IntakeError.invalidQuantity }
                totals[amount.nutrient, default: 0] += value
                origins[amount.nutrient] = origins[amount.nutrient] == .aiEstimate || amount.origin == .aiEstimate ? .aiEstimate : (origins[amount.nutrient] == .manual || amount.origin == .manual ? .manual : amount.origin)
            }
        }
        // Unknown-only meals are local records, never fabricated HealthKit nutrition.
        guard !totals.isEmpty || allowLocalOnly else { throw IntakeError.invalidProduct }
        let amounts = Nutrient.allCases.compactMap { nutrient -> NutrientAmount? in
            guard let value = totals[nutrient], value.isFinite, value >= 0 else { return nil }
            return .init(nutrient, value, nutrient == .energyConsumed ? .kcal : .g, origin: origins[nutrient] ?? .aiEstimate)
        }
        var product = Product(name: items.map(\.name).joined(separator: "、"), serving: "本次实际摄入", nutrients: amounts, sourceText: "用户核对实际可食用重量或饮用体积及营养值后记录；逐项来源保留在餐食明细；未知营养未纳入总计。", confirmedAt: Date())
        product.kind = .food; product.mealDetails = items
        try product.validate()
        return product
    }
}
