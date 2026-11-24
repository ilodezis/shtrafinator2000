import Foundation

enum DateParsing {
    private static let isoPrefix = Pattern(#"^(\d{4})-(\d{1,2})-(\d{1,2})"#)

    /// Форматы, которые понимала исходная программа: %Y-%m-%d, %d.%m.%Y, %d.%m.%y, %Y/%m/%d, %d/%m/%Y.
    private static let formats: [(Pattern, @Sendable (Int, Int, Int) -> (Int, Int, Int))] = [
        (Pattern(#"^(\d{4})-(\d{1,2})-(\d{1,2})$"#), { ($0, $1, $2) }),
        (Pattern(#"^(\d{1,2})\.(\d{1,2})\.(\d{4})$"#), { ($2, $1, $0) }),
        (Pattern(#"^(\d{1,2})\.(\d{1,2})\.(\d{2})$"#), { ($2 < 69 ? 2000 + $2 : 1900 + $2, $1, $0) }),
        (Pattern(#"^(\d{4})/(\d{1,2})/(\d{1,2})$"#), { ($0, $1, $2) }),
        (Pattern(#"^(\d{1,2})/(\d{1,2})/(\d{4})$"#), { ($2, $1, $0) }),
    ]

    /// Дата из текста или `nil`, если формат не распознан.
    static func parse(_ text: String) -> CalendarDate? {
        let s = text.trimmed
        for (pattern, order) in formats {
            guard let groups = pattern.firstMatch(in: s),
                  let a = groups[1].flatMap(Int.init),
                  let b = groups[2].flatMap(Int.init),
                  let c = groups[3].flatMap(Int.init)
            else { continue }
            let (year, month, day) = order(a, b, c)
            if let date = CalendarDate(year: year, month: month, day: day) { return date }
        }
        return nil
    }

    /// Дата из ISO-строки ячейки типа `d` ("2026-02-01T00:00:00").
    static func isoDatePrefix(_ text: String) -> CalendarDate? {
        guard let groups = isoPrefix.firstMatch(in: text.trimmed),
              let y = groups[1].flatMap(Int.init),
              let m = groups[2].flatMap(Int.init),
              let d = groups[3].flatMap(Int.init)
        else { return nil }
        return CalendarDate(year: y, month: m, day: d)
    }

    /// Привести значение ячейки периода к дате (`_coerce_date`).
    static func coerce(_ value: CellValue?) -> CalendarDate? {
        switch value {
        case .date(let d): return d
        case .number(let n): return n.isFinite ? CalendarDate(excelSerial: n) : nil
        case .string(let s): return parse(s)
        case .bool, .none: return nil
        }
    }
}

enum NumberParsing {
    /// Число из ячейки. Текст вида «30 000», «1 234,56» тоже понимается —
    /// исходная программа падала на нём для всего файла сразу.
    static func number(_ value: CellValue?) -> Double? {
        switch value {
        case .number(let n): return n.isFinite ? n : nil
        case .string(let s): return parse(s).map { $0.value }
        default: return nil
        }
    }

    /// Доля фрода: число как есть (0.0186), текст «1,86%» → 0.0186.
    static func fraction(_ value: CellValue?) -> Double? {
        switch value {
        case .number(let n): return n.isFinite ? n : nil
        case .string(let s):
            guard let parsed = parse(s) else { return nil }
            return parsed.hadPercent ? parsed.value / 100 : parsed.value
        default: return nil
        }
    }

    private static func parse(_ text: String) -> (value: Double, hadPercent: Bool)? {
        var s = text.trimmed
        let hadPercent = s.hasSuffix("%")
        if hadPercent { s.removeLast() }
        s = s.replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .replacingOccurrences(of: "руб.", with: "")
            .replacingOccurrences(of: "руб", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty, let value = Double(s), value.isFinite else { return nil }
        return (value, hadPercent)
    }
}
