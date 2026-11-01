import SwiftUI
import UserNotifications

@MainActor enum WaterNotifications {
    static let prefix = "org.openintake.water."
    static func configure(enabled: Bool, start: Int, end: Int, interval: Int) async throws {
        let center = UNUserNotificationCenter.current()
        if enabled {
            try await IntakeNotifications.request()
        }
        let hours = try WaterReminderPlan.hours(start: start, end: end, interval: interval)
        let ids = (0...23).map { prefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }
        do {
            for hour in hours {
                let content = UNMutableNotificationContent(); content.title = L10n.tr("喝水时间"); content.body = L10n.tr("按需喝水，喝完后请在 OpenIntake 记录实际毫升数。"); content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
                try await center.add(UNNotificationRequest(identifier: prefix + String(hour), content: content, trigger: trigger))
            }
        } catch { center.removePendingNotificationRequests(withIdentifiers: ids); throw error }
    }
}
struct WaterCard: View {
    @ObservedObject var store: IntakeStore
    @AppStorage("waterGoalML") private var goal = 2000.0
    var openSettings: () -> Void
    @State private var custom = 250.0
    var body: some View {
        Section(L10n.tr("今日饮水")) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let progress = HydrationProgress(events: store.library.events, goal: goal, date: context.date)
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(.blue.opacity(0.15), lineWidth: 10)
                        Circle().trim(from: 0, to: progress.fraction).stroke(.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: "drop.fill").foregroundStyle(.blue).font(.title)
                    }.frame(width: 112, height: 112).accessibilityLabel(L10n.tr("饮水目标完成 \(Int(progress.fraction * 100))%"))
                    VStack(alignment: .leading) {
                        Text("\(progress.milliliters, specifier: "%.0f") / \(progress.goal, specifier: "%.0f") mL").font(.headline)
                        Text(L10n.tr("本 App 今日记录；目标由你设定")).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.tr("目标与提醒")) { openSettings() }
                    }
                }.padding(.vertical, 6)
            }
            HStack {
                ForEach([150.0, 250, 500], id: \.self) { amount in
                    Button("+\(Int(amount)) mL") { record(amount) }.buttonStyle(.bordered)
                }
            }
            HStack {
                TextField(L10n.tr("自定义毫升"), value: $custom, format: .number).keyboardType(.decimalPad)
                Button(L10n.tr("记录饮水")) { record(custom) }.disabled(!custom.isFinite || custom <= 0 || custom > 10000)
            }
        }
    }
    private func record(_ amount: Double) {
        Task { do { try await store.logUnits(HydrationProgress.product(), units: amount) } catch { store.message = error.localizedDescription } }
    }
}
struct WaterSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("waterGoalML") private var savedGoal = 2000.0
    @AppStorage("waterReminderEnabled") private var savedEnabled = false
    @AppStorage("waterReminderStart") private var savedStart = 8
    @AppStorage("waterReminderEnd") private var savedEnd = 20
    @AppStorage("waterReminderInterval") private var savedInterval = 2
    @State private var goal = 2000.0
    @State private var enabled = false
    @State private var start = 8
    @State private var end = 20
    @State private var interval = 2
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                NotificationAccessSection()
                Section(L10n.tr("个人目标")) {
                    TextField(L10n.tr("每日目标 mL"), value: $goal, format: .number).keyboardType(.decimalPad)
                    Text(L10n.tr("初始值仅为可编辑的记录目标，不是医学饮水建议。")).font(.footnote)
                }
                Section(L10n.tr("本机提醒")) {
                    Toggle(L10n.tr("定时提醒"), isOn: $enabled)
                    Stepper(L10n.tr("开始：\(start):00"), value: $start, in: 0...23)
                    Stepper(L10n.tr("结束：\(end):00"), value: $end, in: start...23)
                    Stepper(L10n.tr("每 \(interval) 小时"), value: $interval, in: 1...12)
                    Text(L10n.tr("按所选时段每天定时提醒；达到目标后仍按计划提醒。系统专注模式、通知设置可能影响送达。不需要服务器。")).font(.footnote)
                }
                if let error { Text(L10n.diagnostic(error)).foregroundStyle(.red) }
            }.disabled(saving)
            .onChange(of: start) { end = max(start, end) }
            .onAppear { goal = savedGoal; enabled = savedEnabled; start = savedStart; end = savedEnd; interval = savedInterval }
            .onDisappear { WatchDashboardBridge.shared.publish(events: IntakeStore.shared.library.events) }
            .navigationTitle(L10n.tr("饮水设置"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) { Task {
                    saving = true; defer { saving = false }
                    do {
                        try await WaterNotifications.configure(enabled: enabled, start: start, end: end, interval: interval)
                        savedGoal = goal; savedEnabled = enabled; savedStart = start; savedEnd = end; savedInterval = interval; dismiss()
                    } catch {
                        // Failed rescheduling removes partial notifications; don't claim reminders remain on.
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0...23).map { WaterNotifications.prefix + String($0) })
                        savedEnabled = false; self.error = error.localizedDescription
                    }
                } }.disabled(saving || !goal.isFinite || goal <= 0 || goal > 20000) }
            }
        }
    }
}
