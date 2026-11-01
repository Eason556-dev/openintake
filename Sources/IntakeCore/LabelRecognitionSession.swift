import Foundation

/// Single deterministic path from one OCR revision to the UI/persisted product.
/// An expired generation can never change a newer scan. Repeated completed snapshots are no-ops.
public struct LabelRecognitionSession: Sendable {
    public private(set) var generation = UUID()
    public private(set) var document = OCRDocument(blocks: [])
    public private(set) var rules = SemanticProposal()
    public private(set) var proposal = SemanticProposal()
    public private(set) var result: ValidatedLabel?
    private var validatedRules: ValidatedLabel?
    private var lastAI: SemanticProposal?
    public init() {}
    @discardableResult public mutating func begin(_ document: OCRDocument) -> UUID {
        generation = UUID(); self.document = document
        rules = OfflineSemanticProvider.draft(document); proposal = rules; lastAI = nil
        let checked = SemanticValidator.validate(rules, document: document, provider: "offlineRules")
        validatedRules = checked; result = checked
        return generation
    }
    public mutating func cancel() { generation = UUID() }
    @discardableResult public mutating func receive(_ proposal: SemanticProposal, generation: UUID) -> Bool {
        guard generation == self.generation, proposal != lastAI, let rules = validatedRules else { return false }
        lastAI = proposal; self.proposal = proposal
        let checked = SemanticValidator.validate(proposal, document: document, provider: "appleFoundationModels")
        result = SemanticReconciliation.complete(checked, with: rules)
        return true
    }
    public func applying(to input: Product) -> Product {
        guard let result else { return input }
        var product = input
        product.sourceText = document.rawText; product.ocrDocument = document
        product.semanticProposal = proposal; product.ruleProposal = rules
        product.aiProposal = proposal.rawModelResponses?.joined(separator: "\n")
        product.labelBasis = result.basis; product.recommendations = result.recommendations
        product.parsingProvider = result.provider; product.parsingWarnings = result.warnings
        // Empty results must clear stale ingredients from the previous scan, not silently retain them.
        product.ingredients = result.ingredients; product.nutrients = []
        product.serving = result.serving; product.unitsPerServing = result.unitsPerServing
        if product.name.isEmpty {
            product.name = result.productName
            if product.name.isEmpty, let first = result.ingredients.first {
                product.name = first.displayName(language: "zh") + (result.ingredients.count > 1 ? " 等（标签产品）" : "")
            }
        }
        return product
    }
}
