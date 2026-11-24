import Foundation

public enum ShtrafinatorError: LocalizedError, Equatable, Sendable {
    case fileNotFound(String)
    case folderNotFound(String)
    case invalidArchive
    case invalidWorkbook(String)
    case sheetNotFound(available: [String])
    case missingColumns([String])
    case noRowsToProcess
    case fineMissing
    case fineNegative(Int64)
    case fineTooLarge(Int64)
    case templateUnavailable

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Файл не найден: \(path)"
        case .folderNotFound(let path):
            return "Папка не найдена: \(path)"
        case .invalidArchive:
            return "Файл повреждён или не является документом Office"
        case .invalidWorkbook(let reason):
            return "Не удалось прочитать Excel-файл: \(reason)"
        case .sheetNotFound(let available):
            return "Лист «Для соп-я» не найден. Доступные листы: \(available.joined(separator: ", "))"
        case .missingColumns(let fields):
            return "В заголовках не найдены колонки: \(fields.joined(separator: ", "))"
        case .noRowsToProcess:
            return "Не найдено строк с решением «да» для обработки"
        case .fineMissing:
            return "Не удалось распознать сумму штрафа"
        case .fineNegative(let amount):
            return "Сумма штрафа не может быть отрицательной: \(amount)"
        case .fineTooLarge(let amount):
            return "Сумма штрафа слишком велика для прописи: \(amount)"
        case .templateUnavailable:
            return "Не найден шаблон уведомления"
        }
    }
}
