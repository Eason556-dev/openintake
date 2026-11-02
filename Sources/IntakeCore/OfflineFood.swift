import Foundation
#if SWIFT_PACKAGE
import CSQLite
import IntakeShared
#else
import SQLite3
#endif

public struct ReferenceOnlyNutrient: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var value: Double
    public var unit: String
}
public struct FoodServing: Codable, Equatable, Sendable {
    public var name: String
    public var grams: Double
}
public enum ReferenceFoodState: String, Sendable { case raw, cooked, unspecified }
public struct ReferenceFood: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var nutrients: [NutrientAmount]
    public var servings: [FoodServing]
    public var referenceOnly: [ReferenceOnlyNutrient]
    public var category: String
    public var referenceGrams: Double { 100 }
    public var nutrientCoverage: Set<Nutrient> { Set(nutrients.map(\.nutrient)) }
    public var preparation: String? {
        ["raw","boiled","steamed","roasted","grilled","fried","baked","cooked","dried","dry"].first { name.range(of: "\\b" + $0 + "\\b", options: [.regularExpression,.caseInsensitive]) != nil }
    }
    public var cookingState: ReferenceFoodState {
        if preparation == "raw" { return .raw }
        if let preparation, ["boiled","steamed","roasted","grilled","fried","baked","cooked"].contains(preparation) { return .cooked }
        return .unspecified
    }
    public func displayName(language: String) -> String {
        language.hasPrefix("zh") ? aliases.first(where: { $0.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil }) ?? name : name
    }
    public static let source = "USDA FoodData Central / SR Legacy April 2018"
    public func portion(quantity: Double, unit: FoodQuantityUnit) throws -> MealPortion {
        let grams = try unit.grams(quantity, servings: servings)
        var item = MealPortion(name: name, grams: grams, per100g: nutrients, notes: Self.source + " · FDC " + id)
        item.referenceFoodID = id
        item.referenceOnlyNutrients = referenceOnly
        return item
    }
}
public enum FoodQuantityUnit: Equatable, Sendable {
    case g, kg, oz, mL, L, serving(String), referenceServing(Int)
    public func grams(_ quantity: Double, servings: [FoodServing] = []) throws -> Double {
        guard quantity.isFinite, quantity > 0 else { throw IntakeError.invalidQuantity }
        let factor: Double
        switch self {
        case .g: factor = 1
        case .kg: factor = 1000
        case .oz: factor = 28.349523125
        case .mL, .L: throw FoodReferenceError.massRequired
        case .serving(let name):
            let matches = servings.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            guard let value = matches.first, Set(matches.map(\.grams)).count == 1, value.grams.isFinite, value.grams > 0 else { throw FoodReferenceError.massRequired }
            factor = value.grams
        case .referenceServing(let index):
            guard servings.indices.contains(index), servings[index].grams.isFinite, servings[index].grams > 0 else { throw FoodReferenceError.massRequired }
            factor = servings[index].grams
        }
        let result = quantity * factor
        guard result.isFinite, result <= 10000 else { throw IntakeError.invalidQuantity }
        return result
    }
}
public enum FoodReferenceError: Error { case unavailable, invalidData, massRequired }

/// Read-only SQLite: bounded queries, no network, no full-dataset decoding in memory.
/// Create a connection per operation so no database handle crosses an actor boundary.
public struct FoodReference: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var bundled: FoodReference? {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "FoodReference", withExtension: "sqlite")
        #else
        let url = Bundle.main.url(forResource: "FoodReference", withExtension: "sqlite")
        #endif
        return url.map(FoodReference.init)
    }
    public func search(_ query: String, limit: Int = 30) throws -> [ReferenceFood] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        let exact = query.lowercased()
        let match = terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
        return try read(sql: "SELECT id,name,aliases,nutrients,servings,extras,category FROM food WHERE id IN (SELECT id FROM food_search WHERE food_search MATCH ?) ORDER BY CASE WHEN instr(aliases,?)>0 THEN 0 ELSE 1 END,length(name),id LIMIT ?", parameters: [match, "\"" + exact + "\"", String(max(1,min(100,limit)))])
    }
    public func food(id: String) throws -> ReferenceFood? {
        try read(sql: "SELECT id,name,aliases,nutrients,servings,extras,category FROM food WHERE id=?", parameters: [id]).first
    }
    private func read(sql: String, parameters: [String]) throws -> [ReferenceFood] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { if db != nil { sqlite3_close(db) }; throw FoodReferenceError.unavailable }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw FoodReferenceError.invalidData }
        defer { sqlite3_finalize(statement) }
        for (index, value) in parameters.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw FoodReferenceError.invalidData }
        }
        func string(_ column: Int32) -> String { sqlite3_column_text(statement,column).map { String(cString:$0) } ?? "" }
        let decoder = JSONDecoder()
        var foods: [ReferenceFood] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let aliases = try decoder.decode([String].self, from: Data(string(2).utf8))
            let rows = try decoder.decode([[String]].self, from: Data(string(3).utf8))
            let nutrients = try rows.map { row -> NutrientAmount in
                guard row.count == 3, let nutrient = Nutrient(rawValue: row[0]), let value = Double(row[1]), value.isFinite, value >= 0, let unit = NutritionUnit(rawValue: row[2]), unit.dimension == nutrient.dimension else { throw FoodReferenceError.invalidData }
                return NutrientAmount(nutrient, value, unit, origin: .database)
            }
            let servings = try decoder.decode([FoodServing].self, from: Data(string(4).utf8))
            foods.append(.init(id:string(0),name:string(1),aliases:aliases,nutrients:nutrients,servings:servings,referenceOnly:try decoder.decode([ReferenceOnlyNutrient].self,from:Data(string(5).utf8)),category:string(6)))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw FoodReferenceError.invalidData }
        return foods
    }
}

public struct FoodMatch: Identifiable, Sendable {
    public var id = UUID()
    public var item: MealPortion
    public var candidates: [ReferenceFood]
}
public struct OfflineMealDraft: Sendable {
    public var matches: [FoodMatch]
    public var energy: NutrientAmount?
    public var name: String?
    public var nutrients: [NutrientAmount] = []
}
public enum OfflineMealParser {
    /// Quantities are explicit evidence. Unmatched names remain unchanged and unknown.
    public static func parse(_ text: String, reference: FoodReference? = .bundled) throws -> [FoodMatch] {
        try draft(text, reference: reference).matches
    }
    public static func draft(_ text: String, reference: FoodReference? = .bundled) throws -> OfflineMealDraft {
        try TextMealValidation.validateInput(text)
        let summary = try MealNutritionText.extract(text)
        let normalized = summary.foodText.replacingOccurrences(of: "([0-9]+(?:\\.[0-9]+)?)\\s*(?:ounces?|oz)\\b", with: "$1 oz", options: [.regularExpression, .caseInsensitive])
        let ozPattern = try NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?) oz")
        var converted = normalized
        for match in ozPattern.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).reversed() {
            if let number = Range(match.range(at: 1), in: normalized), let range = Range(match.range, in: converted), let value = Double(normalized[number]) { converted.replaceSubrange(range, with: String(value * 28.349523125) + " g") }
        }
        let separated = converted.replacingOccurrences(of: "\\s+and\\s+", with: "，", options: .regularExpression)
        let segments = TextMealValidation.segments(separated)
        guard segments.count <= 30 else { throw TextMealError.invalidInput }
        var result = OfflineMealDraft(matches: [], energy: summary.nutrients.first { $0.nutrient == .energyConsumed }, name: nil)
        result.nutrients = summary.nutrients.filter { $0.nutrient != .energyConsumed }
        for segment in segments {
            let annotation = try explicitEnergy(segment)
            let source = annotation?.foodText ?? segment
            if let annotation, LabelEvidence.quantities(source).isEmpty {
                guard segments.count == 1 || source.isEmpty || annotation.total else {
                    throw MealReviewError.blocked(["多项餐食中的能量缺少对应份量，请补充重量或体积，或单独注明本餐总能量。"])
                }
                guard result.energy.map({ MealNutritionText.sameValue($0, annotation.amount) }) ?? true else { throw MealReviewError.blocked(["本餐有多条总能量，请保留一个明确数值，避免重复累计。"]) }
                result.energy = annotation.amount
                if !source.isEmpty { result.name = source }
                continue
            }
            if let annotation, annotation.total {
                guard result.energy.map({ MealNutritionText.sameValue($0, annotation.amount) }) ?? true else { throw MealReviewError.blocked(["本餐有多条总能量，请保留一个明确数值，避免重复累计。"]) }
                result.energy = annotation.amount
            }
            let items = try TextMealValidation.fallback(source).items
            for item in items {
                let candidates = try reference?.search(item.name) ?? []
                let exact = candidates.filter { $0.name.caseInsensitiveCompare(item.name) == .orderedSame || $0.aliases.contains(where: { $0.caseInsensitiveCompare(item.name) == .orderedSame }) }
                var resolved = item
                if exact.count == 1, item.portionUnit == .g, let grams = item.quantity {
                    resolved = try exact[0].portion(quantity: grams, unit: .g)
                    resolved.name = item.name
                }
                if let annotation, !annotation.total {
                    guard let quantity = resolved.quantity, quantity.isFinite, quantity > 0 else { throw IntakeError.invalidQuantity }
                    let per100 = annotation.amount.value * annotation.amount.unit.canonicalMultiplier * 100 / quantity
                    resolved.nutrientsPer100.removeAll { $0.nutrient == .energyConsumed }
                    resolved.nutrientsPer100.append(.init(.energyConsumed, per100, .kcal, origin: .manual))
                    resolved.notes += "\n" + segment
                    try MealValidation.validate(resolved)
                }
                result.matches.append(FoodMatch(item: resolved, candidates: resolved.referenceFoodID == nil ? (exact.isEmpty ? candidates : exact) : []))
            }
        }
        return result
    }
    private struct EnergyAnnotation {
        var foodText: String
        var amount: NutrientAmount
        var total: Bool
    }
    private static func explicitEnergy(_ text: String) throws -> EnergyAnnotation? {
        let regex = try NSRegularExpression(pattern: #"(?i)(?<![\d.,-])([0-9]+(?:\.[0-9]+)?)\s*(kcal\b|kj\b|calories?\b|千卡|大卡|卡路里|千焦(?:耳)?)"#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let match = matches.first,
              text.range(of: #"(?i)(per\s*(?:100|serving)|每\s*(?:100|份)|/\s*100)"#, options: .regularExpression) == nil else {
            throw MealReviewError.blocked(["文字中的能量计量基准不明确。请按每100克或每100毫升填写营养表，或单独注明本餐总能量。"])
        }
        let ns = text as NSString
        guard let value = Double(ns.substring(with: match.range(at: 1))), value.isFinite else { throw IntakeError.invalidQuantity }
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        var food = ns.replacingCharacters(in: match.range, with: "")
        let total = text.range(of: #"(?i)(total(?:\s+energy)?|本餐(?:总能量|能量|热量)?|总能量|总热量|合计)"#, options: .regularExpression) != nil
        food = food.replacingOccurrences(of: #"(?i)(?:total\s+energy|total\s+calories?|energy|calories?|本餐总能量|本餐热量|总能量|总热量|能量|热量|合计)\s*[:：=]?\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：=·()（）")))
        return EnergyAnnotation(foodText: food, amount: .init(.energyConsumed, value, unit == "kj" || unit.hasPrefix("千焦") ? .kJ : .kcal, origin: .manual), total: total)

    }
}

public struct MealNutrientSummary: Equatable, Sendable {
    public var nutrient: Nutrient
    public var value: Double?
    public var knownItems: Int
    public var totalItems: Int
    public var complete: Bool { knownItems == totalItems && totalItems > 0 }
}
public enum MealCalculation {
    public static func summarize(_ items: [MealPortion]) throws -> [MealNutrientSummary] {
        guard MealValidation.portionIssues(items).isEmpty else { throw IntakeError.invalidQuantity }
        return Nutrient.allCases.map { nutrient in
            var value: Double?; var count = 0
            for item in items {
                if let amount = item.nutrientsPer100.first(where: { $0.nutrient == nutrient }), let quantity = item.quantity {
                    value = (value ?? 0) + amount.value * amount.unit.canonicalMultiplier * quantity / 100
                    count += 1
                }
            }
            return .init(nutrient: nutrient, value: value, knownItems: count, totalItems: items.count)
        }
    }
    public static func apply(overrides: [NutrientAmount], to calculated: [NutrientAmount]) throws -> [NutrientAmount] {
        guard Set(overrides.map(\.nutrient)).count == overrides.count else { throw IntakeError.invalidProduct }
        var values = Dictionary(uniqueKeysWithValues: calculated.map { ($0.nutrient,$0) })
        for var amount in overrides {
            guard amount.value.isFinite, amount.value >= 0, amount.unit.dimension == amount.nutrient.dimension else { throw IntakeError.invalidQuantity }
            if amount.origin != .manualEstimate { amount.origin = .manual }; values[amount.nutrient] = amount
        }
        return Nutrient.allCases.compactMap { values[$0] }
    }
}

public extension MealCalculation {
    /// A discrepancy calls for review, not inventing a different calorie value.
    static func energyNeedsReview(_ item: MealPortion) -> Bool {
        var values: [Nutrient:Double] = [:]
        for amount in item.nutrientsPer100 { values[amount.nutrient] = amount.value * amount.unit.canonicalMultiplier }
        guard let energy = values[.energyConsumed], let protein = values[.protein], let carbs = values[.carbohydrates], let fat = values[.fatTotal] else { return false }
        let approximate = protein * 4 + carbs * 4 + fat * 9
        return abs(energy-approximate) > max(50, approximate * 0.35)
    }
}
