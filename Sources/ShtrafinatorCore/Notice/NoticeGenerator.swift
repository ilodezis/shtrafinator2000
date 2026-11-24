import Foundation

public struct GenerationResult: Sendable, Identifiable, Equatable {
    public let id: Int
    public let filename: String
    public let fileURL: URL
    public let companyName: String
    public let success: Bool
    public let warnings: [String]
    public let error: String?
}

public enum FileNaming {
    /// Безопасное имя файла из названия компании: кавычки убираются, запрещённые символы → «_».
    public static func sanitize(_ name: String) -> String {
        var clean = name.trimmed
        for ch in "«»\"“”„'`" { clean = clean.replacingOccurrences(of: String(ch), with: "") }
        for ch in "\\/:*?<>|" { clean = clean.replacingOccurrences(of: String(ch), with: "_") }
        clean = Pattern("_+").replacingMatches(in: clean, with: "_")
        clean = Pattern(#"\s+"#).replacingMatches(in: clean, with: " ")
        clean = clean.strippingCharacters(in: " _")
        // Длинные названия упираются в лимит файловой системы (255 байт ≈ 127 кириллических букв).
        if clean.count > 120 { clean = String(clean.prefix(120)).strippingCharacters(in: " _.") }
        // Ведущая точка сделала бы файл скрытым в Finder.
        while clean.hasPrefix(".") || clean.hasPrefix(" ") { clean.removeFirst() }
        return clean
    }

    /// Имя .docx для компании; «Без названия», если от названия ничего не осталось.
    public static func noticeFilename(for companyName: String) -> String {
        let stem = sanitize(companyName)
        return (stem.isEmpty ? "Без названия" : stem) + ".docx"
    }

    /// Добавляет «_2», «_3»… если имя уже занято в этом запуске (без учёта регистра).
    public static func uniqueName(_ filename: String, used: inout Set<String>) -> String {
        if used.insert(filename.lowercased()).inserted { return filename }
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let base = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
            if used.insert(candidate.lowercased()).inserted { return candidate }
            counter += 1
        }
    }
}

public enum NoticeGenerator {
    /// Генерирует уведомления по всем строкам «да». `progress(текущий, всего)` вызывается после каждого файла.
    public static func generateAll(
        registryURL: URL,
        outputDirectory: URL,
        letterDate: CalendarDate,
        signatory: String,
        template: NoticeTemplate,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> [GenerationResult] {
        let records = try Registry.readRecords(from: registryURL)
        guard !records.isEmpty else { throw ShtrafinatorError.noRowsToProcess }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var used: Set<String> = []
        var results: [GenerationResult] = []
        for (index, record) in records.enumerated() {
            let filename = FileNaming.uniqueName(FileNaming.noticeFilename(for: record.companyName), used: &used)
            let url = outputDirectory.appendingPathComponent(filename)
            do {
                let (data, warnings) = try template.fill(record, letterDate: letterDate, signatory: signatory)
                try data.write(to: url, options: .atomic)
                results.append(GenerationResult(
                    id: index, filename: filename, fileURL: url, companyName: record.companyName,
                    success: true, warnings: warnings, error: nil
                ))
            } catch {
                results.append(GenerationResult(
                    id: index, filename: filename, fileURL: url, companyName: record.companyName,
                    success: false, warnings: [], error: error.localizedDescription
                ))
            }
            progress?(index + 1, records.count)
        }
        return results
    }
}
