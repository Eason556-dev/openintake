import Foundation

/// All 39 targeted SDK nutrition quantities. Added sugars has no dedicated type;
/// total sugar must never be presented as added sugar. Actual availability is checked by the adapter.
public enum NutritionRegistry {
    public enum Group: String, CaseIterable, Sendable {
        case macros, fats, sugars, vitamins, minerals, other
        public var title: String { switch self { case .macros: "能量与宏量营养"; case .fats: "脂肪酸"; case .sugars: "糖与纤维"; case .vitamins: "维生素"; case .minerals: "矿物质"; case .other: "其他" } }
    }
    public static func group(_ nutrient: Nutrient) -> Group {
        switch nutrient {
        case .energyConsumed, .protein, .carbohydrates, .fatTotal: .macros
        case .fatSaturated, .fatMonounsaturated, .fatPolyunsaturated, .cholesterol: .fats
        case .sugar, .fiber: .sugars
        case .vitaminA, .vitaminB6, .vitaminB12, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin, .niacin, .folate, .biotin, .pantothenicAcid: .vitamins
        case .water, .caffeine: .other
        default: .minerals
        }
    }
    public static func displayUnit(_ nutrient: Nutrient) -> NutritionUnit {
        switch nutrient {
        case .energyConsumed: .kcal
        case .water: .mL
        case .protein, .carbohydrates, .fatTotal, .fatSaturated, .fatMonounsaturated, .fatPolyunsaturated, .sugar, .fiber: .g
        case .vitaminA, .vitaminD, .vitaminK, .vitaminB12, .folate, .biotin, .selenium, .chromium, .molybdenum, .iodine: .mcg
        default: .mg
        }
    }
    public static func converted(_ amount: NutrientAmount, to unit: NutritionUnit) throws -> Double {
        guard amount.value.isFinite, amount.value >= 0, amount.unit.dimension == unit.dimension else { throw IntakeError.invalidQuantity }
        let result = amount.value * amount.unit.canonicalMultiplier / unit.canonicalMultiplier
        guard result.isFinite else { throw IntakeError.invalidQuantity }; return result
    }
    public static func recorded(_ nutrient: Nutrient, events: [IntakeEvent], date: Date, calendar: Calendar = .current) -> Double? {
        var total: Double?
        for event in events where event.state != .deleted && event.state != .deletionPending && calendar.isDate(event.date, inSameDayAs: date) {
            for amount in (try? event.healthSamples) ?? [] where amount.nutrient == nutrient {
                let value = event.canonicalValue(for: amount) / displayUnit(nutrient).canonicalMultiplier
                if value.isFinite && value >= 0 { total = (total ?? 0) + value }
            }
        }
        return total
    }
}

public extension NutritionRegistry {
    struct Entry: Sendable {
        public var internalID: String
        public var healthKitIdentifier: String?
        public var canonicalUnit: NutritionUnit
        /// A supported declaration, not proof of runtime availability or authorization.
        public var writeCandidate: Bool { healthKitIdentifier != nil }
    }
    static var entries: [Entry] {
        Nutrient.allCases.map { .init(internalID: $0.rawValue, healthKitIdentifier: $0.healthKitIdentifier, canonicalUnit: $0 == .energyConsumed ? .kcal : $0 == .water ? .mL : .g) } + [.init(internalID: "addedSugars", healthKitIdentifier: nil, canonicalUnit: .g)]
    }
    static func coverage(_ nutrient: Nutrient, events: [IntakeEvent], date: Date, calendar: Calendar = .current) -> (known: Int, total: Int) {
        var known = 0, total = 0
        for event in events where event.state != .deleted && event.state != .deletionPending && calendar.isDate(event.date, inSameDayAs: date) {
            if nutrient != .water && event.product.kind == .water { continue }
            if let items = event.product.mealDetails, nutrient != .water {
                total += max(1, items.count)
                if event.product.mealOverrides?.contains(where: { $0.nutrient == nutrient }) == true { known += max(1, items.count) }
                else { known += items.filter { $0.nutrientsPer100.contains { $0.nutrient == nutrient } }.count }
            } else {
                total += 1
                if (try? event.healthSamples.contains { $0.nutrient == nutrient }) == true { known += 1 }
            }
        }
        return (known,total)
    }
}
