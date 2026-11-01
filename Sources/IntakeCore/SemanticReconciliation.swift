import Foundation

/// Both inputs have passed the independent validator. Rule evidence can fill model
/// omissions or rejected fields; a conflicting verified number is NEVER silently replaced.
public enum SemanticReconciliation {
    public static func complete(_ ai: ValidatedLabel, with rules: ValidatedLabel) -> ValidatedLabel {
        func identity(_ item: Ingredient) -> String {
            (item.canonicalID ?? "raw:" + IngredientCatalog.normalized(item.originalName ?? item.name)) + "|" + (item.chemicalForm ?? "") + "|" + item.relation.rawValue
        }
        var result = ai
        var selected = ai.ingredients
        var supplemented = false
        for rule in rules.ingredients {
            if let i = selected.firstIndex(where: { identity($0) == identity(rule) }) {
                let candidate = selected[i]
                if (candidate.reviewReasons ?? []).isEmpty, (rule.reviewReasons ?? []).isEmpty,
                   let av = candidate.value, let bv = rule.value {
                    let au = candidate.quantityUnit, bu = rule.quantityUnit
                    let equal = au != nil && bu != nil && au?.dimension == bu?.dimension
                        ? abs(av * au!.canonicalMultiplier - bv * bu!.canonicalMultiplier) < 1e-10
                        : av == bv && candidate.unit == rule.unit
                    if equal {
                        if candidate.parentID == nil, rule.parentID != nil { selected[i].parentID = rule.parentID; supplemented = true }
                        if candidate.extractRatio == nil, rule.extractRatio != nil { selected[i].extractRatio = rule.extractRatio; selected[i].note = rule.note; supplemented = true }
                    }
                    if !equal {
                        selected[i].value = nil
                        selected[i].reviewReasons = ["AI 与独立原文规则的有效数量冲突，必须人工确认。"]
                    }
                } else if !(candidate.reviewReasons ?? []).isEmpty && (rule.reviewReasons ?? []).isEmpty && rule.value != nil {
                    selected[i] = rule; supplemented = true
                }
            } else { selected.append(rule); supplemented = true }
        }
        // Rebind parent references when an AI row was replaced by an independently grounded row.
        let originals = ai.ingredients + rules.ingredients
        for i in selected.indices {
            guard let oldParent = selected[i].parentID, !selected.contains(where: { $0.id == oldParent }) else { continue }
            if let original = originals.first(where: { $0.id == oldParent }),
               let replacement = selected.first(where: { identity($0) == identity(original) }) {
                selected[i].parentID = replacement.id
            } else {
                selected[i].parentID = nil
                selected[i].reviewReasons = (selected[i].reviewReasons ?? []) + ["原父成分未验证，关系需确认。"]
            }
        }
        if selected.isEmpty { return rules }
        result.ingredients = selected
        if ai.basis.kind == .unknown && rules.basis.kind != .unknown { result.basis = rules.basis; supplemented = true }
        result.recommendations = Array(Set(ai.recommendations + rules.recommendations)).sorted()
        result.warnings += rules.warnings.filter { !$0.hasPrefix("端侧 AI 未使用") }
        if supplemented {
            result.provider = ai.provider + "+validatedRules"
            result.warnings.append("部分 AI 字段缺失或未通过验证，已用独立原文规则结果补全；原始 AI 草稿仍保留，补全部分标为标签来源。")
        }
        return result
    }
}
