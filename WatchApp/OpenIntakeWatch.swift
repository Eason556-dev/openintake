import SwiftUI
import WatchKit

@main struct OpenIntakeWatch: App {
    @AppStorage(L10n.preferenceKey) private var language = "system"
    @StateObject private var store = WatchStore()
    @WKApplicationDelegateAdaptor(WatchBackgroundDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchDashboard(store: store).environment(\.locale, Locale(identifier: L10n.resolved(language)))
                .onChange(of: phase) { if phase == .active { store.refresh() } }
        }
    }
}
struct WatchDashboard: View {
    @ObservedObject var store: WatchStore
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    VStack(spacing: 18) {
                        NavigationLink { WatchQuickEntry(store: store) } label: { Label(L10n.tr("记录摄入"), systemImage: "plus.circle.fill") }
                        if !store.outbox.items.isEmpty {
                            NavigationLink { WatchPendingView(store: store) } label: { Text(L10n.tr("手表待处理：\(store.outbox.items.count)")) }
                        }
                        Text(L10n.tr("今日摄入")).font(.headline)
                        ForEach(DashboardMetric.allCases, id: \.self) { metric in
                            let item = store.snapshot?.metric(metric, at: context.date) ?? DashboardValue(id: metric, value: nil, goal: nil)
                            HStack(spacing: 12) {
                                Gauge(value: item.fraction ?? 0) { Image(systemName: metric.symbol) }
                                    .gaugeStyle(.accessoryCircular).tint(metric == .water ? .cyan : metric.isLimit ? .orange : .green)
                                    .accessibilityLabel(L10n.display(metric.title))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.display(metric.title)).font(.headline)
                                    Text(item.value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit)" } ?? L10n.display("未记录")).font(.body.monospacedDigit())
                                    Text(item.goal.map { "\(L10n.display(metric.isLimit ? "限量" : "目标")) \($0.formatted()) \(metric.unit)" } ?? L10n.display("未设目标")).font(.caption2).foregroundStyle(.secondary)
                                    if item.estimated { Text(L10n.tr("含估算")).font(.caption2).foregroundStyle(.orange) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.horizontal, 4).privacySensitive()
                        }
                        if let snapshot = store.snapshot {
                            if !snapshot.isCurrent(at: context.date) { Text(L10n.tr("等待今天的数据")).foregroundStyle(.orange) }
                            Text(L10n.tr("上次同步")).font(.caption2)
                            Text(snapshot.updatedAt, style: .relative).font(.caption2)
                            if snapshot.pendingCount > 0 { Text(L10n.tr("有记录待同步 Apple 健康")).font(.caption2).foregroundStyle(.orange) }
                        } else { Text(L10n.tr("请打开配对 iPhone 上的 OpenIntake，获取当日数据和目标。")).font(.caption) }
                        if let status = store.status { Text(L10n.diagnostic(status)).font(.caption2).foregroundStyle(.secondary) }
                        Button(L10n.tr("刷新")) { store.refresh() }
                        Text(L10n.tr("仅本 App 记录；未记录不等于零。糖和钠显示已用限量。")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4)
                }
            }.navigationTitle("OpenIntake")
        }.task {
            store.refresh()
            #if DEBUG
            store.runConnectivityAuditIfRequested()
            #endif
        }
    }
}
