import Foundation

/// Conservative same-line extraction. Unsupported, ambiguous and IU values remain in source text.
public enum LabelParser {
    public static func suggestedServing(_ text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            for prefix in ["serving size", "每份用量", "每份"] where line.lowercased().hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: ":： "))
            }
        }
        return ""
    }
    public static func suggestedName(_ text: String) -> String {
        guard let first = text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces),
              !first.lowercased().contains("facts"), !first.lowercased().contains("serving"), first.count < 100,
              parse(first).isEmpty else { return "" }
        return first
    }
    public static func parse(_ text: String) -> [NutrientAmount] {
        let aliases: [(Nutrient, [String])] = [
            (.vitaminA,["vitamin a","维生素a"]),(.vitaminC,["vitamin c","维生素c"]),(.vitaminD,["vitamin d","维生素d"]),
            (.vitaminE,["vitamin e","维生素e"]),(.vitaminK,["vitamin k","维生素k"]),(.vitaminB6,["vitamin b6","维生素b6"]),(.vitaminB12,["vitamin b12","维生素b12"]),
            (.calcium,["calcium","钙"]),(.iron,["iron","铁"]),(.magnesium,["magnesium","镁"]),(.zinc,["zinc","锌"]),(.selenium,["selenium","硒"]),(.iodine,["iodine","碘"]),(.folate,["folate","叶酸"])]
        let regex = try! NSRegularExpression(pattern: #"(?<![\d.,<>≤≥+\-])\b(\d+(?:\.\d+)?)\s*(mcg|µg|μg|mg|g|毫克|微克|克)(?![a-z])"#, options: .caseInsensitive)
        var result: [NutrientAmount] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.lowercased()
            // Never infer ingredient mass from compound mass, %DV, IU or inequalities.
            guard line.range(of: #"\biu\b"#, options: .regularExpression) == nil, !line.contains("国际单位"), !line.contains("<"), !line.contains(">"), !line.contains("≤"), !line.contains("≥") else { continue }
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard matches.count == 1, let match = matches.first,
                  let vr = Range(match.range(at: 1), in: line), let ur = Range(match.range(at: 2), in: line), let value = Double(line[vr]) else { continue }
            guard !line.contains("rae"), !line.contains("dfe") else { continue }
            let candidates = aliases.filter { _, names in names.contains { alias in
                if alias.unicodeScalars.contains(where: { $0.value > 127 }) { return line.hasPrefix(alias) }
                guard line.hasPrefix(alias) else { return false }
                let suffix = line.dropFirst(alias.count).trimmingCharacters(in: .whitespaces)
                return suffix.first?.isNumber == true || suffix.hasPrefix("(") || suffix.hasPrefix(":")
            } }
            guard candidates.count == 1 else { continue }
            let unitText = String(line[ur])
            let unit: MassUnit = ["mg","毫克"].contains(unitText) ? .mg : ["g","克"].contains(unitText) ? .g : .mcg
            result.append(NutrientAmount(candidates[0].0, value, unit, origin: .labelOCR))
        }
        // Two columns / multiple serving bases are ambiguous. Discard repeated nutrient proposals.
        return result.filter { item in result.filter { $0.nutrient == item.nutrient }.count == 1 }
    }
}
