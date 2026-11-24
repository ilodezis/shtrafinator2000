import XCTest
@testable import ShtrafinatorCore

/// Подставной источник текста: отдаёт заранее заданные строки, без чтения настоящих PDF.
struct FakeScanTextExtractor: ScanTextExtracting {
    var linesByFileName: [String: [String]] = [:]
    var defaultLines: [String] = []
    var failure: (any Error)?

    func lines(fromPDFAt url: URL) throws -> [String] {
        if let failure { throw failure }
        return linesByFileName[url.lastPathComponent] ?? defaultLines
    }
}

final class ScanRenamingTests: XCTestCase {
    private var root: URL!
    private var scans: URL!

    override func setUpWithError() throws {
        root = try TestSupport.makeTemporaryDirectory()
        scans = root.appendingPathComponent("scans", isDirectory: true)
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makePDF(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? scans).appendingPathComponent(name)
        try Data("%PDF-1.4 dummy".utf8).write(to: url)
        return url
    }

    private func item(
        at url: URL, proposed: String, status: ScanItem.Status = .matched
    ) -> ScanItem {
        ScanItem(
            fileURL: url, proposedName: proposed, companyName: "ООО Альфа Трейд", inn: "7701999888",
            method: .body, confidence: 0.95, status: status
        )
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: - Анализ папки

    func testAnalyzeMatchesAgainstDocxInParentFolderThenRenames() throws {
        try Data("dummy docx".utf8).write(to: root.appendingPathComponent("ООО Альфа Трейд.docx"))
        let pdf = try makePDF("SKM_C25822092212000.pdf")

        let extractor = FakeScanTextExtractor(defaultLines: [
            "Уведомление об удержании штрафа",
            "ИНН 7701999888",
            "Между ООО Альфа Трейд (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС»",
        ])
        let results = try ScanRenaming.analyze(folder: scans, extractor: extractor)

        XCTAssertEqual(results.count, 1)
        let item = try XCTUnwrap(results.first)
        XCTAssertEqual(item.status, .matched)
        XCTAssertTrue(item.companyName.contains("Альфа Трейд"))
        XCTAssertEqual(item.proposedName, "ООО Альфа Трейд.pdf")
        XCTAssertTrue(item.needsRename)

        let outcomes = ScanRenaming.apply([item])
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(try XCTUnwrap(outcomes.first).success)

        XCTAssertFalse(FileManager.default.fileExists(atPath: pdf.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scans.appendingPathComponent("ООО Альфа Трейд.pdf").path))
    }

    func testAnalyzeEmptyFolderReturnsNothing() throws {
        XCTAssertEqual(try ScanRenaming.analyze(folder: scans, extractor: FakeScanTextExtractor()), [])
    }

    func testAnalyzeMissingFolderThrows() {
        let missing = root.appendingPathComponent("нет такой папки")
        XCTAssertThrowsError(try ScanRenaming.analyze(folder: missing, extractor: FakeScanTextExtractor())) { error in
            XCTAssertEqual(error as? ShtrafinatorError, ShtrafinatorError.folderNotFound(missing.path))
        }
    }

    func testAnalyzeIgnoresNonPDFAndSystemFiles() throws {
        try Data("x".utf8).write(to: scans.appendingPathComponent("заметки.txt"))
        try makePDF("._apple_double.pdf")
        try makePDF("~$lock.pdf")
        let results = try ScanRenaming.analyze(folder: scans, extractor: FakeScanTextExtractor())
        XCTAssertEqual(results, [])
    }

    func testUnrecognisedScanIsReportedAndKeepsName() throws {
        try makePDF("scan.pdf")
        let extractor = FakeScanTextExtractor(defaultLines: ["Какой-то текст без реквизитов"])
        let item = try XCTUnwrap(try ScanRenaming.analyze(folder: scans, extractor: extractor).first)
        XCTAssertEqual(item.status, .unrecognized)
        XCTAssertEqual(item.companyName, "—")
        XCTAssertEqual(item.proposedName, "scan.pdf")
        XCTAssertFalse(item.needsRename)
    }

    func testExtractorFailureBecomesErrorItem() throws {
        try makePDF("broken.pdf")
        let extractor = FakeScanTextExtractor(failure: ShtrafinatorError.invalidArchive)
        let item = try XCTUnwrap(try ScanRenaming.analyze(folder: scans, extractor: extractor).first)
        XCTAssertEqual(item.status, .error)
        XCTAssertNotNil(item.error)
        XCTAssertEqual(item.proposedName, "broken.pdf")
    }

    func testTwoScansOfSameCompanyGetDistinctProposals() throws {
        try makePDF("a.pdf")
        try makePDF("b.pdf")
        let extractor = FakeScanTextExtractor(defaultLines: [
            "Между ООО Альфа Трейд (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС»",
        ])
        let items = try ScanRenaming.analyze(folder: scans, extractor: extractor)
        XCTAssertEqual(items.map(\.proposedName), ["ООО Альфа Трейд.pdf", "ООО Альфа Трейд_2.pdf"])
    }

    func testFileAlreadyNamedCorrectlyKeepsItsName() throws {
        try makePDF("ООО Альфа Трейд.pdf")
        let extractor = FakeScanTextExtractor(defaultLines: [
            "Между ООО Альфа Трейд (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС»",
        ])
        let item = try XCTUnwrap(try ScanRenaming.analyze(folder: scans, extractor: extractor).first)
        XCTAssertEqual(item.proposedName, "ООО Альфа Трейд.pdf")
        XCTAssertFalse(item.needsRename)
    }

    func testProposalAvoidsNameAlreadyTakenByAnotherPDFInFolder() throws {
        // «ООО Альфа Трейд.pdf» уже лежит в папке и принадлежит другому скану (с другим текстом)
        try makePDF("ООО Альфа Трейд.pdf")
        try makePDF("новый.pdf")
        let extractor = FakeScanTextExtractor(linesByFileName: [
            "новый.pdf": ["Между ООО Альфа Трейд (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС»"],
            "ООО Альфа Трейд.pdf": ["Между ООО Вектор (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС»"],
        ])
        let items = try ScanRenaming.analyze(folder: scans, extractor: extractor)
        let fresh = try XCTUnwrap(items.first { $0.originalName == "новый.pdf" })
        XCTAssertEqual(fresh.proposedName, "ООО Альфа Трейд_2.pdf")
    }

    // MARK: - Переименование

    func testApplyNeverOverwritesExistingFile() throws {
        let source = try makePDF("скан.pdf")
        let existing = try makePDF("цель.pdf")
        let outcome = try XCTUnwrap(ScanRenaming.apply([item(at: source, proposed: "цель.pdf")]).first)

        XCTAssertFalse(outcome.success)
        XCTAssertFalse(outcome.skipped)
        XCTAssertTrue(try XCTUnwrap(outcome.error).contains("уже существует"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertEqual(try Data(contentsOf: existing), Data("%PDF-1.4 dummy".utf8))
    }

    func testApplyAppendsPdfExtensionWhenMissing() throws {
        let source = try makePDF("скан.pdf")
        let outcome = try XCTUnwrap(ScanRenaming.apply([item(at: source, proposed: "Новое имя")]).first)

        XCTAssertTrue(outcome.success)
        XCTAssertEqual(outcome.newURL.lastPathComponent, "Новое имя.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.newURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testApplyReturnsNewURL() throws {
        let source = try makePDF("старое.pdf")
        let outcome = try XCTUnwrap(ScanRenaming.apply([item(at: source, proposed: "новое.pdf")]).first)
        XCTAssertEqual(outcome.newURL.deletingLastPathComponent().standardizedFileURL, scans.standardizedFileURL)
        XCTAssertEqual(outcome.newURL.lastPathComponent, "новое.pdf")
    }

    func testCaseOnlyRenameWorks() throws {
        let source = try makePDF("scan.pdf")
        let outcome = try XCTUnwrap(ScanRenaming.apply([item(at: source, proposed: "SCAN.pdf")]).first)

        XCTAssertTrue(outcome.success, outcome.error ?? "")
        XCTAssertTrue(try names(in: scans).contains("SCAN.pdf"))
        XCTAssertFalse(try names(in: scans).contains("scan.pdf"))
    }

    func testSameNameIsSkippedNotFailed() throws {
        let source = try makePDF("ООО Альфа Трейд.pdf")
        let outcome = try XCTUnwrap(ScanRenaming.apply([item(at: source, proposed: "ООО Альфа Трейд.pdf")]).first)
        XCTAssertTrue(outcome.success)
        XCTAssertTrue(outcome.skipped)
    }

    func testMissingSourceAndEmptyNameAreReported() throws {
        let ghost = scans.appendingPathComponent("нет.pdf")
        let missing = try XCTUnwrap(ScanRenaming.apply([item(at: ghost, proposed: "x.pdf")]).first)
        XCTAssertFalse(missing.success)
        XCTAssertEqual(missing.error, "Файл не найден")

        let source = try makePDF("скан.pdf")
        let empty = try XCTUnwrap(ScanRenaming.apply([item(at: source, proposed: "   ")]).first)
        XCTAssertFalse(empty.success)
        XCTAssertEqual(empty.error, "Пустое имя файла")
    }

    func testNormalizedTargetNameReplacesSeparatorsAndAddsExtension() {
        XCTAssertEqual(ScanRenaming.normalizedTargetName("ООО/Ромашка:2026"), "ООО_Ромашка_2026.pdf")
        XCTAssertEqual(ScanRenaming.normalizedTargetName("Итог.PDF"), "Итог.PDF")
    }
}
