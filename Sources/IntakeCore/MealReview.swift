import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

/// The same value state is used by SwiftUI and regression tests. Only actual content
/// edits invalidate confirmation; rendering/encoding/order of JSON keys cannot do so.
public struct MealReviewState: Sendable {
    public var items: [MealPortion] = [] { didSet { if oldValue != items { accepted = false } } }
    public var text = "" { didSet { if oldValue != text { accepted = false } } }
    public var parsedText = ""
    public var nutrientOverrides: [NutrientAmount] = []
    public var matches: [FoodMatch] = []
    public var suggestedMealName: String?
    public private(set) var parsedEnergyKilocalories: Double?
    private var explicitlyUnknown: Set<Nutrient> = []
    private var placeholderZeroCandidates: Set<Nutrient> = []
    public var pendingPlaceholderZeros: Set<Nutrient> {
        Set(placeholderZeroCandidates.filter { nutrient in nutrientOverrides.contains { $0.nutrient == nutrient && $0.value == 0 } })
    }
    public private(set) var parsedNutrients: [NutrientAmount] = []
    public var energyKilocalories: Double? {
        get { nutrientOverrides.first { $0.nutrient == .energyConsumed }.map { $0.value * $0.unit.canonicalMultiplier } }
        set {
            parsedEnergyKilocalories = nil
            nutrientOverrides.removeAll { $0.nutrient == .energyConsumed }
            if let newValue { nutrientOverrides.append(.init(.energyConsumed, newValue, .kcal, origin: .manual)) }
        }
    }
    public var hasMealEnergy: Bool { energyKilocalories.map { $0.isFinite && $0 >= 0 } == true }
    /// A user-entered whole-meal energy value is independent of missing food weights.
    /// Per-100 nutrient profiles still require quantities; invalid quantities never pass.
    public var recordsEnergyOnly: Bool { recordsProvidedTotals && hasMealEnergy }
    public var recordsProvidedTotals: Bool {
        !nutrientOverrides.isEmpty && items.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.nutrientsPer100.isEmpty &&
            ($0.quantity.map { $0.isFinite && $0 > 0 && $0 <= 10000 } ?? true)
        }
    }
    public private(set) var accepted = false
    public private(set) var analysisID: UUID?
    public private(set) var submitting = false
    public private(set) var submitted = false
    public var busy: Bool { analysisID != nil }
    public var textNeedsReview: Bool { text != parsedText }
    public var canAnalyzePhoto: Bool { items.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public init() {}
    public var confirmationIssues: [String] {
        var issues = recordsProvidedTotals ? [] : MealValidation.portionIssues(items)
        if (try? MealCalculation.apply(overrides: nutrientOverrides, to: [])) == nil { issues.append("营养总量或单位无效，请填写有限且不小于零的数值。") }
        if !pendingPlaceholderZeros.isEmpty { issues.append("完整模板中的零值可能是未知占位，请先确认实际为零或设为未知。") }
        if busy { issues.append("正在整理餐食，请等待完成或停止识别后再确认。") }
        if textNeedsReview { issues.append("文字已修改，请重新整理并核对结果。") }
        if submitting || submitted { issues.append("本餐正在记录或已经记录，请勿重复提交。") }
        return issues
    }
    public var submissionIssues: [String] {
        var issues = confirmationIssues
        for issue in MealValidation.submissionIssues(items, confirmed: accepted) where !issues.contains(issue) { issues.append(issue) }
        return issues
    }
    /// The user's tap on Record is the confirmation. No AI or separate checkbox is required.
    public var recordingIssues: [String] { confirmationIssues }
    public mutating func beginRecording(requestID: UUID) throws -> Product {
        guard recordingIssues.isEmpty else { throw MealReviewError.blocked(recordingIssues) }
        var product: Product
        if recordsProvidedTotals {
            product = Product(name: suggestedMealName ?? (items.isEmpty ? L10n.tr("餐食") : items.map(\.name).joined(separator: "、")), serving: L10n.tr("本次实际摄入"), nutrients: [], confirmedAt: Date())
            product.kind = .food; product.mealDetails = items
        } else { product = try MealValidation.product(items, confirmed: true, allowLocalOnly: true) }
        product.nutrients = try MealCalculation.apply(overrides: nutrientOverrides, to: product.nutrients)
        product.mealOverrides = nutrientOverrides
        product.mealInputText = text
        let supplied = Set(parsedNutrients.map(\.nutrient)).union(parsedEnergyKilocalories == nil ? [] : [.energyConsumed])
        let final = Set(product.nutrients.map(\.nutrient))
        product.mealUnknownNutrients = Nutrient.allCases.filter { !final.contains($0) && (explicitlyUnknown.contains($0) || supplied.contains($0)) }
        product.id = requestID
        submitting = true
        return product
    }
    public mutating func setAccepted(_ value: Bool) {
        accepted = value && confirmationIssues.isEmpty
    }
    public mutating func prepareText(_ source: String) throws {
        accepted = false; cancelAnalysis(); text = source
        let draft = try OfflineMealParser.draft(source)
        matches = draft.matches; items = matches.map(\.item); suggestedMealName = draft.name
        // A source energy total is explicit user input, never a model estimate.
        let previousTextEnergy = parsedEnergyKilocalories
        if let previousTextEnergy, energyKilocalories == previousTextEnergy { energyKilocalories = nil }
        if let energy = draft.energy {
            energyKilocalories = energy.value * energy.unit.canonicalMultiplier
            parsedEnergyKilocalories = energyKilocalories
        } else { parsedEnergyKilocalories = nil }
        for old in parsedNutrients where !draft.nutrients.contains(where: { $0.nutrient == old.nutrient }) {
            nutrientOverrides.removeAll { MealNutritionText.sameValue($0, old) }
        }
        for amount in draft.nutrients {
            let current = nutrientOverrides.first { $0.nutrient == amount.nutrient }
            let previous = parsedNutrients.first { $0.nutrient == amount.nutrient }
            if current == nil || (previous.map { old in current.map { MealNutritionText.sameValue($0, old) } ?? false } ?? false) {
                nutrientOverrides.removeAll { $0.nutrient == amount.nutrient }
                nutrientOverrides.append(amount)
            }
        }
        parsedNutrients = draft.nutrients
        let supplied = draft.nutrients + (draft.energy.map { [$0] } ?? [])
        // The external 39-field schema permits placeholder zeros. Require a decision;
        // a short explicit manual record is not assumed to be an external template.
        let externalSchema = source.range(of: #"(?im)^\s*Meal\s*:"#, options: .regularExpression) != nil && supplied.count >= 30
        placeholderZeroCandidates = externalSchema ? Set(supplied.filter { $0.value == 0 }.map(\.nutrient)) : []
        if externalSchema {
            for index in nutrientOverrides.indices where supplied.contains(where: { MealNutritionText.sameValue($0, nutrientOverrides[index]) }) {
                nutrientOverrides[index].origin = .manualEstimate
            }
        }
        parsedText = source
    }
    public mutating func resolvePlaceholderZero(_ nutrient: Nutrient, knownZero: Bool) {
        placeholderZeroCandidates.remove(nutrient)
        if !knownZero { explicitlyUnknown.insert(nutrient); nutrientOverrides.removeAll { $0.nutrient == nutrient } }
        else if let index = nutrientOverrides.firstIndex(where: { $0.nutrient == nutrient }) { nutrientOverrides[index].origin = .manual }
    }
    public mutating func restoreUnknownNutrients(_ nutrients: [Nutrient]) {
        for nutrient in nutrients { resolvePlaceholderZero(nutrient, knownZero: false) }
    }
    public mutating func discardPlaceholderZeros() {
        for nutrient in pendingPlaceholderZeros { explicitlyUnknown.insert(nutrient); nutrientOverrides.removeAll { $0.nutrient == nutrient } }
        placeholderZeroCandidates.removeAll()
    }
    @discardableResult public mutating func startAnalysis() -> UUID {
        accepted = false
        let token = UUID(); analysisID = token; return token
    }
    public mutating func cancelAnalysis() { analysisID = nil }
    @discardableResult public mutating func finishAnalysis(_ token: UUID, items result: [MealPortion]? = nil) -> Bool {
        guard analysisID == token, !submitting, !submitted else { return false }
        if let result { items = result }
        analysisID = nil
        return true
    }
    public static func validateRequest(_ requestID: UUID, events: [IntakeEvent]) throws {
        guard !events.contains(where: { $0.product.id == requestID }) else {
            throw MealReviewError.blocked(["本餐已经记录，请在最近摄入中查看或重试同步，无需重复提交。"])
        }
    }
    public mutating func beginSubmission(requestID: UUID) throws -> Product {
        let issues = submissionIssues
        guard issues.isEmpty else { throw MealReviewError.blocked(issues) }
        var product = try MealValidation.product(items, confirmed: accepted)
        product.id = requestID
        submitting = true
        return product
    }
    public mutating func finishSubmission(succeeded: Bool) {
        submitting = false; submitted = succeeded
    }
}
public enum MealReviewError: LocalizedError {
    case blocked([String])
    public var errorDescription: String? { switch self { case .blocked(let reasons): reasons.joined(separator: "\n") } }
}


/// Diagnose legacy meal rows without counting raw text in dashboards or silently
/// changing a previously confirmed HealthKit record. A repair must be reviewed.
public enum MealNutritionRecovery {
    public static func missing(in event: IntakeEvent) -> [NutrientAmount] {
        guard event.state == .synced || event.state == .localOnly,
              event.product.kind == .food, event.product.mealDetails != nil,
              let source = event.product.mealInputText, !source.isEmpty,
              let extracted = try? MealNutritionText.extract(source), let samples = try? event.healthSamples else { return [] }
        let written = Set(samples.map(\.nutrient)).union(event.product.mealUnknownNutrients ?? [])
        return extracted.nutrients.filter { !written.contains($0.nutrient) }
    }
    public static func isNutrientRow(_ item: MealPortion) -> Bool {
        guard item.nutrientsPer100.isEmpty else { return false }
        if MealNutritionText.resolve(item.name) != nil { return true }
        guard let parsed = try? MealNutritionText.extract(item.name) else { return false }
        return parsed.foodText.isEmpty && !parsed.nutrients.isEmpty
    }
}
public extension MealReviewState {
    mutating func prepareRecovery(_ event: IntakeEvent) throws {
        guard !MealNutritionRecovery.missing(in: event).isEmpty, let source = event.product.mealInputText else { throw IntakeError.invalidProduct }
        try prepareText(source)
        // Keep original food metadata/quantities, remove only rows misclassified as nutrients.
        items = (event.product.mealDetails ?? []).filter { !MealNutritionRecovery.isNutrientRow($0) }.map { item in
            var item = item
            if let quantity = item.quantity { item.quantity = quantity * event.servings }
            return item
        }
        nutrientOverrides = nutrientOverrides.map { amount in
            var amount = amount; amount.value *= event.servings; return amount
        }
        // Existing saved values win over archived text, including deliberate prior edits.
        for amount in try event.healthSamples {
            nutrientOverrides.removeAll { $0.nutrient == amount.nutrient }
            nutrientOverrides.append(.init(amount.nutrient, amount.value * event.servings, amount.unit, origin: amount.origin == .manualEstimate || amount.origin == .aiEstimate ? .manualEstimate : .manual))
        }
        restoreUnknownNutrients(event.product.mealUnknownNutrients ?? [])
    }
}
