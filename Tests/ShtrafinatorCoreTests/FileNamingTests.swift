import XCTest
@testable import ShtrafinatorCore

final class FileNamingTests: XCTestCase {
    func testSanitizeRemovesQuotesInsteadOfReplacingThem() {
        XCTAssertEqual(FileNaming.sanitize("ООО \"Ромашка\""), "ООО Ромашка")
        XCTAssertEqual(FileNaming.sanitize("ИП «Иванов И.И.»"), "ИП Иванов И.И.")
        XCTAssertEqual(FileNaming.sanitize("ООО “Ромашка”"), "ООО Ромашка")
        XCTAssertFalse(FileNaming.sanitize("ООО «Ромашка»").contains("_"))
    }

    func testSanitizeReplacesForbiddenCharactersWithUnderscore() {
        XCTAssertEqual(FileNaming.sanitize("ООО/Финанс:2026*"), "ООО_Финанс_2026")
    }

    func testSanitizeCollapsesWhitespace() {
        XCTAssertEqual(FileNaming.sanitize("  ООО   Вектор   "), "ООО Вектор")
    }

    func testSanitizeTruncatesLongNames() {
        let long = String(repeating: "Я", count: 300)
        let clean = FileNaming.sanitize(long)
        XCTAssertLessThanOrEqual(clean.count, 120)
        XCTAssertGreaterThan(clean.count, 100)
    }

    func testSanitizeStripsLeadingDots() {
        XCTAssertEqual(FileNaming.sanitize("...Скрытый"), "Скрытый")
        XCTAssertFalse(FileNaming.sanitize(".ООО Вектор").hasPrefix("."))
    }

    func testNoticeFilenameFallsBackForEmptyName() {
        XCTAssertEqual(FileNaming.noticeFilename(for: ""), "Без названия.docx")
        XCTAssertEqual(FileNaming.noticeFilename(for: "\"\""), "Без названия.docx")
        XCTAssertEqual(FileNaming.noticeFilename(for: "ООО «Ромашка»"), "ООО Ромашка.docx")
    }

    func testUniqueNameAddsCounterCaseInsensitively() {
        var used: Set<String> = []
        XCTAssertEqual(FileNaming.uniqueName("ООО Альфа.docx", used: &used), "ООО Альфа.docx")
        XCTAssertEqual(FileNaming.uniqueName("ооо альфа.DOCX", used: &used), "ооо альфа_2.DOCX")
        XCTAssertEqual(FileNaming.uniqueName("ООО Альфа.docx", used: &used), "ООО Альфа_3.docx")
        XCTAssertEqual(FileNaming.uniqueName("ООО Бета.docx", used: &used), "ООО Бета.docx")
    }
}
