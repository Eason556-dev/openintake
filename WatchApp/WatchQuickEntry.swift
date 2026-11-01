import SwiftUI
import WatchKit
import WatchConnectivity

struct WatchQuickEntry: View {
    @ObservedObject var store: WatchStore
    var body: some View {
        List {
            NavigationLink(L10n.tr("饮水")) { WatchQuantityEntry(store: store, product: nil) }
            ForEach(store.products) { product in
                NavigationLink(product.name) { WatchQuantityEntry(store: store, product: product) }
            }
            Text(L10n.tr("新产品请在 iPhone 添加。此处仅记录已配置产品的实际摄入。")).font(.caption2)
        }.navigationTitle(L10n.tr("记录摄入"))
    }
}
struct WatchQuantityEntry: View {
    @ObservedObject var store: WatchStore
    let product: WatchProduct?
    @State private var quantity: Double = 250
    @State private var submitted = false
    var unit: String { product?.unit ?? "mL" }
    var body: some View {
        Form {
            Text(product?.name ?? L10n.tr("饮水"))
            TextField(L10n.tr("实际数量"), value: $quantity, format: .number)
            Stepper(value: $quantity, in: 1...10000, step: unit == "mL" || unit == "g" ? 50 : 1) {
                Text("\(quantity.formatted()) \(L10n.display(unit))")
            }
            Button(L10n.tr("确认并记录")) {
                let before = store.outbox.items.count
                store.record(product: product, quantity: quantity)
                submitted = store.outbox.items.count > before
            }.disabled(submitted || !quantity.isFinite || quantity <= 0)
            if submitted { Text(L10n.tr("已保存在手表，正在自动同步")).font(.caption) }
            if let status = store.status { Text(L10n.diagnostic(status)).font(.caption2) }
        }.onAppear { if !submitted { quantity = product?.quantity ?? 250 } }
    }
}
struct WatchPendingView: View {
    @ObservedObject var store: WatchStore
    var body: some View {
        List {
            ForEach(store.outbox.items) { item in
                VStack(alignment: .leading) {
                    Text(item.name)
                    Text("\(item.request.quantity.formatted()) \(L10n.display(item.request.unit))")
                    if let rejection = item.rejection {
                        Text(L10n.tr("未记录：请在 iPhone 检查重复记录或产品变更，再重新选择产品。")).font(.caption2)
                        Text(rejection).font(.caption2).foregroundStyle(.secondary)
                        Button(L10n.tr("移除失败请求")) { store.dismissRejected(item.id) }
                    } else { Text(L10n.tr("等待 iPhone 确认，不计入今日总量")).font(.caption2) }
                }
            }
        }.navigationTitle(L10n.tr("待同步"))
    }
}
/// Complete connectivity refresh tasks only once WC has drained pending content.
@MainActor final class WatchBackgroundDelegate: NSObject, WKApplicationDelegate {
    private var tasks: Set<WKWatchConnectivityRefreshBackgroundTask> = []
    private var completionTask: Task<Void, Never>?
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask { tasks.insert(connectivity) }
            else { task.setTaskCompletedWithSnapshot(false) }
        }
        guard completionTask == nil else { return }
        completionTask = Task {
            // Give delegate deliveries time to persist before completing background execution.
            repeat { try? await Task.sleep(for: .milliseconds(200)) }
            while WCSession.default.activationState != .activated || WCSession.default.hasContentPending
            for task in tasks { task.setTaskCompletedWithSnapshot(false) }
            tasks.removeAll(); completionTask = nil
        }
    }
}
