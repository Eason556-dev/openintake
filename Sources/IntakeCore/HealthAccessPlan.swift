import Foundation
#if SWIFT_PACKAGE
import IntakeShared
#endif

/// Permission preparation never creates intake events or changes their write snapshots.
public enum HealthAccessPlan {
    public static func suggested(products: [Product], events: [IntakeEvent]) -> [Nutrient] {
        var types = Set<Nutrient>()
        for product in products where product.confirmedAt != nil && product.kind != .medication {
            if let amounts = try? HealthPlan.samples(for: product) { types.formUnion(amounts.map(\.nutrient)) }
        }
        for event in events where event.state == .pending || event.state == .deletionPending {
            if let amounts = try? event.healthSamples { types.formUnion(amounts.map(\.nutrient)) }
        }
        return Nutrient.allCases.filter { types.contains($0) }
    }
    public static func explanation(for product: Product) -> String {
        do {
            let plan = try HealthPlan.samples(for: product)
            if !plan.isEmpty { return "可写入：" + plan.map { L10n.display($0.nutrient.title) }.joined(separator: "、") + "。记录实际摄入时才写入。" }
            if MappingPresentation.needsBroadConsent(product) { return "尚未启用 Omega-3 → 多不饱和脂肪映射。请编辑产品确认后，再记录实际摄入。" }
            if (product.ingredients ?? []).contains(where: { !($0.reviewReasons ?? []).isEmpty }) { return "有成分待确认，尚未生成可写项目。请编辑产品核对名称、含量、单位和每份定义。" }
            return "没有可写入的健康营养项；无对应类型或无法换算的成分保留本机。授权不能新增 Apple 尚未提供的类型。"
        } catch { return "写入清单未通过校验：" + error.localizedDescription }
    }
}
