import SwiftUI
import WidgetKit

struct IntakeEntry: TimelineEntry { var date: Date; var snapshot: DashboardSnapshot? }
struct IntakeProvider: TimelineProvider {
    func placeholder(in context: Context) -> IntakeEntry { .init(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (IntakeEntry) -> Void) { completion(.init(date: .now, snapshot: DashboardCache.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<IntakeEntry>) -> Void) {
        let now = Date(), snapshot = DashboardCache.load()
        var entries = [IntakeEntry(date: now, snapshot: snapshot)]
        // Explicit midnight entry prevents yesterday's values persisting as today's.
        if let end = snapshot?.dayEnd, end > now { entries.append(.init(date: end, snapshot: snapshot)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}
struct IntakeComplicationView: View {
    let entry: IntakeEntry
    let metric: DashboardMetric
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var tint: Color { metric == .water ? .cyan : metric == .energy ? .orange : metric == .protein ? .green : metric == .sugar ? .pink : .purple }
    var renderedColor: Color { renderingMode == .fullColor ? tint : .primary }
    var item: DashboardValue { entry.snapshot?.metric(metric, at: entry.date) ?? .init(id: metric, value: nil, goal: nil) }
    var amount: String { item.value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—" }
    var goal: String { item.goal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—" }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: item.fraction ?? 0) { Image(systemName: metric.symbol) } currentValueLabel: { Text(amount).minimumScaleFactor(0.5) }
                    .gaugeStyle(.accessoryCircular).tint(renderedColor).widgetAccentable()
                    .widgetLabel { Text("\(goal) \(metric.unit)") }
            case .accessoryCorner:
                Text(amount).font(.title3.bold()).foregroundStyle(renderedColor).widgetAccentable().widgetCurvesContent()
                    .widgetLabel { Gauge(value: item.fraction ?? 0) { Text(L10n.display(metric.title)) } currentValueLabel: { Text("\(goal) \(metric.unit)") } }
            case .accessoryInline:
                Text("\(L10n.display(metric.title)) \(amount)/\(goal) \(metric.unit)")
            default:
                // Three compact lines inside the system's content margins. No fixed large fonts or extra footer.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: metric.symbol).foregroundStyle(renderedColor).widgetAccentable()
                        Text(L10n.display(metric.title)).font(.caption2.weight(.semibold))
                        Spacer(minLength: 0)
                        if entry.snapshot?.pendingCount ?? 0 > 0 { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9)) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(amount).font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(renderedColor).widgetAccentable()
                        Text("/ \(goal) \(metric.unit)").font(.caption2)
                    }
                    Gauge(value: item.fraction ?? 0) { EmptyView() }
                        .gaugeStyle(.accessoryLinear).tint(renderedColor).widgetAccentable()
                }
                .lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            }
        }.privacySensitive()
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "openintake://dashboard"))
            .accessibilityLabel("\(L10n.display(metric.title)) \(amount) / \(goal) \(metric.unit)")
    }
}
struct WaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenIntakeWatchWater", provider: IntakeProvider()) { IntakeComplicationView(entry: $0, metric: .water) }
            .configurationDisplayName("补水进度").description("当前饮水量与个人目标")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
struct EnergyComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenIntakeWatchEnergy", provider: IntakeProvider()) { IntakeComplicationView(entry: $0, metric: .energy) }
            .configurationDisplayName("营养 · 能量").description("当前膳食能量与个人目标")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
struct ProteinComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenIntakeWatchProtein", provider: IntakeProvider()) { IntakeComplicationView(entry: $0, metric: .protein) }
            .configurationDisplayName("营养 · 蛋白质").description("当前蛋白质与个人目标")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
struct SugarComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenIntakeWatchSugar", provider: IntakeProvider()) { IntakeComplicationView(entry: $0, metric: .sugar) }
            .configurationDisplayName("营养 · 糖限量").description("已记录糖占个人限量的比例")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
struct SodiumComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenIntakeWatchSodium", provider: IntakeProvider()) { IntakeComplicationView(entry: $0, metric: .sodium) }
            .configurationDisplayName("营养 · 钠限量").description("已记录钠占个人限量的比例")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
@main struct OpenIntakeComplications: WidgetBundle {
    var body: some Widget { WaterComplication(); EnergyComplication(); ProteinComplication(); SugarComplication(); SodiumComplication() }
}
