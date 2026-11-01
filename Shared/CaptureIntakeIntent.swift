import AppIntents
import Foundation

enum CaptureKind: String, AppEnum {
    case water, supplementUnits, supplementServings, food, textMeal, photoMeal
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "记录方式")
    static let caseDisplayRepresentations: [CaptureKind: DisplayRepresentation] = [
        .water: "喝水", .supplementUnits: "补充剂 · 按粒", .supplementServings: "补充剂 · 按份",
        .food: "饮料／食品 · 按标签", .textMeal: "文字记录一顿饭", .photoMeal: "拍照记录餐食"
    ]
}
struct CaptureProduct: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "已确认产品")
    static let defaultQuery = CaptureProductQuery()
    var id: UUID
    var name: String
    var unit: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "数量单位：\(unit)") }
}
struct CaptureProductQuery: EntityStringQuery {
    @MainActor func items() -> [CaptureProduct] {
        #if WIDGET_EXTENSION
        return WidgetCatalog.read().map { CaptureProduct(id: $0.id, name: $0.name, unit: $0.unit) }
        #else
        return IntakeStore.shared.library.products.filter { $0.kind == .supplement || $0.manualNutrition != nil }.map { CaptureProduct(id: $0.id, name: $0.name, unit: $0.intakeUnitTitle) }
        #endif
    }
    @MainActor func entities(for identifiers: [UUID]) async throws -> [CaptureProduct] { items().filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [CaptureProduct] { items().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    @MainActor func suggestedEntities() async throws -> [CaptureProduct] { items() }
}
/// A single executable workflow: ask only the parameters required by the chosen branch.
struct CaptureIntakeIntent: AppIntent {
    static let title: LocalizedStringResource = "选择并记录摄入"
    static let description = IntentDescription("运行后选择喝水、补充剂、饮料食品或文字／拍照餐食。只运行选中的一项，不把多个记录动作顺序执行。")
    static let openAppWhenRun = true
    @Parameter(title: "记录方式") var kind: CaptureKind?
    @Parameter(title: "产品") var product: CaptureProduct?
    @Parameter(title: "实际数量") var quantity: Double?
    @Parameter(title: "本餐吃了什么") var mealText: String?
    static var parameterSummary: some ParameterSummary { Summary("选择并记录摄入") }
    init() { }
    init(kind: CaptureKind) { self.kind = kind }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        try requireHostForCapture()
        return .result(dialog: IntentDialog(stringLiteral: L10n.tr("请解锁并打开 OpenIntake。尚未记录摄入。")))
        #else
        let choice: CaptureKind
        if let kind { choice = kind }
        else { choice = try await $kind.requestDisambiguation(among: CaptureKind.allCases, dialog: IntentDialog(stringLiteral: L10n.tr("这次要记录什么？"))) }
        let store = IntakeStore.shared
        guard !store.busy else { throw IntakeError.busy }
        switch choice {
        case .water:
            let amount: Double
            if let quantity { amount = quantity } else { amount = try await $quantity.requestValue(IntentDialog(stringLiteral: L10n.tr("实际喝了多少毫升水？"))) }
            try await store.logQuick(productID: nil, quantity: amount)
        case .supplementUnits, .supplementServings, .food:
            let candidates = store.library.products.filter {
                choice == .food ? $0.manualNutrition != nil : $0.kind == .supplement && (choice == .supplementServings || $0.unitsPerServing != nil)
            }
            guard !candidates.isEmpty else { throw CaptureWorkflowError.noProducts }
            let selected: CaptureProduct
            if let product { selected = product } else {
                selected = try await $product.requestDisambiguation(among: candidates.map { CaptureProduct(id: $0.id, name: $0.name, unit: $0.intakeUnitTitle) }, dialog: IntentDialog(stringLiteral: L10n.tr("选择本次实际摄入的产品")))
            }
            guard let current = candidates.first(where: { $0.id == selected.id }) else { throw IntakeError.missing }
            let unit = choice == .supplementServings ? "份" : current.intakeUnitTitle
            let amount: Double
            if let quantity { amount = quantity } else { amount = try await $quantity.requestValue(IntentDialog(stringLiteral: L10n.tr("实际摄入多少 \(L10n.display(unit))？"))) }
            if choice == .supplementServings { try await store.log(current, servings: amount) }
            else { try await store.logQuick(productID: current.id, quantity: amount, expectedUnit: selected.unit) }
        case .textMeal:
            guard store.mealRequest == nil else { throw CaptureWorkflowError.draftOpen }
            let text: String
            if let mealText { text = mealText } else { text = try await $mealText.requestValue(IntentDialog(stringLiteral: L10n.tr("输入本餐所有内容，尽量写明实际克数，例如米饭150g、鸡肉100g、苹果80g。未知份量稍后校准。"))) }
            try TextMealValidation.validateInput(text)
            store.mealRequest = MealRequest(text: text)
            return .result(dialog: IntentDialog(stringLiteral: L10n.tr("请填写已知营养并核对实际份量，确认后才写入 Apple 健康。")))
        case .photoMeal:
            guard store.mealRequest == nil else { throw CaptureWorkflowError.draftOpen }
            store.mealRequest = MealRequest(startCamera: true)
            return .result(dialog: IntentDialog(stringLiteral: L10n.tr("拍摄餐食后校准并确认。尚未记录摄入。")))
        }
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(store.message ?? "请查看同步状态")))
        #endif
    }
}
enum CaptureWorkflowError: LocalizedError {
    case noProducts, draftOpen
    var errorDescription: String? {
        switch self {
        case .noProducts: L10n.tr("暂无适用产品。请先在 App 保存并确认标签和每份定义，再运行此流程。")
        case .draftOpen: L10n.tr("请先完成或取消当前餐食草稿，尚未创建新记录。")
        }
    }
}
private func requireHostForCapture() throws { throw WidgetActionError.openAppRequired }

struct OpenCaptureWorkflowIntent: AppIntent {
    static let title: LocalizedStringResource = "打开摄入记录菜单"
    static let openAppWhenRun = true
    static let isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        try requireHostForCapture()
        #else
        guard IntakeStore.shared.mealRequest == nil else { throw CaptureWorkflowError.draftOpen }
        IntakeStore.shared.captureMenuRequested = true
        #endif
        return .result()
    }
}
