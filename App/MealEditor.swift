import SwiftUI
import UIKit

struct MealRequest: Identifiable {
    let id = UUID()
    var image: Data?
    var text: String?
    var startCamera = false
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
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let photo, let image = UIImage(data: photo) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180) }
                    TextField(L10n.tr("本餐文字：米饭150g、鸡肉100g、苹果80g"), text: $review.text, axis: .vertical).lineLimit(3...6).disabled(review.busy)
                    if review.textNeedsReview { Text(L10n.tr("文字已修改，请重新整理后核对。我们不会用旧结果记录新文字。")).font(.caption).foregroundStyle(.orange) }
                    Button(L10n.tr("整理文字餐食"), systemImage: "text.alignleft") { analyzeText(review.text) }.disabled(review.busy || review.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.tr("拍摄本次餐食"), systemImage: "camera") { camera = true }.disabled(review.busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                    NavigationLink { ExternalInformationGuide() } label: { Label(L10n.tr("借助外部工具核对"), systemImage: "questionmark.circle") }
                    Text(L10n.tr("文字仅整理名称与明确份量，不估算营养。请按标签填写已知值；照片仅在本页辅助核对，不会识别或保存。")).font(.footnote)
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
                            TextField(L10n.tr("食物名称"), text: $item.name)
                            HStack { Text(L10n.tr("实际摄入")); TextField(L10n.tr("实际数量"), value: $item.quantity, format: .number).keyboardType(.decimalPad); Picker(L10n.tr("计量单位"), selection: Binding(get: { item.portionUnit }, set: { item.changeUnit(to: $0) })) { Text("g").tag(MealPortionUnit.g); Text("mL").tag(MealPortionUnit.mL) }.fixedSize() }
                            if !item.notes.isEmpty { Text(L10n.diagnostic(item.notes)).font(.caption).foregroundStyle(.secondary) }
                            DisclosureGroup(L10n.tr("核对营养值 · 每 100 \(item.portionUnit.rawValue)")) {
                                ForEach($item.nutrientsPer100) { $amount in
                                    HStack { VStack(alignment: .leading) { Text(L10n.display(amount.nutrient.title)); Text(amount.origin == .aiEstimate ? L10n.tr("AI 估算") : L10n.tr("手动填写")).font(.caption).foregroundStyle(.secondary) }; TextField(L10n.tr("含量"), value: $amount.value, format: .number).keyboardType(.decimalPad); Text(amount.unit.rawValue) }
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
                    if store.busy { Text(L10n.tr("正在处理 Apple 健康请求，请稍候再提交。")).font(.footnote).foregroundStyle(.orange) }
                    ForEach(review.recordingIssues, id: \.self) { reason in
                        Text(L10n.diagnostic(reason)).font(.footnote).foregroundStyle(.orange)
                    }
                    if review.items.contains(where: { $0.nutrientsPer100.isEmpty }) {
                        Text(L10n.tr("部分项目没有已知营养值：将保留名称和份量，仅汇总已有营养；Apple 健康中的数值不是本餐完整总量。")).font(.footnote)
                    }
                    if let product = try? MealValidation.product(review.items, confirmed: true, allowLocalOnly: true) {
                        ForEach(product.nutrients) { amount in Text("\(L10n.display(amount.nutrient.title)) \(amount.value, specifier: "%.4g") \(amount.unit.rawValue)") }
                    }
                    if review.items.allSatisfy({ $0.nutrientsPer100.isEmpty }) {
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
                    try? review.prepareText(L10n.language == "en" ? "Rice 150 g, Tea 250 mL" : "米饭 150 克，茶 250 毫升")
                    message = L10n.tr("模拟器界面预览，尚未记录摄入。")
                    return
                }
                #endif
                photo = request.image
                if let text = request.text { review.text = text; analyzeText(text) }
                else if let data = request.image { analyze(data) }
                else if request.startCamera { camera = UIImagePickerController.isSourceTypeAvailable(.camera); if !camera { message = L10n.tr("此设备没有可用摄像头，可填写文字餐食。") } }
            }
            .onChange(of: review.text) {
                guard !review.submitting, !review.submitted,
                      review.items.allSatisfy({ $0.nutrientsPer100.isEmpty }) else { return }
                // Rules only, no model: keep name/quantity previews ready while typing.
                try? review.prepareText(review.text)
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
                    }.navigationTitle(L10n.tr("补充营养值")).toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { nutrientTarget = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("添加")) {
                            if let value = newValue, let index = review.items.firstIndex(where: { $0.id == nutrientTarget }) {
                                let amount = NutrientAmount(newNutrient, value, newUnit, origin: .manual)
                                do { try MealValidation.validate(.init(name: review.items[index].name.isEmpty ? L10n.tr("待填写食物") : review.items[index].name, per100g: [amount])); review.items[index].nutrientsPer100.append(amount); nutrientTarget = nil }
                                catch { message = L10n.tr("含量或单位无效，请核对当前计量基准下的数值。"); nutrientTarget = nil }
                            }
                        }.disabled(newValue.map { !$0.isFinite || $0 <= 0 } ?? true) }
                    }
                }
            }
            .sheet(isPresented: $camera) { MealCamera { data in camera = false; if let data { analyze(data) } } }
        }
    }
    private func submit() {
        guard !store.busy else { return }
        do {
            let product = try review.beginRecording(requestID: request.id)
            // Claim synchronously before starting the async task; rapid taps cannot enqueue twice.
            Task {
                do { try await store.logMeal(product, requestID: request.id); review.finishSubmission(succeeded: true); dismiss() }
                catch { review.finishSubmission(succeeded: false); message = error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    private func analyzeText(_ text: String) {
        do {
            try review.prepareText(text)
            message = L10n.tr("已整理名称与明确份量，请补充已知营养值；未知留空。")
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
