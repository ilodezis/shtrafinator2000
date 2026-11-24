import Foundation
import Observation
import ShtrafinatorCore

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case notices, scans

    var id: Self { self }

    var title: String {
        switch self {
        case .notices: return "Уведомления"
        case .scans: return "Сканы"
        }
    }

    var subtitle: String {
        switch self {
        case .notices: return "Word из Excel-реестра"
        case .scans: return "Переименование PDF"
        }
    }

    var symbol: String {
        switch self {
        case .notices: return "doc.richtext"
        case .scans: return "doc.viewfinder"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var section: AppSection = .notices
    var showsRules = false

    let generator: GeneratorModel
    let scans: ScansModel

    init() {
        let generator = GeneratorModel()
        self.generator = generator
        scans = ScansModel(notices: { [weak generator] in generator?.outputDirectory })
    }
}

// MARK: - Генерация уведомлений

@MainActor
@Observable
final class GeneratorModel {
    enum ResultFilter: String, CaseIterable, Identifiable {
        case all, ready, warnings, errors
        var id: Self { self }
    }

    enum Phase: Equatable {
        case idle, generating, finished, failed(String)
    }

    private(set) var registryURL: URL?
    var outputDirectory: URL?
    var letterDate = Date()
    var signatory: String = UserDefaults.standard.string(forKey: "signatory") ?? "" {
        didSet { UserDefaults.standard.set(signatory, forKey: "signatory") }
    }

    private(set) var isInspecting = false
    private(set) var inspection: RegistryInspection?
    private(set) var inspectionError: String?

    private(set) var phase: Phase = .idle
    private(set) var progress = (current: 0, total: 0)
    private(set) var results: [GenerationResult] = []
    var filter: ResultFilter = .all

    var canGenerate: Bool {
        registryURL != nil && outputDirectory != nil && phase != .generating && !isInspecting
            && (inspection?.validRowsCount ?? 0) > 0
    }

    var readyCount: Int { results.filter { $0.success && $0.warnings.isEmpty }.count }
    var warningCount: Int { results.filter { $0.success && !$0.warnings.isEmpty }.count }
    var errorCount: Int { results.filter { !$0.success }.count }

    func count(for filter: ResultFilter) -> Int {
        switch filter {
        case .all: return results.count
        case .ready: return readyCount
        case .warnings: return warningCount
        case .errors: return errorCount
        }
    }

    var filteredResults: [GenerationResult] {
        switch filter {
        case .all: return results
        case .ready: return results.filter { $0.success && $0.warnings.isEmpty }
        case .warnings: return results.filter { $0.success && !$0.warnings.isEmpty }
        case .errors: return results.filter { !$0.success }
        }
    }

    var statusText: String {
        switch phase {
        case .idle:
            if let inspection { return "Готово к генерации: \(inspection.validRowsCount) уведомл." }
            return "Выберите реестр, чтобы начать"
        case .generating:
            return "Формирование документов: \(progress.current) из \(progress.total)…"
        case .finished:
            return errorCount == 0
                ? "Сформировано уведомлений: \(results.count)"
                : "Готово: \(results.count - errorCount) успешно, \(errorCount) с ошибками"
        case .failed(let message):
            return message
        }
    }

    func chooseRegistry() {
        if let url = Finder.chooseFile(title: "Excel-реестр штрафов", extensions: ["xlsx"]) {
            setRegistry(url)
        }
    }

    func chooseOutputDirectory() {
        if let url = Finder.chooseFolder(title: "Папка для уведомлений", startingAt: outputDirectory ?? registryURL?.deletingLastPathComponent()) {
            outputDirectory = url
        }
    }

    func useRegistryFolder() {
        outputDirectory = registryURL?.deletingLastPathComponent()
    }

    func setRegistry(_ url: URL) {
        guard url.pathExtension.lowercased() == "xlsx" else {
            inspection = nil
            inspectionError = "Нужен файл Excel в формате .xlsx"
            return
        }
        registryURL = url
        if outputDirectory == nil { outputDirectory = url.deletingLastPathComponent() }
        results = []
        phase = .idle
        inspect()
    }

    func inspect() {
        guard let url = registryURL else { return }
        isInspecting = true
        inspectionError = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try Registry.inspect(url) }
            }.value
            guard url == registryURL else { return }
            isInspecting = false
            switch outcome {
            case .success(let value):
                inspection = value
                progress = (0, value.validRowsCount)
            case .failure(let error):
                inspection = nil
                inspectionError = error.localizedDescription
            }
        }
    }

    func setToday() { letterDate = Date() }

    func setEndOfMonth() {
        letterDate = CalendarDate(letterDate).endOfMonth.date()
    }

    func generate() {
        guard canGenerate, let registryURL, let outputDirectory else { return }
        phase = .generating
        results = []
        filter = .all
        progress = (0, inspection?.validRowsCount ?? 0)

        let date = CalendarDate(letterDate)
        let signatory = signatory
        let model = self
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result {
                    try NoticeGenerator.generateAll(
                        registryURL: registryURL,
                        outputDirectory: outputDirectory,
                        letterDate: date,
                        signatory: signatory,
                        template: try AppResources.loadTemplate(),
                        progress: { current, total in
                            Task { @MainActor in model.progress = (current, total) }
                        }
                    )
                }
            }.value
            switch outcome {
            case .success(let items):
                results = items
                phase = .finished
            case .failure(let error):
                phase = .failed("Ошибка генерации: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Переименование сканов

@MainActor
@Observable
final class ScansModel {
    enum Phase: Equatable {
        case idle, analyzing, renaming
    }

    private let noticesDirectory: @MainActor () -> URL?

    private(set) var folder: URL?
    var items: [ScanItem] = []
    private(set) var phase: Phase = .idle
    private(set) var progress = (current: 0, total: 0, filename: "")
    private(set) var statusText = "Выберите папку, куда сканер сохранил PDF"
    private(set) var lastRename: (renamed: Int, failed: Int)?
    private(set) var renameErrors: [UUID: String] = [:]

    init(notices: @escaping @MainActor () -> URL?) {
        noticesDirectory = notices
    }

    var suggestedScansFolder: URL? {
        noticesDirectory()?.appendingPathComponent("сканы", isDirectory: true)
    }

    var recognizedCount: Int { items.filter { $0.status == .matched }.count }
    var manualCount: Int { items.count - recognizedCount }
    var pendingRenames: Int { items.filter(\.needsRename).count }

    func chooseFolder() {
        if let url = Finder.chooseFolder(title: "Папка со сканами", startingAt: folder ?? suggestedScansFolder ?? noticesDirectory()) {
            setFolder(url)
        }
    }

    func useSuggestedFolder() {
        if let url = suggestedScansFolder { setFolder(url) }
    }

    func setFolder(_ url: URL) {
        var isDirectory: ObjCBool = false
        let target = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            ? url.deletingLastPathComponent()
            : url
        folder = target
        items = []
        lastRename = nil
        renameErrors = [:]
        statusText = "Папка выбрана — можно распознавать"
        analyze()
    }

    func analyze() {
        guard let folder, phase == .idle else { return }
        phase = .analyzing
        lastRename = nil
        renameErrors = [:]
        progress = (0, 0, "")
        statusText = "Поиск PDF и распознавание текста…"

        let model = self
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result {
                    try ScanRenaming.analyze(folder: folder, extractor: PDFScanTextExtractor()) { current, total, name in
                        Task { @MainActor in model.progress = (current, total, name) }
                    }
                }
            }.value
            phase = .idle
            switch outcome {
            case .success(let found):
                items = found
                statusText = found.isEmpty
                    ? "В папке нет файлов .pdf"
                    : "Распознано \(recognizedCount) из \(found.count)"
            case .failure(let error):
                items = []
                statusText = error.localizedDescription
            }
        }
    }

    func proposedName(for id: UUID) -> String {
        items.first { $0.id == id }?.proposedName ?? ""
    }

    func setProposedName(_ name: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].proposedName = name
        renameErrors[id] = nil
    }

    func applyRenames() {
        let pending = items.filter(\.needsRename)
        guard !pending.isEmpty, phase == .idle else { return }
        phase = .renaming
        statusText = "Переименование…"

        Task {
            let outcomes = await Task.detached(priority: .userInitiated) { ScanRenaming.apply(pending) }.value
            var renamed = 0
            var failed = 0
            for outcome in outcomes {
                guard let index = items.firstIndex(where: { $0.id == outcome.itemID }) else { continue }
                if outcome.success {
                    if !outcome.skipped { renamed += 1 }
                    // Обновляем путь: теперь файл можно переименовать ещё раз (раньше это ломалось).
                    items[index].fileURL = outcome.newURL
                    items[index].proposedName = outcome.newURL.lastPathComponent
                    renameErrors[outcome.itemID] = nil
                } else {
                    failed += 1
                    renameErrors[outcome.itemID] = outcome.error
                }
            }
            lastRename = (renamed, failed)
            phase = .idle
            statusText = failed == 0
                ? "Переименовано файлов: \(renamed)"
                : "Переименовано: \(renamed), не удалось: \(failed)"
        }
    }
}
