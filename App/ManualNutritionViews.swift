import SwiftUI
import HealthKit

private struct ManualNutrientField: Identifiable {
    var id: Nutrient { nutrient }
    let nutrient: Nutrient
    var value: Double?
    var unit: NutritionUnit
    init(_ nutrient: Nutrient) {
        self.nutrient = nutrient
        unit = nutrient == .energyConsumed ? .kcal : [.sodium, .caffeine].contains(nutrient) ? .mg : .g
    }
    var amount: NutrientAmount? { value.map { .init(nutrient, $0, unit, origin: .manual) } }
}
struct ManualNutritionEditor: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    var original: Product?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: ManualFoodCategory = .beverage
    @State private var reference = 100.0
    @State private var package: Double?
    @State private var fields = [ManualNutrientField(.sugar), ManualNutrientField(.sodium), ManualNutrientField(.energyConsumed)]
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("产品和标签基准")) {
                    TextField(L10n.tr("饮料／食品名称"), text: $name)
                    Picker(L10n.tr("类型"), selection: $category) { ForEach(ManualFoodCategory.allCases, id: \.self) { Text(L10n.display($0.title)).tag($0) } }
                    HStack { Text(L10n.tr("以下含量对应每")); TextField(L10n.tr("标签基准"), value: $reference, format: .number).keyboardType(.decimalPad); Text(category.unit) }
                    Text(L10n.tr("标签写每100mL就填100；写每瓶330mL就填330。改变基准时，请一起核对下方含量。")).font(.footnote)
                    HStack { Text(category == .beverage ? L10n.tr("一瓶／杯容量") : L10n.tr("常用一份重量")); TextField(L10n.tr("可选"), value: $package, format: .number).keyboardType(.decimalPad); Text(category.unit) }
                }
                Section(L10n.tr("照标签填写 · 空白表示未知")) {
                    ForEach($fields) { $field in
                        HStack {
                            Text(L10n.display(field.nutrient.title))
                            TextField(L10n.tr("未标注"), value: $field.value, format: .number).keyboardType(.decimalPad)
                            Picker(L10n.tr("\(field.nutrient.title)单位"), selection: $field.unit) {
                                ForEach(NutritionUnit.allCases.filter { $0.dimension == field.nutrient.dimension }, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().fixedSize()
                        }
                    }.onDelete { fields.remove(atOffsets: $0) }
                    Menu(L10n.tr("添加其他已知营养项")) {
                        ForEach(Nutrient.allCases.filter { $0 != .water && !fields.map(\.nutrient).contains($0) }, id: \.self) { nutrient in
                            Button(L10n.display(nutrient.title)) { fields.append(ManualNutrientField(nutrient)) }
                        }
                    }
                    Text(L10n.tr("糖填总糖，不以碳水或添加糖代替；钠填标签的钠，不是盐的重量。明确标注为0时可以填0。饮料体积不计入喝水圆环。")).font(.footnote)
                }
                if let message { Text(L10n.diagnostic(message)).foregroundStyle(.red) }
                Text(L10n.tr("保存只建立常用模板；实际喝下或吃下后，再在首页记录数量。没有已知营养也可保存，仅记录数量，不写虚构营养。")).font(.footnote)
            }.navigationTitle(original == nil ? L10n.tr("添加饮料／食品") : L10n.tr("编辑饮料／食品"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存模板")) { save() }.disabled(store.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .onAppear {
                    if let original, let template = original.manualNutrition {
                        name = original.name; category = template.category; reference = template.referenceQuantity; package = template.packageQuantity
                        fields = template.amounts.map { amount in var field = ManualNutrientField(amount.nutrient); field.value = amount.value; field.unit = amount.unit; return field }
                        if fields.isEmpty { fields = [ManualNutrientField(.sugar), ManualNutrientField(.sodium)] }
                    }
                }
        }
    }
    private func save() {
        do {
            let template = ManualNutritionTemplate(category: category, referenceQuantity: reference, packageQuantity: package, amounts: fields.compactMap(\.amount))
            var product = try template.product(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            if let original { product.id = original.id }
            try store.save(product); store.message = L10n.tr("模板已保存；实际摄入后再记录数量。"); dismiss()
        } catch { message = L10n.tr("请核对标签基准、份量和营养数值。数值需有限且非负，糖不能超过已填写的碳水，食品营养质量不能超过食品重量。") }
    }
}
struct ManualFoodRow: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    let product: Product
    var edit: () -> Void
    @State private var quantity: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(product.name, action: edit).buttonStyle(.borderless)
            if let template = product.manualNutrition {
                Text(L10n.tr("标签每 \(template.referenceQuantity, specifier: "%.4g") \(template.category.unit)")).font(.caption).foregroundStyle(.secondary)
                if let size = template.packageQuantity {
                    HStack {
                        Button(template.category == .beverage ? L10n.tr("一瓶／杯 \(size.formatted()) mL") : L10n.tr("一份 \(size.formatted()) g")) { log(size) }
                        Button(template.category == .beverage ? L10n.tr("半瓶／杯") : L10n.tr("半份")) { log(size / 2) }
                    }.buttonStyle(.bordered)
                }
            }
            HStack {
                TextField(L10n.tr("实际摄入量"), value: $quantity, format: .number).keyboardType(.decimalPad)
                Text(product.intakeUnitTitle)
                Button(L10n.tr("记录并同步")) { if let quantity { log(quantity) } }.buttonStyle(.borderedProminent)
                    .disabled(quantity.map { !$0.isFinite || $0 <= 0 } ?? true)
            }
        }.onAppear { quantity = product.manualNutrition?.packageQuantity ?? 100 }
            .swipeActions(allowsFullSwipe: false) {
                Button(L10n.tr("移除模板"), role: .destructive) { do { try store.removeProduct(product.id) } catch { store.message = error.localizedDescription } }
            }
    }
    private func log(_ quantity: Double) {
        Task { do { try await store.logUnits(product, units: quantity) } catch { store.message = error.localizedDescription } }
    }
}
struct DailyNutritionCard: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    var openPermissions: () -> Void
    var openSync: () -> Void
    var accessRefresh: UUID
    @Environment(\.scenePhase) private var phase
    @State private var writer: HealthWriter?
    @State private var sugarAccess = L10n.tr("正在检查")
    @State private var sodiumAccess = L10n.tr("正在检查")
    var body: some View {
        Section(L10n.tr("今日已记录 · 糖与钠")) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let summary = DailyNutritionSummary(events: store.library.events, date: context.date)
                HStack {
                    Text(L10n.tr("糖 \(summary.sugarGrams.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " g" } ?? "未记录")"))
                    Spacer()
                    Text(L10n.tr("钠 \(summary.sodiumMilligrams.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " mg" } ?? "未记录")"))
                }.font(.headline)
                let sync = NutritionSyncStatus(events: store.library.events, nutrients: [.sugar, .sodium], date: context.date)
                Text(L10n.tr("Apple 健康写入权限：糖\(sugarAccess) · 钠\(sodiumAccess)")).font(.caption)
                Text(L10n.tr("今日糖／钠记录：已写入并核验 \(sync.verified) · 待同步 \(sync.pending) · 待撤销 \(sync.deleting)")).font(.caption)
                if sync.submittedUnverified > 0 { Text(L10n.tr("另有 \(sync.submittedUnverified) 条旧记录已提交但未核验。")).font(.caption).foregroundStyle(.orange) }
                Button(L10n.tr("授权／检查糖与钠写入"), action: openPermissions).buttonStyle(.borderless)
                Button(L10n.tr("查看写入结果与重试"), action: openSync).buttonStyle(.borderless)
                if summary.estimated { Text(L10n.tr("含估算值；请查看摄入记录的来源说明。")).font(.caption).foregroundStyle(.orange) }
                Text(L10n.tr("仅汇总本 App 的有效记录，包含待同步项；不是全天完整摄入。未填项保持未知。撤销后扣除，恢复后重新计入。")).font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { if writer == nil { writer = HealthWriter() }; refreshAccess() }
            .onChange(of: phase) { if phase == .active { refreshAccess() } }
            .onChange(of: accessRefresh) { refreshAccess() }
    }
    private func refreshAccess() {
        func title(_ nutrient: Nutrient) -> String {
            guard let status = writer?.authorization(for: nutrient) else { return L10n.tr("不可用") }
            switch status {
            case .notDetermined: return L10n.tr("尚未申请")
            case .sharingAuthorized: return L10n.tr("已允许")
            case .sharingDenied: return L10n.tr("未允许")
            @unknown default: return L10n.tr("未知")
            }
        }
        sugarAccess = title(.sugar); sodiumAccess = title(.sodium)
    }
}
struct SaltEntry: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double?
    @State private var shared = false
    @State private var percent: Double?
    @State private var confirmed = false
    @State private var message: String?
    private var fraction: Double { shared ? (percent ?? 0) / 100 : 1 }
    private var consumed: Double? { guard let grams else { return nil }; return try? OrdinarySalt.consumedGrams(saltGrams: grams, fraction: fraction) }
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("仅适用于普通食盐")) {
                    Toggle(L10n.tr("填写的是整道菜用盐量"), isOn: $shared)
                    HStack { Text(shared ? L10n.tr("整道菜用盐") : L10n.tr("实际吃下的食盐")); TextField(L10n.tr("克数"), value: $grams, format: .number).keyboardType(.decimalPad); Text("g") }
                    if shared { HStack { Text(L10n.tr("我吃了约")); TextField(L10n.tr("比例"), value: $percent, format: .number).keyboardType(.decimalPad); Text("%") } }
                    if let consumed { Text(L10n.tr("本次估算：食盐 \(consumed, specifier: "%.3g") g → 钠 \(consumed * 400, specifier: "%.4g") mg")) }
                    Text(L10n.tr("普通食盐按约400mg钠/g换算。低钠盐、酱油等请用自己的标签建立模板；仅凭照片不能知道加盐量。")).font(.footnote)
                    Toggle(L10n.tr("确认是普通食盐，且未在餐食钠中重复计入"), isOn: $confirmed)
                    Text(L10n.tr("分食比例和换算均标为人工估算。确认后记录实际摄入，并同步钠；不会把盐的克数直接写成钠。")).font(.footnote)
                    if let message { Text(L10n.diagnostic(message)).foregroundStyle(.red) }
                }
            }.navigationTitle(L10n.tr("记录食盐 · 估算钠")).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() }.disabled(store.busy) }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("确认并记录")) {
                    Task { do {
                        guard let grams else { throw IntakeError.invalidQuantity }
                        let product = try OrdinarySalt.product(saltGrams: grams, fraction: fraction, confirmed: confirmed)
                        try await store.logUnits(product, units: OrdinarySalt.consumedGrams(saltGrams: grams, fraction: fraction)); dismiss()
                    } catch { message = error.localizedDescription } }
                }.disabled(store.busy || !confirmed || consumed == nil) }
            }
        }
    }
}
