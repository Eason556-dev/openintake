import Foundation

/// UI-only localization. Never use localized strings as IDs, units or parsing evidence.
public enum L10n {
    public static let preferenceKey = "interfaceLanguage"
    public static var preference: String {
        #if WIDGET_EXTENSION
        UserDefaults(suiteName: DashboardCache.group)?.string(forKey: preferenceKey) ?? "system"
        #else
        UserDefaults.standard.string(forKey: preferenceKey) ?? "system"
        #endif
    }
    public static func resolved(_ preference: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if preference == "en" || preference == "zh-Hans" { return preference }
        return preferred.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
    public static var language: String { resolved(preference) }
    public static var locale: Locale { Locale(identifier: language) }
    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
    public static func tr(_ message: Message, language: String? = nil) -> String {
        let code = language ?? self.language
        let bundle = resources.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? resources
        let result = bundle.localizedString(forKey: message.key, value: message.key, table: "Localizable")
        // Substitute once, so braces inside a product name remain literal user data.
        let expression = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        let source = result as NSString
        var output = "", offset = 0
        for match in expression.matches(in: result, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            let index = Int(source.substring(with: match.range(at: 1)))!
            output += message.arguments.indices.contains(index) ? message.arguments[index] : source.substring(with: match.range)
            offset = NSMaxRange(match.range)
        }
        return output + source.substring(from: offset)
    }
    /// For known UI labels/errors from the core or stored sync status, not user product names/OCR.
    public static func display(_ source: String) -> String {
        tr(Message(stringLiteral: source))
    }
    /// Only for app-generated diagnostics, never product names, OCR evidence or user text.
    /// Recognizes archived messages in either supported language without rewriting stored data.
    public static func diagnostic(_ source: String, language: String? = nil) -> String {
        let code = language ?? self.language
        let english = diagnosticEnglish
        if let translated = english[source] { return code == "en" ? translated : source }
        if let key = english.first(where: { $0.value == source })?.key { return code == "en" ? source : key }
        for template in diagnosticTemplates {
            let pattern = code == "en" ? template.chinese : template.english
            let input = source as NSString
            guard let match = pattern.firstMatch(in: source, range: NSRange(location: 0, length: input.length)) else { continue }
            let output = code == "en" ? template.translation : template.key
            let markers = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
            let ns = output as NSString
            var result = "", offset = 0
            for marker in markers.matches(in: output, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: offset, length: marker.range.location - offset))
                let index = Int(ns.substring(with: marker.range(at: 1)))!
                if let group = template.indices.firstIndex(of: index), group + 1 < match.numberOfRanges {
                    // Arguments are opaque user data. Never translate or re-interpolate them.
                    result += input.substring(with: match.range(at: group + 1))
                }
                offset = NSMaxRange(marker.range)
            }
            return result + ns.substring(from: offset)
        }
        if source.contains("\n") {
            return source.components(separatedBy: "\n").map { diagnostic($0, language: code) }.joined(separator: "\n")
        }
        return source
    }
    private static let diagnosticEnglish: [String: String] = {
        guard let path = resources.path(forResource: "Localizable", ofType: "strings", inDirectory: "en.lproj"),
              let data = FileManager.default.contents(atPath: path),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return [:] }
        return table
    }()
    private struct DiagnosticTemplate: @unchecked Sendable {
        var key: String
        var translation: String
        var chinese: NSRegularExpression
        var english: NSRegularExpression
        var indices: [Int]
    }
    private static let diagnosticTemplates: [DiagnosticTemplate] = {
        let markers = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        func pattern(_ text: String) -> (NSRegularExpression, [Int])? {
            let ns = text as NSString
            let matches = markers.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty, ns.length - matches.reduce(0, { $0 + $1.range.length }) >= 8 else { return nil }
            var regex = "^", offset = 0, indices: [Int] = []
            for match in matches {
                regex += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: offset, length: match.range.location - offset))) + "(.*?)"
                indices.append(Int(ns.substring(with: match.range(at: 1)))!)
                offset = NSMaxRange(match.range)
            }
            regex += NSRegularExpression.escapedPattern(for: ns.substring(from: offset)) + "$"
            return (try! NSRegularExpression(pattern: regex, options: .dotMatchesLineSeparators), indices)
        }
        return diagnosticEnglish.sorted { $0.key.count > $1.key.count }.compactMap { key, translation in
            guard let zh = pattern(key), let en = pattern(translation), zh.1 == en.1 else { return nil }
            return DiagnosticTemplate(key: key, translation: translation, chinese: zh.0, english: en.0, indices: zh.1)
        }
    }()
    public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        public var key: String
        public var arguments: [String]
        public init(stringLiteral value: String) { key = value; arguments = [] }
        public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
        public struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []
            public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
            public mutating func appendLiteral(_ literal: String) { key += literal }
            public mutating func appendInterpolation<T>(_ value: T) {
                key += "{\(arguments.count)}"; arguments.append(String(describing: value))
            }
            public mutating func appendInterpolation(_ value: Double, specifier: String) {
                key += "{\(arguments.count)}"; arguments.append(String(format: specifier, locale: L10n.locale, value))
            }
        }
    }
}
