import Foundation

public extension OCRDocument {
    /// Vision can return one physical line as both paragraph text and table-cell text.
    /// Merge only identical text in the same physical region, never bilingual synonyms or pages.
    mutating func appendEvidence(_ block: OCRBlock) {
        if let b = block.box, let i = blocks.firstIndex(where: { old in
            guard old.page == block.page, old.text == block.text, let a = old.box else { return false }
            let width = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
            let height = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
            let overlap = width * height, union = a.width * a.height + b.width * b.height - overlap
            return union > 0 && overlap / union > 0.8
        }) {
            if let table = block.table {
                blocks[i].table = table; blocks[i].row = block.row; blocks[i].column = block.column
            }
            // Preserve the conservative confidence rather than inflating duplicate observations.
            if let value = block.confidence { blocks[i].confidence = min(blocks[i].confidence ?? value, value) }
        } else { blocks.append(block) }
    }
}
