import Foundation

/// Источник текста первой страницы PDF. На macOS — PDFKit + Vision, в тестах — подставной.
public protocol ScanTextExtracting: Sendable {
    func lines(fromPDFAt url: URL) throws -> [String]
}

public struct ScanItem: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable {
        case matched, unrecognized, error
    }

    public let id: UUID
    public var fileURL: URL
    public var proposedName: String
    public var companyName: String
    public var inn: String
    public var method: CompanyInfo.Method
    public var confidence: Double
    public var status: Status
    public var error: String?

    public var originalName: String { fileURL.lastPathComponent }
    public var needsRename: Bool { proposedName.trimmed != originalName }

    public init(
        id: UUID = UUID(), fileURL: URL, proposedName: String, companyName: String, inn: String,
        method: CompanyInfo.Method, confidence: Double, status: Status, error: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.proposedName = proposedName
        self.companyName = companyName
        self.inn = inn
        self.method = method
        self.confidence = confidence
        self.status = status
        self.error = error
    }
}

public struct RenameOutcome: Sendable, Equatable {
    public let itemID: UUID
    public let newURL: URL
    public let success: Bool
    public let skipped: Bool
    public let error: String?
}

public enum ScanRenaming {
    /// Имена готовых уведомлений (.docx) в папке со сканами и уровнем выше — кандидаты для сопоставления.
    public static func candidateNames(near folder: URL) -> [String] {
        var folders = [folder]
        let parent = folder.standardizedFileURL.deletingLastPathComponent()
        if parent.path != folder.standardizedFileURL.path { folders.append(parent) }

        var candidates: Set<String> = []
        for directory in folders {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for item in items where item.lowercased().hasSuffix(".docx") && !item.hasPrefix("~$") {
                let stem = String(item.dropLast(5))
                let lower = stem.lowercased()
                if !lower.contains("шаблон") && !lower.contains("реестр") { candidates.insert(stem) }
            }
        }
        return candidates.sorted()
    }

    static func pdfFiles(in folder: URL) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ShtrafinatorError.folderNotFound(folder.path)
        }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.lowercased().hasSuffix(".pdf") && !$0.hasPrefix("._") && !$0.hasPrefix("~$") }
            .sorted()
    }

    /// Распознаёт каждый PDF в папке и предлагает новое имя. `progress(текущий, всего, имя файла)`.
    public static func analyze(
        folder: URL,
        extractor: ScanTextExtracting,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) throws -> [ScanItem] {
        let files = try pdfFiles(in: folder)
        guard !files.isEmpty else { return [] }

        let candidates = candidateNames(near: folder)
        // Имена, уже занятые в папке: новый скан той же компании не должен затереть старый.
        let existing = Set(files.map { $0.lowercased() })
        var usedProposed: Set<String> = []
        var items: [ScanItem] = []

        for (index, filename) in files.enumerated() {
            let url = folder.appendingPathComponent(filename)
            progress?(index + 1, files.count, filename)

            do {
                let info = CompanyRecognition.parse(try extractor.lines(fromPDFAt: url))
                let company = CompanyRecognition.bestCandidate(for: info.companyName, among: candidates) ?? info.companyName
                let stem = FileNaming.sanitize(company)

                guard !stem.isEmpty else {
                    items.append(ScanItem(
                        fileURL: url, proposedName: filename, companyName: company.isEmpty ? "—" : company,
                        inn: info.inn.isEmpty ? "—" : info.inn, method: info.method,
                        confidence: info.confidence, status: .unrecognized
                    ))
                    continue
                }

                var proposed = "\(stem).pdf"
                var counter = 2
                func taken(_ name: String) -> Bool {
                    let lower = name.lowercased()
                    return usedProposed.contains(lower) || (existing.contains(lower) && lower != filename.lowercased())
                }
                while taken(proposed) {
                    proposed = "\(stem)_\(counter).pdf"
                    counter += 1
                }
                usedProposed.insert(proposed.lowercased())

                items.append(ScanItem(
                    fileURL: url, proposedName: proposed, companyName: company,
                    inn: info.inn.isEmpty ? "—" : info.inn, method: info.method,
                    confidence: info.confidence, status: .matched
                ))
            } catch {
                items.append(ScanItem(
                    fileURL: url, proposedName: filename, companyName: "—", inn: "—",
                    method: .error, confidence: 0, status: .error, error: error.localizedDescription
                ))
            }
        }
        return items
    }

    /// Приводит введённое вручную имя к допустимому: без слэшей, с расширением .pdf.
    public static func normalizedTargetName(_ name: String) -> String {
        var clean = name.trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if !clean.lowercased().hasSuffix(".pdf") { clean += ".pdf" }
        return clean
    }

    /// Переименовывает файлы. Существующие файлы не перезаписываются (раньше они молча затирались).
    public static func apply(_ items: [ScanItem]) -> [RenameOutcome] {
        let fm = FileManager.default
        return items.map { item in
            let source = item.fileURL
            func fail(_ message: String, url: URL? = nil) -> RenameOutcome {
                RenameOutcome(itemID: item.id, newURL: url ?? source, success: false, skipped: false, error: message)
            }

            guard fm.fileExists(atPath: source.path) else { return fail("Файл не найден") }
            let rawName = item.proposedName.trimmed
            guard !rawName.isEmpty, rawName != ".pdf" else { return fail("Пустое имя файла") }

            let targetName = normalizedTargetName(rawName)
            let target = source.deletingLastPathComponent().appendingPathComponent(targetName)
            if target.path == source.path {
                return RenameOutcome(itemID: item.id, newURL: source, success: true, skipped: true, error: nil)
            }

            let caseOnlyChange = target.path.lowercased() == source.path.lowercased()
            if !caseOnlyChange && fm.fileExists(atPath: target.path) {
                return fail("Файл «\(targetName)» уже существует")
            }

            do {
                if caseOnlyChange {
                    // На нечувствительной к регистру APFS прямое переименование «a» → «A» — no-op.
                    let temporary = source.deletingLastPathComponent()
                        .appendingPathComponent(".\(UUID().uuidString).pdf")
                    try fm.moveItem(at: source, to: temporary)
                    try fm.moveItem(at: temporary, to: target)
                } else {
                    try fm.moveItem(at: source, to: target)
                }
                return RenameOutcome(itemID: item.id, newURL: target, success: true, skipped: false, error: nil)
            } catch {
                return fail(error.localizedDescription)
            }
        }
    }
}
