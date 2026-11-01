import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

public enum Nutrient: String, Codable, CaseIterable, Sendable {
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK, thiamin, riboflavin, niacin, vitaminB6, vitaminB12, folate, biotin, pantothenicAcid
    case fatPolyunsaturated, fatTotal, fatMonounsaturated, fatSaturated
    case caffeine, carbohydrates, chloride, cholesterol, fiber, phosphorus, protein, sugar
    case water, energyConsumed
    case calcium, iron, magnesium, zinc, selenium, copper, manganese, chromium, molybdenum, iodine, potassium, sodium
    public var healthKitIdentifier: String { "HKQuantityTypeIdentifierDietary" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    public var dimension: NutritionDimension { self == .water ? .volume : self == .energyConsumed ? .energy : .mass }
    public var title: String {
        switch self {
        case .vitaminA: "维生素 A"; case .vitaminC: "维生素 C"; case .vitaminD: "维生素 D"
        case .vitaminE: "维生素 E"; case .vitaminK: "维生素 K"; case .vitaminB6: "维生素 B6"; case .vitaminB12: "维生素 B12"
        case .thiamin: "硫胺素"; case .riboflavin: "核黄素"; case .niacin: "烟酸"; case .folate: "叶酸"
        case .biotin: "生物素"; case .pantothenicAcid: "泛酸"; case .calcium: "钙"; case .iron: "铁"
        case .magnesium: "镁"; case .zinc: "锌"; case .selenium: "硒"; case .copper: "铜"; case .manganese: "锰"
        case .chromium: "铬"; case .molybdenum: "钼"; case .iodine: "碘"; case .potassium: "钾"; case .sodium: "钠"
        case .fatPolyunsaturated: "多不饱和脂肪"; case .fatTotal: "总脂肪"
        case .fatMonounsaturated: "单不饱和脂肪"; case .fatSaturated: "饱和脂肪"
        case .caffeine: "咖啡因"; case .carbohydrates: "碳水化合物"; case .chloride: "氯化物"
        case .cholesterol: "胆固醇"; case .fiber: "膳食纤维"; case .phosphorus: "磷"
        case .protein: "蛋白质"; case .sugar: "糖"
        case .water: "饮水"; case .energyConsumed: "膳食能量"
        }
    }
}
public enum NutritionDimension: String, Codable, Sendable { case mass, volume, energy }
public enum NutritionUnit: String, Codable, CaseIterable, Sendable {
    case g, mg, mcg, mL, L, kcal, kJ
    public var dimension: NutritionDimension {
        switch self { case .g, .mg, .mcg: .mass; case .mL, .L: .volume; case .kcal, .kJ: .energy }
    }
    /// Canonical units are g, mL and kcal, respectively. Never mix dimensions.
    public var canonicalMultiplier: Double {
        switch self { case .g, .mL, .kcal: 1; case .mg: 0.001; case .mcg: 0.000001; case .L: 1000; case .kJ: 1 / 4.184 }
    }
    public var grams: Double { precondition(dimension == .mass); return canonicalMultiplier }
    public static func fromLabel(_ unit: String) -> NutritionUnit? {
        switch unit.lowercased() {
        case "g", "克": .g; case "mg", "毫克": .mg; case "mcg", "μg", "µg", "ug", "微克": .mcg
        case "ml", "毫升": .mL; case "l", "升": .L; case "kcal", "千卡": .kcal; case "kj", "千焦": .kJ
        default: nil
        }
    }
}
/// Source compatibility for v0.1; serialized mass-unit strings are unchanged.
public typealias MassUnit = NutritionUnit
public enum DataOrigin: String, Codable, Sendable { case labelOCR, manual, database, aiEstimate, manualEstimate }
public struct NutrientAmount: Codable, Equatable, Sendable, Identifiable {
    public var id: Nutrient { nutrient }
    public var nutrient: Nutrient
    public var value: Double
    public var unit: MassUnit
    public var origin: DataOrigin
    public init(_ nutrient: Nutrient, _ value: Double, _ unit: MassUnit, origin: DataOrigin = .manual) {
        self.nutrient = nutrient; self.value = value; self.unit = unit; self.origin = origin
    }
}
public enum ProductKind: String, Codable, Sendable { case supplement, medication, food, water }
public struct Product: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: ProductKind = .supplement
    /// Nutrients are per label serving, not per capsule.
    public var serving: String
    public var nutrients: [NutrientAmount] // legacy v1 field, retained for existing products/events
    public var ingredients: [Ingredient]?
    public var allowBroadMapping: Bool?
    public var unitsPerServing: Double?
    public var intakeUnitName: String?
    public var parsingWarnings: [String]?
    public var ocrDocument: OCRDocument?
    public var semanticProposal: SemanticProposal?
    public var ruleProposal: SemanticProposal?
    public var labelBasis: LabelBasis?
    public var recommendations: [String]?
    public var parsingProvider: String?
    public var mealDetails: [MealPortion]?
    public var manualNutrition: ManualNutritionTemplate?
    public var aiProposal: String?
    public var sourceText: String
    public var confirmedAt: Date?
    public var revision = UUID()
    public init(name: String, serving: String = "", nutrients: [NutrientAmount] = [], sourceText: String = "", confirmedAt: Date? = nil) {
        self.name = name; self.serving = serving; self.nutrients = nutrients; self.sourceText = sourceText; self.confirmedAt = confirmedAt
    }
    public var displayName: String {
        if kind == .water && id == UUID(uuidString: "BA6F7680-DC92-47EB-BCF2-656B4CAEF098") { return L10n.tr("饮水") }
        if id == UUID(uuidString: "77920D9C-0586-48DF-A55D-EF07DAA31E55") { return L10n.tr("普通食盐（钠估算）") }
        return name
    }
    public var intakeUnitTitle: String { labelBasis?.kind == .per100g ? "g" : labelBasis?.kind == .per100mL ? "mL" : unitsPerServing == nil ? "份" : "粒" }
    public var defaultIntakeQuantity: Double { labelBasis?.kind == .per100g || labelBasis?.kind == .per100mL ? 100 : 1 }
    public func servings(forUnits units: Double) throws -> Double {
        let scale: Double? = labelBasis?.kind == .per100g || labelBasis?.kind == .per100mL ? 100 : unitsPerServing ?? 1
        guard let basis = scale, basis.isFinite, basis > 0, units.isFinite, units > 0,
              (units / basis).isFinite else { throw IntakeError.invalidQuantity }
        return units / basis
    }
    public func validate() throws {
        guard kind != .medication else { throw IntakeError.medication }
        if let manualNutrition {
            try manualNutrition.validate()
            let normalized: [NutrientAmount] = manualNutrition.amounts.map {
                .init($0.nutrient, $0.value * 100 / manualNutrition.referenceQuantity, $0.unit, origin: .manual)
            }
            guard kind == .food, nutrients == normalized,
                  labelBasis?.kind == (manualNutrition.category == .beverage ? .per100mL : .per100g),
                  manualNutrition.amounts.isEmpty || ingredients == nil else { throw IntakeError.invalidProduct }
        }
        if let ingredients {
            guard !ingredients.isEmpty, Set(ingredients.map(\.id)).count == ingredients.count else { throw IntakeError.invalidProduct }
            let byID = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0) })
            for item in ingredients {
                guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !item.unit.isEmpty,
                      item.value.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw IntakeError.invalidProduct }
                if let value = item.value, let unit = item.massUnit, item.relation == .component {
                    let childMass = ingredients.filter { $0.parentID == item.id && $0.relation == .component }.reduce(0.0) { sum, child in
                        sum + (child.value.flatMap { v in child.massUnit.map { v * $0.grams } } ?? 0)
                    }
                    guard childMass <= value * unit.grams + 1e-10 else { throw IntakeError.invalidHierarchy }
                }
                var current: Ingredient? = item; var seen = Set<UUID>()
                while let node = current {
                    guard seen.insert(node.id).inserted else { throw IntakeError.invalidProduct }
                    if let parent = node.parentID {
                        guard byID[parent] != nil else { throw IntakeError.invalidProduct }
                        current = byID[parent]
                    } else { current = nil }
                }
            }
            if let unitsPerServing { guard unitsPerServing.isFinite && unitsPerServing > 0 else { throw IntakeError.invalidProduct } }
            _ = try HealthPlan.samples(for: self)
        }
        let localMeal = kind == .food && ingredients == nil && nutrients.isEmpty && mealDetails.map {
            !$0.isEmpty && $0.allSatisfy { $0.nutrientsPer100.isEmpty } && MealValidation.portionIssues($0).isEmpty
        } == true
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !serving.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              confirmedAt != nil, (!(ingredients?.isEmpty ?? nutrients.isEmpty) || localMeal), Set(nutrients.map(\.nutrient)).count == nutrients.count,
              nutrients.allSatisfy({ $0.value.isFinite && $0.value >= 0 && $0.unit.dimension == $0.nutrient.dimension }) else { throw IntakeError.invalidProduct }
    }
}
public enum SyncState: String, Codable, Sendable { case pending, synced, localOnly, deletionPending, deleted }
public struct IntakeEvent: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var product: Product // immutable snapshot, including revision and provenance
    public var servings: Double
    public var date: Date
    public var state: SyncState = .pending
    public var lastError: String?
    public var healthVerifiedAt: Date?
    public var healthWriteSnapshot: [NutrientAmount]?
    /// Absent in older libraries. Restoration keeps the event identity but advances its sync revision.
    public var healthSyncVersion: Int?
    public var watchRequest: WatchIntakeRequest?
    public var syncVersion: Int { healthSyncVersion ?? 1 }
    public init(product: Product, servings: Double, date: Date = Date()) throws {
        try product.validate()
        guard servings.isFinite && servings > 0, product.nutrients.allSatisfy({ ($0.value * $0.unit.canonicalMultiplier * servings).isFinite }),
              (product.ingredients ?? []).allSatisfy({ $0.amount(forServings: servings)?.isFinite ?? true }) else { throw IntakeError.invalidQuantity }
        let plan = try HealthPlan.samples(for: product)
        guard plan.allSatisfy({ $0.unit.dimension == $0.nutrient.dimension && ($0.value * $0.unit.canonicalMultiplier * servings).isFinite }) else { throw IntakeError.invalidQuantity }
        self.product = product; self.servings = servings; self.date = date
        self.healthWriteSnapshot = plan
    }
    public var healthSamples: [NutrientAmount] { get throws { try healthWriteSnapshot ?? HealthPlan.samples(for: product) } }
    public var consumedQuantity: Double { servings * (product.labelBasis?.kind == .per100g || product.labelBasis?.kind == .per100mL ? 100 : product.unitsPerServing ?? 1) }
    public var consumedUnitCount: Double? { product.unitsPerServing.map { $0 * servings } }
    public func canonicalValue(for amount: NutrientAmount) -> Double { amount.value * amount.unit.canonicalMultiplier * servings }
    public func grams(for amount: NutrientAmount) -> Double { precondition(amount.unit.dimension == .mass); return canonicalValue(for: amount) }
    public func syncID(for nutrient: Nutrient) -> String { "intake.\(id.uuidString).\(nutrient.rawValue)" }
    public func duplicates(_ other: IntakeEvent) -> Bool {
        product.id == other.product.id && servings == other.servings && abs(date.timeIntervalSince(other.date)) < 60 && other.state != .deleted && other.state != .deletionPending
    }
}
public enum IntakeError: LocalizedError {
    case medication, invalidProduct, invalidQuantity, duplicate, busy, permission, missing, ambiguousMapping, invalidHierarchy
    public var errorDescription: String? {
        switch self {
        case .invalidHierarchy: L10n.tr("包含的子成分质量超过了父成分总量，请核对含量、单位与包含关系。等效量不参与相加。")
        case .ambiguousMapping: L10n.tr("多个独立成分映射到同一健康类型，无法确定是否重叠。请核对并合并重复项，或关闭宽泛映射。")
        case .medication: L10n.tr("药品不能写入营养数据，请使用 Apple 健康的用药功能。")
        case .invalidProduct: L10n.tr("请确认名称、每份定义和营养含量；不支持重复营养项。")
        case .invalidQuantity: L10n.tr("份数必须是有限的正数。")
        case .duplicate: L10n.tr("一分钟内已有相同产品及份数的记录，请先检查历史。")
        case .busy: L10n.tr("正在处理，请稍后重试。")
        case .permission: L10n.tr("尚未允许全部相关营养类型写入。请在健康授权中开启后重试。")
        case .missing: L10n.tr("产品不存在，请重新选择。")
        }
    }
}
public struct Library: Codable, Sendable {
    public var schemaVersion = 1
    public var products: [Product] = []
    public var events: [IntakeEvent] = []
    public init() {}
}
