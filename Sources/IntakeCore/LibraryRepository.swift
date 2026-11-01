import Foundation

/// Single-process repository. Main-app and foreground intents use one MainActor store.
public struct LibraryRepository: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Library {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Library() }
        // Permission and file-protection errors must never look like an empty library.
        let library = try JSONDecoder().decode(Library.self, from: data)
        guard library.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        for product in library.products { try product.validate() }
        for event in library.events { _ = try IntakeEvent(product: event.product, servings: event.servings, date: event.date) }
        return library
    }
    public func save(_ value: Library) throws {
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        #endif
        var resource = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
    }
}
public extension Library {
    mutating func enqueue(_ event: IntakeEvent) throws {
        guard !events.contains(where: { event.duplicates($0) }) else { throw IntakeError.duplicate }
        events.insert(event, at: 0)
    }
    mutating func revoke(_ id: UUID) throws {
        guard let i = events.firstIndex(where: { $0.id == id }) else { throw IntakeError.missing }
        if events[i].state != .deleted { events[i].state = .deletionPending }
    }
    /// Restore the original timestamp, quantities and frozen mapping; never create a second event.
    mutating func restore(_ id: UUID) throws {
        guard let i = events.firstIndex(where: { $0.id == id }) else { throw IntakeError.missing }
        guard events[i].state == .deleted || events[i].state == .deletionPending else { return }
        guard !events.contains(where: { $0.id != id && events[i].duplicates($0) }) else { throw IntakeError.duplicate }
        guard events[i].syncVersion > 0, events[i].syncVersion < Int.max else { throw IntakeError.invalidQuantity }
        events[i].healthSyncVersion = events[i].syncVersion + 1
        events[i].state = .pending
        events[i].lastError = nil
        events[i].healthVerifiedAt = nil
    }
    mutating func completeSync(_ id: UUID) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        guard events[i].state == .pending || events[i].state == .deletionPending else { return }
        events[i].state = events[i].state == .deletionPending ? .deleted : ((try? events[i].healthSamples.isEmpty) == true ? .localOnly : .synced)
        events[i].lastError = nil
    }
}
