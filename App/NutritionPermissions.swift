import SwiftUI
import HealthKit

struct NutritionPermissions: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    var initialSelection: Set<Nutrient>? = nil
    var requestOnOpen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = Set<Nutrient>()
    @State private var statuses: [Nutrient: HKAuthorizationStatus] = [:]
    @State private var available = Set<Nutrient>()
    @State private var requesting = false
    @State private var message: String?
    @State private var writer: HealthWriter?
    @State private var showRecovery = false
    @State private var didRequestOnOpen = false
    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("营养写入权限")) {
                    Text(L10n.tr("勾选的是本次申请的类型，不是系统权限开关。实际授权状态显示在每项名称下方；这里只管理权限，不记录摄入。")).font(.callout)
                    Button(L10n.tr("选择当前产品和待同步记录涉及的类型")) {
                        selected = Set(HealthAccessPlan.suggested(products: store.library.products, events: store.library.events)).intersection(available)
                        if selected.isEmpty { message = L10n.tr("当前没有可写项目。请先核对下方产品映射，或手动选择你需要的类型。") }
                    }
                    Button(L10n.tr("选择全部 39 种营养类型")) { selected = available }
                    Button(L10n.tr("取消选择")) { selected = [] }
                    Button(requesting ? L10n.tr("正在申请…") : L10n.tr("申请所选 \(selected.count) 项写入权限")) { Task { await request() } }
                        .buttonStyle(.borderedProminent).disabled(selected.isEmpty || requesting)
                    if let message { Text(L10n.diagnostic(message)).font(.callout) }
                    Button(L10n.tr("已关闭权限？查看重新开启步骤")) { refresh(); showRecovery = true }
                    Button(L10n.tr("刷新实际授权状态")) { refresh(); message = L10n.tr("已重新读取 Apple 健康写入权限。") }
                    Text(L10n.tr("已允许或已拒绝的类型，系统可能不再弹窗。拒绝后请到 Apple 健康的个人资料 → App／数据访问权限 → OpenIntake 修改；不同系统菜单名称可能不同。")).font(.footnote).foregroundStyle(.secondary)
                }
                Section(L10n.tr("勾选要申请的类型 · 下方为实际写入状态")) {
                    ForEach(Nutrient.allCases, id: \.self) { nutrient in
                        Button {
                            if selected.contains(nutrient) { selected.remove(nutrient) } else { selected.insert(nutrient) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(L10n.display(nutrient.title)).foregroundStyle(.primary)
                                    Text(title(nutrient)).font(.caption).foregroundStyle(statuses[nutrient] == .sharingDenied ? .orange : .secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(nutrient) ? "checkmark.circle.fill" : "circle")
                            }
                        }.disabled(!available.contains(nutrient))
                            .accessibilityLabel("\(L10n.display(nutrient.title))，\(title(nutrient))，\(selected.contains(nutrient) ? L10n.tr("已选入本次申请") : L10n.tr("未选入本次申请"))")
                    }
                }
                Section(L10n.tr("产品是否有可写项目")) {
                    ForEach(store.library.products) { product in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(product.name).font(.headline)
                            Text(L10n.diagnostic(HealthAccessPlan.explanation(for: product))).font(.footnote)
                        }
                    }
                    Text(L10n.tr("权限与成分映射是两回事。保存产品不会写入；历史“仅本机”记录不会因授权或修改产品而自动补写。")).font(.footnote)
                }
            }
            .disabled(requesting)
            .navigationTitle(L10n.tr("营养写入权限"))
            .toolbar { Button(L10n.tr("完成")) { dismiss() }.disabled(requesting) }
            .onAppear {
                if writer == nil { writer = HealthWriter() }
                refresh()
                selected = (initialSelection ?? Set(HealthAccessPlan.suggested(products: store.library.products, events: store.library.events))).intersection(available)
                if requestOnOpen && !didRequestOnOpen && !selected.isEmpty {
                    didRequestOnOpen = true
                    Task { await request() }
                }
            }
            .onChange(of: scenePhase) { if scenePhase == .active { refresh(); message = nil } }
            .alert(L10n.tr("重新开启健康写入权限"), isPresented: $showRecovery) {
                Button(L10n.tr("知道了"), role: .cancel) { }
            } message: {
                Text(L10n.tr("打开 Apple 健康 → 点击个人头像 → App／数据访问权限 → OpenIntake → 开启需要的写入类型。不同系统菜单名称可能不同。\n\n已关闭的类型不能由 App 自行重新开启。完成后返回这里会自动刷新，也可点“刷新实际授权状态”。授权不会自动补写摄入；待同步记录需主动重试。"))
            }
        }
    }
    private func refresh() {
        guard let writer else { return }
        var values: [Nutrient: HKAuthorizationStatus] = [:]
        for nutrient in Nutrient.allCases { values[nutrient] = writer.authorization(for: nutrient) }
        statuses = values; available = Set(values.keys)
    }
    private func title(_ nutrient: Nutrient) -> String {
        guard let status = statuses[nutrient] else { return L10n.tr("此设备健康数据或类型不可用") }
        switch status {
        case .notDetermined: return L10n.tr("尚未申请写入")
        case .sharingAuthorized: return L10n.tr("已允许写入")
        case .sharingDenied: return L10n.tr("未允许写入 · 请在 Apple 健康修改")
        @unknown default: return L10n.tr("状态未知")
        }
    }
    private func request() async {
        guard let writer else { return }
        requesting = true; defer { requesting = false }
        let types = Nutrient.allCases.filter { selected.contains($0) }
        do {
            refresh()
            let requestStatus = try await writer.requestStatus(types)
            if requestStatus == .unnecessary {
                if types.contains(where: { statuses[$0] == .sharingDenied }) {
                    message = L10n.tr("所选类型中有已关闭权限；系统不会再次弹出授权窗口。请按步骤在 Apple 健康重新开启。")
                    showRecovery = true
                } else {
                    message = L10n.tr("所选类型已处理，无需重复弹窗。请查看各项实际写入状态。")
                }
                return
            }
            try await writer.requestAccess(types); refresh()
            let granted = types.filter { statuses[$0] == .sharingAuthorized }.count
            message = L10n.tr("所选 \(types.count) 项：已允许 \(granted)，未允许 \(types.count - granted)。尚未写入任何摄入记录。")
            if types.contains(where: { statuses[$0] == .sharingDenied }) { showRecovery = true }
        } catch { refresh(); message = L10n.tr("权限申请未完成：") + error.localizedDescription }
    }
}
