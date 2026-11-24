import Foundation

/// Значение ячейки после вычисления формул (как `openpyxl` с `data_only=True`).
public enum CellValue: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case date(CalendarDate)

    /// Текстовое представление, как `str(value)` для текстовых колонок.
    var text: String {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "True" : "False"
        case .date(let d): return d.description
        case .number(let n): return Self.format(n)
        }
    }

    /// Число без хвоста `.0` у целых значений: 1027700123456.0 → "1027700123456".
    static func format(_ n: Double) -> String {
        if n.isFinite, n == n.rounded(.towardZero), abs(n) < 1e18 {
            return String(Int64(n))
        }
        return String(n)
    }
}

/// Лист Excel: ячейки по (строка, колонка), нумерация с 1.
public struct Worksheet: Sendable {
    public let name: String
    var cells: [Int: [Int: CellValue]]
    public let maxRow: Int
    public let maxColumn: Int

    public subscript(row: Int, column: Int) -> CellValue? {
        cells[row]?[column]
    }
}

/// Минимальный читатель .xlsx: имена листов, общие строки и значения ячеек.
struct XLSXWorkbook {
    let sheetNames: [String]
    private let sheetPaths: [String: String]
    private let package: ZipPackage
    private let sharedStrings: [String]

    init(contentsOf url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ShtrafinatorError.fileNotFound(url.path)
        }
        do {
            package = try ZipPackage(contentsOf: url)
        } catch {
            throw ShtrafinatorError.invalidWorkbook("это не файл .xlsx")
        }

        guard let workbookData = package["xl/workbook.xml"] else {
            throw ShtrafinatorError.invalidWorkbook("нет xl/workbook.xml")
        }
        let workbook = try XMLDocument.parseOOXML(workbookData)
        let relationships = try Self.relationships(package["xl/_rels/workbook.xml.rels"])

        var names: [String] = []
        var paths: [String: String] = [:]
        let sheets = workbook.rootElement()?.firstChild(named: "sheets")?.childElements(named: "sheet") ?? []
        for sheet in sheets {
            guard let name = sheet.attributeValue("name") else { continue }
            names.append(name)
            if let rid = sheet.attributeValue("id"), let target = relationships[rid] {
                paths[name] = Self.resolve(target: target)
            }
        }
        sheetNames = names
        sheetPaths = paths
        sharedStrings = try Self.sharedStrings(package["xl/sharedStrings.xml"])
    }

    func worksheet(named name: String) throws -> Worksheet {
        guard let path = sheetPaths[name], let data = package[path] else {
            throw ShtrafinatorError.invalidWorkbook("не удалось открыть лист «\(name)»")
        }
        let document = try XMLDocument.parseOOXML(data)
        var cells: [Int: [Int: CellValue]] = [:]
        var maxRow = 0
        var maxColumn = 0

        let rows = document.rootElement()?.firstChild(named: "sheetData")?.childElements(named: "row") ?? []
        var implicitRow = 0
        for row in rows {
            let rowIndex = row.attributeValue("r").flatMap(Int.init) ?? implicitRow + 1
            implicitRow = rowIndex
            var implicitColumn = 0
            for cell in row.childElements(named: "c") {
                let column = cell.attributeValue("r").flatMap(Self.columnIndex) ?? implicitColumn + 1
                implicitColumn = column
                maxRow = max(maxRow, rowIndex)
                maxColumn = max(maxColumn, column)
                if let value = value(of: cell) {
                    cells[rowIndex, default: [:]][column] = value
                }
            }
        }
        return Worksheet(name: name, cells: cells, maxRow: maxRow, maxColumn: maxColumn)
    }

    private func value(of cell: XMLElement) -> CellValue? {
        let type = cell.attributeValue("t") ?? "n"
        if type == "inlineStr" {
            return cell.firstChild(named: "is").map { .string(Self.richText($0)) }
        }
        guard let raw = cell.firstChild(named: "v")?.stringValue else { return nil }
        switch type {
        case "s":
            guard let index = Int(raw.trimmed), sharedStrings.indices.contains(index) else { return nil }
            return .string(sharedStrings[index])
        case "str", "e":
            return .string(raw)
        case "b":
            return .bool(raw.trimmed == "1")
        case "d":
            return DateParsing.isoDatePrefix(raw).map(CellValue.date) ?? .string(raw)
        default:
            guard !raw.trimmed.isEmpty else { return nil }
            return Double(raw.trimmed).map(CellValue.number) ?? .string(raw)
        }
    }

    /// Текст общей/встроенной строки: все `<t>`, кроме фонетических подсказок `<rPh>`.
    private static func richText(_ element: XMLElement) -> String {
        var text = ""
        func walk(_ node: XMLElement) {
            for child in node.childElements {
                switch child.bareName {
                case "t": text += child.stringValue ?? ""
                case "rPh", "phoneticPr": continue
                default: walk(child)
                }
            }
        }
        walk(element)
        return text
    }

    private static func sharedStrings(_ data: Data?) throws -> [String] {
        guard let data else { return [] }
        let document = try XMLDocument.parseOOXML(data)
        return (document.rootElement()?.childElements(named: "si") ?? []).map(richText)
    }

    private static func relationships(_ data: Data?) throws -> [String: String] {
        guard let data else { return [:] }
        let document = try XMLDocument.parseOOXML(data)
        var result: [String: String] = [:]
        for rel in document.rootElement()?.childElements(named: "Relationship") ?? [] {
            if let id = rel.attributeValue("Id"), let target = rel.attributeValue("Target") {
                result[id] = target
            }
        }
        return result
    }

    private static func resolve(target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        return "xl/" + target
    }

    /// "AB12" → 28.
    static func columnIndex(_ reference: String) -> Int? {
        var index = 0
        var sawLetter = false
        for scalar in reference.uppercased().unicodeScalars {
            guard (65...90).contains(scalar.value) else { break }
            index = index * 26 + Int(scalar.value - 64)
            sawLetter = true
        }
        return sawLetter ? index : nil
    }
}
