import Foundation

public struct LabelNameMatch: Sendable {
    public var range: NSRange
    public var quote: String
    public var canonicalID: String
}
/// Reviewed aliases and grammatical bilingual contractions, never edit-distance guessing.
public enum LabelNameEvidence {
    private static let vitaminPrefixes = #"(?:vitamine|vitamina|vitamin|维生素|ビタミン|비타민)"#
    private static let vitaminSuffix = #"(?:B12|B6|B5|B3|B2|B1|D3|D2|A|C|D|E|K)"#
    public static func sharedVitamin(_ name: String) -> String? {
        let pattern = "^" + vitaminPrefixes + "(?:\\s*/\\s*" + vitaminPrefixes + ")+\\s*(" + vitaminSuffix + ")$"
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let match = LabelEvidence.matches(pattern, clean).first else { return nil }
        return IngredientCatalog.resolve("Vitamin " + LabelEvidence.capture(match, 1, clean))
    }
    public static func matches(in text: String) -> [LabelNameMatch] {
        let ns = text as NSString
        var candidates: [LabelNameMatch] = []
        var aliases = IngredientCatalog.aliases.values.flatMap { $0 }
        aliases += Nutrient.allCases.flatMap { [$0.title, $0.rawValue] }
        for alias in Set(aliases) {
            let pattern = alias.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.map(NSRegularExpression.escapedPattern).joined(separator: #"[\s\p{Pd}]*"#)
            for m in LabelEvidence.matches(pattern, text) {
                let quote = ns.substring(with: m.range)
                if let id = IngredientCatalog.resolve(quote) { candidates.append(.init(range: m.range, quote: quote, canonicalID: id)) }
            }
        }
        let shared = vitaminPrefixes + "(?:\\s*/\\s*" + vitaminPrefixes + ")+\\s*" + vitaminSuffix
        for match in LabelEvidence.matches(shared, text) {
            let quote = ns.substring(with: match.range)
            if let id = sharedVitamin(quote) { candidates.append(.init(range: match.range, quote: quote, canonicalID: id)) }
        }
        candidates.sort { $0.range.length == $1.range.length ? $0.range.location < $1.range.location : $0.range.length > $1.range.length }
        let annotations = LabelEvidence.matches(#"[（(][^()（）]*[)）]"#, text).filter { LabelEvidence.quantities(LabelEvidence.capture($0, 0, text)).isEmpty }.map(\.range)
        var selected: [LabelNameMatch] = []
        for match in candidates {
            if annotations.contains(where: { NSIntersectionRange($0, match.range) == match.range }) { continue }
            let end = NSMaxRange(match.range)
            if match.quote.first?.isASCII == true, match.range.location > 0,
               UnicodeScalar(ns.character(at: match.range.location - 1)).map({ CharacterSet.letters.contains($0) }) == true { continue }
            if end < ns.length, UnicodeScalar(ns.character(at: end)).map({ CharacterSet.letters.contains($0) }) == true { continue }
            // B1 cannot be reduced from B12, nor D from D3.
            if match.quote.last?.isASCII == true, end < ns.length,
               UnicodeScalar(ns.character(at: end)).map({ CharacterSet.decimalDigits.contains($0) }) == true,
               match.quote.lowercased().hasPrefix("vitamin") { continue }
            if !selected.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) { selected.append(match) }
        }
        return selected.sorted { $0.range.location < $1.range.location }
    }
    /// Replace a normalized model label only with a uniquely identified, verbatim source span.
    public static func groundedQuote(_ requested: String, in blocks: [OCRBlock]) -> String? {
        for block in blocks {
            if let range = block.text.range(of: requested, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]), !requested.isEmpty {
                return String(block.text[range])
            }
        }
        guard let id = IngredientCatalog.resolve(requested) else { return nil }
        let candidates = blocks.flatMap { matches(in: $0.text) }.filter { $0.canonicalID == id }
        let quotes = Set(candidates.map(\.quote))
        guard quotes.count == 1 else { return nil }
        return quotes.first
    }
}
