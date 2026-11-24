import XCTest
@testable import ShtrafinatorCore

final class RegistryTests: XCTestCase {
    private let d2026_02_01 = TestSupport.date(2026, 2, 1)

    // MARK: - Заголовки

    func testHeaderMatchesRequiresAllWordsOfOneOption() {
        XCTAssertTrue(Registry.headerMatches("Отчетный период", [["отчетный", "период"]]))
        XCTAssertFalse(Registry.headerMatches("Период", [["отчетный", "период"]]))
    }

    func testHeaderMatchesAcceptsAnyOption() {
        XCTAssertTrue(Registry.headerMatches("директор", [["директор"], ["руководитель"]]))
        XCTAssertTrue(Registry.headerMatches("руководитель", [["директор"], ["руководитель"]]))
        XCTAssertFalse(Registry.headerMatches("менеджер", [["директор"], ["руководитель"]]))
    }

    func testHeaderMatchTreatsYoAsYe() {
        // «Отчётный» с ё раньше не находился — теперь совпадает с «Отчетный»
        XCTAssertTrue(Registry.headerMatches("Отчётный период", [["отчетный", "период"]]))
    }

    // MARK: - Даты

    func testCoerceDateFromCellValues() {
        // настоящая дата проходит как есть
        XCTAssertEqual(DateParsing.coerce(.date(d2026_02_01)), d2026_02_01)
        // Excel-серийник (1900 date system)
        XCTAssertEqual(DateParsing.coerce(.number(46054)), d2026_02_01)
        // текстовые форматы
        XCTAssertEqual(DateParsing.coerce(.string("2026-02-01")), d2026_02_01)
        XCTAssertEqual(DateParsing.coerce(.string("01.02.2026")), d2026_02_01)
    }

    func testCoerceDateUnrecognisedIsNilNotCrash() {
        XCTAssertNil(DateParsing.coerce(.string("февраль 2026")))
        XCTAssertNil(DateParsing.coerce(nil))
        XCTAssertNil(DateParsing.coerce(.bool(true)))
        XCTAssertNil(DateParsing.coerce(.string("2026-02-30")))
    }

    // MARK: - Чтение реестра

    func testReadsOptionalColumns() throws {
        let records = try Registry.readRecords(from: TestSupport.fixture("optional_columns.xlsx"))
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.companyName, "ООО Тест")
        XCTAssertEqual(record.director, "Иванов Иван Иванович")
        XCTAssertEqual(record.ogrn, "1027700123456")
        XCTAssertEqual(record.email, "test@test.ru")
        XCTAssertEqual(record.period, d2026_02_01)
        XCTAssertEqual(record.inn, "1234567890")
        XCTAssertEqual(record.fine, 5000)
        XCTAssertEqual(try XCTUnwrap(record.fraudShare), 0.01, accuracy: 1e-12)
    }

    func testMissingOptionalColumnsGiveNil() throws {
        let records = try Registry.readRecords(from: TestSupport.fixture("missing_optional.xlsx"))
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.companyName, "ООО Тест")
        XCTAssertNil(record.director)
        XCTAssertNil(record.ogrn)
        XCTAssertNil(record.email)
    }

    func testTextualPeriodParsedAndUnknownPeriodSkipped() throws {
        // «неизвестно» — не дата, но строка не теряется (период nil)
        let records = try Registry.readRecords(from: TestSupport.fixture("textual_period.xlsx"))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].period, d2026_02_01)
        XCTAssertNil(records[1].period)
        XCTAssertEqual(records[1].companyName, "ООО Тест2")
    }

    func testMixedWorkbookPicksSheetBySubstringAndFiltersRows() throws {
        let records = try Registry.readRecords(from: TestSupport.fixture("mixed.xlsx"))
        // «Пропуск» (нет) отброшена; «Без периода» с пустой датой пропущена целиком
        XCTAssertEqual(records.map(\.companyName), ["ИП Смирнов Алексей Викторович", "ООО «Текстовый штраф»"])

        let ip = records[0]
        XCTAssertEqual(ip.period, d2026_02_01)
        XCTAssertEqual(ip.inn, "7701234567")
        XCTAssertEqual(ip.fine, 243322)
        XCTAssertEqual(try XCTUnwrap(ip.fraudShare), 0.0186, accuracy: 1e-12)
        XCTAssertEqual(ip.rowNumber, 2)

        // текстовые значения: «30 000» и «1,86%» понимаются (раньше падало на всём файле)
        let text = records[1]
        XCTAssertEqual(text.period, CalendarDate(year: 2026, month: 4, day: 1))
        XCTAssertEqual(text.inn, "502409876543")
        XCTAssertEqual(text.fine, 30000)
        XCTAssertEqual(try XCTUnwrap(text.fraudShare), 0.0186, accuracy: 1e-12)
    }

    func testUnreadableFineIsNilNotFatal() throws {
        let records = try Registry.readRecords(from: TestSupport.fixture("unreadable_fine.xlsx"))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].fine, 5000)
        XCTAssertNil(records[1].fine)
        XCTAssertEqual(records[1].companyName, "ООО Плохая")
    }

    func testMissingRequiredColumnsThrowWithFieldNames() throws {
        XCTAssertThrowsError(try Registry.readRecords(from: TestSupport.fixture("missing_columns.xlsx"))) { error in
            guard case ShtrafinatorError.missingColumns(let fields) = error else {
                return XCTFail("неожиданная ошибка: \(error)")
            }
            XCTAssertTrue(fields.contains("decision"))
            XCTAssertTrue(fields.contains("fine"))
            XCTAssertFalse(fields.contains("period"))
            XCTAssertFalse(fields.contains("inn"))
        }
    }

    func testNoMatchingSheetThrowsWithAvailableNames() throws {
        XCTAssertThrowsError(try Registry.readRecords(from: TestSupport.fixture("no_sheet.xlsx"))) { error in
            XCTAssertEqual(
                error as? ShtrafinatorError,
                ShtrafinatorError.sheetNotFound(available: ["Лист1", "Итоги"])
            )
        }
    }

    // MARK: - Инспекция

    func testInspectSummarisesRegistry() throws {
        let meta = try Registry.inspect(TestSupport.fixture("inspect.xlsx"))
        XCTAssertEqual(meta.sheetName, "Для соп-я")
        XCTAssertEqual(meta.totalRows, 2)
        XCTAssertEqual(meta.validRowsCount, 1)
        XCTAssertEqual(meta.totalFineSum, 5000.0)
        XCTAssertTrue(meta.hasDirector)
        XCTAssertTrue(meta.hasOgrn)
        XCTAssertTrue(meta.hasEmail)
        XCTAssertEqual(meta.samples.count, 1)
        XCTAssertEqual(meta.samples.first?.companyName, "ООО Альфа")
    }
}
