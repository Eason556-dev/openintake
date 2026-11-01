import Foundation

/// Resolve a system action against the current library, never a stale widget snapshot.
public enum QuickIntake {
    /// Select a widget default without replacing a deleted explicit choice or reusing a quantity in a new unit.
    public static func widgetSelection(products: [Product], preferredID: UUID?, quantity: Double?, expectedUnit: String?) -> (Product, Double)? {
        let eligible = products.filter { ($0.kind == .supplement || $0.manualNutrition != nil) && (try? $0.validate()) != nil }
        let product = preferredID.map { id in eligible.first { $0.id == id } } ?? eligible.first
        guard let product else { return nil }
        let fallback = product.manualNutrition?.packageQuantity ?? product.defaultIntakeQuantity
        let amount = quantity.map { $0.isFinite && $0 > 0 && expectedUnit == product.intakeUnitTitle ? $0 : fallback } ?? fallback
        return (product, amount)
    }

    public static func resolve(productID: UUID?, quantity: Double, products: [Product], expectedUnit: String? = nil) throws -> (Product, Double) {
        guard quantity.isFinite, quantity > 0 else { throw IntakeError.invalidQuantity }
        guard let productID else {
            guard quantity <= 10000 else { throw IntakeError.invalidQuantity }
            return (HydrationProgress.product(), quantity)
        }
        guard let product = products.first(where: { $0.id == productID }) else { throw IntakeError.missing }
        guard product.kind == .supplement || product.manualNutrition != nil else { throw IntakeError.invalidProduct }
        if let expectedUnit, expectedUnit != product.intakeUnitTitle { throw QuickIntakeError.unitChanged }
        try product.validate()
        _ = try product.servings(forUnits: quantity)
        return (product, quantity)
    }
}

public enum QuickIntakeError: LocalizedError {
    case unitChanged
    public var errorDescription: String? { "产品的数量单位已改变。请重新选择快捷指令或小组件中的产品并核对数量；尚未记录摄入。" }
}
