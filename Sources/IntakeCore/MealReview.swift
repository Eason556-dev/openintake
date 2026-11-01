import Foundation

/// The same value state is used by SwiftUI and regression tests. Only actual content
/// edits invalidate confirmation; rendering/encoding/order of JSON keys cannot do so.
public struct MealReviewState: Sendable {
    public var items: [MealPortion] = [] { didSet { if oldValue != items { accepted = false } } }
    public var text = "" { didSet { if oldValue != text { accepted = false } } }
    public var parsedText = ""
    public private(set) var accepted = false
    public private(set) var analysisID: UUID?
    public private(set) var submitting = false
    public private(set) var submitted = false
    public var busy: Bool { analysisID != nil }
    public var textNeedsReview: Bool { text != parsedText }
    public var canAnalyzePhoto: Bool { items.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public init() {}
    public var confirmationIssues: [String] {
        var issues = MealValidation.portionIssues(items)
        if busy { issues.append("正在整理餐食，请等待完成或停止识别后再确认。") }
        if textNeedsReview { issues.append("文字已修改，请重新整理并核对结果。") }
        if submitting || submitted { issues.append("本餐正在记录或已经记录，请勿重复提交。") }
        return issues
    }
    public var submissionIssues: [String] {
        var issues = confirmationIssues
        for issue in MealValidation.submissionIssues(items, confirmed: accepted) where !issues.contains(issue) { issues.append(issue) }
        return issues
    }
    /// The user's tap on Record is the confirmation. No AI or separate checkbox is required.
    public var recordingIssues: [String] { confirmationIssues }
    public mutating func beginRecording(requestID: UUID) throws -> Product {
        guard recordingIssues.isEmpty else { throw MealReviewError.blocked(recordingIssues) }
        var product = try MealValidation.product(items, confirmed: true, allowLocalOnly: true)
        product.id = requestID
        submitting = true
        return product
    }
    public mutating func setAccepted(_ value: Bool) {
        accepted = value && confirmationIssues.isEmpty
    }
    public mutating func prepareText(_ source: String) throws {
        accepted = false; cancelAnalysis(); text = source
        let draft = try TextMealValidation.fallback(source)
        items = draft.items; parsedText = source
    }
    @discardableResult public mutating func startAnalysis() -> UUID {
        accepted = false
        let token = UUID(); analysisID = token; return token
    }
    public mutating func cancelAnalysis() { analysisID = nil }
    @discardableResult public mutating func finishAnalysis(_ token: UUID, items result: [MealPortion]? = nil) -> Bool {
        guard analysisID == token, !submitting, !submitted else { return false }
        if let result { items = result }
        analysisID = nil
        return true
    }
    public static func validateRequest(_ requestID: UUID, events: [IntakeEvent]) throws {
        guard !events.contains(where: { $0.product.id == requestID }) else {
            throw MealReviewError.blocked(["本餐已经记录，请在最近摄入中查看或重试同步，无需重复提交。"])
        }
    }
    public mutating func beginSubmission(requestID: UUID) throws -> Product {
        let issues = submissionIssues
        guard issues.isEmpty else { throw MealReviewError.blocked(issues) }
        var product = try MealValidation.product(items, confirmed: accepted)
        product.id = requestID
        submitting = true
        return product
    }
    public mutating func finishSubmission(succeeded: Bool) {
        submitting = false; submitted = succeeded
    }
}
public enum MealReviewError: LocalizedError {
    case blocked([String])
    public var errorDescription: String? { switch self { case .blocked(let reasons): reasons.joined(separator: "\n") } }
}
