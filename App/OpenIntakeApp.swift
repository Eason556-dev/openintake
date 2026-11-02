import SwiftUI
import UIKit
import UserNotifications
@main struct OpenIntakeApp: App {
    @AppStorage(L10n.preferenceKey) private var language = "system"
    init() {
        _ = WatchDashboardBridge.shared // Activate for background WatchConnectivity delivery.
        UNUserNotificationCenter.current().delegate = IntakeNotificationDelegate.shared
        if ProcessInfo.processInfo.arguments.contains("--healthkit-catalog-audit") { AppleNutritionCatalog.printAudit() }
    }
    var body: some Scene { WindowGroup { HomeView(store: .shared).environment(\.locale, Locale(identifier: L10n.resolved(language))) } }
}
struct HomeView: View {
    @ObservedObject var store: IntakeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: Product?
    @State private var showNew = false
    @State private var showManualFood = false
    @State private var editingFood: Product?
    @State private var showSalt = false
    @State private var showHealthCatalog = false
    @State private var showSync = false
    @State private var showPermissions = false
    @State private var focusedHealthTypes: Set<Nutrient>?
    @State private var accessRefresh = UUID()
    @State private var showWaterSettings = false
    @State private var showReminders = false
    @State private var showSystemActions = false
    @State private var captureMenuVisible = false
    @State private var presentedMeal: MealRequest?
    @State private var routeTask: Task<Void, Never>?
    @AppStorage(L10n.preferenceKey) private var language = "system"
    @State private var tab = 0
    @State private var quantities: [UUID: Double] = [:]
    var body: some View {
        TabView(selection: $tab) {
            nutritionPage.tabItem { Label(L10n.tr("营养"), systemImage: "leaf.fill") }.tag(0)
            hydrationPage.tabItem { Label(L10n.tr("补水"), systemImage: "drop.fill") }.tag(1)
            settingsPage.tabItem { Label(L10n.tr("设置"), systemImage: "gearshape.fill") }.tag(2)
        }
            .tint(tab == 1 ? .cyan : .green)
            .environment(\.locale, L10n.locale)
            .disabled(store.busy)
             .task {
                ShortcutIndex.refresh()
                await Task.yield()
                #if DEBUG && targetEnvironment(simulator)
                if scenePhase == .active && !ProcessInfo.processInfo.arguments.contains("--localization-ui-audit") { await store.requestInitialHealthAccess() }
                #else
                if scenePhase == .active { await store.requestInitialHealthAccess() }
                #endif
                #if DEBUG
                #if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--meal-review-ui-audit") { store.mealRequest = MealRequest() }
                #endif
                #endif
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--startup-audit") {
                    FileHandle.standardOutput.write(Data("OPENINTAKE_UI_READY\n".utf8))
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    if store.loadError != nil { store.reload() }
                    store.scheduleAutomaticSync()
                    WidgetPublisher.refresh(products: store.library.products)
                    WatchDashboardBridge.shared.publish(events: store.library.events)
                    Task { await store.requestInitialHealthAccess() }
                }
            }
            .sheet(isPresented: $showManualFood) { ManualNutritionEditor(store: store) }
            .sheet(item: $editingFood) { product in ManualNutritionEditor(store: store, original: product) }
            .sheet(isPresented: $showSalt) { SaltEntry(store: store) }
            .sheet(isPresented: $showReminders) { ReminderSettings(store: store) }
            .sheet(isPresented: $showWaterSettings) { WaterSettings() }
            .sheet(isPresented: $showSystemActions) { SystemActionsGuide(store: store) }
            .onAppear { WidgetPublisher.refresh(products: store.library.products); WatchDashboardBridge.shared.publish(events: store.library.events) }
            .sheet(isPresented: $showPermissions, onDismiss: { accessRefresh = UUID() }) { NutritionPermissions(store: store, initialSelection: focusedHealthTypes, requestOnOpen: focusedHealthTypes != nil) }
            .sheet(isPresented: $showSync, onDismiss: { accessRefresh = UUID() }) { SyncCenter(store: store) }
            .sheet(isPresented: $captureMenuVisible, onDismiss: { store.captureMenuRequested = false }) { CaptureWorkflowView(store: store) }
            .sheet(item: $presentedMeal, onDismiss: { store.mealRequest = nil }) { request in MealEditor(store: store, request: request) }
            .onChange(of: language) { WatchDashboardBridge.shared.publish(events: store.library.events) }
            .onChange(of: store.mealRequest?.id) { if store.mealRequest != nil { routeCapture() } }
            .onChange(of: store.captureMenuRequested) { if store.captureMenuRequested { routeCapture() } }
            .onAppear { if store.mealRequest != nil || store.captureMenuRequested { routeCapture() } }
            .sheet(isPresented: $showHealthCatalog) { NutritionCatalogView() }
            .sheet(isPresented: $showNew) { ProductEditor(store: store, product: Product(name: "")) }
            .sheet(item: $editing) { product in ProductEditor(store: store, product: product) }
    }
    private var nutritionPage: some View {
        NavigationStack {
            List {
                status
                Section { NutritionOverview(store: store).listRowSeparator(.hidden) }
                HStack {
                    Button { showNew = true } label: { Label(L10n.tr("扫描标签"), systemImage: "viewfinder").padding(12).frame(maxWidth: .infinity) }.intakeGlass()
                    Button { store.mealRequest = MealRequest() } label: { Label(L10n.tr("记录餐食"), systemImage: "fork.knife").padding(12).frame(maxWidth: .infinity) }.intakeGlass()
                }.buttonStyle(.plain).listRowBackground(Color.clear)
                Section(L10n.tr("饮料与食品 · 实际摄入后记录")) {
                    Button(L10n.tr("添加饮料／食品模板"), systemImage: "plus") { showManualFood = true }
                    Button(L10n.tr("记录普通食盐（估算钠）"), systemImage: "scalemass") { showSalt = true }
                    ForEach(store.library.products.filter { $0.manualNutrition != nil }) { product in
                        ManualFoodRow(store: store, product: product) { editingFood = product }
                    }
                }
                Section(L10n.tr("补充剂 · 实际服用后记录")) {
                    ForEach(store.library.products.filter { $0.manualNutrition == nil }) { product in
                        VStack(alignment: .leading, spacing: 8) {
                            Button(product.name) { editing = product }
                            Text(L10n.tr("标签每份：\(product.serving)")).font(.caption).foregroundStyle(.secondary)
                            if MappingPresentation.needsBroadConsent(product) {
                                Text(L10n.tr("Omega-3 可写入“多不饱和脂肪”，尚待确认。")).font(.caption).foregroundStyle(.orange)
                                Button(L10n.tr("确认 Apple 健康映射")) { editing = product }
                            }
                            HStack {
                                Stepper("\(quantities[product.id, default: product.defaultIntakeQuantity], specifier: "%.2g") \(L10n.display(product.intakeUnitTitle))", value: Binding(get: { quantities[product.id, default: product.defaultIntakeQuantity] }, set: { quantities[product.id] = $0 }), in: 0.25...(product.defaultIntakeQuantity == 100 ? 1000 : 20), step: product.defaultIntakeQuantity == 100 ? 1 : 0.25)
                                Button(L10n.tr("记录并同步")) { Task { do {
                                    try await store.logUnits(product, units: quantities[product.id, default: product.defaultIntakeQuantity])
                                } catch { store.message = error.localizedDescription } } }.buttonStyle(.borderedProminent)
                            }
                        }.swipeActions { Button(L10n.tr("移除产品"), role: .destructive) { do { try store.removeProduct(product.id) } catch { store.message = error.localizedDescription } } }
                    }
                }
            }.navigationTitle(L10n.tr("营养"))
                .scrollContentBackground(.hidden)
                .background(Color.green.opacity(0.04))
        }
    }
    private var hydrationPage: some View {
        NavigationStack {
            List {
                status
                WaterCard(store: store) { showWaterSettings = true }
                Section {
                    Text(L10n.tr("实际喝下后记录。每次摄入都会保存在本机，并通过原有队列同步 Apple 健康。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle(L10n.tr("补水"))
                .scrollContentBackground(.hidden).background(Color.cyan.opacity(0.04))
        }
    }
    private var settingsPage: some View {
        NavigationStack {
            List {
                Section(L10n.tr("记录与同步")) {
                    NavigationLink { RecordHistory(store: store) } label: { Label(L10n.tr("记录管理"), systemImage: "clock.arrow.circlepath") }
                    Button { showSync = true } label: { Label(L10n.tr("Apple 健康同步"), systemImage: "heart.text.clipboard") }
                    Button(L10n.tr("营养写入权限")) { focusedHealthTypes = nil; showPermissions = true }
                    Button(L10n.tr("Apple 健康营养类型完整清单")) { showHealthCatalog = true }
                }
                Section(L10n.tr("个人设置")) {
                    NavigationLink { GoalSettings(store: store) } label: { Label(L10n.tr("目标与限量"), systemImage: "target") }
                    Button(L10n.tr("饮水目标与提醒")) { showWaterSettings = true }
                    Button(L10n.tr("通知与服用提醒")) { showReminders = true }
                    NavigationLink { LanguageSettings(store: store) } label: { Label(L10n.tr("语言"), systemImage: "globe") }
                }
                Section(L10n.tr("系统与设备")) {
                    Button(L10n.tr("小组件与快捷指令")) { showSystemActions = true }
                    NavigationLink { WatchSettings(store: store) } label: { Label("Apple Watch", systemImage: "applewatch") }
                    NavigationLink { FoodReferenceInformation() } label: { Label(L10n.tr("离线食物资料与许可"), systemImage: "books.vertical") }
                    NavigationLink { ExternalInformationGuide() } label: { Label(L10n.tr("借助外部工具核对"), systemImage: "questionmark.circle") }
                    Text(L10n.tr("离线记录 · 无账号 · 无内置 AI")).font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle(L10n.tr("设置"))
        }
    }
    @ViewBuilder private var status: some View {
        if let message = store.message { Text(L10n.diagnostic(message)).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
        if let error = store.loadError {
            Text(L10n.diagnostic(error)).foregroundStyle(.red)
            Button(L10n.tr("解锁后重新读取资料库")) { store.reload() }
        }
    }
    private func routeCapture() {
        routeTask?.cancel()
        showSystemActions = false; showNew = false; editing = nil; editingFood = nil
        showManualFood = false; showSalt = false; showReminders = false; showWaterSettings = false
        showPermissions = false; showSync = false; showHealthCatalog = false
        if store.mealRequest != nil { captureMenuVisible = false }
        routeTask = Task { @MainActor in
            // Allow any existing sheet to finish dismissing before presenting the requested workflow.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if let request = store.mealRequest { presentedMeal = request }
            else if store.captureMenuRequested { captureMenuVisible = true }
        }
    }
    func stateTitle(_ state: SyncState) -> String {
        switch state { case .pending: L10n.tr("待同步"); case .synced: L10n.tr("已同步"); case .localOnly: L10n.tr("已记录本机（无健康映射）"); case .deletionPending: L10n.tr("待撤销"); case .deleted: L10n.tr("已撤销") }
    }
}
