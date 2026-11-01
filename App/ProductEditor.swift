import SwiftUI
import VisionKit
import AVFoundation
import UIKit

struct ProductEditor: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    @State var product: Product
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false
    @State private var cameraRequesting = false
    @State private var error: String?
    @State private var recognition = LabelRecognitionSession()
    @State private var parseStatus: String?
    @State private var customName = ""
    @State private var customAmount = ""
    @State private var customUnit = "mg"
    private var ingredientBinding: Binding<[Ingredient]> {
        Binding(get: { product.ingredients ?? [] }, set: { product.ingredients = $0 })
    }
    private var broadBinding: Binding<Bool> { Binding(get: { product.allowBroadMapping ?? false }, set: { product.allowBroadMapping = $0 }) }
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("标签识别")) {
                    Button(L10n.tr("拍摄补充剂标签"), systemImage: "camera") { Task { await prepareCamera() } }.disabled(!VNDocumentCameraViewController.isSupported || cameraRequesting)
                    if !VNDocumentCameraViewController.isSupported { Text(L10n.tr("此设备无法使用文档相机，可粘贴标签文字。")).font(.footnote) }
                    DisclosureGroup(L10n.tr("原始标签文字 / 粘贴输入")) { TextEditor(text: $product.sourceText).frame(minHeight: 130) }
                    if let parseStatus { Text(parseStatus).font(.callout).foregroundStyle(.secondary) }
                    NavigationLink { ExternalInformationGuide() } label: { Label(L10n.tr("借助外部工具核对"), systemImage: "questionmark.circle") }
                    Button(L10n.tr("重新解析并验证标签")) {
                        let document = product.ocrDocument.flatMap { $0.rawText == product.sourceText ? $0 : nil } ?? OCRDocument(text: product.sourceText)
                        applyDocument(document)
                    }
                    DisclosureGroup(L10n.tr("本机语言能力与 OCR 证据")) {
                        if let document = product.ocrDocument {
                            Text(L10n.tr("OCR：\(document.engine)\n可识别语言：\(document.supportedOCRLanguages.joined(separator: ", "))\n推测输入语言：\(document.languages.joined(separator: ", "))")).font(.caption)
                            Text(document.promptText).font(.caption).textSelection(.enabled)
                            if let proposal = product.semanticProposal, let json = try? JSONEncoder().encode(proposal), let text = String(data: json, encoding: .utf8) {
                                DisclosureGroup(L10n.tr("原始结构化草稿（未直接写入健康）")) { Text(text).font(.caption).textSelection(.enabled) }
                            }
                        }
                        if let raw = product.aiProposal { DisclosureGroup(L10n.tr("历史模型草稿（仅供追溯）")) { Text(raw).font(.caption).textSelection(.enabled) } }
                        Text(L10n.tr("OCR 仅辅助抄录，请对照包装核对名称、含量与每份定义。")).font(.caption)
                    }
                }
                Section(L10n.tr("产品")) {
                    TextField(L10n.tr("产品名称"), text: $product.name)
                    TextField(L10n.tr("标签每份定义，例如 1 粒"), text: $product.serving)
                    if product.labelBasis?.kind == .per100g || product.labelBasis?.kind == .per100mL {
                        Text(L10n.tr("首页按实际 \(L10n.display(product.intakeUnitTitle)) 记录，系统按每 100 \(L10n.display(product.intakeUnitTitle)) 的标签基准换算。")).font(.footnote)
                    } else {
                        HStack {
                            Text(L10n.tr("每份包含"))
                            TextField(L10n.tr("粒数（未知留空）"), value: $product.unitsPerServing, format: .number).keyboardType(.decimalPad)
                            Text(L10n.tr("粒 / 片"))
                        }
                    }
                    if let basis = product.labelBasis { Text(L10n.tr("包装基准：\(basis.evidence)；已知每份粒数时自动归一为每粒，每 100 g / mL 标签保留原基准。")).font(.footnote) }
                    ForEach(product.recommendations ?? [], id: \.self) { Text(L10n.tr("包装建议（不会自动记录）：") + $0).font(.footnote) }
                    Text(L10n.tr("记录的是实际服用数量；保存产品不会生成摄入事件。计量基准不明时，先核对每份定义和成分数量。")).font(.footnote)
                }
                if let broad = product.ingredients?.filter({ $0.mapping.kind == .broader }), !broad.isEmpty {
                    Section(L10n.tr("可选：较宽泛的健康分类")) {
                        ForEach(broad) { item in Text("\(item.name)：\(L10n.diagnostic(item.mapping.explanation))").font(.footnote) }
                        Toggle(L10n.tr("将 Omega-3 记为多不饱和脂肪（需确认）"), isOn: broadBinding)
                        Text(L10n.tr("默认关闭。无论是否开启，所有成分都保存在本机。不会把 EPA、DHA 再加到 Omega-3 总量。")).font(.footnote)
                    }
                }
                Section(L10n.tr("以后记录时同步到 Apple 健康")) {
                    if let plan = try? HealthPlan.samples(for: product), !plan.isEmpty {
                        ForEach(plan) { amount in
                            Text("\(L10n.display(amount.nutrient.title))：\(amount.value, specifier: "%.4g") \(amount.unit.rawValue)")
                        }
                    } else if MappingPresentation.needsBroadConsent(product) {
                        Text(L10n.tr("尚未启用上述宽泛映射；当前只保存在本地。Apple 健康支持多不饱和脂肪，确认后可写入 Omega-3 含量。"))
                    } else { Text(L10n.tr("当前无可写项目；未支持成分及未知数量保留本地。")) }
                    Text(L10n.tr("修改映射只影响今后的摄入。既有记录保留当时的写入清单；需要纠正时先撤销原记录，再重新记录。")).font(.footnote)
                }
                Section(L10n.tr("识别结果")) {
                    ForEach(ingredientBinding) { $item in
                        IngredientEditorRow(item: $item, allIngredients: product.ingredients ?? [], displayLanguage: L10n.language)
                    }.onDelete { offsets in
                        var items = product.ingredients ?? []
                        let removed = Set(offsets.map { items[$0].id })
                        items.remove(atOffsets: offsets)
                        for i in items.indices where items[i].parentID.map({ removed.contains($0) }) == true { items[i].parentID = nil }
                        product.ingredients = items
                    }
                    if product.ingredients?.isEmpty != false { Text(L10n.tr("尚未识别到成分，可粘贴标签或补充成分。")) }
                }
                if let warnings = product.parsingWarnings, !warnings.isEmpty {
                    Section(L10n.tr("请核对")) { ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in Text(L10n.diagnostic(warning)).font(.footnote) } }
                }
                DisclosureGroup(L10n.tr("补充未识别成分")) {
                    TextField(L10n.tr("成分名称"), text: $customName)
                    TextField(L10n.tr("含量（未知留空）"), text: $customAmount).keyboardType(.decimalPad)
                    TextField(L10n.tr("单位，例如 mg、mcg、IU"), text: $customUnit)
                    Button(L10n.tr("添加成分")) { addCustomIngredient() }.disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(L10n.tr("核对后保存。实际服用时，再在首页记录数量；此处不会写入 Apple 健康。")).font(.footnote)
                if let error { Text(L10n.diagnostic(error)).foregroundStyle(.red) }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.tr("确认成分"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button(L10n.tr("完成")) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("保存产品")) {
                        do {
                            product.confirmedAt = Date(); product.revision = UUID()
                            try store.save(product); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(product.ingredients?.isEmpty != false || product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onDisappear { recognition.cancel() }
            .onAppear {
                // Existing v1 products migrate in the editor, while historical event snapshots stay untouched.
                if product.ingredients == nil {
                    product.ingredients = product.nutrients.map { Ingredient(name: $0.nutrient.title, value: $0.value, unit: $0.unit.rawValue, sourceText: product.sourceText, origin: $0.origin) }
                }
            }
            .sheet(isPresented: $scanning) {
                LabelScanner(completion: { result in
                    scanning = false
                    switch result {
                    case .success(let document): product.sourceText = document.rawText; applyDocument(document)
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }, cancellation: { scanning = false })
            }
        }
    }
    private func applyDocument(_ input: OCRDocument) {
        _ = recognition.begin(input)
        adoptCurrentRecognition()
        parseStatus = L10n.tr("已使用离线规则整理，请核对结果。")
    }
    private func adoptCurrentRecognition() {
        product = recognition.applying(to: product)
        if product.ingredients?.isEmpty != false { error = L10n.tr("未找到可验证成分。原文已保留，请重拍清晰的成分表。") }
        else { error = nil }
    }
    private func addCustomIngredient() {
        let amount = customAmount.isEmpty ? nil : Double(customAmount)
        guard customAmount.isEmpty || (amount.map { $0.isFinite && $0 >= 0 } == true), !customUnit.isEmpty else { error = L10n.tr("含量或单位无效，未知含量请留空。"); return }
        var items = product.ingredients ?? []
        items.append(Ingredient(name: customName, value: amount, unit: customUnit, origin: .manual))
        product.ingredients = items; customName = ""; customAmount = ""; error = nil
    }
    @MainActor private func prepareCamera() async {
        guard !cameraRequesting else { return }
        cameraRequesting = true; defer { cameraRequesting = false }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed = status == .notDetermined ? await AVCaptureDevice.requestAccess(for: .video) : status == .authorized
        guard allowed else { error = L10n.tr("相机未获授权。请在 iPhone 设置中允许 OpenIntake 使用相机，或粘贴文字。"); return }
        error = nil; scanning = true
    }
}

private struct IngredientEditorRow: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @Binding var item: Ingredient
    var allIngredients: [Ingredient]
    var displayLanguage: String
    private var parentName: String? { allIngredients.first(where: { $0.id == item.parentID })?.displayName(language: L10n.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.displayName(language: displayLanguage)).font(.headline)
                Spacer()
                Text((item.reviewReasons ?? []).isEmpty ? mappingTitle : L10n.tr("待确认")).font(.caption).foregroundStyle(.secondary)
            }
            if let parentName { Text(item.relation == .equivalent ? L10n.tr("等效于 \(parentName)，不是额外摄入") : L10n.tr("包含在 \(parentName) 中，不另相加")).font(.caption).foregroundStyle(.secondary) }
            HStack {
                TextField(L10n.tr("含量未知"), value: $item.value, format: .number).keyboardType(.decimalPad)
                TextField(L10n.tr("单位"), text: $item.unit).frame(width: 80)
            }
            ForEach(item.reviewReasons ?? [], id: \.self) { Text(L10n.diagnostic($0)).font(.caption).foregroundStyle(.orange) }
            if let sources = item.chemicalSources, !sources.isEmpty {
                Text(L10n.tr("来源形式：") + sources.map(\.name).joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
            }
            if let concentration = item.concentration { Text(L10n.tr("浓度：") + concentration).font(.caption) }
            if !item.note.isEmpty { Text(L10n.diagnostic(item.note)).font(.caption) }
            DisclosureGroup(L10n.tr("成分与映射详情")) {
                TextField(L10n.tr("成分名称"), text: $item.name)
                if let original = item.originalName { Text(L10n.tr("包装原名：") + original).font(.caption) }
                if let sources = item.chemicalSources, !sources.isEmpty {
                    Text(L10n.tr("化学来源（不额外计量）：") + sources.map(\.name).joined(separator: "、")).font(.caption)
                }
                if let form = item.chemicalForm { Text(L10n.tr("化学形式：") + form).font(.caption) }
                if let printed = item.labelValue { Text(L10n.tr("标签原值：\(printed.formatted()) \(item.labelUnit ?? "")")).font(.caption) }
                if !(item.reviewReasons ?? []).isEmpty {
                    Button(L10n.tr("已对照原文修正此成分")) { item.reviewReasons = []; item.origin = .manual }
                }
                Picker(L10n.tr("包含在 / 等效于"), selection: $item.parentID) {
                    Text(L10n.tr("独立成分")).tag(nil as UUID?)
                    ForEach(allIngredients.filter { $0.id != item.id }) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker(L10n.tr("关系"), selection: $item.relation) {
                    Text(L10n.tr("包含的子成分")).tag(IngredientRelation.component)
                    Text(L10n.tr("等效量（非额外摄入）")).tag(IngredientRelation.equivalent)
                }
                Text(L10n.diagnostic(item.mapping.explanation)).font(.footnote)
                if let nutrient = item.mapping.nutrient { Text(nutrient.healthKitIdentifier).font(.caption).textSelection(.enabled) }
                Text(L10n.tr("来源：\(L10n.display(item.origin.rawValue))\n原始文字：\(item.sourceText)")).font(.caption)
            }
        }
        .onChange(of: item.value) { item.origin = .manual }
        .onChange(of: item.unit) { item.origin = .manual }
        .onChange(of: item.name) { item.origin = .manual; item.canonicalID = IngredientCatalog.resolve(item.name); item.originalName = nil }
    }
    private var mappingTitle: String {
        switch item.mapping.kind { case .exact: L10n.tr("准确对应"); case .broader: L10n.tr("可选宽泛映射"); case .localOnly: L10n.tr("仅本地保存") }
    }
}
