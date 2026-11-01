import SwiftUI
import AppIntents

struct SystemActionsGuide: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    @AppStorage("widgetFavoriteID") private var widgetFavoriteID = ""
    @State private var widgetQuantity: Double?
    @State private var widgetMessage: String?
    private var widgetProducts: [Product] { store.library.products.filter { $0.kind == .supplement || $0.manualNutrition != nil } }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("直接运行记录流程")) {
                    Button { store.captureMenuRequested = true } label: { Label(L10n.tr("选择并记录摄入"), systemImage: "play.circle.fill") }
                        .buttonStyle(.borderedProminent)
                    Text(L10n.tr("运行后从列表选择一项：喝水、补充剂按粒／份、饮料食品、文字餐食或拍照餐食。按提示填数量；文字／照片先核对草稿再确认。"))
                    Text(L10n.tr("在快捷指令中只添加一个‘选择并记录摄入’动作即可获得同样的交互流程，也可绑定操作按钮。不要把所有记录动作顺序串联。"))
                }
                Section(L10n.tr("添加系统小组件")) {
                    Text(L10n.tr("长按 iPhone 主屏幕 → 编辑 → 添加小组件 → 搜索 OpenIntake。"))
                    Text(L10n.tr("快速饮水：实际喝下后点 150 或 250 mL。常用产品：在下方选择产品和实际数量，再添加小组件。饮料用 mL，食品用 g，补充剂以显示的粒／份为准。"))
                    Text(L10n.tr("小组件会打开 App 完成记录与健康核验。请先解锁；产品列表为空时先打开 App。列表会随系统刷新。"))
                }
                Section(L10n.tr("常用产品小组件设置")) {
                    Picker(L10n.tr("产品"), selection: $widgetFavoriteID) {
                        Text(L10n.tr("自动使用首个产品")).tag("")
                        ForEach(widgetProducts) { Text($0.name + " · " + $0.intakeUnitTitle).tag($0.id.uuidString) }
                    }
                    TextField(L10n.tr("实际数量（留空用包装常用量）"), value: $widgetQuantity, format: .number).keyboardType(.decimalPad)
                    Text(L10n.tr("小号和中号共用此设置。按钮会显示实际数量及单位；请按真实用量设置。旧版空白产品组件请移除后重新添加。")).font(.caption)
                    Button(L10n.tr("更新小组件")) {
                        UserDefaults.standard.set(widgetQuantity ?? 0, forKey: "widgetFavoriteQuantity")
                        let selected = widgetProducts.first { $0.id.uuidString == widgetFavoriteID } ?? widgetProducts.first
                        UserDefaults.standard.set(selected?.intakeUnitTitle, forKey: "widgetFavoriteUnit")
                        WidgetPublisher.refresh(products: store.library.products)
                        widgetMessage = WidgetCatalog.url == nil ? L10n.tr("产品共享尚未连接，请检查两目标的 App Group 签名。") : L10n.tr("已请求更新，系统决定刷新时间。")
                    }.disabled(widgetQuantity.map { !$0.isFinite || $0 <= 0 } ?? false)
                    if let widgetMessage { Text(widgetMessage).font(.caption) }
                }
                Section(L10n.tr("快捷指令／操作按钮／Siri")) {
                    ShortcutsLink()
                    Text(L10n.tr("打开快捷指令 → 新建 → 添加操作 → 搜索 OpenIntake，选择记录饮水、补充剂服用粒数或饮料食品实际数量。固定常用数量，或把数量设为每次询问。"))
                    Text(L10n.tr("补充剂：先在 App 保存并确认产品。按粒数记录需已确认每份粒数；否则使用按份动作。饮料食品：先创建标签模板，再输入实际 mL／g。"))
                    Text(L10n.tr("操作按钮：iPhone 设置 → 操作按钮 → 快捷指令 → 选择刚创建的流程。Siri 可运行你为该快捷指令起的名称。"))
                }
                Section(L10n.tr("拍照餐食 → 校准 → 确认")) {
                    Text(L10n.tr("快捷指令可将照片传给“参考餐食照片并手动记录”。照片仅供本页核对；手动填写实际数量与已知营养后确认，不会自动识别。"))
                }
                Section(L10n.tr("如何确认已同步")) {
                    Text(L10n.tr("只有显示‘已写入并核验 Apple 健康’才代表本次样本核验通过。权限关闭或写入失败会保留本机待同步记录，可在同步中心重试。保存产品、编辑小组件和拍照都不代表实际摄入。"))
                    Text(L10n.tr("动作可能打开 App 或要求解锁；系统小组件不保证即时刷新。误点可在最近摄入左滑撤销，也可恢复。重复触发仍受现有重复记录检测保护。"))
                }
            }.onAppear {
                let value = UserDefaults.standard.double(forKey: "widgetFavoriteQuantity")
                widgetQuantity = value > 0 && value.isFinite ? value : nil
            }.onChange(of: widgetFavoriteID) { widgetQuantity = nil; UserDefaults.standard.removeObject(forKey: "widgetFavoriteQuantity"); WidgetPublisher.refresh(products: store.library.products) }
            .navigationTitle(L10n.tr("小组件与快捷指令")).toolbar { Button(L10n.tr("完成")) { dismiss() } }
        }
    }
}
