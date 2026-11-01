import Foundation

public struct SupplementDraft: Sendable {
    public var ingredients: [Ingredient]
    public var serving: String
    public var unitsPerServing: Double?
    public var warnings: [String]
}
/// Offline label parser. Preserves unsupported ingredients and unconvertible units;
/// only explicit quantities are parsed. OCR reading order and serving basis require review.
public enum SupplementParser {
    private static let amountPattern = #"(?<![\d.,+\-<>≤≥])((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)\s*(mcg\s*(?:DFE|RAE)|mcg|µg|μg|ug|mg|g|IU|CFU|毫克|微克|克|国际单位)(?![a-z])"#
    private static let namedPattern = #"fish\s*oil|鱼油|omega\s*[-–—]?\s*3(?:\s*fatty\s*acids)?|ω\s*[-–—]?\s*3|欧米伽\s*[-–—]?\s*3|\bEPA(?![a-z])|\bDHA(?![a-z])|\b(?:eicosapentaenoic\s*acid|docosahexaenoic\s*acid)\b|turmeric(?:\s*(?:root|rhizome))?(?:\s*extract)?|姜黄(?:提取物|萃取物)?|equivalent\s*(?:to)?\s*(?:dry|dried)\s*(?:herb|root|rhizome)|(?:相当于|等效于)(?:干燥)?(?:草本|草药|草根)|vitamin\s*(?:B12|B6|[ACDEK])|维生素\s*(?:B12|B6|[ACDEK])|calcium|magnesium|selenium|zinc|iron|folate|iodine|polyunsaturated\s*fat|total\s*fat|多不饱和脂肪|总脂肪|钙|镁|硒|锌|铁|叶酸|碘"#
    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
    private static func captured(_ match: NSTextCheckingResult, _ group: Int, _ text: String) -> String {
        Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
    }
    public static func parse(_ text: String, origin: DataOrigin = .labelOCR) -> SupplementDraft {
        var ingredients: [Ingredient] = []
        var warnings: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let amounts = matches(amountPattern, line)
            let names = matches(namedPattern, line)
            if amounts.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                for nameMatch in names where IngredientMapper.canonical(trimmed) == IngredientMapper.canonical(captured(nameMatch, 0, line)) || trimmed.lowercased().contains("unknown") || trimmed.contains("未知") {
                    let name = displayName(captured(nameMatch, 0, line))
                    ingredients.append(Ingredient(name: name, value: nil, unit: "未标注", sourceText: line, origin: origin))
                    warnings.append("\(name) 缺少可靠含量或单位，仅保留本地。")
                }
                continue
            }
            if names.isEmpty {
                guard let first = amounts.first, let range = Range(first.range, in: line) else { continue }
                let name = String(line[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " :：,，;；-"))
                guard !name.isEmpty else { warnings.append("未能识别成分名称：\(line)"); continue }
                if name.lowercased().contains("serving") || name.contains("每份") { continue }
                let value = Double(captured(first, 1, line).replacingOccurrences(of: ",", with: ""))
                ingredients.append(Ingredient(name: name, value: value, unit: captured(first, 2, line), sourceText: line, origin: origin))
                if amounts.count > 1 { warnings.append("同一行含多个数量，请核对并补全：\(line)") }
                continue
            }
            for (index, match) in names.enumerated() {
                let end = index + 1 < names.count ? names[index + 1].range.location : (line as NSString).length
                let segment = (line as NSString).substring(with: NSRange(location: match.range.location, length: end - match.range.location))
                guard let amount = matches(amountPattern, segment).first else {
                    // Preserve an explicitly named ingredient with missing quantity as unknown.
                    let rawName = captured(match, 0, line)
                    ingredients.append(Ingredient(name: displayName(rawName), value: nil, unit: "mg", sourceText: segment, origin: origin))
                    warnings.append("\(displayName(rawName)) 缺少可靠含量，请核对原始标签。")
                    continue
                }
                let rawName = captured(match, 0, line)
                let valueText = captured(amount, 1, segment).replacingOccurrences(of: ",", with: "")
                let hasInequality = segment.contains("<") || segment.contains(">") || segment.contains("≤") || segment.contains("≥")
                var item = Ingredient(name: displayName(rawName), value: hasInequality ? nil : Double(valueText), unit: captured(amount, 2, segment), sourceText: segment, origin: origin)
                if isEquivalent(rawName) { item.relation = .equivalent }
                if let ratio = matches(#"\b\d+\s*:\s*\d+\b"#, segment).first { item.note = "提取比例 " + captured(ratio, 0, segment) }
                ingredients.append(item)
            }
        }
        let fish = uniqueID("鱼油", ingredients)
        let omega = uniqueID("Omega-3", ingredients)
        let turmeric = uniqueID("姜黄提取物", ingredients)
        for i in ingredients.indices {
            switch ingredients[i].name {
            case "Omega-3": ingredients[i].parentID = fish
            case "EPA", "DHA": ingredients[i].parentID = omega
            default: if ingredients[i].relation == .equivalent { ingredients[i].parentID = turmeric }
            }
        }
        if ingredients.contains(where: { $0.parentID != nil }) {
            warnings.append("已按鱼油 / Omega-3 / EPA、DHA 及草本等效量建立关系；请与包装核对，子成分不与总量相加。")
        }
        let basis = servingBasis(text)
        if basis.1 == nil { warnings.append("未能可靠确定每份包含几粒，请确认每份定义及粒数。") }
        return SupplementDraft(ingredients: ingredients, serving: basis.0, unitsPerServing: basis.1, warnings: warnings)
    }
    private static func uniqueID(_ name: String, _ items: [Ingredient]) -> UUID? {
        let selected = items.filter { $0.name == name }; return selected.count == 1 ? selected[0].id : nil
    }
    private static func isEquivalent(_ name: String) -> Bool {
        let text = name.lowercased(); return text.hasPrefix("equivalent") || text.hasPrefix("相当于") || text.hasPrefix("等效于")
    }
    private static func displayName(_ name: String) -> String {
        let key = IngredientMapper.canonical(name)
        if key == "fishoil" || key == "鱼油" { return "鱼油" }
        if key.hasPrefix("omega3") || key == "ω3" || key == "欧米伽3" { return "Omega-3" }
        if key == "epa" || key == "eicosapentaenoicacid" { return "EPA" }
        if key == "dha" || key == "docosahexaenoicacid" { return "DHA" }
        if key.hasPrefix("turmeric") || key.hasPrefix("姜黄") { return "姜黄提取物" }
        if isEquivalent(name) { return "干燥草本等效量" }
        return IngredientMapper.exactNutrient(name)?.title ?? name
    }
    public static func servingBasis(_ text: String) -> (String, Double?) {
        let pattern = #"(?:serving\s*size\s*:?|每份(?:用量)?\s*[:：]?)\s*(\d+(?:\.\d+)?)\s*(?:softgels?|capsules?|tablets?|粒|片)"#
        if let match = matches(pattern, text).first, let count = Double(captured(match, 1, text)), count > 0 { return ("\(count.formatted()) 粒", count) }
        if !matches(#"each\s*(?:softgel|capsule|tablet)|per\s*(?:softgel|capsule|tablet)|每粒|每片"#, text).isEmpty { return ("1 粒", 1) }
        return (LabelParser.suggestedServing(text), nil)
    }
}
