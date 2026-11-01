import Foundation

public struct OCRBox: Codable, Equatable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
}
public struct OCRBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var page: Int
    public var text: String
    public var confidence: Double?
    public var language: String?
    public var box: OCRBox?
    public var table: String?
    public var row: Int?
    public var column: Int?
    public init(id: String, page: Int = 0, text: String, confidence: Double? = nil, language: String? = nil, box: OCRBox? = nil, table: String? = nil, row: Int? = nil, column: Int? = nil) {
        self.id = id; self.page = page; self.text = text; self.confidence = confidence; self.language = language; self.box = box; self.table = table; self.row = row; self.column = column
    }
}
public struct OCRDocument: Codable, Equatable, Sendable {
    public var blocks: [OCRBlock]
    public var languages: [String]
    public var supportedOCRLanguages: [String]
    public var engine: String
    public var structureJSON: String? // Vision paragraphs/tables; no images or fabricated confidence
    public var warnings: [String]
    public init(blocks: [OCRBlock], languages: [String] = [], supportedOCRLanguages: [String] = [], engine: String = "manualText", structureJSON: String? = nil, warnings: [String] = []) {
        self.blocks = blocks; self.languages = languages; self.supportedOCRLanguages = supportedOCRLanguages; self.engine = engine; self.structureJSON = structureJSON; self.warnings = warnings
    }
    public init(text: String) {
        self.init(blocks: text.components(separatedBy: .newlines).enumerated().map { OCRBlock(id: "text-\($0.offset)", text: $0.element) })
    }
    public var rawText: String { blocks.map(\.text).joined(separator: "\n") }
    public var promptText: String {
        blocks.map { block in
            var fields: [String: Any] = ["evidenceID": block.id, "page": block.page, "table": block.table ?? "", "row": block.row ?? -1, "column": block.column ?? -1, "text": block.text]
            if let box = block.box { fields["bounds"] = [box.x, box.y, box.width, box.height] }
            if let confidence = block.confidence { fields["confidence"] = confidence }
            return (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }.joined(separator: "\n")
    }
}
public enum LabelBasisKind: String, Codable, Sendable { case perUnit, perServing, per100g, per100mL, perDaily, unknown }
public struct LabelBasis: Codable, Equatable, Sendable {
    public var kind: LabelBasisKind
    public var units: Double?
    public var evidence: String
    public init(kind: LabelBasisKind = .unknown, units: Double? = nil, evidence: String = "") { self.kind = kind; self.units = units; self.evidence = evidence }
    public var title: String {
        switch kind { case .perUnit: "每粒 / 每片"; case .perServing: "每份"; case .per100g: "每 100 g"; case .per100mL: "每 100 mL"; case .perDaily: "标签每日用量（不是实际摄入）"; case .unknown: "计量基准待确认" }
    }
}
public struct SemanticIngredient: Codable, Equatable, Sendable {
    public var key, name, canonicalID, chemicalForm, amount, unit, parentKey, relation, ratio, concentration: String
    public var evidenceIDs: [String]
    public var nameQuote, amountQuote: String
    public init(key: String, name: String, canonicalID: String = "", chemicalForm: String = "", amount: String = "", unit: String = "", parentKey: String = "", relation: String = "component", ratio: String = "", concentration: String = "", evidenceIDs: [String], nameQuote: String, amountQuote: String = "") {
        self.key = key; self.name = name; self.canonicalID = canonicalID; self.chemicalForm = chemicalForm; self.amount = amount; self.unit = unit; self.parentKey = parentKey; self.relation = relation; self.ratio = ratio; self.concentration = concentration; self.evidenceIDs = evidenceIDs; self.nameQuote = nameQuote; self.amountQuote = amountQuote
    }
}
public struct SemanticProposal: Codable, Equatable, Sendable {
    public var productName: String
    public var basisQuote: String
    public var recommendations: [String]
    public var ingredients: [SemanticIngredient]
    public var rawModelResponses: [String]?
    public init(productName: String = "", basisQuote: String = "", recommendations: [String] = [], ingredients: [SemanticIngredient] = []) {
        self.productName = productName; self.basisQuote = basisQuote; self.recommendations = recommendations; self.ingredients = ingredients
    }
}
public protocol SemanticParsingProvider: Sendable {
    var identifier: String { get }
    func propose(_ document: OCRDocument) async throws -> SemanticProposal
}
public struct ValidatedLabel: Sendable {
    public var productName: String
    public var basis: LabelBasis
    public var recommendations: [String]
    public var ingredients: [Ingredient]
    public var warnings: [String]
    public var provider: String
    public var unitsPerServing: Double? { basis.kind == .perUnit || ((basis.kind == .perServing || basis.kind == .perDaily) && basis.units != nil) ? 1 : nil }
    public var serving: String { unitsPerServing != nil ? "1 粒 / 片" : basis.title }
}
