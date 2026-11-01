import Foundation

/// Chemical sources are descriptive evidence, never additional nutrient doses.
public struct ChemicalSource: Codable, Equatable, Sendable {
    public var name: String
    public var canonicalID: String?
    public var evidenceIDs: [String]
}
public enum ChemicalSources {
    private static let aliases: [String: [String]] = [
        "ascorbicAcid": ["Ascorbic acid", "acide ascorbique", "抗坏血酸"],
        "sodiumAscorbate": ["Sodium ascorbate", "ascorbate de sodium", "抗坏血酸钠"],
        "calciumAscorbate": ["Calcium ascorbate", "ascorbate de calcium", "抗坏血酸钙"],
        "calciumCarbonate": ["Calcium carbonate", "carbonate de calcium", "碳酸钙"],
        "cholecalciferol": ["Cholecalciferol", "cholécalciférol", "胆钙化醇"],
        "ergocalciferol": ["Ergocalciferol", "ergocalciférol", "麦角钙化醇"]
    ]
    private static func identity(_ name: String) -> String? {
        let key = IngredientCatalog.normalized(name)
        return aliases.first { $0.value.contains { IngredientCatalog.normalized($0) == key } }?.key
    }
    public static func isSourceLine(_ block: OCRBlock, in document: OCRDocument) -> Bool {
        guard LabelEvidence.quantities(block.text).isEmpty else { return false }
        let lines = document.blocks.filter { $0.page == block.page && $0.table == block.table }
        guard let index = lines.firstIndex(where: { $0.id == block.id }) else { return false }
        let clean = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("(") || clean.hasPrefix("（") { return true }
        guard index > 0 else { return false }
        var balance = 0
        for line in lines[max(0, index - 3)..<index] {
            balance += line.text.filter { "(（".contains($0) }.count - line.text.filter { ")）".contains($0) }.count
        }
        return balance > 0
    }
    public static func attached(nameBlocks: [OCRBlock], amountBlocks: [OCRBlock], in document: OCRDocument) -> [ChemicalSource] {
        var sources: [ChemicalSource] = []
        func collect(_ raw: String, ids: [String]) {
            guard LabelEvidence.quantities(raw).isEmpty, !LabelEvidence.isInstruction(raw) else { return }
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "()（）")))
            for part in clean.components(separatedBy: CharacterSet(charactersIn: ",，/;；")) {
                var name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                for prefix in ["as ", "sous forme de "] where name.lowercased().hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
                guard !name.isEmpty else { continue }
                let id = identity(name)
                if let i = sources.firstIndex(where: { id != nil ? $0.canonicalID == id : IngredientCatalog.normalized($0.name) == IngredientCatalog.normalized(name) }) {
                    sources[i].evidenceIDs = Array(Set(sources[i].evidenceIDs + ids)).sorted()
                } else { sources.append(.init(name: name, canonicalID: id, evidenceIDs: ids)) }
            }
        }
        for block in nameBlocks {
            for match in LabelEvidence.matches(#"[（(]([^()（）]+)[)）]"#, block.text) { collect(LabelEvidence.capture(match, 1, block.text), ids: [block.id]) }
        }
        let anchors = nameBlocks + amountBlocks
        let lines = document.blocks
        let indices = anchors.compactMap { block in lines.firstIndex(where: { $0.id == block.id }) }
        guard let last = indices.max(), last + 1 < lines.count, let name = nameBlocks.first else { return sources }
        var raw = "", ids: [String] = [], balance = 0
        for index in (last + 1)..<min(last + 5, lines.count) {
            let block = lines[index]
            guard block.page == name.page, LabelEvidence.quantities(block.text).isEmpty else { break }
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if ids.isEmpty {
                guard text.hasPrefix("(") || text.hasPrefix("（") else { break }
                // Camera data needs spatial evidence too. Pasted text uses explicit bracket grammar.
                if let a = name.box, let b = block.box {
                    guard a.y > b.y, a.y - b.y < max(a.height, b.height) * 3.5,
                          abs(a.x - b.x) < max(a.width, b.width) * 0.65 else { break }
                } else if document.engine != "manualText" { break }
            }
            raw += (raw.isEmpty ? "" : " ") + text; ids.append(block.id)
            balance += text.filter { "(（".contains($0) }.count - text.filter { ")）".contains($0) }.count
            if balance <= 0 { collect(raw, ids: ids); break }
        }
        return sources
    }
    public static func isDetachedChemicalRow(_ row: SemanticIngredient, in document: OCRDocument) -> Bool {
        let blocks = row.evidenceIDs.compactMap { id in document.blocks.first { $0.id == id } }
        let containing = blocks.filter { $0.text.contains(row.nameQuote) }
        return !containing.isEmpty && containing.allSatisfy { isSourceLine($0, in: document) }
    }
}
