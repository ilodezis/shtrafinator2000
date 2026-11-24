import XCTest
@testable import ShtrafinatorCore

final class NoticeTemplateTests: XCTestCase {
    private var template: NoticeTemplate!
    private var temporaryDirectories: [URL] = []

    override func setUpWithError() throws {
        template = NoticeTemplate(data: try TestSupport.templateData())
    }

    override func tearDownWithError() throws {
        for url in temporaryDirectories { try? FileManager.default.removeItem(at: url) }
        temporaryDirectories = []
    }

    private func fill(
        _ record: NoticeRecord, signatory: String = ""
    ) throws -> (text: String, warnings: [String], docx: Data) {
        let (data, warnings) = try template.fill(
            record, letterDate: TestSupport.date(2026, 3, 15), signatory: signatory
        )
        return (try TestSupport.documentText(data), warnings, data)
    }

    // MARK: - Руководитель

    func testIndividualEntrepreneurNameIsDeclined() {
        let record = NoticeRecord(companyName: "ИП Завгороднев Григорий Викторович")
        let (name, missing) = NoticeTemplate.director(for: record)
        XCTAssertEqual(name, "Завгородневу Григорию Викторовичу")
        XCTAssertFalse(missing)
    }

    func testCompanyWithoutDirectorUsesPlaceholder() {
        let record = NoticeRecord(companyName: "ООО \"Атлантик Айти\"")
        let (name, missing) = NoticeTemplate.director(for: record)
        XCTAssertEqual(name, "[Руководитель не указан]")
        XCTAssertTrue(missing)
    }

    func testExplicitDirectorIsDeclined() {
        let record = NoticeRecord(
            companyName: "ООО \"Атлантик Айти\"", director: "Завгороднев Григорий Викторович"
        )
        let (name, missing) = NoticeTemplate.director(for: record)
        XCTAssertEqual(name, "Завгородневу Григорию Викторовичу")
        XCTAssertFalse(missing)
    }

    // MARK: - Интервал перед подписью

    func testShortRecordGetsMaximumSpacing() {
        let record = NoticeRecord(companyName: "ООО «Ромашка»", fine: 50000)
        XCTAssertEqual(NoticeTemplate.signatureSpacing(for: record), 2800)
    }

    func testMediumRecordGetsReducedSpacing() {
        let record = NoticeRecord(
            companyName: "ООО «АВТОТРАНСПОРТНЫЕ СИСТЕМЫ И ТЕХНОЛОГИИ»",
            fine: 345678, director: "Константинов Александр Сергеевич"
        )
        let spacing = NoticeTemplate.signatureSpacing(for: record)
        XCTAssertTrue((1800..<2800).contains(spacing), "spacing = \(spacing)")
    }

    func testLongRecordIsScaledDownButNotBelowFloor() {
        let medium = NoticeRecord(
            companyName: "ООО «АВТОТРАНСПОРТНЫЕ СИСТЕМЫ И ТЕХНОЛОГИИ»",
            fine: 345678, director: "Константинов Александр Сергеевич"
        )
        let long = NoticeRecord(
            companyName: "ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ «МЕЖДУНАРОДНЫЕ ЛОГИСТИЧЕСКИЕ СИСТЕМЫ И ЦИФРОВЫЕ СЕРВИСЫ ДЛЯ ЭЛЕКТРОННОЙ КОММЕРЦИИ»",
            fine: 12_894_567,
            director: "Константинопольский-Владимирский Вениамин Александрович",
            email: "headquarters-billing-department@international-logistics-ecommerce-group.com"
        )
        let longSpacing = NoticeTemplate.signatureSpacing(for: long)
        XCTAssertLessThan(longSpacing, NoticeTemplate.signatureSpacing(for: medium))
        XCTAssertGreaterThanOrEqual(longSpacing, 100)
    }

    func testExtremeRecordReachesFloor() {
        let extreme = NoticeRecord(
            companyName: String(repeating: "О", count: 200),
            fine: 999_999_999,
            director: String(repeating: "И", count: 100),
            email: String(repeating: "e", count: 100)
        )
        XCTAssertEqual(NoticeTemplate.signatureSpacing(for: extreme), 100)
    }

    // MARK: - Заполнение шаблона

    func testFillPutsFineInWordsIntoText() throws {
        let record = TestSupport.sampleRecord(
            companyName: "ООО \"Тест\"", fine: 243322, director: "Иванов Иван Иванович",
            ogrn: "1027700123456", email: "test@test.ru"
        )
        let (text, _, _) = try fill(record)
        XCTAssertTrue(
            text.contains("в размере 243 322 руб. (двести сорок три тысячи триста двадцать два рубля 00 копеек)."),
            text
        )
    }

    func testFillInsertsValuesAndHasNoWarningsForOptionalFields() throws {
        let (text, warnings, _) = try fill(TestSupport.sampleRecord())
        XCTAssertTrue(text.contains("Боваренко Сергею Владимировичу"))
        XCTAssertTrue(text.contains("1234567890123"))
        XCTAssertTrue(text.contains("test@atlantic.it"))
        XCTAssertTrue(text.contains("б/н от 15.03.2026г."))
        XCTAssertFalse(warnings.contains("Руководитель не указан"))
        XCTAssertFalse(warnings.contains("ОГРН не указан"))
        XCTAssertFalse(warnings.contains("Email не указан"))
    }

    func testFillRemovesDocumentProtectionFromSettings() throws {
        let (_, _, docx) = try fill(TestSupport.sampleRecord())
        let settings = try TestSupport.part(docx, "word/settings.xml")
        XCTAssertEqual(settings.childElements(named: "documentProtection").count, 0)
    }

    func testDefaultSignatoryIsPlaceholderWithWarning() throws {
        let (text, warnings, _) = try fill(TestSupport.sampleRecord())
        XCTAssertTrue(text.contains("____________/[Подписант не указан]"))
        XCTAssertTrue(warnings.contains("Подписант не указан"))
    }

    func testCustomSignatoryIsInjected() throws {
        let (text, warnings, _) = try fill(TestSupport.sampleRecord(), signatory: "Петров П.П.")
        XCTAssertTrue(text.contains("____________/Петров П.П."))
        XCTAssertFalse(warnings.contains("Подписант не указан"))
    }

    func testUnparseablePeriodGetsPlaceholder() throws {
        let (text, warnings, _) = try fill(TestSupport.sampleRecord(period: nil))
        XCTAssertTrue(warnings.contains("Период не распознан"))
        XCTAssertTrue(text.contains("[Период не указан]"))
    }

    func testMissingFraudShareAndOptionalFieldsGetPlaceholdersAndWarnings() throws {
        var record = TestSupport.sampleRecord(director: nil, ogrn: nil, email: nil)
        record.fraudShare = nil
        let (text, warnings, _) = try fill(record)
        XCTAssertTrue(text.contains("[% не указан]"))
        XCTAssertTrue(text.contains("[ОГРН не указан]"))
        XCTAssertTrue(text.contains("[Email не указан]"))
        XCTAssertTrue(text.contains("[Руководитель не указан]"))
        XCTAssertTrue(warnings.contains("% фрода не указан"))
        XCTAssertTrue(warnings.contains("ОГРН не указан"))
        XCTAssertTrue(warnings.contains("Email не указан"))
        XCTAssertTrue(warnings.contains("Руководитель не указан"))
    }

    func testFillThrowsWhenFineIsNil() {
        let record = TestSupport.sampleRecord(fine: nil)
        XCTAssertThrowsError(try template.fill(record, letterDate: TestSupport.date(2026, 3, 15))) { error in
            XCTAssertEqual(error as? ShtrafinatorError, ShtrafinatorError.fineMissing)
        }
    }

    func testTemplateSpacingWidthsAndWhitespace() throws {
        let (_, _, docx) = try fill(TestSupport.sampleRecord())
        let root = try TestSupport.part(docx, "word/document.xml")

        // Ширины колонок первой таблицы: 5845 и 3500
        let table = try XCTUnwrap(root.descendants(named: "tbl").first)
        let grid = try XCTUnwrap(table.firstChild(named: "tblGrid"))
        let gridCols = grid.childElements(named: "gridCol")
        XCTAssertGreaterThanOrEqual(gridCols.count, 2)
        XCTAssertEqual(gridCols[0].attributeValue("w"), "5845")
        XCTAssertEqual(gridCols[1].attributeValue("w"), "3500")

        let row = try XCTUnwrap(table.descendants(named: "tr").first)
        let cells = row.childElements(named: "tc")
        XCTAssertGreaterThanOrEqual(cells.count, 2)
        XCTAssertEqual(cells[0].descendants(named: "tcW").first?.attributeValue("w"), "5845")
        XCTAssertEqual(cells[1].descendants(named: "tcW").first?.attributeValue("w"), "3500")

        // Двойной пробел в ОГРН и в «–  «Условия»» убран
        let text = try TestSupport.documentText(docx)
        XCTAssertFalse(text.contains("ОГРН  "))
        XCTAssertTrue(text.contains("ОГРН 1234567890123"))
        XCTAssertFalse(text.contains("–  «Условия»"))
        XCTAssertTrue(text.contains("– «Условия»"))
    }

    // MARK: - Интервал перед таблицей подписи

    func testSignatureSpacingIsSetOnParagraphBeforeSignatureTable() throws {
        let record = TestSupport.sampleRecord(companyName: "ООО «Ромашка»", fine: 50000, director: "Иванов Иван Иванович", ogrn: "1027700123456", email: "test@romashka.ru")
        let (_, _, docx) = try fill(record, signatory: "Жаворонкина А.М.")
        let root = try TestSupport.part(docx, "word/document.xml")
        let body = try XCTUnwrap(root.firstChild(named: "body"))

        let elements = body.childElements
        let signatureTable = try XCTUnwrap(elements.last { $0.bareName == "tbl" })
        let index = try XCTUnwrap(elements.firstIndex { $0 === signatureTable })
        let paragraph = elements[index - 1]

        let spacing = try XCTUnwrap(paragraph.descendants(named: "spacing").first)
        XCTAssertEqual(spacing.attributeValue("after"), "2800")
    }

    func testSpacingPrecedesRunPropertiesInParagraphProperties() throws {
        let (_, _, docx) = try fill(TestSupport.sampleRecord(companyName: "ООО «Ромашка»", fine: 50000, director: "Иванов Иван Иванович"))
        let root = try TestSupport.part(docx, "word/document.xml")
        let body = try XCTUnwrap(root.firstChild(named: "body"))
        let elements = body.childElements
        let signatureTable = try XCTUnwrap(elements.last { $0.bareName == "tbl" })
        let index = try XCTUnwrap(elements.firstIndex { $0 === signatureTable })
        let pPr = try XCTUnwrap(elements[index - 1].firstChild(named: "pPr"))

        let names = pPr.childElements.map(\.bareName)
        let spacingIndex = try XCTUnwrap(names.firstIndex(of: "spacing"), "spacing не найден в pPr: \(names)")
        if let rPrIndex = names.firstIndex(of: "rPr") {
            XCTAssertLessThan(spacingIndex, rPrIndex, "порядок pPr: \(names)")
        }
        if let jcIndex = names.firstIndex(of: "jc") {
            XCTAssertLessThan(spacingIndex, jcIndex, "порядок pPr: \(names)")
        }
    }

    // MARK: - Пакетная генерация

    func testGenerateAllWritesFilesForEveryRecordInRegistry() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        temporaryDirectories.append(directory)
        let output = directory.appendingPathComponent("out", isDirectory: true)

        let results = try NoticeGenerator.generateAll(
            registryURL: TestSupport.fixture("mixed.xlsx"),
            outputDirectory: output,
            letterDate: TestSupport.date(2026, 3, 15),
            signatory: "Петров П.П.",
            template: template
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(\.success), "\(results)")
        XCTAssertEqual(results.map(\.filename), ["ИП Смирнов Алексей Викторович.docx", "ООО Текстовый штраф.docx"])
        for result in results {
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        }
    }

    func testGenerateAllReportsBadRowWithoutFailingOthers() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        temporaryDirectories.append(directory)
        let output = directory.appendingPathComponent("out", isDirectory: true)

        let results = try NoticeGenerator.generateAll(
            registryURL: TestSupport.fixture("unreadable_fine.xlsx"),
            outputDirectory: output,
            letterDate: TestSupport.date(2026, 3, 15),
            signatory: "",
            template: template
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[0].fileURL.path))

        XCTAssertFalse(results[1].success)
        XCTAssertNotNil(results[1].error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: results[1].fileURL.path))
    }
}
