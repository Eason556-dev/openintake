import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public enum IngredientRelation: String, Codable, Sendable { case component, equivalent }
public enum MappingKind: String, Codable, Sendable { case exact, broader, localOnly }
public struct IngredientMapping: Codable, Equatable, Sendable {
    public var kind: MappingKind
    public var nutrient: Nutrient?
    public var explanation: String
    public init(_ kind: MappingKind, _ nutrient: Nutrient? = nil, _ explanation: String) {
        self.kind = kind; self.nutrient = nutrient; self.explanation = explanation
    }
}
public struct Ingredient: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: Double? // nil means unknown, never an inferred zero
    public var unit: String
    public var parentID: UUID?
    public var relation: IngredientRelation = .component
    public var note: String = ""
    public var sourceText: String
    public var canonicalID: String?
    public var originalName: String?
    public var chemicalForm: String?
    public var chemicalSources: [ChemicalSource]?
    public var evidenceIDs: [String]?
    public var reviewReasons: [String]?
    public var labelBasis: LabelBasis?
    public var labelValue: Double?
    public var labelUnit: String?
    public var extractRatio: String?
    public var concentration: String?
    public var origin: DataOrigin
    public init(name: String, value: Double?, unit: String, parentID: UUID? = nil, relation: IngredientRelation = .component, note: String = "", sourceText: String = "", origin: DataOrigin = .labelOCR) {
        self.name = name; self.value = value; self.unit = unit; self.parentID = parentID; self.relation = relation
        self.note = note; self.sourceText = sourceText; self.origin = origin
    }
    public var quantityUnit: NutritionUnit? { NutritionUnit.fromLabel(unit) }
    public var massUnit: MassUnit? { quantityUnit.flatMap { $0.dimension == .mass ? $0 : nil } }
    public func displayName(language: String) -> String { IngredientCatalog.title(canonicalID ?? IngredientCatalog.resolve(name), original: originalName ?? name, language: language) }
    public var healthAmount: NutrientAmount? {
        guard (reviewReasons ?? []).isEmpty, let value, value.isFinite, value >= 0 else { return nil }
        let id = canonicalID ?? IngredientCatalog.resolve(name)
        let nutrient = id == "omega3" ? Nutrient.fatPolyunsaturated : id.flatMap(Nutrient.init(rawValue:)) ?? IngredientMapper.exactNutrient(name)
        guard let nutrient else { return nil }
        if let unit = quantityUnit, unit.dimension == nutrient.dimension { return NutrientAmount(nutrient, value, unit, origin: origin) }
        // Vitamin D only: 1 mcg = 40 IU. No generic IU/DFE/RAE conversion.
        if nutrient == .vitaminD, ["iu", "ui", "国际单位"].contains(unit.lowercased()) { return NutrientAmount(nutrient, value / 40, .mcg, origin: origin) }
        return nil
    }
    public var mapping: IngredientMapping { IngredientMapper.mapping(self) }
    public func amount(forServings servings: Double) -> Double? { value.map { $0 * servings } }
}
public enum IngredientMapper {
    public static func mapping(_ item: Ingredient) -> IngredientMapping {
        guard item.relation != .equivalent else { return .init(.localOnly, nil, "干燥草本等效量不是额外摄入，不写入健康。") }
        guard (item.reviewReasons ?? []).isEmpty else { return .init(.localOnly, nil, L10n.tr("待确认：") + (item.reviewReasons ?? []).map { L10n.diagnostic($0) }.joined(separator: L10n.language == "en" ? "; " : "；")) }
        guard item.healthAmount != nil else { return .init(.localOnly, nil, "含量未知、单位 / 化学形式不适用或没有准确类型；保留本地。DFE、RAE、CFU 及非维生素 D 的 IU 不作通用换算。") }
        let key = item.canonicalID == "omega3" ? "omega3" : canonical(item.name)
        if ["omega3", "omega3fattyacids", "ω3", "欧米伽3"].contains(key) {
            return .init(.broader, .fatPolyunsaturated, "Omega-3 属于多不饱和脂肪；Apple 健康仅记录这一较宽分类，没有 Omega-3 专用字段，也不能代表全部多不饱和脂肪。EPA/DHA 已包含在此总量中，不再次相加。")
        }
        if let nutrient = item.healthAmount?.nutrient {
            return .init(.exact, nutrient, "标签成分与 Apple 健康的“\(L10n.display(nutrient.title))”直接对应；使用该营养素适用的质量、容量或能量单位；维生素 D 的 IU 按专属规则换算。")
        }
        return .init(.localOnly, nil, "Apple 健康没有该成分的准确类型；保留名称、含量与包含关系，不强行写入其他营养项。")
    }
    public static func canonical(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && !"-–—:：()（）".contains($0) }
    }
    public static func exactNutrient(_ name: String) -> Nutrient? {
        if let id = IngredientCatalog.resolve(name), let n = Nutrient(rawValue: id) { return n }
        let key = canonical(name)
        if let n = Nutrient.allCases.first(where: { canonical($0.rawValue) == key || canonical($0.title) == key }) { return n }
        let aliases: [String: Nutrient] = ["vitaminb1": .thiamin, "vitaminb2": .riboflavin, "vitaminb3": .niacin,
            "vitaminb5": .pantothenicAcid, "维生素b1": .thiamin, "维生素b2": .riboflavin,
            "polyunsaturatedfat": .fatPolyunsaturated, "多不饱和脂肪": .fatPolyunsaturated,
            "totalfat": .fatTotal, "总脂肪": .fatTotal,
            "monounsaturatedfat": .fatMonounsaturated, "saturatedfat": .fatSaturated,
            "dietaryfiber": .fiber, "dietaryfibre": .fiber, "fibre": .fiber,
            "sugars": .sugar, "总糖": .sugar]
        return aliases[key]
    }
}

public enum HealthPlan {
    /// Parent totals suppress descendants mapped to the SAME type. Different Apple
    /// nutrition categories (e.g. total fat and PUFA) remain separate samples, never summed.
    /// Unrelated totals for the same type
    /// are rejected, not blindly added. Equivalents and unmapped ingredients never enter the plan.
    public static func samples(for product: Product) throws -> [NutrientAmount] {
        guard let ingredients = product.ingredients else { return product.nutrients }
        guard Set(ingredients.map(\.id)).count == ingredients.count else { throw IntakeError.invalidProduct }
        let candidates = ingredients.filter {
            let mapping = $0.mapping
            return mapping.kind == .exact || (mapping.kind == .broader && product.allowBroadMapping == true)
        }
        let byID = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0) })
        let selectedIDs = Set(candidates.map(\.id))
        let selected = candidates.filter { item in
            var parent = item.parentID
            var seen = Set<UUID>()
            while let id = parent, seen.insert(id).inserted {
                if selectedIDs.contains(id), byID[id]?.mapping.nutrient == item.mapping.nutrient { return false }
                parent = byID[id]?.parentID
            }
            return true
        }
        var result: [NutrientAmount] = []
        for item in selected {
            guard let amount = item.healthAmount else { continue }
            let nutrient = amount.nutrient
            guard !result.contains(where: { $0.nutrient == nutrient }) else { throw IntakeError.ambiguousMapping }
            result.append(amount)
        }
        return result
    }
}

/// Explains a write plan without conflating unsupported types with unapproved mappings.
public enum MappingPresentation {
    public static func needsBroadConsent(_ product: Product) -> Bool {
        product.allowBroadMapping != true && (product.ingredients ?? []).contains { $0.mapping.kind == .broader }
    }
    public static func localReason(_ product: Product) -> String {
        needsBroadConsent(product) ? "已记录本机；Omega-3 可写入多不饱和脂肪，请先在产品中确认宽泛映射。" : "已记录本机；这些成分没有可用的准确健康映射，或含量 / 单位尚待核对。"
    }
    public static func localEventTitle(_ product: Product) -> String {
        needsBroadConsent(product) ? "仅本地（当时未启用宽泛映射）" : "仅本地（无可用准确映射）"
    }
}
