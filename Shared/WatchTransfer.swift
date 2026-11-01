import Foundation

/// A cached choice, never a second source of nutrition facts. Only iPhone resolves the recipe.
public struct WatchProduct: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var revision: UUID
    public var name: String
    public var unit: String
    public var quantity: Double
    public init(id: UUID, revision: UUID, name: String, unit: String, quantity: Double) {
        self.id = id; self.revision = revision; self.name = name; self.unit = unit; self.quantity = quantity
    }
}
public struct WatchIntakeRequest: Codable, Identifiable, Equatable, Sendable {
    public var schema = 1
    public var id: UUID
    public var productID: UUID?
    public var revision: UUID?
    public var unit: String
    public var quantity: Double
    public var date: Date
    public init(id: UUID = UUID(), productID: UUID? = nil, revision: UUID? = nil, unit: String = "mL", quantity: Double, date: Date = Date()) {
        self.id = id; self.productID = productID; self.revision = revision; self.unit = unit; self.quantity = quantity; self.date = date
    }
}
public struct WatchReceipt: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case accepted, rejected, retry }
    public var id: UUID
    public var outcome: Outcome
    public var reason: String
    public init(id: UUID, outcome: Outcome, reason: String = "") { self.id = id; self.outcome = outcome; self.reason = reason }
}
public struct WatchEnvelope: Codable, Sendable {
    public var dashboard: DashboardSnapshot
    public var products: [WatchProduct]
    public init(dashboard: DashboardSnapshot, products: [WatchProduct]) { self.dashboard = dashboard; self.products = products }
}
public struct WatchPendingItem: Codable, Identifiable, Sendable {
    public var request: WatchIntakeRequest
    public var name: String
    public var rejection: String?
    public var id: UUID { request.id }
    public init(request: WatchIntakeRequest, name: String) { self.request = request; self.name = name }
}
/// Acknowledgement follows a durable phone save, not a transport completion callback.
public struct WatchOutbox: Codable, Sendable {
    public var items: [WatchPendingItem] = []
    public init() {}
    public mutating func add(_ item: WatchPendingItem) {
        if !items.contains(where: { $0.id == item.id }) { items.append(item) }
    }
    public mutating func receive(_ receipt: WatchReceipt) {
        guard let index = items.firstIndex(where: { $0.id == receipt.id }) else { return }
        switch receipt.outcome {
        case .accepted: items.remove(at: index)
        case .rejected: items[index].rejection = receipt.reason
        case .retry: break
        }
    }
}
