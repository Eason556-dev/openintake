import Foundation

/// A deliberately limited fallback, not an AI substitute. Unknown names remain in raw OCR.
public struct OfflineSemanticProvider: SemanticParsingProvider {
    public let identifier = "offlineRules"
    public init() {}
    public func propose(_ document: OCRDocument) async throws -> SemanticProposal { Self.draft(document) }
    public static func draft(_ document: OCRDocument) -> SemanticProposal {
        let blocks = document.blocks
        var rows: [SemanticIngredient] = []
        for block in blocks where !LabelEvidence.isInstruction(block.text) && !ChemicalSources.isSourceLine(block, in: document) {
            let ns = block.text as NSString
            let hits = LabelNameEvidence.matches(in: block.text).map { ($0.range, $0.quote) }
            // A product heading mentioning two ingredients but no quantities is not a composition row.
            let hasQuantity = !LabelEvidence.quantities(block.text).isEmpty || hits.contains { !LabelEvidence.quantities(ns.substring(from: NSMaxRange($0.0))).isEmpty }
            if !hasQuantity && (hits.count != 1 || IngredientCatalog.normalized(block.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) != IngredientCatalog.normalized(hits[0].1)) { continue }
            if hits.isEmpty, let q = LabelEvidence.quantities(block.text).first, let range = block.text.range(of: q.quote) {
                let name = String(block.text[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " :：;；(（"))
                if !name.isEmpty && !LabelEvidence.isConnector(name) && LabelEvidence.basis(block.text).kind == .unknown {
                    rows.append(.init(key: "r\(rows.count)", name: name, amount: String(q.value), unit: q.unit, evidenceIDs: [block.id], nameQuote: name, amountQuote: q.quote))
                }
            }
            for (i, hit) in hits.enumerated() {
                let end = hits.dropFirst(i + 1).first(where: { IngredientCatalog.resolve($0.1) != IngredientCatalog.resolve(hit.1) })?.0.location ?? ns.length
                let segment = ns.substring(with: NSRange(location: hit.0.location, length: end - hit.0.location))
                let q = LabelEvidence.quantities(String(segment.dropFirst(hit.1.count))).first
                var rawName = hit.1
                if hits.count == 1, let q, let range = block.text.range(of: q.quote) {
                    let prefix = String(block.text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: " :：;；.·•…|—–-")))
                    let leading = prefix.range(of: hit.1).map { String(prefix[..<$0.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) } ?? ""
                    let withoutSources = prefix.replacingOccurrences(of: #"[（(][^()（）]*[)）]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                    if IngredientCatalog.resolve(withoutSources) != IngredientCatalog.resolve(hit.1), prefix != hit.1, !LabelEvidence.isConnector(leading), !prefix.lowercased().hasSuffix("providing"), !prefix.lowercased().hasSuffix("fournissant") { rawName = prefix }
                }
                let id = IngredientCatalog.resolve(rawName) ?? ""
                var evidence = [block.id]; var amount = q
                if amount == nil, let next = LabelEvidenceLink.amount(for: block, in: document) {
                    amount = LabelEvidence.quantities(next.text).first; evidence.append(next.id)
                }
                let ratio = LabelEvidence.matches(#"\b\d+\s*:\s*\d+\b"#, segment).first.map { LabelEvidence.capture($0, 0, segment) } ?? ""
                rows.append(SemanticIngredient(key: "r\(rows.count)", name: rawName, canonicalID: id, amount: amount.map { String($0.value) } ?? "", unit: amount?.unit ?? "", relation: id == "dryHerbEquivalent" ? "equivalent" : "component", ratio: ratio, evidenceIDs: evidence, nameQuote: rawName, amountQuote: amount?.quote ?? ""))
            }
        }
        // Specific, known containment; never infer a generic nutrient hierarchy from model prose.
        for i in rows.indices {
            let parentID: String? = ["omega3":"fishOil", "epa":"omega3", "dha":"omega3", "dryHerbEquivalent":"turmericExtract"][rows[i].canonicalID]
            if let parentID, let parent = rows.first(where: { $0.canonicalID == parentID }) { rows[i].parentKey = parent.key }
        }
        var result = header(document); result.ingredients = rows
        return result
    }
    public static func header(_ document: OCRDocument) -> SemanticProposal {
        let blocks = document.blocks
        let basis = blocks.first { LabelEvidence.basis($0.text).kind != .unknown && !LabelEvidence.isInstruction($0.text) }?.text ?? ""
        let heading = blocks.first?.text ?? ""
        return SemanticProposal(productName: LabelEvidence.quantities(heading).isEmpty && LabelEvidence.basis(heading).kind == .unknown ? heading : "", basisQuote: basis, recommendations: blocks.filter { LabelEvidence.isInstruction($0.text) }.map(\.text))
    }
}
