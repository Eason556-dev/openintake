import Foundation

public enum ManualFoodCategory: String, Codable, CaseIterable, Sendable {
    case beverage, food
    public var title: String { self == .beverage ? "饮料" : "食品／酱料" }
    public var unit: String { self == .beverage ? "mL" : "g" }
}
/// Original user-entered label basis. An absent nutrient is unknown, never zero.
public struct ManualNutritionTemplate: Codable, Sendable {
    public var category: ManualFoodCategory
    public var referenceQuantity: Double
    public var packageQuantity: Double?
    public var amounts: [NutrientAmount]
    public init(category: ManualFoodCategory, referenceQuantity: Double, packageQuantity: Double? = nil, amounts: [NutrientAmount]) {
        self.category = category; self.referenceQuantity = referenceQuantity
        self.packageQuantity = packageQuantity; self.amounts = amounts
    }
    public func validate() throws {
        guard referenceQuantity.isFinite, referenceQuantity > 0,
              packageQuantity.map({ $0.isFinite && $0 > 0 }) ?? true,
              Set(amounts.map(\.nutrient)).count == amounts.count else { throw IntakeError.invalidQuantity }
        for amount in amounts {
            guard amount.nutrient != .water, amount.origin == .manual,
                  amount.unit.dimension == amount.nutrient.dimension,
                  amount.value.isFinite, amount.value >= 0,
                  (amount.value * 100 / referenceQuantity).isFinite else { throw IntakeError.invalidQuantity }
            if category == .food, amount.nutrient.dimension == .mass {
                guard amount.value * amount.unit.canonicalMultiplier <= referenceQuantity + 1e-9 else { throw IntakeError.invalidQuantity }
            }
        }
        func mass(_ nutrient: Nutrient) -> Double? {
            amounts.first { $0.nutrient == nutrient }.map { $0.value * $0.unit.canonicalMultiplier }
        }
        if let sugar = mass(.sugar), let carbs = mass(.carbohydrates), sugar > carbs + 1e-9 { throw IntakeError.invalidQuantity }
        if category == .food {
            let macros = [Nutrient.protein, .carbohydrates, .fatTotal].compactMap { mass($0) }.reduce(0, +)
            guard macros <= referenceQuantity + 1e-9 else { throw IntakeError.invalidQuantity }
        }
    }
    public func product(name: String) throws -> Product {
        try validate()
        var product = Product(name: name, serving: "100 \(category.unit)", nutrients: amounts.map {
            .init($0.nutrient, $0.value * 100 / referenceQuantity, $0.unit, origin: .manual)
        }, sourceText: "用户按标签手动填写：每 \(referenceQuantity) \(category.unit)；空白营养项未知。", confirmedAt: Date())
        product.kind = .food; product.manualNutrition = self
        product.labelBasis = .init(kind: category == .beverage ? .per100mL : .per100g, evidence: product.sourceText)
        if amounts.isEmpty {
            product.ingredients = [Ingredient(name: name, value: nil, unit: "未标注", sourceText: "营养未知，仅记录实际数量", origin: .manual)]
        }
        try product.validate()
        return product
    }
}

/// Sums only this app's active intake ledger, including pending writes. No global Health claim.
public struct DailyNutritionSummary: Sendable {
    public var sugarGrams: Double?
    public var sodiumMilligrams: Double?
    public var estimated = false
    public var unquantifiedRecords = 0
    public init(events: [IntakeEvent], date: Date = Date(), calendar: Calendar = .current) {
        for event in events where calendar.isDate(event.date, inSameDayAs: date) && event.state != .deleted && event.state != .deletionPending {
            let amounts = (try? event.healthSamples) ?? []
            if !amounts.contains(where: { $0.nutrient == .sugar }) || !amounts.contains(where: { $0.nutrient == .sodium }) { unquantifiedRecords += 1 }
            for amount in amounts {
                let value = event.canonicalValue(for: amount)
                if amount.nutrient == .sugar { sugarGrams = (sugarGrams ?? 0) + value }
                if amount.nutrient == .sodium { sodiumMilligrams = (sodiumMilligrams ?? 0) + value * 1000 }
                if [.sugar, .sodium].contains(amount.nutrient), [.aiEstimate, .manualEstimate].contains(amount.origin) { estimated = true }
            }
        }
    }
}
public enum OrdinarySalt {
    public static func consumedGrams(saltGrams: Double, fraction: Double) throws -> Double {
        guard saltGrams.isFinite, saltGrams > 0, fraction.isFinite, fraction > 0, fraction <= 1,
              (saltGrams * fraction).isFinite, saltGrams * fraction > 0 else { throw IntakeError.invalidQuantity }
        return saltGrams * fraction
    }
    /// Ordinary salt only, approximate 400 mg sodium/g. Not a low-sodium-salt formula.
    public static func product(saltGrams: Double, fraction: Double, confirmed: Bool) throws -> Product {
        guard confirmed else { throw IntakeError.invalidProduct }
        _ = try consumedGrams(saltGrams: saltGrams, fraction: fraction)
        var product = Product(name: "普通食盐（钠估算）", serving: "100 g", nutrients: [.init(.sodium, 40000, .mg, origin: .manualEstimate)],
            sourceText: "普通食盐约400mg钠/g；填写食盐\(saltGrams)g，个人食用比例\(fraction)。非低钠盐；用户确认未在餐食钠中重复计入。", confirmedAt: Date())
        product.id = UUID(uuidString: "77920D9C-0586-48DF-A55D-EF07DAA31E55")!
        product.kind = .food; product.labelBasis = .init(kind: .per100g, evidence: product.sourceText)
        try product.validate(); return product
    }
}
