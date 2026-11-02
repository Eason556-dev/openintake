import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public struct TextFoodProposal: Sendable {
    public var nameQuote: String
    public var sourceQuote: String
    public var quantityQuote: String
    public var estimates: [NutrientAmount]
    public var notes: String
    public var nutrientBasis: MealPortionUnit
    public init(nameQuote: String, sourceQuote: String, quantityQuote: String = "", estimates: [NutrientAmount] = [], notes: String = "", nutrientBasis: MealPortionUnit = .g) {
        self.nameQuote = nameQuote; self.sourceQuote = sourceQuote; self.quantityQuote = quantityQuote; self.estimates = estimates; self.notes = notes; self.nutrientBasis = nutrientBasis
    }
}
public struct TextMealDraft: Sendable {
    public var items: [MealPortion]
    public var warnings: [String]
}
public enum TextMealValidation {
    public static func validateInput(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000 else { throw TextMealError.invalidInput }
    }
    public static func build(_ rows: [TextFoodProposal], source: String) throws -> TextMealDraft {
        try validateInput(source)
        guard rows.count <= 30 else { throw TextMealError.invalidInput }
        var items: [MealPortion] = []; var warnings: [String] = []; var used: [String: Int] = [:]; var coveredSource = source
        for row in rows {
            let name = row.nameQuote.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = row.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !evidence.isEmpty, source.contains(evidence), evidence.contains(name) else {
                warnings.append("缺少原文依据的食物已排除。"); continue
            }
            let occurrences = source.components(separatedBy: evidence).count - 1
            guard used[evidence, default: 0] < occurrences, coveredSource.range(of: evidence) != nil else { warnings.append("重复引用的食物已合并。"); continue }
            used[evidence, default: 0] += 1
            if let range = coveredSource.range(of: evidence) { coveredSource.replaceSubrange(range, with: "") }
            var grams: Double?
            var milliliters: Double?
            let modelQuote = row.quantityQuote.trimmingCharacters(in: .whitespacesAndNewlines)
            let printed = LabelEvidence.quantities(evidence)
            // Missing model quantity cannot erase the sole explicit quantity in its source row.
            let quote = modelQuote.isEmpty && printed.count == 1 ? printed[0].quote : modelQuote
            let quantities = LabelEvidence.quantities(quote)
            if !quote.isEmpty, evidence.contains(quote), LabelEvidence.quantities(evidence).count == 1, quantities.count == 1, let value = quantities.first,
               ["g", "kg", "mL", "L"].contains(value.unit) {
                let actual = value.value * (["kg", "L"].contains(value.unit) ? 1000 : 1)
                if actual.isFinite && actual > 0 && actual <= 10000 {
                    if ["mL", "L"].contains(value.unit) { milliliters = actual } else { grams = actual }
                }
            }
            var amounts: [NutrientAmount] = []
            let duplicated = Dictionary(grouping: row.estimates, by: \.nutrient).filter { $0.value.count > 1 }.keys
            for amount in row.estimates {
                guard amount.origin == .aiEstimate, !duplicated.contains(amount.nutrient),
                      (try? MealValidation.validate(MealPortion(name: name, per100g: [amount]))) != nil else {
                    warnings.append("部分未知、重复或非法营养估算已排除；未作为零写入。"); continue
                }
                amounts.append(amount)
            }
            let isVolume = milliliters != nil || (grams == nil && row.nutrientBasis == .mL)
            if !amounts.isEmpty && row.nutrientBasis != (isVolume ? .mL : .g) {
                amounts = []; warnings.append("饮料营养估算的计量基准不匹配，已保留体积并清空估算；未将毫升换算为克。")
            }
            var item = MealPortion(name: name, grams: grams, per100g: isVolume ? [] : amounts, notes: "",
                                   milliliters: milliliters, per100mL: isVolume ? amounts : nil)
            // Validate the remaining set together: conflicting macro totals invalidate the whole estimate.
            if (try? MealValidation.validate(item)) == nil {
                item.nutrientsPer100 = []; warnings.append("部分营养估算未通过总量验证，已保留食物并清空估算，请手动核对。")
            }
            item.notes = "文字依据：\(evidence)\n\(row.notes)\n" + (item.nutrientsPer100.isEmpty ? "未提供可用营养值，未知项不参与总计。" : "营养为 AI 估算，未知项不参与总计。")
            if item.quantity == nil { warnings.append("未明确标注实际重量或体积的项目需手动校准；不把杯、碗、个猜成克或毫升。") }
            items.append(item)
        }
        // Preserve explicit source segments the model omitted. They are unestimated,
        // editable rows, never silently dropped or assigned invented nutrition.
        for segment in segments(source) {
            guard let range = coveredSource.range(of: segment) else { continue }
            coveredSource.replaceSubrange(range, with: "")
            items.append(explicitItem(segment))
            warnings.append("模型未整理此原文项目，已保留待核对：\(segment)")
        }
        guard items.count <= 30 else { throw TextMealError.invalidInput }
        guard !items.isEmpty else { throw TextMealError.noEvidence }
        return TextMealDraft(items: items, warnings: Array(Set(warnings)).sorted())
    }
    /// No model: retain user text as editable rows with no guessed nutrient values or portion mass.
    public static func fallback(_ text: String) throws -> TextMealDraft {
        try validateInput(text)
        let parts = segments(text)
        guard parts.count <= 30 else { throw TextMealError.invalidInput }
        return TextMealDraft(items: parts.map(explicitItem), warnings: [])
    }
    static func segments(_ text: String) -> [String] {
        // Commas between digits are decimal/thousands separators, not food boundaries.
        let separated = text.replacingOccurrences(of: #"(?<![0-9]),|,(?![0-9])"#, with: "；", options: .regularExpression)
        return separated.components(separatedBy: CharacterSet(charactersIn: "\n、;；，")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private static func explicitItem(_ segment: String) -> MealPortion {
        let quantities = LabelEvidence.quantities(segment)
        var item = MealPortion(name: segment, notes: "文字依据：\(segment)\n未提供可用营养值；请核对本项，未知值不会填零。")
        if quantities.count == 1, let q = quantities.first, ["g", "kg", "mL", "L"].contains(q.unit) {
            let value = q.value * (["kg", "L"].contains(q.unit) ? 1000 : 1)
            let name = segment.replacingOccurrences(of: q.quote, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { item.name = name }
            if ["mL", "L"].contains(q.unit) { item.per100mL = []; item.milliliters = value } else { item.grams = value }
        }
        return item
    }
}
public enum TextMealError: LocalizedError {
    case invalidInput, noEvidence
    public var errorDescription: String? {
        switch self {
        case .invalidInput: L10n.tr("请输入1至4000字的本次实际餐食内容，最多30项；没有记录摄入。")
        case .noEvidence: L10n.tr("模型未返回有原文依据的食物。请重试或手动填写；没有记录摄入。")
        }
    }
}

/// Whole-meal nutrient declarations are not food portions. Only exact known names
/// and explicit dimension-compatible units are accepted; unsupported forms stay unknown.
public enum MealNutritionText {
    public struct Result: Sendable {
        public var foodText: String
        public var nutrients: [NutrientAmount]
    }
    public static func extract(_ text: String) throws -> Result {
        try TextMealValidation.validateInput(text)
        let expression = try NSRegularExpression(pattern: #"(?i)^\s*(?:[•*]\s*)?(.+?)\s*[:：=]?\s*([+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?)\s*(kcal|kj|calories?|mcg|μg|µg|ug|mg|ml|g|l|微克|毫克|毫升|克|升|千卡|大卡|卡路里|千焦(?:耳)?|iu|dfe|rae)\s*\.?\s*$"#)
        var foods: [String] = [], values: [Nutrient: NutrientAmount] = [:]
        for segment in TextMealValidation.segments(text) {
            if ["nutrition","nutrition summary","nutrients","meal details","energy and macronutrients","other dietary components","vitamins","minerals","```","```text","```plaintext","营养信息","营养汇总"].contains(segment.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":："))).lowercased()) { continue }
            let ns = segment as NSString
            if let match = expression.firstMatch(in: segment, range: NSRange(location: 0, length: ns.length)),
               let nutrient = resolve(ns.substring(with: match.range(at: 1))) {
                guard text.range(of: #"(?i)(per\s*(?:100|serving)|每\s*(?:100|份)|/\s*100)"#, options: .regularExpression) == nil else {
                    throw MealReviewError.blocked(["文字中的能量计量基准不明确。请按每100克或每100毫升填写营养表，或单独注明本餐总能量。"])
                }
                let rawUnit = ns.substring(with: match.range(at: 3)).lowercased()
                let unit = ["calorie","calories","大卡","卡路里"].contains(rawUnit) ? NutritionUnit.kcal : rawUnit == "千焦耳" ? .kJ : NutritionUnit.fromLabel(rawUnit)
                guard let unit, unit.dimension == nutrient.dimension,
                      let value = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")), value.isFinite, value >= 0 else {
                    throw MealReviewError.blocked(["营养文字的数值或单位无效，请核对；没有将它作为食物重量或填零。"])
                }
                let amount = NutrientAmount(nutrient, value, unit, origin: .manual)
                if let existing = values[nutrient] {
                    guard sameValue(existing, amount) else { throw MealReviewError.blocked(["同一营养素有多个不同总量，请核对后保留一个数值，避免重复累计。"]) }
                } else { values[nutrient] = amount }
            } else {
                let pair = segment.components(separatedBy: CharacterSet(charactersIn: ":：="))
                if pair.count == 2, resolve(pair[0]) != nil {
                    let unknown = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if ["unknown","未知","—","n/a","na","not provided","未提供"].contains(unknown) { continue }
                    throw MealReviewError.blocked(["营养文字的数值或单位无效，请核对；没有将它作为食物重量或填零。"])
                }
                foods.append(segment)
            }
        }
        return Result(foodText: foods.joined(separator: "\n"), nutrients: Nutrient.allCases.compactMap { values[$0] })
    }
    public static func resolve(_ name: String) -> Nutrient? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：=•*")))
        switch IngredientMapper.canonical(clean) {
        case "dietaryenergy", "energyconsumed", "本餐总能量", "总能量", "总热量": return .energyConsumed
        case "carbs": return .carbohydrates
        case "thiaminb1", "thiamineb1": return .thiamin
        case "riboflavinb2": return .riboflavin
        default:
            let key = IngredientCatalog.normalized(clean)
            return Nutrient.allCases.first {
                IngredientCatalog.normalized($0.rawValue) == key || IngredientCatalog.normalized($0.title) == key ||
                (IngredientCatalog.aliases[$0.rawValue] ?? []).contains { IngredientCatalog.normalized($0) == key }
            }
        }
    }
    public static func sameValue(_ lhs: NutrientAmount, _ rhs: NutrientAmount) -> Bool {
        let a = lhs.value * lhs.unit.canonicalMultiplier, b = rhs.value * rhs.unit.canonicalMultiplier
        return lhs.nutrient == rhs.nutrient && abs(a-b) <= max(1e-10, max(abs(a),abs(b)) * 1e-9)
    }
}
