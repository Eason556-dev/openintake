import SwiftUI
import WidgetKit

struct WaterEntry: TimelineEntry { let date: Date }
struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry { WaterEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) { completion(WaterEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) { completion(Timeline(entries: [WaterEntry(date: Date())], policy: .never)) }
}
struct WaterWidget: Widget {
    let kind = "OpenIntakeWater"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaterProvider()) { _ in
            VStack(alignment: .leading, spacing: 9) {
                HStack { Image(systemName: "drop.fill").foregroundStyle(.cyan); Text(L10n.tr("喝水")).font(.headline); Spacer() }
                Text(L10n.tr("喝下后，轻点记录")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(intent: WidgetWaterIntent(150)) { Text("150").font(.title3.bold()).frame(maxWidth: .infinity) }
                    Button(intent: WidgetWaterIntent(250)) { Text("250").font(.title3.bold()).frame(maxWidth: .infinity) }
                }.buttonStyle(.borderedProminent).tint(.cyan)
                Text(L10n.tr("毫升 · Apple 健康同步")).font(.caption2).foregroundStyle(.secondary)
            }.containerBackground(LinearGradient(colors: [.cyan.opacity(0.16), .blue.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), for: .widget)
        }.configurationDisplayName("快速饮水").description("实际喝水后，一键打开 App 记录并核验健康写入。")
            .supportedFamilies([.systemSmall])
    }
}
struct ProductEntry: TimelineEntry {
    var date: Date
    var product: WidgetProduct?
    var message: String?
    var preview = false
    var quantity: Double { product?.defaultQuantity ?? 1 }
}
struct ProductProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProductEntry { example() }
    func getSnapshot(in context: Context, completion: @escaping (ProductEntry) -> Void) { completion(context.isPreview ? example() : entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProductEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(1800))))
    }
    private func example() -> ProductEntry {
        ProductEntry(date: Date(), product: WidgetProduct(id: UUID(), name: L10n.tr("你的常用产品"), unit: L10n.tr("粒"), defaultQuantity: 1), message: L10n.tr("在 App 选择产品"), preview: true)
    }
    private func entry() -> ProductEntry {
        let catalog = WidgetCatalog.load()
        return ProductEntry(date: Date(), product: catalog.items.first, message: catalog.message)
    }
}
struct ProductWidgetView: View {
    var entry: ProductEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.tr("常用摄入"), systemImage: "leaf.fill").font(.headline).foregroundStyle(.green)
                if let product = entry.product {
                    Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(2).privacySensitive()
                    if entry.preview { Text(L10n.tr("在 App 设置产品与数量")).font(.caption).foregroundStyle(.secondary) }
                    else if entry.quantity.isFinite && entry.quantity > 0 {
                        Button(intent: WidgetProductIntent(id: product.id, quantity: entry.quantity, unit: product.unit)) {
                            Text(L10n.tr("记录 \(entry.quantity.formatted()) \(L10n.display(product.unit))")).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.75)
                        }.buttonStyle(.borderedProminent).tint(.green).privacySensitive()
                    } else { Text(L10n.tr("请编辑为有效数量")).font(.caption) }
                } else {
                    Text(entry.message ?? L10n.tr("选择你的常用产品")).font(.caption).foregroundStyle(.secondary)
                    Button(intent: OpenCaptureWorkflowIntent()) { Label(L10n.tr("选择并记录"), systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.green)
                }
                Text(L10n.tr("实际摄入后记录")).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "list.bullet.circle.fill").font(.largeTitle).foregroundStyle(.green.opacity(0.6))
                    Button(intent: OpenCaptureWorkflowIntent()) { Text(L10n.tr("其他摄入")) }.buttonStyle(.bordered)
                    Text(L10n.tr("喝水 · 产品 · 餐食")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.containerBackground(LinearGradient(colors: [.green.opacity(0.15), .mint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), for: .widget)
    }
}
struct ProductWidget: Widget {
    let kind = "OpenIntakeFavorite"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductProvider()) { ProductWidgetView(entry: $0) }
            .configurationDisplayName("常用产品").description("显示你在 App 选择的常用产品与实际数量；点按记录并同步健康。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
@main struct OpenIntakeWidgets: WidgetBundle {
    var body: some Widget { WaterWidget(); ProductWidget() }
}
