import Foundation

/// WatchConnectivity's Objective-C block parameters are not annotated @Sendable in the SDK.
/// A closure created in a @MainActor method can inherit its isolation, then trap when WC
/// invokes it on a background queue. Construct the block here, outside actor isolation,
/// and pass only Sendable Data across the explicit main-actor hop.
public enum ConnectivityCallbacks {
    public nonisolated static func reply(
        _ receive: @escaping @MainActor @Sendable (_ envelope: Data?, _ receipt: Data?) -> Void
    ) -> @Sendable ([String: Any]) -> Void {
        { @Sendable payload in
            let envelope = payload["envelope"] as? Data
            let receipt = payload["receipt"] as? Data
            Task { @MainActor in receive(envelope, receipt) }
        }
    }
    public static let ignoreError: @Sendable (any Error) -> Void = { _ in }
}
