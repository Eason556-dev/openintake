import Foundation

/// Associates split label/value columns using real geometry, never reading order alone.
public enum OCRLayout {
    public static func rightHandAmount(for name: OCRBlock, in document: OCRDocument) -> OCRBlock? {
        guard let a = name.box else { return nil }
        let candidates = document.blocks.filter { block in
            guard block.id != name.id, block.page == name.page, let b = block.box,
                  LabelEvidence.quantities(block.text).count == 1,
                  !LabelEvidence.isInstruction(block.text),
                  !block.text.contains("%"),
                  b.x >= a.x + a.width - 0.02,
                  abs((a.y + a.height / 2) - (b.y + b.height / 2)) <= max(a.height, b.height) * 0.55 else { return false }
            let q = LabelEvidence.quantities(block.text)[0]
            return block.text.replacingOccurrences(of: q.quote, with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty
        }
        // Multiple amount columns require an explicit basis selection; do not pick nearest.
        guard candidates.count == 1, let amount = candidates.first, let b = amount.box else { return nil }
        let names = document.blocks.filter { block in
            guard block.page == name.page, let box = block.box,
                  box.x + box.width <= b.x + 0.02,
                  abs((box.y + box.height / 2) - (b.y + b.height / 2)) <= max(box.height, b.height) * 0.55 else { return false }
            return !LabelNameEvidence.matches(in: block.text).isEmpty
        }
        guard names.count == 1, names.first?.id == name.id else { return nil }
        return amount
    }
}
