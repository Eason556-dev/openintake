import SwiftUI

struct SyncCenter: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    @Environment(\.dismiss) private var dismiss
    @State private var permissions = false
    var body: some View {
        NavigationStack {
            List {
                let summary = SyncSummary(events: store.library.events)
                Section(L10n.tr("Apple 健康同步")) {
                    Text(L10n.tr("已写入 \(summary.synced) · 待同步 \(summary.pending) · 仅本机 \(summary.local) · 待撤销 \(summary.deleting)"))
                    Button(store.busy ? L10n.tr("正在同步…") : L10n.tr("同步待处理记录")) { Task { await store.retry() } }.disabled(store.busy || !summary.needsSync)
                    Button(L10n.tr("检查营养写入权限")) { permissions = true }
                    if let message = store.message { Text(L10n.diagnostic(message)).font(.callout) }
                    Text(L10n.tr("新版保存后会核对本 App 对应样本的数量、时间和来源，核验通过才标记成功；旧记录单独标明未核验。不读取其他来源的数据。")).font(.footnote)
                }
                ForEach(store.library.events) { event in
                    Section {
                        Text(event.product.displayName).font(.headline)
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                        Text(Self.title(event)).foregroundStyle(event.state == .pending || event.state == .deletionPending ? .orange : .secondary)
                        if let amounts = try? event.healthSamples, !amounts.isEmpty {
                            ForEach(amounts) { amount in Text("\(L10n.display(amount.nutrient.title))：\(amount.value * event.servings, specifier: "%.4g") \(amount.unit.rawValue)") }
                        } else { Text(L10n.diagnostic(MappingPresentation.localReason(event.product))).font(.caption) }
                        if let error = event.lastError { Text(L10n.diagnostic(error)).font(.caption).foregroundStyle(.red) }
                        if event.state != .deleted && event.state != .deletionPending {
                            Button(L10n.tr("撤销本次记录"), role: .destructive) { Task { do { try await store.undo(event.id) } catch { store.message = error.localizedDescription } } }.disabled(store.busy)
                        } else {
                            Button(event.state == .deleted ? L10n.tr("恢复记录") : L10n.tr("取消撤销并恢复")) {
                                Task { do { try await store.restore(event.id) } catch { store.message = error.localizedDescription } }
                            }.disabled(store.busy)
                        }
                    }
                }
                if store.library.events.isEmpty { Text(L10n.tr("还没有摄入记录。扫描并保存产品不会写入健康。")) }
            }.navigationTitle(L10n.tr("同步状态"))
                .toolbar { Button(L10n.tr("完成")) { dismiss() } }
                .sheet(isPresented: $permissions) { NutritionPermissions(store: store) }
        }
    }
    static func title(_ event: IntakeEvent) -> String {
        switch event.state {
        case .synced: event.healthVerifiedAt == nil ? L10n.tr("已提交 Apple 健康（旧版未做样本核验）") : L10n.tr("已写入并核验 Apple 健康")
        case .pending: L10n.tr("已保存本机 · 尚未同步")
        case .localOnly: L10n.tr("仅本机 · 没有启用可写入的营养项")
        case .deletionPending: L10n.tr("已申请撤销 · 等待删除健康样本")
        case .deleted: L10n.tr("已撤销")
        }
    }
}
