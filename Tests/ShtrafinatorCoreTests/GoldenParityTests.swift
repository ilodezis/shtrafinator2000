import Foundation
import XCTest
@testable import ShtrafinatorCore

/// Сверка с `golden.json`, который получен от ИСХОДНОГО Python-кода:
/// суммы прописью, штрафы, доли, нечёткое сопоставление, интервал подписи и текст готового документа.
final class GoldenParityTests: XCTestCase {
    private static func load() throws -> [String: Any] {
        let url = try TestSupport.fixture("golden.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    private static func section(_ name: String) throws -> Any {
        try XCTUnwrap(try load()[name], "в golden.json нет раздела \(name)")
    }

    private static func parseISODate(_ text: String) throws -> CalendarDate {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 3, "дата \(text)")
        return try XCTUnwrap(CalendarDate(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - Суммы прописью

    func testRublesMatchPython() throws {
        let table = try XCTUnwrap(try Self.section("rubles") as? [String: String])
        XCTAssertGreaterThan(table.count, 20)
        for (key, expected) in table {
            let amount = try XCTUnwrap(Int64(key), "ключ \(key)")
            XCTAssertEqual(try RussianText.rublesInWords(amount), expected, "сумма \(amount)")
        }
    }

    // MARK: - Штрафы

    func testFineFormattingMatchesPython() throws {
        let table = try XCTUnwrap(try Self.section("fine") as? [String: String])
        XCTAssertGreaterThan(table.count, 5)
        for (key, expected) in table {
            // ключ — repr числа из Python: "30000.0", "243322", "1000.5"
            let value = try XCTUnwrap(Double(key), "ключ \(key)")
            XCTAssertEqual(try RussianText.formatFine(value), expected, "штраф \(key)")
        }
    }

    // MARK: - Доли фрода

    func testFraudShareMatchesPython() throws {
        let table = try XCTUnwrap(try Self.section("fraud") as? [String: String])
        XCTAssertGreaterThan(table.count, 3)
        for (key, expected) in table {
            let value = try XCTUnwrap(Double(key), "ключ \(key)")
            XCTAssertEqual(RussianText.formatFraudShare(value), expected, "доля \(key)")
        }
    }

    // MARK: - Нечёткое сходство

    func testSequenceRatioMatchesDifflib() throws {
        let triples = try XCTUnwrap(try Self.section("ratio") as? [[Any]])
        XCTAssertGreaterThan(triples.count, 3)
        for triple in triples {
            let a = try XCTUnwrap(triple[0] as? String)
            let b = try XCTUnwrap(triple[1] as? String)
            let expected = try XCTUnwrap(triple[2] as? Double)
            XCTAssertEqual(SequenceMatcher(a, b).ratio, expected, accuracy: 1e-12, "ratio(\(a.prefix(20)), \(b.prefix(20)))")
        }
    }

    // MARK: - Сопоставление с кандидатами

    func testBestCandidateMatchesPython() throws {
        let cases = try XCTUnwrap(try Self.section("match") as? [[Any]])
        XCTAssertGreaterThan(cases.count, 3)
        for item in cases {
            let extracted = try XCTUnwrap(item[0] as? String)
            let candidates = try XCTUnwrap(item[1] as? [String])
            let expected = item[2] as? String // null в JSON → nil
            XCTAssertEqual(
                CompanyRecognition.bestCandidate(for: extracted, among: candidates), expected,
                "извлечено «\(extracted)»"
            )
        }
    }

    // MARK: - Интервал перед подписью

    func testSignatureSpacingMatchesPython() throws {
        let cases = try XCTUnwrap(try Self.section("spacing") as? [[Any]])
        XCTAssertGreaterThan(cases.count, 2)
        for item in cases {
            let dict = try XCTUnwrap(item[0] as? [String: Any])
            let expected = try XCTUnwrap(item[1] as? Int)
            let record = NoticeRecord(
                companyName: try XCTUnwrap(dict["yl"] as? String),
                fine: try XCTUnwrap(dict["fine"] as? Double),
                director: dict["director"] as? String,
                email: dict["email"] as? String
            )
            XCTAssertEqual(NoticeTemplate.signatureSpacing(for: record), expected, "запись \(dict["yl"] ?? "")")
        }
    }

    // MARK: - Готовый документ

    func testFilledDocumentTextMatchesPython() throws {
        let golden = try XCTUnwrap(try Self.section("document") as? [String: Any])
        let recordDict = try XCTUnwrap(golden["record"] as? [String: Any])

        let record = NoticeRecord(
            period: try Self.parseISODate(try XCTUnwrap(recordDict["period"] as? String)),
            inn: try XCTUnwrap(recordDict["inn"] as? String),
            companyName: try XCTUnwrap(recordDict["yl"] as? String),
            fine: try XCTUnwrap(recordDict["fine"] as? Double),
            fraudShare: try XCTUnwrap(recordDict["fraud_pct"] as? Double),
            director: recordDict["director"] as? String,
            ogrn: recordDict["ogrn"] as? String,
            email: recordDict["email"] as? String
        )
        let letterDate = try Self.parseISODate(try XCTUnwrap(golden["letter_date"] as? String))
        let template = NoticeTemplate(data: try TestSupport.templateData())

        let (docx, warnings) = try template.fill(
            record, letterDate: letterDate, signatory: try XCTUnwrap(golden["signatory"] as? String)
        )

        XCTAssertEqual(try TestSupport.documentText(docx), try XCTUnwrap(golden["text"] as? String))
        XCTAssertEqual(warnings, try XCTUnwrap(golden["warnings"] as? [String]))
    }
}
