import Foundation
import SwiftUI

@MainActor
final class IntakeStore: ObservableObject {
    static let shared = IntakeStore()
    @Published private(set) var library = Library()
    @Published var message: String?
    @Published var mealRequest: MealRequest?
    @Published var captureMenuRequested = false
    @Published private(set) var busy = false
    @Published private(set) var loadError: String?
    private let url: URL
    private lazy var health = HealthWriter()
    private var attemptedInitialAccess = false
    private var automaticSyncTask: Task<Void, Never>?
    init() {
        url = URL.applicationSupportDirectory.appending(path: "OpenIntake/library.json")
        do {
            library = try LibraryRepository(url: url).load()
        } catch { loadError = "本地资料库无法读取，已停止写入以保护原始文件：\(L10n.diagnostic(error.localizedDescription))" }
    }
    /// Runs after the first foreground UI is ready, never from App.init.
    func requestInitialHealthAccess() async {
        let key = "nutritionHealthAccessRequested.v1"
        guard !attemptedInitialAccess, !UserDefaults.standard.bool(forKey: key), !busy,
              !ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("-audit") }) else { return }
        attemptedInitialAccess = true; busy = true; defer { busy = false }
        do {
            try await health.requestAccess(Nutrient.allCases)
            UserDefaults.standard.set(true, forKey: key)
            let granted = Nutrient.allCases.filter { health.authorization(for: $0) == .sharingAuthorized }.count
            message = "Apple 健康：已允许 \(granted)/39 项营养写入。授权不会产生摄入记录。"
        } catch { message = "Apple 健康连接未完成：\(L10n.diagnostic(error.localizedDescription))。请打开“营养写入权限”重试。" }
    }
    func reload() {
        guard !busy else { return }
        do { library = try LibraryRepository(url: url).load(); loadError = nil }
        catch { loadError = "本地资料库无法读取，已停止写入以保护原始文件：\(L10n.diagnostic(error.localizedDescription))" }
    }
    private func persist(_ value: Library) throws {
        guard loadError == nil else { throw CocoaError(.fileReadCorruptFile) }
        try LibraryRepository(url: url).save(value)
        library = value
        WatchDashboardBridge.shared.publish(events: library.events)
        scheduleAutomaticSync()
    }
    func save(_ product: Product) throws {
        guard !busy else { throw IntakeError.busy }
        try product.validate()
        var product = product
        product.revision = UUID() // Invalidate stale Watch recipes, including manual foods.
        var value = library
        if let i = value.products.firstIndex(where: { $0.id == product.id }) { value.products[i] = product }
        else { value.products.append(product) }
        try persist(value)
        ShortcutIndex.refresh()
        WidgetPublisher.refresh(products: library.products)
    }
    func removeProduct(_ id: UUID) throws {
        guard !busy else { throw IntakeError.busy }
        var value = library; value.products.removeAll { $0.id == id }; try persist(value)
        IntakeNotifications.remove(id)
        ShortcutIndex.refresh()
        WidgetPublisher.refresh(products: library.products)
    }
    func logQuick(productID: UUID?, quantity: Double, expectedUnit: String? = nil) async throws {
        let (product, units) = try QuickIntake.resolve(productID: productID, quantity: quantity, products: library.products, expectedUnit: expectedUnit)
        try await logUnits(product, units: units)
    }
    func logUnits(_ product: Product, units: Double) async throws {
        try await log(product, servings: product.servings(forUnits: units))
    }
    func editMeal(_ id: UUID, product: Product) async throws {
        guard !busy else { throw IntakeError.busy }; busy = true; defer { busy = false }
        var value = library; try value.editMeal(id, product: product); try persist(value)
        await sync(id)
    }
    func logMeal(_ product: Product, requestID: UUID, date: Date = Date()) async throws {
        // Durable request identity also protects reopening/retrying this same draft.
        try MealReviewState.validateRequest(requestID, events: library.events)
        var snapshot = product; snapshot.id = requestID
        try await log(snapshot, servings: 1, date: date)
    }
    func log(_ product: Product, servings: Double, date: Date = Date()) async throws {
        guard !busy else { throw IntakeError.busy }
        busy = true; defer { busy = false }
        let event = try IntakeEvent(product: product, servings: servings, date: date)
        var value = library; try value.enqueue(event)
        try persist(value) // durable outbox before any HealthKit write
        await sync(event.id)
    }
    /// The event ID and frozen recipe are committed together, before acknowledgement or HealthKit.
    func receiveWatch(_ request: WatchIntakeRequest) -> WatchReceipt {
        guard !busy, loadError == nil else { return .init(id: request.id, outcome: .retry) }
        do {
            var value = library
            if try WatchIntake.apply(request, to: &value) != nil { try persist(value) }
            scheduleAutomaticSync()
            return .init(id: request.id, outcome: .accepted)
        } catch let error as WatchIntakeError {
            return .init(id: request.id, outcome: .rejected, reason: error.rawValue)
        } catch is IntakeError {
            return .init(id: request.id, outcome: .rejected, reason: "invalid")
        } catch is QuickIntakeError {
            return .init(id: request.id, outcome: .rejected, reason: "changedProduct")
        } catch { return .init(id: request.id, outcome: .retry) } // Protected/unavailable disk: retain on Watch.
    }
    func scheduleAutomaticSync() {
        guard automaticSyncTask == nil else { return }
        automaticSyncTask = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                if !self.busy { await self.retryPendingAutomatically() }
                guard self.library.events.contains(where: { $0.state == .pending || $0.state == .deletionPending }) else { break }
                delay = min(delay * 2, 300)
            }
            self?.automaticSyncTask = nil
        }
    }
    private func retryPendingAutomatically() async {
        guard !busy, loadError == nil else { return }
        busy = true; health.allowsAuthorizationUI = false
        defer { busy = false; health.allowsAuthorizationUI = true }
        for id in library.events.filter({ $0.state == .pending || $0.state == .deletionPending }).map(\.id) { await sync(id) }
    }
    func retry() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let ids = library.events.filter { $0.state == .pending || $0.state == .deletionPending }.map(\.id)
        guard !ids.isEmpty else { message = "没有待同步的记录。"; return }
        for id in ids { await sync(id) }
        let summary = SyncSummary(events: library.events)
        message = "同步完成：已写入 \(summary.synced)，待同步 \(summary.pending)，仅本机 \(summary.local)，待撤销 \(summary.deleting)。"
    }
    func undo(_ id: UUID) async throws {
        guard !busy else { throw IntakeError.busy }; busy = true; defer { busy = false }
        var value = library
        guard let i = value.events.firstIndex(where: { $0.id == id }) else { throw IntakeError.missing }
        guard value.events[i].state != .deleted else { return }
        try value.revoke(id)
        try persist(value) // tombstone precedes deletion; a crash cannot reinsert a revoked event
        await sync(id)
    }
    func restore(_ id: UUID) async throws {
        guard !busy else { throw IntakeError.busy }; busy = true; defer { busy = false }
        var value = library
        guard let event = value.events.first(where: { $0.id == id }) else { throw IntakeError.missing }
        guard event.state == .deleted || event.state == .deletionPending else { return }
        try value.restore(id)
        try persist(value) // durable restoration intent before touching Apple Health
        await sync(id)
    }
    private func sync(_ id: UUID) async {
        guard let event = library.events.first(where: { $0.id == id }) else { return }
        do {
            try await EventSync.perform(event, using: health)
            var value = library
            if value.events.contains(where: { $0.id == id }) {
                value.completeSync(id)
                if event.state == .pending, (try? event.healthSamples.isEmpty) == false,
                   let index = value.events.firstIndex(where: { $0.id == id }) {
                    value.events[index].healthVerifiedAt = Date()
                    value.events[index].healthSampleIDs = health.sampleIDs(for: event.id)
                }
                try persist(value)
            }
            message = event.state == .deletionPending ? "已撤销" : ((try? event.healthSamples.isEmpty) == true ? (event.product.mealDetails != nil ? L10n.tr("餐食已保存在本机；没有已知营养值可写入 Apple 健康。") : MappingPresentation.localReason(event.product)) : "已写入并核验 Apple 健康")
        } catch {
            var value = library
            if let i = value.events.firstIndex(where: { $0.id == id }) { value.events[i].lastError = error.localizedDescription }
            do { try persist(value) } catch { message = "状态保存失败：\(L10n.diagnostic(error.localizedDescription))"; return }
            message = "已保存在本机，等待重试：\(L10n.diagnostic(error.localizedDescription))"
        }
    }
}
