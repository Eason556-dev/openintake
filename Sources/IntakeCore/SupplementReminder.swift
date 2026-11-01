import Foundation

public struct SupplementReminder: Codable, Equatable, Sendable {
    public var productID: UUID
    public var hour: Int
    public var minute: Int
    public init(productID: UUID, hour: Int, minute: Int) { self.productID = productID; self.hour = hour; self.minute = minute }
    public var identifier: String { "org.openintake.supplement." + productID.uuidString }
    public func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else { throw IntakeError.invalidQuantity }
    }
}
