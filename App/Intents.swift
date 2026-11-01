import AppIntents
import Foundation
import UniformTypeIdentifiers

struct ProductEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "补充剂")
    static let defaultQuery = ProductQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct ProductQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [ProductEntity] {
        IntakeStore.shared.library.products.filter { $0.kind == .supplement }.filter { identifiers.contains($0.id) }.map { ProductEntity(id: $0.id, name: $0.name) }
    }
    @MainActor func entities(matching string: String) async throws -> [ProductEntity] {
        IntakeStore.shared.library.products.filter { $0.kind == .supplement }.filter { $0.name.localizedCaseInsensitiveContains(string) }.map { ProductEntity(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [ProductEntity] {
        IntakeStore.shared.library.products.filter { $0.kind == .supplement }.map { ProductEntity(id: $0.id, name: $0.name) }
    }
}
struct LogSupplementIntent: AppIntent {
    static let title: LocalizedStringResource = "记录补充剂摄入（按份）"
    static let description = IntentDescription("记录已确认产品的实际摄入份数。请先在 App 中保存产品。")
    // Foreground guarantees one writer, unlocked protected storage and visible authorization.
    static let openAppWhenRun = true
    @Parameter(title: "产品") var product: ProductEntity
    @Parameter(title: "份数", default: 1.0) var servings: Double
    static var parameterSummary: some ParameterSummary { Summary("记录 \(\.$product) \(\.$servings) 份") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntakeStore.shared
        guard let item = store.library.products.first(where: { $0.id == product.id && $0.kind == .supplement }) else { throw IntakeError.missing }
        try await store.log(item, servings: servings)
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(store.message ?? "已记录")))
    }
}
struct LogSupplementUnitsIntent: AppIntent {
    static let title: LocalizedStringResource = "记录补充剂服用粒数"
    static let description = IntentDescription("按实际服用粒数记录；请先扫描并确认产品的每份粒数。")
    static let openAppWhenRun = true
    @Parameter(title: "产品") var product: ProductEntity
    @Parameter(title: "实际服用粒数", default: 1.0) var units: Double
    static var parameterSummary: some ParameterSummary { Summary("服用 \(\.$product) \(\.$units) 粒") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntakeStore.shared
        guard let item = store.library.products.first(where: { $0.id == product.id && $0.kind == .supplement }) else { throw IntakeError.missing }
        guard item.unitsPerServing != nil else { throw IntakeError.invalidProduct }
        try await store.logUnits(item, units: units)
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(store.message ?? "已记录")))
    }
}
struct IntakeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureIntakeIntent(), phrases: ["在 \(.applicationName) 记录摄入", "Record intake in \(.applicationName)"], shortTitle: "选择并记录", systemImageName: "list.bullet.circle")
        AppShortcut(intent: LogWaterIntent(), phrases: ["在 \(.applicationName) 记录喝水", "Log water in \(.applicationName)"], shortTitle: "记录饮水", systemImageName: "drop")
        AppShortcut(intent: LogFoodIntent(), phrases: ["在 \(.applicationName) 记录饮料食品", "Log food in \(.applicationName)"], shortTitle: "记录饮料食品", systemImageName: "takeoutbag.and.cup.and.straw")
        AppShortcut(intent: LogSupplementUnitsIntent(), phrases: ["在 \(.applicationName) 记录补充剂", "Log supplement in \(.applicationName)"], shortTitle: "记录补充剂", systemImageName: "pills")
    }
}

/// Indexing is a best-effort system integration, never a launch/save prerequisite.
/// Coalesce repeated changes; the helper/XPC call must not run on the UI thread.
@MainActor enum ShortcutIndex {
    private static var refreshTask: Task<Void, Never>?
    private static var needsRefresh = false
    static func refresh() {
        needsRefresh = true
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while needsRefresh {
                needsRefresh = false
                let worker = Task.detached(priority: .utility) {
                    IntakeShortcuts.updateAppShortcutParameters()
                }
                await worker.value
            }
            refreshTask = nil
        }
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "记录饮水"
    static let openAppWhenRun = true
    @Parameter(title: "实际毫升数", default: 250.0) var milliliters: Double
    static var parameterSummary: some ParameterSummary { Summary("记录 \(\.$milliliters) mL 饮水") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntakeStore.shared.logQuick(productID: nil, quantity: milliliters)
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(IntakeStore.shared.message ?? "已记录饮水")))
    }
}
@available(iOS 18.0, *)
struct ReviewMealPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "参考餐食照片并手动记录"
    static let description = IntentDescription("接收照片作为填写参考；请手动填写实际数量和已知营养值，确认后同步 Apple 健康。")
    static let openAppWhenRun = true
    @Parameter(title: "餐食照片", supportedContentTypes: [.image]) var photo: IntentFile
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !IntakeStore.shared.busy else { throw IntakeError.busy }
        guard IntakeStore.shared.mealRequest == nil else { throw MealReviewError.blocked(["请先完成或取消当前餐食草稿。"]) }
        let data = photo.data
        guard !data.isEmpty, data.count <= 20_000_000 else { throw MealReviewError.blocked(["照片为空或超过20 MB。"]) }
        IntakeStore.shared.mealRequest = MealRequest(image: data)
        return .result(dialog: IntentDialog(stringLiteral: L10n.tr("请在 OpenIntake 校准份量并确认。此时尚未记录摄入。")))
    }
}

struct FoodEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "饮料或食品模板")
    static let defaultQuery = FoodQuery()
    var id: UUID
    var name: String
    var unit: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "实际数量单位：\(unit)") }
}
struct FoodQuery: EntityStringQuery {
    @MainActor private func items() -> [FoodEntity] {
        IntakeStore.shared.library.products.filter { $0.manualNutrition != nil }.map { FoodEntity(id: $0.id, name: $0.name, unit: $0.intakeUnitTitle) }
    }
    @MainActor func entities(for identifiers: [UUID]) async throws -> [FoodEntity] { items().filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [FoodEntity] { items().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    @MainActor func suggestedEntities() async throws -> [FoodEntity] { items() }
}
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "记录饮料或食品实际数量"
    static let description = IntentDescription("选择已保存的手动模板。饮料填写实际 mL，食品填写实际 g；糖、钠等按标签计算并同步 Apple 健康。")
    static let openAppWhenRun = true
    @Parameter(title: "饮料或食品") var product: FoodEntity
    @Parameter(title: "实际数量（饮料 mL／食品 g）") var quantity: Double
    static var parameterSummary: some ParameterSummary { Summary("记录 \(\.$product) 实际数量 \(\.$quantity)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntakeStore.shared
        guard store.library.products.contains(where: { $0.id == product.id && $0.manualNutrition != nil }) else { throw IntakeError.missing }
        try await store.logQuick(productID: product.id, quantity: quantity, expectedUnit: product.unit)
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(store.message ?? "请查看同步状态")))
    }
}
