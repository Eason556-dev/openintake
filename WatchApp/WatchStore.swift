import Foundation
import WatchConnectivity
import WidgetKit
import SwiftUI

@MainActor final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = DashboardCache.load()
    @Published var products: [WatchProduct] = []
    @Published var outbox = WatchOutbox()
    @Published var status: String?
    private var session: WCSession?
    private var loadFailed = false
    private let directory = URL.applicationSupportDirectory.appending(path: "OpenIntakeWatch")
    private var retryTask: Task<Void, Never>?
    private var lastFlush = Date.distantPast
    #if DEBUG
    private var auditReplies = 0
    private var auditStarted = false
    func runConnectivityAuditIfRequested() {
        guard !auditStarted, ProcessInfo.processInfo.arguments.contains("--watch-sync-audit") else { return }
        auditStarted = true
        Task {
            for _ in 0..<12 {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
            let result: [String: Any] = ["completed": true, "refreshReplies": auditReplies]
            // Debug-only transport evidence. No intake creation, product names or Health samples.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: result) {
                try? data.write(to: directory.appending(path: "connectivity-audit.json"), options: .atomic)
            }
        }
    }
    #endif
    override init() {
        super.init()
        do {
            let url = directory.appending(path: "outbox.json")
            if FileManager.default.fileExists(atPath: url.path) { outbox = try JSONDecoder().decode(WatchOutbox.self, from: Data(contentsOf: url)) }
            if let data = try? Data(contentsOf: directory.appending(path: "catalog.json")), let envelope = try? JSONDecoder().decode(WatchEnvelope.self, from: data) { products = envelope.products }
        } catch { loadFailed = true; status = L10n.tr("手表记录暂不可读，已停止新增以保护数据") }
        if WCSession.isSupported() { session = .default; session?.delegate = self; session?.activate() }
    }
    private func save(_ value: WatchOutbox) throws {
        guard !loadFailed else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: directory.appending(path: "outbox.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        outbox = value
    }
    func record(product: WatchProduct? = nil, quantity: Double) {
        guard quantity.isFinite, quantity > 0, product != nil || quantity <= 10000 else { status = L10n.tr("请输入有效的实际数量"); return }
        let request = WatchIntakeRequest(productID: product?.id, revision: product?.revision, unit: product?.unit ?? "mL", quantity: quantity)
        var value = outbox; value.add(.init(request: request, name: product?.name ?? L10n.tr("饮水")))
        do { try save(value); status = L10n.tr("已保存在手表，正在自动同步"); flush() }
        catch { status = L10n.tr("保存失败，尚未记录，请重试") }
    }
    func dismissRejected(_ id: UUID) {
        var value = outbox
        value.items.removeAll { $0.id == id && $0.rejection != nil }
        do { try save(value) } catch { status = L10n.tr("保存失败，尚未记录，请重试") }
    }
    func refresh() {
        guard let session, session.activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        flush()
        if session.isReachable {
            session.sendMessage(["requestDashboard": true], replyHandler: ConnectivityCallbacks.reply { [weak self] envelope, _ in
                #if DEBUG
                self?.auditReplies += 1
                #endif
                self?.acceptEnvelope(envelope)
            }, errorHandler: ConnectivityCallbacks.ignoreError)
        }
    }
    private func flush() {
        guard let session, session.activationState == .activated, !loadFailed else { return }
        guard Date().timeIntervalSince(lastFlush) >= 5 else { return }
        lastFlush = Date()
        for item in outbox.items where item.rejection == nil {
            guard let data = try? JSONEncoder().encode(item.request) else { continue }
            // Transport delivery is not a durable intake acknowledgement. The disk outbox stays intact.
            let queued = session.outstandingUserInfoTransfers.contains { ($0.userInfo["requestID"] as? String) == item.id.uuidString }
            if !queued { session.transferUserInfo(["intake": data, "requestID": item.id.uuidString]) }
            if session.isReachable {
                session.sendMessage(["intake": data], replyHandler: ConnectivityCallbacks.reply { [weak self] envelope, receipt in
                    self?.acceptReceipt(receipt); self?.acceptEnvelope(envelope)
                }, errorHandler: ConnectivityCallbacks.ignoreError)
            }
        }
        if retryTask == nil, outbox.items.contains(where: { $0.rejection == nil }) {
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.retryTask = nil; self?.flush()
            }
        }
    }
    private func acceptReceipt(_ data: Data?) {
        guard let data, let receipt = try? JSONDecoder().decode(WatchReceipt.self, from: data) else { return }
        var value = outbox; value.receive(receipt)
        do {
            try save(value)
            if receipt.outcome == .accepted { status = L10n.tr("已送达 iPhone；健康写入状态见今日汇总") }
        } catch { status = L10n.tr("确认暂未保存，将安全重试") }
    }
    private func receive(_ context: [String: Any]) {
        acceptReceipt(context["receipt"] as? Data)
        if let data = context["envelope"] as? Data { acceptEnvelope(data) }
        else if let data = context["dashboard"] as? Data, let value = try? JSONDecoder().decode(DashboardSnapshot.self, from: data) { accept(value) }
    }
    private func acceptEnvelope(_ data: Data?) {
        guard let data, let value = try? JSONDecoder().decode(WatchEnvelope.self, from: data), value.dashboard.isValid,
              snapshot.map({ $0.updatedAt <= value.dashboard.updatedAt }) ?? true else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: "catalog.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            products = value.products; accept(value.dashboard)
            flush() // A fresh phone context also retries previously protected/locked writes.
        } catch { status = L10n.tr("产品列表暂未保存，请稍后重试") }
    }
    private func accept(_ value: DashboardSnapshot) {
        guard value.isValid, snapshot.map({ $0.updatedAt <= value.updatedAt }) ?? true else { return }
        do {
            try DashboardCache.save(value)
            UserDefaults.standard.set(value.language, forKey: L10n.preferenceKey)
            UserDefaults(suiteName: DashboardCache.group)?.set(value.language, forKey: L10n.preferenceKey)
            snapshot = value
            WidgetCenter.shared.reloadAllTimelines()
        } catch { status = L10n.display("手表共享数据不可用，请检查 App Group 签名") }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["envelope"] as? Data
        Task { @MainActor in self.acceptEnvelope(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let data = message["envelope"] as? Data
        Task { @MainActor in self.acceptEnvelope(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let data = userInfo["receipt"] as? Data
        Task { @MainActor in self.acceptReceipt(data) }
    }
}
