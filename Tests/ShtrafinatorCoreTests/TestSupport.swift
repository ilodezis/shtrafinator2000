import Foundation
import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import ShtrafinatorCore

/// Общие помощники тестов: фикстуры, шаблон, временные папки, разбор docx.
enum TestSupport {
    /// Корень репозитория: Tests/ShtrafinatorCoreTests/TestSupport.swift → ../../..
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func fixture(_ name: String) throws -> URL {
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return directory.appendingPathComponent(name)
    }

    static func templateData() throws -> Data {
        try Data(contentsOf: repoRoot.appendingPathComponent("Resources/template.docx"))
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shtrafinator-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Корневой элемент XML-части docx/xlsx.
    static func part(_ package: Data, _ path: String) throws -> XMLElement {
        let zip = try ZipPackage(data: package)
        let data = try XCTUnwrap(zip[path], "в пакете нет \(path)")
        // Тот же приём, что в продакшене: иначе Foundation на macOS теряет узлы из одних пробелов.
        return try XCTUnwrap(XMLDocument.parseOOXMLPreservingSpaces(data).rootElement())
    }

    /// Текст документа так же, как `"".join(root.itertext())` в Python.
    static func documentText(_ docx: Data) throws -> String {
        (try part(docx, "word/document.xml").stringValue ?? "")
            .replacingOccurrences(of: String(XMLDocument.spaceSentinel), with: " ")
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        guard let date = CalendarDate(year: year, month: month, day: day) else {
            fatalError("некорректная тестовая дата \(year)-\(month)-\(day)")
        }
        return date
    }

    /// Типичная запись для заполнения шаблона; отдельные поля переопределяются в тестах.
    static func sampleRecord(
        companyName: String = "ООО «Атлантик Айти»",
        fine: Double? = 30000,
        director: String? = "Боваренко Сергей Владимирович",
        ogrn: String? = "1234567890123",
        email: String? = "test@atlantic.it",
        period: CalendarDate? = date(2026, 2, 1)
    ) -> NoticeRecord {
        NoticeRecord(
            period: period, inn: "344708426365", companyName: companyName, fine: fine,
            fraudShare: 0.0186, rowNumber: 2, director: director, ogrn: ogrn, email: email
        )
    }
}
