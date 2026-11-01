import Foundation

public struct LabelQuantity: Sendable {
    public var value: Double
    public var unit: String
    public var quote: String
}
public enum LabelEvidence {
    public static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
    public static func capture(_ match: NSTextCheckingResult, _ group: Int, _ text: String) -> String {
        Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
    }
    public static func number(_ text: String) -> Double? {
        var clean = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: "\u{202f}", with: "")
        if clean.contains(",") {
            if matches(#"^\d{1,3}(?:,\d{3})+(?:\.\d+)?$"#, clean).count == 1, !clean.hasPrefix("0,") { clean = clean.replacingOccurrences(of: ",", with: "") }
            else if !clean.contains(".") { clean = clean.replacingOccurrences(of: ",", with: ".") }
            else { return nil }
        }
        guard let value = Double(clean), value.isFinite, value >= 0 else { return nil }; return value
    }
    public static func quantities(_ text: String) -> [LabelQuantity] {
        let pattern = #"(?<![A-Za-z\d.,+\-])((?:\d{1,3}(?:[ ,\u00a0\u202f]\d{3})+|\d+)(?:[.,]\d+)?)\s*(mcg\s*(?:RAE|DFE)|[μµu]g\s*(?:RAE|DFE)|mcg|[μµu]g|mg|kg|kcal|kJ|mL|IU|UI|CFU|g|L|毫克|微克|千克|克|毫升|升|千卡|千焦|国际单位)(?![a-z])"#
        return matches(pattern, text).compactMap { match in
            guard let value = number(capture(match, 1, text)) else { return nil }
            let raw = capture(match, 2, text)
            let unit = raw.lowercased().replacingOccurrences(of: " ", with: "")
            let aliases = ["μg":"mcg", "µg":"mcg", "ug":"mcg", "毫克":"mg", "微克":"mcg", "克":"g", "千克":"kg", "毫升":"mL", "ml":"mL", "升":"L", "l":"L", "kj":"kJ", "千焦":"kJ", "千卡":"kcal", "ui":"IU", "iu":"IU", "国际单位":"IU", "cfu":"CFU", "mcgrae":"mcg RAE", "mcgdfe":"mcg DFE", "μgrae":"mcg RAE", "μgdfe":"mcg DFE"]
            return LabelQuantity(value: value, unit: aliases[unit] ?? raw, quote: capture(match, 0, text))
        }
    }
    public static func isInstruction(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        return ["posologie", "adultes:", "adultes :", "prendre", "directions", "recommended dose", "recommended use", "adults:", "take ", "suggested use", "服用说明", "建议服用", "推荐服用", "成人每天", "用法", "摂取目安", "お召し上がり", "복용", "modo de uso", "tomar ", "verzehrempfehlung"].contains { t.hasPrefix($0) }
    }
    public static func isConnector(_ text: String) -> Bool {
        let key = IngredientCatalog.normalized(text)
        return ["fournissant", "providing", "provides", "其中提供", "提供", "dont", "apportant", "providingthefollowing", "fournissantuntotalde", "providingatotalof"].contains(key)
    }
    public static func basis(_ quote: String) -> LabelBasis {
        if !matches(#"(?:per|pour|每|pro|por)\s*100\s*(?:g|克|グラム)(?![a-z])"#, quote).isEmpty { return LabelBasis(kind: .per100g, evidence: quote) }
        if !matches(#"(?:per|pour|每|pro|por)\s*100\s*(?:ml|毫升)(?![a-z])"#, quote).isEmpty { return LabelBasis(kind: .per100mL, evidence: quote) }
        if !matches(#"each\s*(?:softgel|capsule|tablet)|per\s*(?:softgel|capsule|tablet)|chaque\s*(?:gelule|gélule|capsule)|par\s*(?:gelule|gélule|capsule)|每粒|每片|1粒当たり|1錠当たり|1캡슐당|pro\s*kapsel|por\s*cápsula"#, quote).isEmpty { return LabelBasis(kind: .perUnit, units: 1, evidence: quote) }
        let countPattern = #"(?:serving\s*size\s*:?|portion\s*:?|par\s*portion\s*:?|每份(?:用量)?\s*[:：]?|1日当たり|一日当たり)\s*\(?\s*(\d+(?:[.,]\d+)?)\s*(?:softgels?|capsules?|tablets?|gélules?|gelules?|粒|片|錠)"#
        if let m = matches(countPattern, quote).first, let n = number(capture(m, 1, quote)), n > 0 { return LabelBasis(kind: quote.contains("日当たり") ? .perDaily : .perServing, units: n, evidence: quote) }
        if quote.contains("1日当たり") || quote.contains("一日当たり") { return LabelBasis(kind: .perDaily, evidence: quote) }
        if !matches(#"per serving|par portion|每份|pro portion|por porción"#, quote).isEmpty { return LabelBasis(kind: .perServing, evidence: quote) }
        return LabelBasis(evidence: quote)
    }
}
public enum SemanticValidator {
    public static func validate(_ proposal: SemanticProposal, document: OCRDocument, provider: String) -> ValidatedLabel {
        var warnings = document.warnings
        // Duplicate block IDs cannot be used to substitute unrelated evidence.
        guard Set(document.blocks.map(\.id)).count == document.blocks.count else {
            return ValidatedLabel(productName: "", basis: LabelBasis(), recommendations: [], ingredients: [], warnings: ["OCR 证据 ID 重复，已停止自动解析。"], provider: provider)
        }
        let blocks = Dictionary(uniqueKeysWithValues: document.blocks.map { ($0.id, $0) })
        let full = document.blocks.map(\.text).joined(separator: "\n")
        var basis = !proposal.basisQuote.isEmpty && full.contains(proposal.basisQuote) ? LabelEvidence.basis(proposal.basisQuote) : LabelBasis()
        let declared = document.blocks.filter { !LabelEvidence.isInstruction($0.text) }.map { LabelEvidence.basis($0.text) }.filter { $0.kind != .unknown }
        let incompatible = declared.contains { other in
            guard other.kind != .perDaily else { return false }
            let kind = other.kind == .perServing && other.units == 1 ? LabelBasisKind.perUnit : other.kind
            let selected = basis.kind == .perServing && basis.units == 1 ? LabelBasisKind.perUnit : basis.kind
            return kind != selected || (kind == .perServing && other.units != basis.units)
        }
        if incompatible { basis = LabelBasis(); warnings.append("标签包含多个不同计量基准，尚未自动选择表格列；请确认目标基准及含量。") }
        var items: [Ingredient] = []; var keys: [String: UUID] = [:]; var rowByID: [UUID: SemanticIngredient] = [:]
        let recommendations = proposal.recommendations.filter { !$0.isEmpty && full.contains($0) && LabelEvidence.isInstruction($0) }
        for untrustedRow in proposal.ingredients.prefix(80) {
            var normalized = normalizeQuotedName(untrustedRow)
            let cited = normalized.evidenceIDs.compactMap { blocks[$0] }
            if let quote = LabelNameEvidence.groundedQuote(normalized.nameQuote, in: cited) { normalized.nameQuote = quote }
            if ChemicalSources.isDetachedChemicalRow(normalized, in: document) { continue }
            let row = completePrintedQuantity(normalized, blocks: blocks, document: document)
            guard !row.key.isEmpty, keys[row.key] == nil, row.nameQuote.contains(where: { $0.isLetter }), LabelEvidence.quantities(row.nameQuote).isEmpty, LabelEvidence.basis(row.nameQuote).kind == .unknown, !LabelEvidence.isInstruction(row.nameQuote), !LabelEvidence.isConnector(row.nameQuote) else { warnings.append("已排除重复键、服用说明或连接词：\(row.name)"); continue }
            let evidence = row.evidenceIDs.compactMap { blocks[$0] }
            let hasAllEvidence = evidence.count == row.evidenceIDs.count && !evidence.isEmpty
            let nameBlocks = evidence.filter { $0.text.contains(row.nameQuote) }
            let amountBlocks = evidence.filter { !row.amountQuote.isEmpty && $0.text.contains(row.amountQuote) }
            guard hasAllEvidence, !nameBlocks.isEmpty, !evidence.allSatisfy({ LabelEvidence.isInstruction($0.text) }) else { warnings.append("AI 成分缺少原文名称证据，未采用：\(row.name)"); continue }
            // Model labels alone cannot turn arbitrary packaging words into a known nutrient.
            let id = IngredientCatalog.resolve(row.nameQuote)
            var reasons: [String] = []
            if id == nil { reasons.append("名称尚未可靠标准化；可能是未收录成分或 OCR 错字，请核对原文。") }
            if !row.canonicalID.isEmpty && row.canonicalID != (id ?? "") { warnings.append("AI 标识未采用；仅依据原文名称词典决定映射：" + row.nameQuote) }
            var value: Double?; var unit = row.unit.isEmpty ? "未标注" : row.unit
            let found = LabelEvidence.quantities(row.amountQuote)
            let requested = LabelEvidence.number(row.amount)
            if found.count == 1, let q = found.first, let requested, abs(q.value - requested) <= max(1e-10, abs(requested) * 1e-10),
               LabelEvidence.quantities("1 " + row.unit).first?.unit == q.unit, !amountBlocks.isEmpty, !amountBlocks.contains(where: { LabelEvidence.isInstruction($0.text) }),
               !evidence.contains(where: { $0.text.contains("<") || $0.text.contains(">") || $0.text.contains("≤") || $0.text.contains("≥") }) {
                // Same block, table row, or an immediately adjoining single-value line with geometry.
                let connected = nameBlocks.contains { name in amountBlocks.contains { amount in LabelEvidenceLink.linked(name, amount, in: document) } }
                if connected && nameBlocks.contains(where: { safeName(row.nameQuote, in: $0.text) }) && association(row, proposal: proposal, nameBlocks: nameBlocks, amountBlocks: amountBlocks) { value = q.value; unit = q.unit }
                else { reasons.append("跨行名称与数值没有可靠的表格 / 位置关联。") }
            } else { reasons.append("含量、单位或数值证据不足；没有猜测 OCR 错字。") }
            if evidence.contains(where: { ($0.confidence ?? 1) < 0.65 }) { value = nil; reasons.append("OCR 置信度低，需核对。") }
            if (document.languages == ["fr"] || amountBlocks.contains(where: { $0.language == "fr" })), row.amountQuote.contains(","), !LabelEvidence.matches(#"\d,\d{3}\b"#, row.amountQuote).isEmpty { value = nil; reasons.append("法文逗号数字存在歧义，需确认小数 / 千位。") }
            if basis.kind == .unknown || (basis.kind == .perDaily && basis.units == nil) { value = nil; reasons.append("计量基准未知或仅标示每日用量，需确认实际每份定义。") }
            let sources = ChemicalSources.attached(nameBlocks: nameBlocks, amountBlocks: amountBlocks, in: document)
            let redundantForm = id != nil && IngredientCatalog.resolve(row.chemicalForm) == id
            let sourceEvidence = sources.flatMap(\.evidenceIDs).compactMap { blocks[$0] }
            let formIsAttached = !sources.isEmpty && (nameBlocks + sourceEvidence).contains { $0.text.contains(row.chemicalForm) }
            let form = !row.chemicalForm.isEmpty && !redundantForm && (formIsAttached || nameBlocks.contains { $0.text.contains(row.chemicalForm) }) ? row.chemicalForm : ""
            // A declared nutrient total plus bracketed sources is not the mass of each compound.
            if !form.isEmpty && sources.isEmpty { reasons.append("含化学形式的成分需确认标签数值代表营养素净量还是化合物总量；不自动折算。") }
            else if !row.chemicalForm.isEmpty && !redundantForm && form.isEmpty { warnings.append("未采用缺少原文来源证据的 AI 化学形式：" + row.nameQuote) }
            let knownComponent = ["fishOil", "omega3", "epa", "dha", "turmericExtract"].contains(id ?? "")
            if knownComponent && row.relation == "equivalent" { reasons.append("该成分的等效关系缺少已支持的依据，已按成分保留并等待原文核对。") }
            let relation: IngredientRelation = id == "dryHerbEquivalent" || (row.relation == "equivalent" && !knownComponent) ? .equivalent : .component
            var item = Ingredient(name: IngredientCatalog.title(id, original: row.nameQuote), value: value, unit: unit, relation: relation, sourceText: evidence.map(\.text).joined(separator: "\n"), origin: provider == "offlineRules" ? .labelOCR : .aiEstimate)
            item.canonicalID = id; item.originalName = row.nameQuote; item.chemicalSources = sources.isEmpty ? nil : sources
            item.chemicalForm = id != nil && !sources.isEmpty ? nil : (form.isEmpty ? nil : form)
            // Preserve explicitly named D2/D3 variants without inferring a compound dose.
            if id == "vitaminD", let variant = LabelEvidence.matches(#"D[23]\b"#, row.nameQuote).first { item.chemicalForm = LabelEvidence.capture(variant, 0, row.nameQuote).uppercased() }
            item.sourceText = (evidence + sourceEvidence.filter { source in !evidence.contains { $0.id == source.id } }).map(\.text).joined(separator: "\n")
            item.evidenceIDs = Array(Set(row.evidenceIDs + sources.flatMap(\.evidenceIDs))).sorted(); item.reviewReasons = reasons; item.labelBasis = basis
            item.labelValue = value; item.labelUnit = unit
            if (basis.kind == .perServing || basis.kind == .perDaily), let count = basis.units, count > 0 { item.value = value.map { $0 / count } }
            if !row.ratio.isEmpty {
                if evidence.contains(where: { $0.text.contains(row.ratio) }), !LabelEvidence.matches(#"^\d+\s*:\s*\d+$"#, row.ratio).isEmpty { item.note = "提取比例 " + row.ratio; item.extractRatio = row.ratio }
                else { item.reviewReasons?.append("提取比例缺少原文证据。") }
            }
            if !row.concentration.isEmpty, evidence.contains(where: { $0.text.contains(row.concentration) }) { item.concentration = row.concentration }
            keys[row.key] = item.id; rowByID[item.id] = row; items.append(item)
        }
        for i in items.indices {
            guard let row = rowByID[items[i].id], !row.parentKey.isEmpty else { continue }
            if let parent = keys[row.parentKey], parent != items[i].id { items[i].parentID = parent }
            else { items[i].value = nil; items[i].reviewReasons?.append("父成分引用无效；子项已隔离，不自动写入。") }
        }
        // Deduplicate only the same identity, chemical form, relation AND normalized basis.
        var merged: [Ingredient] = []; var remap: [UUID: UUID] = [:]
        for item in items {
            if let id = item.canonicalID, let index = merged.firstIndex(where: { $0.canonicalID == id && $0.chemicalForm == item.chemicalForm && $0.relation == item.relation }) {
                let old = merged[index]
                let same = equalQuantity(old, item)
                if !same { merged[index].value = nil; merged[index].reviewReasons = (old.reviewReasons ?? []) + ["跨语言或重复标签含量冲突，不能自动合并。"] }
                merged[index].reviewReasons = Array(Set((merged[index].reviewReasons ?? []) + (item.reviewReasons ?? []))).sorted()
                merged[index].sourceText += "\n" + item.sourceText
                merged[index].evidenceIDs = Array(Set((old.evidenceIDs ?? []) + (item.evidenceIDs ?? []))).sorted()
                remap[item.id] = old.id
            } else { merged.append(item) }
        }
        for i in merged.indices { if let parent = merged[i].parentID { merged[i].parentID = remap[parent] ?? parent } }
        // Reject cycles, impossible quantities, and invented containment. Keep the untrusted
        // original graph in SemanticProposal; a review draft must still be saveable locally.
        var invalid = Set<UUID>()
        for item in merged {
            var seen = Set<UUID>(); var node: Ingredient? = item
            while let current = node {
                if !seen.insert(current.id).inserted { invalid.formUnion(seen); break }
                node = current.parentID.flatMap { parent in merged.first { $0.id == parent } }
            }
            if let parent = item.parentID.flatMap({ id in merged.first { $0.id == id } }) {
                let allowed: [String: String] = ["omega3":"fishOil", "epa":"omega3", "dha":"omega3", "dryHerbEquivalent":"turmericExtract"]
                // Known biology can validate this hierarchy; other model-created links need review.
                if allowed[item.canonicalID ?? ""] != parent.canonicalID { invalid.insert(item.id); invalid.insert(parent.id) }
            }
            if let v = item.value, let u = item.massUnit, item.relation != .equivalent {
                let children = merged.filter { $0.parentID == item.id && $0.relation == .component }
                let mass = children.reduce(0.0) { $0 + (($1.value ?? 0) * ($1.massUnit?.grams ?? 0)) }
                if mass > v * u.grams + 1e-10 { invalid.insert(item.id); invalid.formUnion(children.map(\.id)) }
            }
        }
        // Block the entire affected tree, including descendants of a conflicted parent.
        var changed = true
        while changed {
            changed = false
            for item in merged where item.parentID.map({ invalid.contains($0) }) == true {
                if invalid.insert(item.id).inserted { changed = true }
            }
        }
        for i in merged.indices where invalid.contains(merged[i].id) {
            merged[i].parentID = nil
            merged[i].reviewReasons = (merged[i].reviewReasons ?? []) + ["包含关系未知、环路或子量超过总量；已隔离该关系并阻止自动写入，原始关系保留在语义草稿中。"]
        }
        warnings += merged.flatMap { $0.reviewReasons ?? [] }
        if provider == "offlineRules" { warnings.append("端侧 AI 未使用：当前是保守规则草稿，需核对全部结果；未识别内容仍保留原文。") }
        return ValidatedLabel(productName: !proposal.productName.isEmpty && full.contains(proposal.productName) ? proposal.productName : "", basis: basis, recommendations: recommendations, ingredients: merged, warnings: Array(Set(warnings)).sorted(), provider: provider)
    }
    private static func normalizeQuotedName(_ row: SemanticIngredient) -> SemanticIngredient {
        guard IngredientCatalog.resolve(row.nameQuote) == nil else { return row }
        let aliases = IngredientCatalog.aliases.values.flatMap { $0 }.sorted { $0.count > $1.count }
        for alias in aliases {
            guard let range = row.nameQuote.range(of: alias, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) else { continue }
            let rest = String(row.nameQuote[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let q = LabelEvidence.quantities(rest)
            guard (q.count == 1 && q[0].quote == rest) || LabelEvidence.number(rest) != nil else { continue }
            var clean = row; clean.nameQuote = String(row.nameQuote[range]); return clean
        }
        return row
    }
    /// Numeric formatting omitted by the model can be completed from a single unambiguous
    /// printed quantity. Never replace a conflicting model number or an unrelated full quote.
    private static func completePrintedQuantity(_ row: SemanticIngredient, blocks: [String: OCRBlock], document: OCRDocument) -> SemanticIngredient {
        guard LabelEvidence.quantities(row.amountQuote).isEmpty else { return row }
        let evidence = row.evidenceIDs.compactMap { blocks[$0] }
        let names = evidence.filter { !$0.text.isEmpty && !row.nameQuote.isEmpty && $0.text.contains(row.nameQuote) }
        var candidates: [LabelQuantity] = []
        for block in evidence where !LabelEvidence.isInstruction(block.text) {
            if let range = block.text.range(of: row.nameQuote), !row.nameQuote.isEmpty {
                if let q = LabelEvidence.quantities(String(block.text[range.upperBound...])).first { candidates.append(q) }
            } else if names.contains(where: { LabelEvidenceLink.linked($0, block, in: document) }), LabelEvidence.quantities(block.text).count == 1 {
                candidates += LabelEvidence.quantities(block.text)
            }
        }
        guard let q = candidates.first, candidates.allSatisfy({ $0.value == q.value && $0.unit == q.unit }),
              row.amount.isEmpty || LabelEvidence.number(row.amount) == q.value,
              row.amountQuote.isEmpty || LabelEvidence.number(row.amountQuote) == q.value,
              row.unit.isEmpty || LabelEvidence.quantities("1 " + row.unit).first?.unit == q.unit else { return row }
        var completed = row
        completed.amount = String(q.value); completed.unit = q.unit; completed.amountQuote = q.quote
        return completed
    }
    private static func safeName(_ name: String, in source: String) -> Bool {
        guard let range = source.range(of: name) else { return false }
        let prefix = String(source[..<range.lowerBound])
        if let last = prefix.last, last.isLetter, name.first?.isASCII == true { return false }
        // Chinese compounds cannot be reduced to their final elemental character.
        if name.first?.isASCII == false, let last = prefix.last, last.isLetter {
            let part = prefix.components(separatedBy: CharacterSet(charactersIn: ",，;；:：()（）")).last ?? prefix
            if !["其中", "其中提供", "提供", "含", "含有"].contains(part.trimmingCharacters(in: .whitespaces)) { return false }
        }
        let suffix = String(source[range.upperBound...]).replacingOccurrences(of: #"[（(][^()（）]*[)）]"#, with: "", options: .regularExpression)
        if let first = suffix.first, first.isLetter { return false }
        if LabelEvidence.quantities(suffix).isEmpty && suffix.contains(where: { $0.isLetter }) { return false }
        return true
    }
    private static func association(_ row: SemanticIngredient, proposal: SemanticProposal, nameBlocks: [OCRBlock], amountBlocks: [OCRBlock]) -> Bool {
        // Bound a name's value to its own segment, never another ingredient on the same line.
        for block in nameBlocks where amountBlocks.contains(where: { $0.id == block.id }) {
            let text = block.text as NSString
            let nameRange = text.range(of: row.nameQuote)
            let start = NSMaxRange(nameRange)
            let boundaries = proposal.ingredients.filter { $0.key != row.key && !$0.nameQuote.isEmpty && (IngredientCatalog.resolve(row.nameQuote) == nil || IngredientCatalog.resolve($0.nameQuote) != IngredientCatalog.resolve(row.nameQuote)) }.compactMap { other -> Int? in
                let r = text.range(of: other.nameQuote, range: NSRange(location: start, length: text.length - start))
                return r.location == NSNotFound ? nil : r.location
            }
            let end = boundaries.min() ?? text.length
            let segment = text.substring(with: NSRange(location: start, length: end - start))
            guard let first = LabelEvidence.quantities(segment).first, first.quote == row.amountQuote, let amountRange = segment.range(of: first.quote) else { return false }
            var between = String(segment[..<amountRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = IngredientCatalog.resolve(row.nameQuote) {
                for alias in (IngredientCatalog.aliases[id] ?? []).sorted(by: { $0.count > $1.count }) { between = between.replacingOccurrences(of: alias, with: "", options: [.caseInsensitive, .diacriticInsensitive]) }
            }
            // A nutrient alias embedded in e.g. "Calcium carbonate" does not establish elemental mass.
            if IngredientCatalog.resolve(row.nameQuote) != nil {
                between = between.replacingOccurrences(of: #"[（(][^()（）]*[)）]"#, with: "", options: .regularExpression)
            }
            let words = between.filter { $0.isLetter }
            return words.isEmpty || ["providing", "fournissant", "含", "提供"].contains(words.lowercased())
        }
        return true // separate blocks are governed by table/geometry validation
    }
    private static func equalQuantity(_ a: Ingredient, _ b: Ingredient) -> Bool {
        let kindA = a.labelBasis?.kind == .perServing && a.labelBasis?.units != nil ? LabelBasisKind.perUnit : a.labelBasis?.kind
        let kindB = b.labelBasis?.kind == .perServing && b.labelBasis?.units != nil ? LabelBasisKind.perUnit : b.labelBasis?.kind
        guard kindA == kindB else { return false }
        if let av = a.value, let bv = b.value, let au = a.quantityUnit, let bu = b.quantityUnit, au.dimension == bu.dimension { return abs(av * au.canonicalMultiplier - bv * bu.canonicalMultiplier) < 1e-10 }
        return a.value == b.value && a.unit == b.unit
    }
}
