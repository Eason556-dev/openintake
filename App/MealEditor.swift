import SwiftUI
import UIKit

struct MealRequest: Identifiable {
    let id = UUID()
    var image: Data?
    var text: String?
    var startCamera = false
    var eventID: UUID?
}
struct MealEditor: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    var request: MealRequest
    @Environment(\.dismiss) private var dismiss
    @State private var review = MealReviewState()
    @State private var initialized = false
    @State private var message: String?
    @State private var camera = false
    @State private var photo: Data?
    @State private var nutrientTarget: UUID?
    @State private var newNutrient: Nutrient = .protein
    @State private var newValue: Double?
    @State private var newUnit: NutritionUnit = .g
    @State private var foodTarget: UUID?
    @State private var foodSearch = ""
    @State private var foodResults: [ReferenceFood] = []
    @State private var overrideNutrient: Nutrient = .protein
    @State private var overrideValue: Double?
    @State private var overrideUnit: NutritionUnit = .g
    @State private var showOverride = false
    @State private var saveReusable = false
    @State private var mealName = ""
    @State private var mealDate = Date()
    @State private var mealType = "meal"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.tr("餐食名称（可选）"), text: $mealName)
                    DatePicker(L10n.tr("日期"), selection: $mealDate).disabled(request.eventID != nil)
                    Picker(L10n.tr("餐次"), selection: $mealType) {
                        Text(L10n.tr("餐食")).tag("meal"); Text(L10n.tr("早餐")).tag("breakfast"); Text(L10n.tr("午餐")).tag("lunch"); Text(L10n.tr("晚餐")).tag("dinner"); Text(L10n.tr("加餐")).tag("snack")
                    }
                }
                Section(L10n.tr("本餐总能量")) {
                    HStack {
                        Text(L10n.tr("能量"))
                        TextField(L10n.tr("未知留空"), value: $review.energyKilocalories, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("meal.energy.kcal")
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    Text(L10n.tr("填写本餐实际总能量；可只记录能量，不要求填写食物重量。留空时使用食物计算结果，未知不会填零。")).font(.caption).foregroundStyle(.secondary)
                }.disabled(review.submitting || store.busy)
                Section {
                    if let photo, let image = UIImage(data: photo) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180) }
                    TextField(L10n.tr("本餐文字：米饭150g、鸡肉100g、苹果80g"), text: $review.text, axis: .vertical).lineLimit(3...6).disabled(review.busy)
                    if review.textNeedsReview { Text(L10n.tr("文字已修改，请重新整理后核对。我们不会用旧结果记录新文字。")).font(.caption).foregroundStyle(.orange) }
                    Text(L10n.tr("例如：午餐650kcal；或米饭200g 260kcal。只识别明确标注的能量与单位。")).font(.caption).foregroundStyle(.secondary)
                    Button(L10n.tr("整理文字餐食"), systemImage: "text.alignleft") { analyzeText(review.text) }.disabled(review.busy || review.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.tr("拍摄本次餐食"), systemImage: "camera") { camera = true }.disabled(review.busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                    NavigationLink { ExternalInformationGuide() } label: { Label(L10n.tr("借助外部工具核对"), systemImage: "questionmark.circle") }
                    Text(L10n.tr("离线匹配食物资料；不明确的品种请自行选择。照片仅辅助核对，不会修改份量。")).font(.footnote)
                    if review.busy {
                        ProgressView(L10n.tr("正在整理餐食…"))
                        Button(L10n.tr("停止识别，手动填写")) { review.cancelAnalysis() }
                    }
                    if let message { Text(L10n.diagnostic(message)).font(.footnote).foregroundStyle(.orange) }
                }
                .disabled(review.submitting || store.busy)
                Section(L10n.tr("食物与实际摄入量 · \(review.items.count) 项")) {
                    ForEach($review.items) { $item in
                        VStack(alignment: .leading) {
                            TextField(L10n.tr("食物名称"), text: Binding(get: { item.name }, set: { item.rename($0) }))
                            if review.matches.contains(where: { $0.item.id == item.id && $0.candidates.count > 1 }), item.referenceFoodID == nil {
                                Text(L10n.tr("有多个参考品种，请选择实际的生熟状态或做法；尚未套用任何营养值。")).font(.caption).foregroundStyle(.orange)
                            }
                            Button(L10n.tr("选择离线食物"), systemImage: "magnifyingglass") { foodTarget = item.id; foodSearch = item.name; searchFoods() }
                            HStack { Text(L10n.tr("实际摄入")); TextField(L10n.tr("实际数量"), value: $item.quantity, format: .number).keyboardType(.decimalPad); Picker(L10n.tr("计量单位"), selection: Binding(get: { item.portionUnit }, set: { item.changeUnit(to: $0) })) { Text("g").tag(MealPortionUnit.g); Text("mL").tag(MealPortionUnit.mL) }.fixedSize() }
                            if MealCalculation.energyNeedsReview(item) { Text(L10n.tr("能量与宏量营养存在较大差异，请核对来源；不会自动改写数值。")).font(.caption).foregroundStyle(.orange) }
                            if !item.notes.isEmpty { Text(L10n.diagnostic(item.notes)).font(.caption).foregroundStyle(.secondary) }
                            if let values = item.referenceOnlyNutrients, !values.isEmpty {
                                DisclosureGroup(L10n.tr("仅本机参考数据")) {
                                    ForEach(values) { value in
                                        if let quantity = item.quantity { Text("\(L10n.display(referenceOnlyTitle(value.id))) · \(value.value * quantity / 100, specifier: "%.4g") \(value.unit)") }
                                        else { Text(L10n.display(referenceOnlyTitle(value.id)) + " · —") }
                                    }
                                    Text(L10n.tr("这些值不写入其他 HealthKit 类别，也不加入宏量营养总量。")).font(.caption)
                                }
                            }
                            if !item.nutrientsPer100.contains(where: { $0.nutrient == .energyConsumed }) {
                                Button(L10n.tr("添加能量（每100）") + " " + item.portionUnit.rawValue, systemImage: "flame") { newNutrient = .energyConsumed; newUnit = .kcal; newValue = nil; nutrientTarget = item.id }
                            }
                            DisclosureGroup(L10n.tr("核对营养值 · 每 100 \(item.portionUnit.rawValue)")) {
                                ForEach($item.nutrientsPer100) { $amount in
                                    HStack { VStack(alignment: .leading) { Text(L10n.display(amount.nutrient.title)); Text(L10n.display(amount.origin == .database ? "食物成分参考资料" : amount.origin == .aiEstimate ? "AI 估算" : "手动填写")).font(.caption).foregroundStyle(.secondary) }; TextField(L10n.tr("含量"), value: Binding(get: { amount.value }, set: { amount.value = $0; amount.origin = .manual }), format: .number).keyboardType(.decimalPad); Text(amount.unit.rawValue) }
                                }.onDelete { item.nutrientsPer100.remove(atOffsets: $0) }
                                Menu(L10n.tr("补充已知营养值")) {
                                    ForEach(Nutrient.allCases.filter { $0 != .water && !item.nutrientsPer100.map(\.nutrient).contains($0) }, id: \.self) { nutrient in
                                        Button(L10n.display(nutrient.title)) { newNutrient = nutrient; newUnit = nutrient == .energyConsumed ? .kcal : .g; newValue = nil; nutrientTarget = item.id }
                                    }
                                }
                                Text(L10n.tr("未知项目请删除，不会作为零写入健康。切换 g／mL 后须重新填写数量及营养，不自动转换。")).font(.caption)
                            }
                        }
                    }.onDelete { review.items.remove(atOffsets: $0) }
                    Button(L10n.tr("添加食物")) { review.items.append(MealPortion(name: "")) }
                }.disabled(review.busy || review.submitting || store.busy)
                Section(L10n.tr("确认后同步")) {
                    Toggle(L10n.tr("保存为常用餐食（可在手表记录）"), isOn: $saveReusable)
                    if !review.pendingPlaceholderZeros.isEmpty {
                        Text(L10n.tr("完整模板中的零值可能是未知占位，请先确认实际为零或设为未知。")).font(.footnote).foregroundStyle(.orange)
                        Button(L10n.tr("将未核对零值全部设为未知")) { review.discardPlaceholderZeros() }
                        ForEach(Nutrient.allCases.filter { review.pendingPlaceholderZeros.contains($0) }, id: \.self) { nutrient in
                            HStack {
                                Text(L10n.display(nutrient.title))
                                Spacer()
                                Button(L10n.tr("实际为零")) { review.resolvePlaceholderZero(nutrient, knownZero: true) }.buttonStyle(.bordered)
                                Button(L10n.tr("未知")) { review.resolvePlaceholderZero(nutrient, knownZero: false) }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if store.busy { Text(L10n.tr("正在处理 Apple 健康请求，请稍候再提交。")).font(.footnote).foregroundStyle(.orange) }
                    ForEach(review.recordingIssues, id: \.self) { reason in
                        Text(L10n.diagnostic(reason)).font(.footnote).foregroundStyle(.orange)
                    }
                    if review.items.contains(where: { $0.nutrientsPer100.isEmpty }) {
                        Text(L10n.tr("部分项目没有已知营养值：将保留名称和份量，仅汇总已有营养；Apple 健康中的数值不是本餐完整总量。")).font(.footnote)
                    }
                    if let product = try? MealValidation.product(review.items, confirmed: true, allowLocalOnly: true) {
                        let amounts = (try? MealCalculation.apply(overrides: review.nutrientOverrides, to: product.nutrients)) ?? product.nutrients
                        ForEach(amounts.filter { summaryNutrients.contains($0.nutrient) }) { amount in nutrientSummary(amount) }
                        DisclosureGroup(L10n.tr("其他已知营养")) {
                            ForEach(amounts.filter { !summaryNutrients.contains($0.nutrient) }) { amount in nutrientSummary(amount) }
                        }
                    }
                    if review.recordsProvidedTotals {
                        ForEach(review.nutrientOverrides) { nutrientSummary($0) }
                    }
                    Button(L10n.tr("调整本餐营养总量")) { showOverride = true }
                    ForEach(review.nutrientOverrides) { amount in
                        HStack { Text(L10n.display(amount.nutrient.title)); Text("\(amount.value.formatted()) \(amount.unit.rawValue)"); Spacer(); Button(L10n.tr("恢复计算值")) { review.nutrientOverrides.removeAll { $0.nutrient == amount.nutrient } } }
                    }
                    Text(L10n.tr("调整值会保留，修改份量不会覆盖；选择恢复计算值可重新使用计算结果。")).font(.caption)
                    if let coverage = try? MealCalculation.summarize(review.items) {
                        if coverage.contains(where: { $0.value != nil && !$0.complete }) {
                            DisclosureGroup(L10n.tr("部分营养总量不完整")) {
                                ForEach(coverage.filter { $0.value != nil && !$0.complete }, id: \.nutrient) { value in Text("\(L10n.display(value.nutrient.title)) · \(value.knownItems)/\(value.totalItems)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if review.items.allSatisfy({ $0.nutrientsPer100.isEmpty }) && review.nutrientOverrides.isEmpty {
                        Text(L10n.tr("没有已知营养值：可保存本机餐食记录，不会向 Apple 健康写入虚构数据。"))
                    }
                    Text(L10n.tr("点击记录即确认本次实际摄入；未知营养留空。")).font(.footnote)
                }.disabled(review.submitting || store.busy)
            }
            .navigationTitle(L10n.tr("确认本次餐食"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() }.disabled(store.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("确认并记录")) { submit() }
                        .disabled(store.busy || !review.recordingIssues.isEmpty)
                }
            }
            .task {
                guard !initialized else { return }; initialized = true
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--meal-review-ui-audit") {
                    if ProcessInfo.processInfo.arguments.contains("--meal-energy-ui-audit") {
                        try? review.prepareText(L10n.language == "en" ? "Lunch 650 kcal" : "午餐650千卡")
                    } else { try? review.prepareText(L10n.language == "en" ? "Rice 150 g, Tea 250 mL" : "米饭 150 克，茶 250 毫升") }
                    message = L10n.tr("模拟器界面预览，尚未记录摄入。")
                    return
                }
                #endif
                if let id = request.eventID, let event = store.library.events.first(where: { $0.id == id }) {
                    mealName = event.product.name; mealDate = event.date; mealType = event.product.mealType ?? "meal"
                    review.text = event.product.mealInputText ?? ""; review.parsedText = review.text
                    review.items = event.product.mealDetails ?? []; review.nutrientOverrides = event.product.mealOverrides ?? []
                    review.restoreUnknownNutrients(event.product.mealUnknownNutrients ?? [])
                    if !MealNutritionRecovery.missing(in: event).isEmpty {
                        do {
                            var repaired = MealReviewState(); try repaired.prepareRecovery(event); review = repaired
                            message = L10n.tr("已从原文补全营养字段。请核对后确认，将更新原记录并重新同步，不会新增一餐。")
                        } catch { message = error.localizedDescription }
                    }
                    return
                }
                photo = request.image
                if let text = request.text { review.text = text; analyzeText(text) }
                else if let data = request.image { analyze(data) }
                else if request.startCamera { camera = UIImagePickerController.isSourceTypeAvailable(.camera); if !camera { message = L10n.tr("此设备没有可用摄像头，可填写文字餐食。") } }
            }
            .onDisappear { review.cancelAnalysis() }
            .sheet(isPresented: Binding(get: { nutrientTarget != nil }, set: { if !$0 { nutrientTarget = nil } })) {
                NavigationStack {
                    Form {
                        Text(L10n.display(newNutrient.title) + L10n.tr(" · 每100") + (review.items.first { $0.id == nutrientTarget }?.portionUnit.rawValue ?? "g"))
                        TextField(L10n.tr("已知含量（未知留空）"), value: $newValue, format: .number).keyboardType(.decimalPad)
                        Picker(L10n.tr("单位"), selection: $newUnit) {
                            ForEach(NutritionUnit.allCases.filter { $0.dimension == newNutrient.dimension }, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }.onAppear { if newUnit.dimension != newNutrient.dimension { newUnit = NutritionRegistry.displayUnit(newNutrient) } }.navigationTitle(L10n.tr("补充营养值")).toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { nutrientTarget = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("添加")) {
                            if let value = newValue, let index = review.items.firstIndex(where: { $0.id == nutrientTarget }) {
                                let unit = newUnit.dimension == newNutrient.dimension ? newUnit : NutritionRegistry.displayUnit(newNutrient)
                                let amount = NutrientAmount(newNutrient, value, unit, origin: .manual)
                                do { try MealValidation.validate(.init(name: review.items[index].name.isEmpty ? L10n.tr("待填写食物") : review.items[index].name, per100g: [amount])); review.items[index].nutrientsPer100.append(amount); nutrientTarget = nil }
                                catch { message = L10n.tr("含量或单位无效，请核对当前计量基准下的数值。"); nutrientTarget = nil }
                            }
                        }.disabled(newValue.map { !$0.isFinite || $0 < 0 } ?? true) }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { foodTarget != nil }, set: { if !$0 { foodTarget = nil } })) {
                NavigationStack {
                    List {
                        Section { Text(L10n.tr("按实际品种、生熟状态选择。毫升不能直接转换为克；无可靠换算时请填写可食用重量。")) }
                        ForEach(foodResults) { food in
                            NavigationLink {
                                ReferenceFoodEntry(food: food, initialQuantity: review.items.first(where: { $0.id == foodTarget && $0.portionUnit == .g })?.quantity) { portion in
                                    if let index = review.items.firstIndex(where: { $0.id == foodTarget }) {
                                        var selected = portion; selected.name = food.displayName(language: L10n.language); selected.id = review.items[index].id
                                        review.items[index] = selected
                                    }
                                    foodTarget = nil
                                }
                            } label: { VStack(alignment: .leading) { Text(food.displayName(language: L10n.language)); Text("FDC " + food.id).font(.caption).foregroundStyle(.secondary) } }
                        }
                        if foodResults.isEmpty { Text(L10n.tr("未找到匹配项。可保留原名称并手动填写已知营养，不会替换成其他食品。")) }
                    }.searchable(text: $foodSearch).onChange(of: foodSearch) { searchFoods() }
                        .navigationTitle(L10n.tr("选择离线食物"))
                        .toolbar { Button(L10n.tr("取消")) { foodTarget = nil } }
                }
            }
            .sheet(isPresented: $showOverride) {
                NavigationStack {
                    Form {
                        Picker(L10n.tr("营养素"), selection: $overrideNutrient) { ForEach(Nutrient.allCases, id: \.self) { Text(L10n.display($0.title)).tag($0) } }
                            .onChange(of: overrideNutrient) { overrideUnit = overrideNutrient == .energyConsumed ? .kcal : overrideNutrient == .water ? .mL : .g; overrideValue = nil }
                        TextField(L10n.tr("含量"), value: $overrideValue, format: .number).keyboardType(.decimalPad)
                        Picker(L10n.tr("单位"), selection: $overrideUnit) { ForEach(NutritionUnit.allCases.filter { $0.dimension == overrideNutrient.dimension }, id: \.self) { Text($0.rawValue).tag($0) } }
                    }.navigationTitle(L10n.tr("调整本餐营养总量")).toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { showOverride = false } }
                        ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) {
                            guard let value = overrideValue else { return }
                            review.nutrientOverrides.removeAll { $0.nutrient == overrideNutrient }
                            review.nutrientOverrides.append(.init(overrideNutrient, value, overrideUnit, origin: .manual)); showOverride = false
                        }.disabled(overrideValue.map { !$0.isFinite || $0 < 0 } ?? true) }
                    }
                }
            }
            .sheet(isPresented: $camera) { MealCamera { data in camera = false; if let data { analyze(data) } } }
        }
    }
    private var summaryNutrients: Set<Nutrient> { [.energyConsumed,.protein,.carbohydrates,.fatTotal,.fiber,.sugar,.sodium] }
    private func nutrientSummary(_ amount: NutrientAmount) -> some View {
        let unit = NutritionRegistry.displayUnit(amount.nutrient)
        let value = (try? NutritionRegistry.converted(amount, to: unit)) ?? amount.value
        return LabeledContent(L10n.display(amount.nutrient.title), value: value.formatted(.number.precision(.significantDigits(1...4))) + " " + unit.rawValue)
    }
    private func referenceOnlyTitle(_ id: String) -> String {
        switch id { case "addedSugars": "添加糖"; case "vitaminARAE": "维生素 A（RAE）"; case "folateDFE": "叶酸（DFE）"; case "foodMoisture": "食物含水量"; default: id }
    }
    private func searchFoods() {
        do { foodResults = try FoodReference.bundled?.search(foodSearch) ?? [] }
        catch { foodResults = []; message = L10n.tr("离线资料暂不可用，请手动填写已知营养。") }
    }
    private func submit() {
        guard !store.busy else { return }
        do {
            var product = try review.beginRecording(requestID: request.id)
            if !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { product.name = mealName }
            product.mealType = mealType
            // Claim synchronously before starting the async task; rapid taps cannot enqueue twice.
            Task {
                do { if saveReusable { try store.save(product) }; if let eventID = request.eventID { try await store.editMeal(eventID, product: product) } else { try await store.logMeal(product, requestID: request.id, date: mealDate) }; review.finishSubmission(succeeded: true); dismiss() }
                catch { review.finishSubmission(succeeded: false); message = error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    private func analyzeText(_ text: String) {
        do {
            try review.prepareText(text)
            if mealName.isEmpty, let name = review.suggestedMealName { mealName = name }
            message = L10n.tr("已离线整理。请检查匹配资料、实际份量与未知项目。")
        } catch { message = error.localizedDescription }
    }
    private func analyze(_ data: Data) {
        photo = data
        message = L10n.tr("照片仅供本页核对，请手动填写食品、实际数量及已知营养值。")
    }

}
struct MealCamera: UIViewControllerRepresentable {
    var completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    @MainActor final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (Data?) -> Void
        init(_ completion: @escaping (Data?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.8)) }
    }
}

/// Structured alternative to text parsing; household weights are tied to this exact source food.
private struct ReferenceFoodEntry: View {
    var food: ReferenceFood
    var initialQuantity: Double?
    var completion: (MealPortion) -> Void
    @State private var quantity: Double? = 100
    @State private var unit = "g"
    @State private var validationError: String?
    var body: some View {
        Form {
            Text(food.displayName(language: L10n.language))
            Text(food.category).font(.caption).foregroundStyle(.secondary)
            TextField(L10n.tr("实际数量"), value: $quantity, format: .number).keyboardType(.decimalPad)
            Picker(L10n.tr("单位"), selection: $unit) {
                ForEach(["g","kg","oz"], id: \.self) { Text($0).tag($0) }
                ForEach(Array(food.servings.enumerated()), id: \.offset) { index, serving in Text("\(serving.name) · \(serving.grams.formatted()) g").tag("serving:\(index)") }
            }
            .onChange(of: unit) { old, new in
                guard let quantity else { return }
                func quantityUnit(_ value: String) -> FoodQuantityUnit {
                    if value.hasPrefix("serving:"), let index = Int(value.dropFirst(8)) { return .referenceServing(index) }
                    return value == "kg" ? .kg : value == "oz" ? .oz : .g
                }
                if let grams = try? quantityUnit(old).grams(quantity, servings: food.servings), let factor = try? quantityUnit(new).grams(1, servings: food.servings) { self.quantity = grams / factor }
            }
            Text(ReferenceFood.source + " · FDC " + food.id).font(.caption).foregroundStyle(.secondary)
            if let validationError { Text(validationError).foregroundStyle(.orange) }
            Button(L10n.tr("使用此食物")) {
                guard let quantity else { return }
                let chosen: FoodQuantityUnit
                if unit.hasPrefix("serving:"), let index = Int(unit.dropFirst(8)), food.servings.indices.contains(index) { chosen = .referenceServing(index) }
                else { chosen = unit == "kg" ? .kg : unit == "oz" ? .oz : .g }
                do { completion(try food.portion(quantity: quantity, unit: chosen)) }
                catch { validationError = L10n.tr("请填写有效的实际可食用重量或可靠份量。") }
            }.disabled(quantity.map { !$0.isFinite || $0 <= 0 } ?? true)
        }.navigationTitle(L10n.tr("实际摄入"))
            .onAppear { quantity = initialQuantity ?? 100 }
    }
}
