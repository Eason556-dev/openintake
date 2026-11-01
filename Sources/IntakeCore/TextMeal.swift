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
    private static func segments(_ text: String) -> [String] {
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
