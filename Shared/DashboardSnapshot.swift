import Foundation

public enum DashboardMetric: String, Codable, CaseIterable, Sendable {
    case water, energy, protein, sugar, sodium
    public var unit: String { self == .water ? "mL" : self == .energy ? "kcal" : self == .sodium ? "mg" : "g" }
    public var isLimit: Bool { self == .sugar || self == .sodium }
    public var symbol: String { switch self { case .water: "drop.fill"; case .energy: "flame.fill"; case .protein: "leaf.fill"; case .sugar: "cube.fill"; case .sodium: "scalemass.fill" } }
    public var title: String { switch self { case .water: "补水"; case .energy: "能量"; case .protein: "蛋白质"; case .sugar: "糖"; case .sodium: "钠" } }
}
public struct DashboardValue: Codable, Equatable, Sendable, Identifiable {
    public var id: DashboardMetric
    public var value: Double?
    public var goal: Double?
    public var estimated: Bool
    public init(id: DashboardMetric, value: Double?, goal: Double?, estimated: Bool = false) {
        self.id = id; self.value = value; self.goal = goal; self.estimated = estimated
    }
    public var fraction: Double? {
        guard let value, let goal, value.isFinite, goal.isFinite, value >= 0, goal > 0 else { return nil }
        return min(1, value / goal)
    }
}
/// Minimal watch projection. No product names, OCR, photos, account IDs or complete ledger.
public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public var schema = 1
    public var updatedAt: Date
    public var dayStart: Date
    public var dayEnd: Date
    public var timeZone: String
    public var values: [DashboardValue]
    public var pendingCount: Int
    public var language: String
    public init(updatedAt: Date, calendar: Calendar, values: [DashboardValue], pendingCount: Int, language: String) {
        self.updatedAt = updatedAt
        dayStart = calendar.startOfDay(for: updatedAt)
        dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? updatedAt.addingTimeInterval(86400)
        timeZone = calendar.timeZone.identifier
        self.values = values; self.pendingCount = pendingCount; self.language = language
    }
    public func isCurrent(at date: Date, calendar: Calendar = .current) -> Bool {
        schema == 1 && date >= dayStart && date < dayEnd && calendar.timeZone.identifier == timeZone
    }
    public func metric(_ id: DashboardMetric, at date: Date, calendar: Calendar = .current) -> DashboardValue {
        let stored = values.first { $0.id == id }
        return DashboardValue(id: id, value: isCurrent(at: date, calendar: calendar) ? stored?.value : nil,
                              goal: stored?.goal, estimated: stored?.estimated ?? false)
    }
    public var isValid: Bool {
        schema == 1 && dayStart < dayEnd && updatedAt >= dayStart && updatedAt < dayEnd && pendingCount >= 0 &&
        Set(values.map(\.id)).count == values.count &&
        values.allSatisfy { ($0.value.map { $0.isFinite && $0 >= 0 } ?? true) && ($0.goal.map { $0.isFinite && $0 > 0 } ?? true) }
    }
}
public enum DashboardCache {
    public static var group: String { Bundle.main.object(forInfoDictionaryKey: "OpenIntakeAppGroup") as? String ?? "group.org.openintake.shared" }
    public static var url: URL? {
        #if os(iOS) || os(watchOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("watch-dashboard.json")
        #else
        nil
        #endif
    }
    public static func load() -> DashboardSnapshot? {
        guard let url, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(DashboardSnapshot.self, from: data), value.isValid else { return nil }
        return value
    }
    public static func save(_ value: DashboardSnapshot) throws {
        guard value.isValid, let url else { throw CocoaError(.fileWriteUnknown) }
        // Ignore delayed older contexts, including foreground/background races.
        if let old = load(), old.updatedAt > value.updatedAt { return }
        let data = try JSONEncoder().encode(value)
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
