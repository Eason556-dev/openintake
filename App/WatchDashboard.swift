import Foundation
import UIKit
import WatchConnectivity
import WidgetKit

@MainActor enum DashboardPreferences {
    static func goals() -> [DashboardMetric: Double] {
        var result: [DashboardMetric: Double] = [.water: UserDefaults.standard.object(forKey: "waterGoalML") as? Double ?? 2000]
        for metric in DashboardMetric.allCases where metric != .water {
            let value = UserDefaults.standard.double(forKey: "goal.\(metric.rawValue)")
            if value.isFinite && value > 0 { result[metric] = value }
        }
        return result
    }
    static func snapshot(_ events: [IntakeEvent], date: Date = Date()) -> DashboardSnapshot {
        DashboardBuilder.build(events: events, goals: goals(), language: L10n.preference, date: date)
    }
}
@MainActor final class WatchDashboardBridge: NSObject, WCSessionDelegate {
    static let shared = WatchDashboardBridge()
    private var latest: DashboardSnapshot?
    private var session: WCSession?
    private var envelopeData: Data?
    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(protectedDataAvailable), name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        if WCSession.isSupported() { session = .default; session?.delegate = self; session?.activate() }
    }
    @objc private func protectedDataAvailable() {
        let store = IntakeStore.shared
        if store.loadError != nil { store.reload() }
        store.scheduleAutomaticSync()
        publish(events: store.library.events)
    }
    func publish(events: [IntakeEvent]) {
        // A protected/unreadable phone library is not an empty day or an empty catalog.
        // Preserve the last successful projection until the authoritative ledger can be read.
        guard IntakeStore.shared.loadError == nil else { return }
        let value = DashboardPreferences.snapshot(events)
        latest = value
        envelopeData = try? JSONEncoder().encode(WatchEnvelope(dashboard: value, products: WatchIntake.catalog(IntakeStore.shared.library.products)))
        try? DashboardCache.save(value)
        UserDefaults(suiteName: DashboardCache.group)?.set(L10n.preference, forKey: L10n.preferenceKey)
        WidgetCenter.shared.reloadAllTimelines()
        sendLatest()
    }
    private func sendLatest() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let latest, let data = try? JSONEncoder().encode(latest) else { return }
        do {
            var payload: [String: Any] = ["dashboard": data]
            if let envelopeData { payload["envelope"] = envelopeData }
            try session.updateApplicationContext(payload)
            if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: ConnectivityCallbacks.ignoreError) }
        }
        catch { /* Re-publish on next activation, foreground or ledger update. No health write occurs. */ }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(events: IntakeStore.shared.library.events); IntakeStore.shared.scheduleAutomaticSync() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.sendLatest() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.publish(events: IntakeStore.shared.library.events)
            IntakeStore.shared.scheduleAutomaticSync()
        }
    }
    private func receive(_ data: Data) -> Data? {
        guard let request = try? JSONDecoder().decode(WatchIntakeRequest.self, from: data) else { return nil }
        let receipt = IntakeStore.shared.receiveWatch(request)
        publish(events: IntakeStore.shared.library.events)
        return try? JSONEncoder().encode(receipt)
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["intake"] as? Data else { return }
        Task { @MainActor in
            if let receipt = self.receive(data) { self.session?.transferUserInfo(["receipt": receipt]) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let data = message["intake"] as? Data
        // WC's callback isn't annotated Sendable. Keep only this one-shot response closure in the bridge.
        let reply = WatchReply(replyHandler)
        Task { @MainActor in
            var response: [String: Any] = [:]
            if let data, let receipt = self.receive(data) { response["receipt"] = receipt }
            self.publish(events: IntakeStore.shared.library.events)
            if let envelopeData = self.envelopeData { response["envelope"] = envelopeData }
            reply.send(response)
        }
    }
}
private final class WatchReply: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
    func send(_ payload: [String: Any]) { handler(payload) }
}
