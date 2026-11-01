import Foundation

/// Compact model transport only. Original OCR, evidence IDs and validation remain unchanged.
public enum SemanticInput {
    public static func batches(_ document: OCRDocument, limit: Int = 1800) -> [String] {
        let rows = document.blocks.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var result: [String] = [], current: [String] = []
        for block in rows {
            var data: [String: Any] = ["id": block.id, "text": block.text, "page": block.page]
            if let table = block.table { data["table"] = table; data["row"] = block.row; data["column"] = block.column }
            if let b = block.box { data["box"] = [b.x,b.y,b.width,b.height].map { ($0 * 1000).rounded() / 1000 } }
            let line = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if !current.isEmpty && (current.joined(separator: "\n").count + line.count > limit || current.count >= 12) {
                result.append(current.joined(separator: "\n"))
                // Two-line overlap retains names/numbers at chunk boundaries. Never truncate text.
                current = Array(current.suffix(2))
            }
            current.append(line)
        }
        if !current.isEmpty { result.append(current.joined(separator: "\n")) }
        return result
    }
    public static func join(_ proposals: [SemanticProposal]) -> SemanticProposal {
        var result = SemanticProposal()
        for (index, proposal) in proposals.enumerated() {
            if result.productName.isEmpty { result.productName = proposal.productName }
            if result.basisQuote.isEmpty { result.basisQuote = proposal.basisQuote }
            result.recommendations += proposal.recommendations
            if let raw = proposal.rawModelResponses { result.rawModelResponses = (result.rawModelResponses ?? []) + raw }
            for var row in proposal.ingredients {
                row.key = "b\(index)." + row.key
                if !row.parentKey.isEmpty { row.parentKey = "b\(index)." + row.parentKey }
                result.ingredients.append(row)
            }
        }
        // Bilingual/overlap deduplication is deliberately left to the independent validator.
        return result
    }
}
