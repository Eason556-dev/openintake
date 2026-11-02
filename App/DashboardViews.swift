import SwiftUI

/// One compact overview, with limits visually distinct from goals.
struct NutritionOverview: View {
    @ObservedObject var store: IntakeStore
    @AppStorage(L10n.preferenceKey) private var language = "system"
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = DashboardPreferences.snapshot(store.library.events, date: context.date)
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.tr("今日营养")).font(.headline)
                if store.library.events.prefix(100).contains(where: { Calendar.current.isDate($0.date, inSameDayAs: context.date) && !MealNutritionRecovery.missing(in: $0).isEmpty }) {
                    NavigationLink { RecordHistory(store: store) } label: {
                        Label(L10n.tr("有餐食营养文字待补全，点此修复同步"), systemImage: "exclamationmark.triangle")
                    }.font(.caption).foregroundStyle(.orange)
                }
                let energy = snapshot.metric(.energy, at: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.display(DashboardMetric.energy.title), systemImage: "flame.fill").foregroundStyle(.orange)
                    Text(energy.value.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "—").font(.largeTitle.bold()).monospacedDigit()
                    if let goal = energy.goal {
                        Text(L10n.tr("目标") + " " + goal.formatted() + " kcal").foregroundStyle(.secondary)
                        if let value = energy.value { Text(L10n.tr("剩余") + " " + max(0,goal-value).formatted() + " kcal"); ProgressView(value: energy.fraction ?? 0).tint(.orange) }
                    }
                else { NavigationLink(L10n.tr("设置每日目标")) { GoalSettings(store: store) }.font(.subheadline) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                    ForEach([DashboardMetric.protein, .carbohydrates, .fat], id: \.self) { metric in
                        MacroProgress(value: snapshot.metric(metric, at: context.date))
                    }
                }
                ForEach([DashboardMetric.fiber, .saturatedFat, .sugar, .sodium, .water], id: \.self) { metric in
                    NutritionProgressRow(value: snapshot.metric(metric, at: context.date))
                }
                NavigationLink(L10n.tr("全部营养与趋势")) { NutritionDetails(store: store) }
                Text(L10n.tr("已记录部分 · 未知不代表零")).font(.caption).foregroundStyle(.secondary)
                if snapshot.values.contains(where: \.estimated) { Text(L10n.tr("含参考估算；不代表实测营养。")).font(.caption).foregroundStyle(.secondary) }
                if snapshot.pendingCount > 0 {
                    Label(L10n.tr("有 \(snapshot.pendingCount) 条记录等待健康同步"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.padding(.vertical, 8)
        }
    }
}
private struct MacroProgress: View {
    var value: DashboardValue
    private var tint: Color { value.id == .protein ? .blue : value.id == .carbohydrates ? .orange : .purple }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(tint.opacity(0.12), lineWidth: 7)
                if let fraction = value.fraction { Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90)) }
                Text(value.value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—").font(.headline).minimumScaleFactor(0.6).padding(8)
            }.frame(maxWidth: 105).aspectRatio(1, contentMode: .fit)
            Text(value.id == .carbohydrates ? L10n.tr("碳水") : value.id == .fat ? L10n.tr("脂肪") : L10n.display(value.id.title)).font(.caption).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).accessibilityLabel(L10n.display(value.id.title))
            Text(value.goal.map { "/ " + $0.formatted() + " g" } ?? ("g · " + L10n.tr("未设目标"))).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
}
private struct NutritionProgressRow: View {
    var value: DashboardValue
    private var overLimit: Bool { value.id.isLimit && value.value != nil && value.goal != nil && value.value! > value.goal! }
    private var tint: Color { overLimit ? .orange : value.id.isLimit ? .secondary : value.id == .protein ? .blue : .green }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: 16); amount }
                VStack(alignment: .leading, spacing: 4) { title; amount }
            }
            if let fraction = value.fraction, value.value != nil {
                ProgressView(value: fraction).tint(tint)
                    .accessibilityLabel(L10n.display(value.id.isLimit ? "已用限量" : "目标进度"))
            }
            if overLimit { Text(L10n.tr("限量已超出")).font(.caption).foregroundStyle(.orange) }
        }.accessibilityElement(children: .combine)
    }
    private var title: some View { Text(L10n.display(value.id.title)).font(.subheadline) }
    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value.value.map { $0.formatted(.number.locale(L10n.locale).precision(.fractionLength(0...1))) } ?? "—")
                .font(.title3.weight(.semibold)).monospacedDigit()
            Text(value.id.unit).font(.caption).foregroundStyle(.secondary)
            if let goal = value.goal {
                Text("· \(L10n.display(value.id.isLimit ? "限量" : "目标")) \(goal.formatted(.number.locale(L10n.locale).precision(.fractionLength(0...1))))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
}
struct GoalSettings: View {
    @ObservedObject var store: IntakeStore
    @AppStorage("goal.energy") private var energy = 0.0
    @AppStorage("goal.protein") private var protein = 0.0
    @AppStorage("goal.sugar") private var sugar = 0.0
    @AppStorage("goal.sodium") private var sodium = 0.0
    @AppStorage("goal.carbohydrates") private var carbohydrates = 0.0
    @AppStorage("goal.fat") private var fat = 0.0
    @AppStorage("goal.fiber") private var fiber = 0.0
    @AppStorage("goal.saturatedFat") private var saturated = 0.0
    var body: some View {
        Form {
            Section(L10n.tr("个人目标与限量")) {
                goal(L10n.tr("能量目标 · kcal"), value: $energy)
                goal(L10n.tr("蛋白质目标 · g"), value: $protein)
                goal(L10n.tr("碳水目标 · g"), value: $carbohydrates)
                goal(L10n.tr("脂肪目标 · g"), value: $fat)
                goal(L10n.tr("纤维目标 · g"), value: $fiber)
                goal(L10n.tr("饱和脂肪限量 · g"), value: $saturated)
                goal(L10n.tr("糖限量 · g"), value: $sugar)
                goal(L10n.tr("钠限量 · mg"), value: $sodium)
                Text(L10n.tr("目标由你选择，0 表示未设置。这些是记录工具中的个人设置，不是医学建议。糖和钠不会以摄入越多为越好。"))
            }
            Section { Text(L10n.tr("Apple Watch 会显示相同目标和最新记录。未记录的营养素保持未知。")) }
        }.navigationTitle(L10n.tr("目标与限量"))
            .onDisappear { WatchDashboardBridge.shared.publish(events: store.library.events) }
    }
    private func goal(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(L10n.display(title)); Spacer()
            TextField(L10n.tr("未设置"), value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}
struct LanguageSettings: View {
    @State private var reminderMessage: String?
    @AppStorage(L10n.preferenceKey) private var language = "system"
    @ObservedObject var store: IntakeStore
    var body: some View {
        Form {
            Picker(L10n.tr("显示语言"), selection: $language) {
                Text(L10n.tr("跟随系统")).tag("system")
                Text(L10n.tr("中文")).tag("zh-Hans")
                Text("English").tag("en")
            }.pickerStyle(.inline)
            Text(L10n.tr("仅更改界面语言。产品名称、包装原文和 OCR 证据保留原样；不会改变营养映射或数量。"))
            Text(L10n.tr("语言会同步到手表和小组件。系统权限弹窗与快捷指令编辑器由系统语言设置控制。"))
            Text(L10n.tr("提醒文字也会更新；不会改变提醒时间。"))
            if let reminderMessage { Text(L10n.diagnostic(reminderMessage)).foregroundStyle(.orange) }
        }.navigationTitle(L10n.tr("语言"))
            .onChange(of: language) {
                WatchDashboardBridge.shared.publish(events: store.library.events)
                Task {
                    do { try await IntakeNotifications.refreshLanguage(); reminderMessage = nil }
                    catch { reminderMessage = L10n.tr("显示语言已更新；部分提醒更新失败，请在提醒设置中重新保存。") }
                }
            }
    }
}
struct WatchSettings: View {
    @ObservedObject var store: IntakeStore
    @State private var requested = false
    var body: some View {
        Form {
            Section(L10n.tr("手腕上的今日进度")) {
                Text(L10n.tr("每次记录会自动同步。Watch 可记录饮水和已配置产品；新产品请在 iPhone 添加。待发送记录与待写入健康的记录会分别显示。"))
                Button(L10n.tr("立即刷新手表数据")) { WatchDashboardBridge.shared.publish(events: store.library.events); requested = true }
                if requested { Text(L10n.tr("已准备最新数据；系统将在配对手表可用时传送。此提示不代表手表已经收到。")) }
            }
            Section(L10n.tr("添加表盘组件")) {
                Text(L10n.tr("在 Apple Watch 长按表盘 → 编辑 → 复杂功能 → 选择 OpenIntake 的补水或营养。支持圆形、矩形、行内和角落位置；可用位置取决于表盘。"))
                Text(L10n.tr("手表和组件会显示数据更新时间。跨日或时区变化后，在收到当天数据前显示 —，不会把昨天的数据当作今天。"))
            }
        }.navigationTitle("Apple Watch")
    }
}
extension View {
    @ViewBuilder func intakeGlass() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .capsule) }
        else { self.background(.regularMaterial, in: Capsule()) }
    }
}
