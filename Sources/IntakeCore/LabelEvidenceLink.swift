import Foundation

/// The same source linkage rules are used by extraction AND validation.
public enum LabelEvidenceLink {
    public static func pureQuantity(_ text: String) -> Bool {
        let values = LabelEvidence.quantities(text)
        guard values.count == 1 else { return false }
        return text.replacingOccurrences(of: values[0].quote, with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty
    }
    public static func linked(_ name: OCRBlock, _ amount: OCRBlock, in document: OCRDocument) -> Bool {
        if name.id == amount.id { return true }
        guard name.page == amount.page, !LabelEvidence.isInstruction(amount.text) else { return false }
        if let table = name.table, table == amount.table, name.row == amount.row, name.row != nil {
            let cells = document.blocks.filter { $0.page == name.page && $0.table == table && $0.row == name.row }
            let identities = Set(cells.flatMap { LabelNameEvidence.matches(in: $0.text).map(\.canonicalID) })
            let valueCells = cells.filter { !LabelEvidence.quantities($0.text).isEmpty }
            return identities.count <= 1 && valueCells.count == 1 && LabelEvidence.quantities(amount.text).count == 1
        }
        if OCRLayout.rightHandAmount(for: name, in: document)?.id == amount.id { return true }
        if name.box == nil && amount.box == nil && name.table == nil && amount.table == nil && document.engine == "manualText" {
            // Explicit pasted line grammar: ONE known standalone name immediately followed by
            // ONE amount-only line. Never extend this to geometry-less camera observations.
            let lines = document.blocks.filter { $0.page == name.page && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard let index = lines.firstIndex(where: { $0.id == name.id }), index + 1 < lines.count,
                  lines[index + 1].id == amount.id, pureQuantity(amount.text),
                  IngredientCatalog.resolve(name.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) != nil else { return false }
            return true
        }
        guard let a = name.box, let b = amount.box else { return false }
        let sameColumn = abs(a.x - b.x) < max(a.width, b.width) * 0.35
        let verticalGap = a.y - b.y // Vision coordinates start at bottom left: quantity must be below.
        guard sameColumn, verticalGap > 0, verticalGap < max(a.height, b.height) * 2.5, pureQuantity(amount.text) else { return false }
        return !document.blocks.contains { block in
            guard block.id != name.id && block.id != amount.id, block.page == name.page, let box = block.box else { return false }
            return box.y > b.y && box.y < a.y && abs(box.x - a.x) < a.width * 0.35 && !LabelNameEvidence.matches(in: block.text).isEmpty
        }
    }
    public static func amount(for name: OCRBlock, in document: OCRDocument) -> OCRBlock? {
        let candidates = document.blocks.filter { $0.id != name.id && pureQuantity($0.text) && linked(name, $0, in: document) }
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }
}
