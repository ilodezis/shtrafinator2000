import Foundation

/// Одна строка реестра с решением «да».
public struct NoticeRecord: Equatable, Sendable {
    public var period: CalendarDate?
    public var inn: String
    public var companyName: String
    /// `nil`, если сумма в ячейке не распозналась — такая строка даст ошибку генерации, а не уронит весь файл.
    public var fine: Double?
    public var fraudShare: Double?
    public var rowNumber: Int
    public var director: String?
    public var ogrn: String?
    public var email: String?

    public init(
        period: CalendarDate? = nil, inn: String = "", companyName: String, fine: Double? = 0,
        fraudShare: Double? = nil, rowNumber: Int = 0, director: String? = nil,
        ogrn: String? = nil, email: String? = nil
    ) {
        self.period = period
        self.inn = inn
        self.companyName = companyName
        self.fine = fine
        self.fraudShare = fraudShare
        self.rowNumber = rowNumber
        self.director = director
        self.ogrn = ogrn
        self.email = email
    }
}

public enum RegistryField: String, CaseIterable, Sendable {
    case period, inn, companyName = "yl", fraudRub = "fraud_rub", fine, decision
    case fraudShare = "fraud_pct", director, ogrn, email

    static let optional: Set<RegistryField> = [.director, .ogrn, .email]

    /// Ключевые слова заголовка: подходит, если все слова одного из вариантов есть в заголовке.
    var anchors: [[String]] {
        switch self {
        case .period: return [["отчетный", "период"]]
        case .inn: return [["инн"]]
        case .companyName: return [["юл"]]
        case .fraudRub: return [["фрод", "руб"]]
        case .fine: return [["штраф"]]
        case .decision: return [["решение"]]
        case .fraudShare: return [["% фрод"], ["фрода от оборота"]]
        case .director: return [["директор"], ["руководитель"], ["гендир"], ["фио"]]
        case .ogrn: return [["огрн"]]
        case .email: return [["email"], ["e-mail"], ["почта"]]
        }
    }
}

public struct RegistryInspection: Sendable {
    public struct Sample: Sendable, Identifiable {
        public let id: Int
        public let companyName: String
        public let inn: String
        public let fine: Double
        public let director: String
    }

    public let sheetName: String
    public let totalRows: Int
    public let validRowsCount: Int
    public let totalFineSum: Double
    public let columnsFound: [RegistryField]
    public let hasDirector: Bool
    public let hasOgrn: Bool
    public let hasEmail: Bool
    public let samples: [Sample]
}

public enum Registry {
    static let preferredSheetName = "Для соп-я"

    static func normalize(_ text: String) -> String {
        // «ё» → «е», чтобы «Отчётный период» находился так же, как «Отчетный период».
        text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmed.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    public static func headerMatches(_ header: String, _ options: [[String]]) -> Bool {
        let h = normalize(header)
        return options.contains { option in option.allSatisfy { h.contains($0) } }
    }

    static func findColumns(_ sheet: Worksheet) throws -> [RegistryField: Int] {
        var mapping: [RegistryField: Int] = [:]
        if sheet.maxColumn > 0 {
            for column in 1...sheet.maxColumn {
                guard let value = sheet[1, column] else { continue }
                let header = value.text
                for field in RegistryField.allCases where mapping[field] == nil {
                    if headerMatches(header, field.anchors) {
                        mapping[field] = column
                        break
                    }
                }
            }
        }
        let missing = RegistryField.allCases
            .filter { mapping[$0] == nil && !RegistryField.optional.contains($0) }
            .map(\.rawValue)
            .sorted()
        if !missing.isEmpty { throw ShtrafinatorError.missingColumns(missing) }
        return mapping
    }

    static func openSheet(_ url: URL) throws -> Worksheet {
        let workbook = try XLSXWorkbook(contentsOf: url)
        let name = workbook.sheetNames.first { $0 == preferredSheetName }
            ?? workbook.sheetNames.first { $0.lowercased().contains("соп") }
        guard let name else { throw ShtrafinatorError.sheetNotFound(available: workbook.sheetNames) }
        return try workbook.worksheet(named: name)
    }

    /// Строки с решением «да» из листа «Для соп-я».
    public static func readRecords(from url: URL) throws -> [NoticeRecord] {
        let sheet = try openSheet(url)
        return try records(in: sheet, columns: findColumns(sheet))
    }

    static func records(in sheet: Worksheet, columns: [RegistryField: Int]) -> [NoticeRecord] {
        func cell(_ row: Int, _ field: RegistryField) -> CellValue? {
            columns[field].flatMap { sheet[row, $0] }
        }
        func optionalText(_ value: CellValue?) -> String? {
            guard let value else { return nil }
            let text = value.text.trimmed
            return text.isEmpty ? nil : text
        }

        guard sheet.maxRow >= 2 else { return [] }
        var result: [NoticeRecord] = []
        for row in 2...sheet.maxRow {
            guard let decision = cell(row, .decision), decision.text.trimmed.lowercased() == "да" else { continue }

            guard let periodCell = cell(row, .period),
                  let innCell = cell(row, .inn),
                  let nameCell = cell(row, .companyName),
                  let fineCell = cell(row, .fine)
            else { continue }

            result.append(NoticeRecord(
                period: DateParsing.coerce(periodCell),
                inn: innCell.text.trimmed,
                companyName: nameCell.text.trimmed,
                fine: NumberParsing.number(fineCell),
                fraudShare: NumberParsing.fraction(cell(row, .fraudShare)),
                rowNumber: row,
                director: optionalText(cell(row, .director)),
                ogrn: optionalText(cell(row, .ogrn)),
                email: optionalText(cell(row, .email))
            ))
        }
        return result
    }

    /// Быстрый анализ файла для превью в интерфейсе.
    public static func inspect(_ url: URL) throws -> RegistryInspection {
        let sheet = try openSheet(url)
        let columns = try findColumns(sheet)
        let records = records(in: sheet, columns: columns)
        return RegistryInspection(
            sheetName: sheet.name,
            totalRows: max(0, sheet.maxRow - 1),
            validRowsCount: records.count,
            totalFineSum: records.reduce(0) { $0 + ($1.fine ?? 0) },
            columnsFound: RegistryField.allCases.filter { columns[$0] != nil },
            hasDirector: columns[.director] != nil,
            hasOgrn: columns[.ogrn] != nil,
            hasEmail: columns[.email] != nil,
            samples: records.prefix(5).enumerated().map { index, record in
                .init(
                    id: index,
                    companyName: record.companyName,
                    inn: record.inn,
                    fine: record.fine ?? 0,
                    director: record.director ?? "—"
                )
            }
        )
    }
}
