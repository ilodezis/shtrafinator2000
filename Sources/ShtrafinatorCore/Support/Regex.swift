import Foundation

/// Тонкая обёртка над NSRegularExpression, чтобы правила разбора читались как в Python.
struct Pattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        // Паттерны — константы в коде; ошибка в них — баг программиста.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Первое совпадение где угодно в строке (`re.search`): группы, 0 — всё совпадение.
    func firstMatch(in text: String) -> [String?]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    func matches(_ text: String) -> Bool { firstMatch(in: text) != nil }

    func replacingMatches(in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

extension String {
    /// Аналог Python `str.strip()` — пробелы и переводы строк, включая неразрывный пробел.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Длина в кодовых точках, как `len()` в Python.
    var scalarCount: Int { unicodeScalars.count }

    func strippingCharacters(in set: String) -> String {
        let chars = Set(set)
        var result = Substring(self)
        while let first = result.first, chars.contains(first) { result.removeFirst() }
        while let last = result.last, chars.contains(last) { result.removeLast() }
        return String(result)
    }
}
