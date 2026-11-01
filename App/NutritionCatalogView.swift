import SwiftUI
import HealthKit

/// Public type availability only. Never reads samples, requests permissions or writes data.
@MainActor enum AppleNutritionCatalog {
    struct Entry: Identifiable {
        var id: String
        var title: String
        var unit: HKUnit
        var unitTitle: String
        var appMapping: Bool
        var type: HKQuantityType? { HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: id)) }
        var compatible: Bool { type?.is(compatibleWith: unit) == true }
    }
    static var entries: [Entry] {
        Nutrient.allCases.map { nutrient in
            Entry(id: nutrient.healthKitIdentifier, title: L10n.display(nutrient.title), unit: HealthWriter.unit(for: nutrient), unitTitle: nutrient.dimension == .mass ? L10n.tr("质量：g / mg / mcg") : nutrient.dimension == .volume ? L10n.tr("体积：mL / L") : L10n.tr("能量：kcal / kJ"), appMapping: true)
        }.sorted { $0.id < $1.id }
    }
    static func printAudit() {
        print("OPENINTAKE_CATALOG os=\(UIDevice.current.systemVersion) count=\(entries.count)")
        for entry in entries {
            print("OPENINTAKE_TYPE \(entry.id) available=\(entry.type != nil) unitCompatible=\(entry.compatible) aggregation=\(entry.type?.aggregationStyle.rawValue ?? -1)")
        }
        // Pure construction validates the Apple adapter's unit contract, without saving a sample.
        if let type = HKObjectType.quantityType(forIdentifier: .dietaryFatPolyunsaturated) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: 0.5)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())
            print("OPENINTAKE_SAMPLE PUFA grams=\(sample.quantity.doubleValue(for: .gram())) saved=false")
        }
    }
}
struct NutritionCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("当前系统核对")) {
                    Text(L10n.tr("iOS \(UIDevice.current.systemVersion) · \(AppleNutritionCatalog.entries.count) 种公开饮食营养类型"))
                    Text(L10n.tr("逐项检查系统是否提供该类型及单位是否兼容。不读取任何健康记录，也不请求权限。其他健康类别不用于保存营养成分。")).font(.footnote)
                    Text(L10n.tr("没有专用 Omega-3、EPA、DHA 或姜黄类型。Omega-3 可经确认记入多不饱和脂肪；这不等于测得全部多不饱和脂肪。")).font(.footnote)
                }
                Section(L10n.tr("完整营养清单")) {
                    ForEach(AppleNutritionCatalog.entries) { entry in
                        DisclosureGroup {
                            Text(entry.id).font(.caption).textSelection(.enabled)
                            Text(entry.appMapping ? L10n.tr("本 App 支持对应的标签数量映射；写入需用户确认及健康授权。") : L10n.tr("Apple 提供此类型；本 App 当前补充剂质量流程尚未接入。"))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.title)
                                Text("\(entry.unitTitle) · \(entry.compatible ? L10n.tr("系统类型及单位有效") : L10n.tr("当前系统检查未通过"))").font(.caption).foregroundStyle(entry.compatible ? Color.secondary : Color.red)
                            }
                        }
                    }
                }
                Section {
                    Link(L10n.tr("Apple 官方 Nutrition Type Identifiers"), destination: URL(string: "https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers")!)
                }
            }
            .navigationTitle(L10n.tr("健康营养类型"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
        }
    }
}
