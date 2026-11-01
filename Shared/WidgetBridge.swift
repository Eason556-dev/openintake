import AppIntents
import Foundation

/// Minimal, disposable read-only projection. The private ingestion ledger stays in the app.
struct WidgetProduct: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var unit: String
    var defaultQuantity: Double?
}
enum WidgetCatalog {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "OpenIntakeAppGroup") as? String ?? "group.org.openintake.shared" }
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget-products.json")
    }
    static func load() -> (items: [WidgetProduct], message: String?) {
        guard let url else { return ([], "产品共享尚未连接，请打开 App 检查") }
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], "打开 App 以准备产品列表") }
        guard let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([WidgetProduct].self, from: data) else {
            return ([], "产品列表暂不可读，请解锁并打开 App")
        }
        return (items, items.isEmpty ? "先在 App 保存常用产品" : nil)
    }
    static func read() -> [WidgetProduct] { load().items }

}
struct WidgetWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "从小组件记录饮水"
    static let openAppWhenRun = true
    static let isDiscoverable = false
    @Parameter(title: "实际毫升数", default: 250.0) var quantity: Double
    init() { }
    init(_ quantity: Double) { self.quantity = quantity }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        try requireMainApp()
        return .result(dialog: IntentDialog(stringLiteral: L10n.tr("未记录，请打开 OpenIntake。")))
        #else
        try await IntakeStore.shared.logQuick(productID: nil, quantity: quantity)
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(IntakeStore.shared.message ?? "请查看同步状态")))
        #endif
    }
}
struct WidgetProductIntent: AppIntent {
    static let title: LocalizedStringResource = "从小组件记录常用摄入"
    static let openAppWhenRun = true
    static let isDiscoverable = false
    @Parameter(title: "产品标识") var identifier: String
    @Parameter(title: "单位") var unit: String
    @Parameter(title: "实际数量", default: 1.0) var quantity: Double
    init() { }
    init(id: UUID, quantity: Double, unit: String) { identifier = id.uuidString; self.quantity = quantity; self.unit = unit }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        try requireMainApp()
        return .result(dialog: IntentDialog(stringLiteral: L10n.tr("未记录，请打开 OpenIntake。")))
        #else
        guard let id = UUID(uuidString: identifier) else { throw IntakeError.missing }
        try await IntakeStore.shared.logQuick(productID: id, quantity: quantity, expectedUnit: unit)
        return .result(dialog: IntentDialog(stringLiteral: L10n.diagnostic(IntakeStore.shared.message ?? "请查看同步状态")))
        #endif
    }
}
enum WidgetActionError: LocalizedError {
    case openAppRequired
    var errorDescription: String? { "请解锁并打开 OpenIntake 后记录；未创建摄入。" }
}

private func requireMainApp() throws { throw WidgetActionError.openAppRequired }
