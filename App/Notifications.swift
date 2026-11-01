import SwiftUI
import UserNotifications
import UIKit

/// One shared delegate must be retained; local reminders also display while the app is open.
final class IntakeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = IntakeNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }
}
@MainActor enum IntakeNotifications {
    static let key = "supplementReminders.v1"
    static func request() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied { throw NotificationAccessError.message(L10n.tr("通知已被关闭，请点击“系统通知设置”开启。")) }
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral { return }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NotificationAccessError.message(L10n.tr("通知未获允许；提醒尚未启用。")) }
    }
    /// Replace text only on existing recurring requests; do not request permissions or change schedules.
    static func refreshLanguage() async throws {
        let center = UNUserNotificationCenter.current()
        for request in await center.pendingNotificationRequests() {
            guard request.identifier.hasPrefix(WaterNotifications.prefix) || request.identifier.hasPrefix("org.openintake.supplement."),
                  request.trigger is UNCalendarNotificationTrigger,
                  let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            content.title = L10n.diagnostic(content.title)
            content.body = L10n.diagnostic(content.body)
            try await center.add(.init(identifier: request.identifier, content: content, trigger: request.trigger))
        }
    }
    static var reminders: [SupplementReminder] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SupplementReminder].self, from: data)) ?? []
    }
    static func remove(_ productID: UUID) {
        let id = SupplementReminder(productID: productID, hour: 0, minute: 0).identifier
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        save(reminders.filter { $0.productID != productID })
    }
    private static func save(_ values: [SupplementReminder]) {
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func configure(_ plan: SupplementReminder, product: Product, enabled: Bool) async throws {
        try plan.validate()
        guard plan.productID == product.id else { throw IntakeError.invalidProduct }
        guard enabled else { remove(product.id); return }
        guard product.kind != .medication else { throw IntakeError.invalidProduct }
        var values = reminders.filter { $0.productID != product.id }
        // At most 24 water + 30 supplement + one test request, below the system pending limit.
        guard values.count < 30 else { throw NotificationAccessError.message(L10n.tr("最多启用 30 个产品提醒，请先关闭不需要的提醒。")) }
        try await request()
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("补充剂提醒")
        content.body = L10n.tr("\(product.name)：请按你确认的计划服用；实际服用后再打开 OpenIntake 记录。")
        content.sound = .default
        try await UNUserNotificationCenter.current().add(.init(identifier: plan.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: plan.hour, minute: plan.minute), repeats: true)))
        values.append(plan); save(values)
    }
    static func test() async throws {
        try await request()
        let content = UNMutableNotificationContent(); content.title = L10n.tr("OpenIntake 提醒测试"); content.body = L10n.tr("本机通知已送达。此测试不会记录任何摄入。"); content.sound = .default
        try await UNUserNotificationCenter.current().add(.init(identifier: "org.openintake.notification-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
}
struct NotificationAccessSection: View {
    @Environment(\.scenePhase) private var phase
    @State private var status = L10n.tr("正在检查…")
    @State private var pending = 0
    @State private var message: String?
    @State private var authorization: UNAuthorizationStatus?
    @State private var working = false
    var body: some View {
        Section(L10n.tr("系统通知")) {
            Text(L10n.diagnostic(status))
            Text(L10n.tr("当前排队的本机提醒：\(pending) 个")).font(.caption)
            Button(authorization == .denied ? L10n.tr("重新开启通知（前往系统设置）") : authorization == .notDetermined ? L10n.tr("允许通知") : L10n.tr("检查／调整通知权限")) {
                Task { await enable() }
            }.disabled(working || authorization == nil)
            Button(L10n.tr("发送测试提醒（5 秒后）")) { Task {
                guard !working else { return }; working = true; defer { working = false }
                do { try await IntakeNotifications.test(); message = L10n.tr("已安排测试；5 秒后查看横幅或通知中心。") } catch { message = error.localizedDescription }; await refresh()
            } }.disabled(working)
            Button(L10n.tr("系统通知设置")) { Task { await openSettings() } }.disabled(working)
            Text(L10n.tr("如果系统未定位到本 App，请手动打开“设置 → 通知 → OpenIntake → 允许通知”。返回后自动刷新状态；设置提醒仍需保存。")).font(.footnote).foregroundStyle(.secondary)
            if let message { Text(L10n.diagnostic(message)).font(.footnote) }
            Text(L10n.tr("通知授权与 Apple 健康授权相互独立。提醒只通知，不代表已服用，不会自动写入健康。专注模式、静音和系统通知设置可能影响展示。")).font(.footnote)
        }.task { await refresh() }.onChange(of: phase) { if phase == .active { message = nil; Task { await refresh() } } }
    }
    private func enable() async {
        guard !working else { return }; working = true; defer { working = false }
        // Read again at tap time: a settings change may have happened since the view appeared.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { try await IntakeNotifications.request(); message = L10n.tr("已更新通知权限。") }
            catch { message = error.localizedDescription }
            await refresh()
        } else {
            await openSettings()
        }
    }
    private func openSettings() async {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString),
           await UIApplication.shared.open(url, options: [:]) { return }
        if let url = URL(string: UIApplication.openSettingsURLString),
           await UIApplication.shared.open(url, options: [:]) { return }
        message = L10n.tr("无法打开系统设置。请手动打开“设置 → 通知 → OpenIntake”，开启“允许通知”，再返回 App。")
    }
    private func refresh() async {
        let center = UNUserNotificationCenter.current(), settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .notDetermined: status = L10n.tr("尚未授权：请点击“允许通知”")
        case .denied: status = L10n.tr("系统通知已关闭：请前往系统设置开启")
        case .authorized, .provisional, .ephemeral: status = L10n.tr("通知已授权 · 横幅\(settings.alertSetting == .enabled ? L10n.tr("开启") : L10n.tr("关闭")) · 声音\(settings.soundSetting == .enabled ? L10n.tr("开启") : L10n.tr("关闭"))")
        @unknown default: status = L10n.tr("通知状态未知，请查看系统设置")
        }
        pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("org.openintake.") }.count
    }
}
struct ReminderSettings: View {
    @ObservedObject var store: IntakeStore
    @Environment(\.dismiss) private var dismiss
    @State private var revision = UUID()
    var body: some View {
        NavigationStack {
            Form {
                NotificationAccessSection().id(revision)
                Section(L10n.tr("补充剂 · 每天一次的自定提醒")) {
                    if store.library.products.isEmpty { Text(L10n.tr("先添加产品，再设置提醒。")) }
                    ForEach(store.library.products.filter { $0.kind == .supplement }) { product in SupplementReminderRow(product: product) { revision = UUID() } }
                    Text(L10n.tr("时间由你设定，默认关闭；不会将瓶身建议用量自动设为服用计划。饮水提醒请在首页“目标与提醒”中开启。")).font(.footnote)
                }
            }.navigationTitle(L10n.tr("通知与服用提醒")).toolbar { Button(L10n.tr("完成")) { dismiss() } }
        }
    }
}
private struct SupplementReminderRow: View {
    let product: Product
    var onSaved: () -> Void
    @State private var enabled = false
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading) {
            Toggle(product.name, isOn: $enabled)
            if enabled { DatePicker(L10n.tr("每天提醒时间"), selection: $time, displayedComponents: .hourAndMinute) }
            Button(L10n.tr("保存此产品提醒")) { Task {
                saving = true; defer { saving = false }
                do {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    try await IntakeNotifications.configure(.init(productID: product.id, hour: c.hour ?? 9, minute: c.minute ?? 0), product: product, enabled: enabled)
                    onSaved()
                    message = enabled ? L10n.tr("已安排每日提醒") : L10n.tr("已关闭此产品提醒")
                } catch { message = error.localizedDescription }
            } }.disabled(saving)
            if let message { Text(L10n.diagnostic(message)).font(.caption) }
        }.disabled(saving).onAppear {
            if let plan = IntakeNotifications.reminders.first(where: { $0.productID == product.id }) {
                enabled = true; time = Calendar.current.date(from: DateComponents(hour: plan.hour, minute: plan.minute)) ?? Date()
            }
        }
    }
}

private enum NotificationAccessError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): return text } }
}
