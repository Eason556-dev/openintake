import SwiftUI

struct CaptureWorkflowView: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CaptureKind?
    @State private var productID: UUID?
    @State private var quantity: Double?
    @State private var text = ""
    @State private var message: String?
    private var products: [Product] {
        store.library.products.filter { item in
            kind == .food ? item.manualNutrition != nil : item.kind == .supplement && (kind == .supplementServings || item.unitsPerServing != nil)
        }
    }
    private var selected: Product? { products.first { $0.id == productID } }
    private var unit: String { kind == .water ? "mL" : kind == .supplementServings ? L10n.tr("份") : selected?.intakeUnitTitle ?? L10n.tr("数量") }
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("这次要记录什么？")) {
                    ForEach(CaptureKind.allCases, id: \.self) { choice in
                        Button { kind = choice; productID = nil; quantity = choice == .water ? 250 : nil; message = nil } label: {
                            HStack { Label(choice.label, systemImage: choice.symbol); Spacer(); if kind == choice { Image(systemName: "checkmark.circle.fill") } }
                        }.buttonStyle(.borderless)
                    }
                }
                if let kind {
                    Section(kind.label) {
                        if kind == .textMeal {
                            TextField(L10n.tr("例如：米饭150g、鸡肉100g、苹果80g"), text: $text, axis: .vertical).lineLimit(3...8)
                            Button(L10n.tr("整理并核对本餐")) { openMeal(text: text) }
                            Text(L10n.tr("文字仅整理名称与明确份量，不估算营养。请按标签填写已知值；照片仅在本页辅助核对，不会识别或保存。")).font(.caption)
                        } else if kind == .photoMeal {
                            Button(L10n.tr("拍照并核对餐食"), systemImage: "camera") { openMeal(text: nil) }
                        } else {
                            if kind != .water {
                                Picker(L10n.tr("产品"), selection: $productID) {
                                    Text(L10n.tr("请选择")).tag(Optional<UUID>.none)
                                    ForEach(products) { Text($0.name).tag(Optional($0.id)) }
                                }
                                if products.isEmpty { Text(L10n.tr("请先在 App 保存并确认适用产品；按粒记录需要确认每份粒数。")).font(.caption).foregroundStyle(.orange) }
                            }
                            HStack { Text(L10n.tr("实际摄入")); TextField(L10n.tr("数量"), value: $quantity, format: .number).keyboardType(.decimalPad); Text(L10n.display(unit)) }
                            Button(L10n.tr("记录并同步 Apple 健康")) { Task { await record() } }
                                .disabled((quantity.map { !$0.isFinite || $0 <= 0 } ?? true) || (kind != .water && selected == nil))
                        }
                    }
                }
                if let message { Section(L10n.tr("本次结果")) { Text(L10n.diagnostic(message)).accessibilityAddTraits(.updatesFrequently) } }
            }.disabled(store.busy)
                .navigationTitle(L10n.tr("选择并记录摄入"))
                .toolbar { Button(L10n.tr("完成")) { dismiss() }.disabled(store.busy) }
                .onChange(of: productID) { if kind != .water { quantity = selected?.manualNutrition?.packageQuantity ?? selected?.defaultIntakeQuantity } }
        }
    }
    private func openMeal(text: String?) {
        guard store.mealRequest == nil else { message = CaptureWorkflowError.draftOpen.localizedDescription; return }
        do {
            if let text { try TextMealValidation.validateInput(text); store.mealRequest = MealRequest(text: text) }
            else { store.mealRequest = MealRequest(startCamera: true) }
        } catch { message = error.localizedDescription }
    }
    private func record() async {
        do {
            guard let kind, let quantity else { throw IntakeError.invalidQuantity }
            if kind == .water { try await store.logQuick(productID: nil, quantity: quantity) }
            else {
                guard let selected else { throw IntakeError.missing }
                if kind == .supplementServings { try await store.log(selected, servings: quantity) }
                else { try await store.logQuick(productID: selected.id, quantity: quantity, expectedUnit: selected.intakeUnitTitle) }
            }
            message = store.message
        } catch { message = error.localizedDescription }
    }
}
extension CaptureKind {
    var label: String {
        switch self { case .water: L10n.tr("喝水"); case .supplementUnits: L10n.tr("补充剂 · 按粒"); case .supplementServings: L10n.tr("补充剂 · 按份"); case .food: L10n.tr("饮料／食品 · 按标签"); case .textMeal: L10n.tr("文字记录一顿饭"); case .photoMeal: L10n.tr("拍照记录餐食") }
    }
    var symbol: String {
        switch self { case .water: "drop.fill"; case .supplementUnits, .supplementServings: "pills.fill"; case .food: "takeoutbag.and.cup.and.straw.fill"; case .textMeal: "text.alignleft"; case .photoMeal: "camera.fill" }
    }
}
