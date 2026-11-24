import XCTest
@testable import ShtrafinatorCore

final class ScanRecognitionTests: XCTestCase {
    func testBodyAnchorExtractsCompanyFromMezhdu() {
        let lines = [
            "Исх. № 100 от 01.09.2026г.",
            "Уведомление об удержании штрафа",
            "Между ООО «Ромашка Финанс» (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС» (далее – «Агрегатор»)",
            "заключены Условия осуществления расчетов...",
        ]
        let info = CompanyRecognition.parse(lines)
        XCTAssertEqual(info.companyName, "ООО «Ромашка Финанс»")
        XCTAssertEqual(info.method, .body)
        XCTAssertGreaterThanOrEqual(info.confidence, 0.85)
    }

    func testHeaderAnchorExtractsCompanyAndRequisites() {
        let lines = [
            "Исх. № 100",
            "Генеральному директору",
            "ООО «Северный Альянс»",
            "ОГРН 1157746123456",
            "ИНН 7701234567",
            "Уведомление об удержании штрафа",
        ]
        let info = CompanyRecognition.parse(lines)
        XCTAssertEqual(info.companyName, "ООО «Северный Альянс»")
        XCTAssertEqual(info.inn, "7701234567")
        XCTAssertEqual(info.ogrn, "1157746123456")
        XCTAssertTrue([CompanyInfo.Method.header, .headerBeforeInn].contains(info.method))
    }

    func testLineWithoutLegalFormBeforeInnIsIgnored() {
        let lines = [
            "Уведомление",
            "Северный Альянс, филиал",
            "ИНН 7701234567",
        ]
        let info = CompanyRecognition.parse(lines)
        XCTAssertEqual(info.inn, "7701234567")
        XCTAssertEqual(info.method, .none)
        XCTAssertEqual(info.companyName, "")
    }

    func testAggregatorLineIsNotTakenAsClient() {
        let info = CompanyRecognition.parse(["ООО «КЛАУДПЭЙМЕНТС»", "ИНН 7701234567"])
        XCTAssertEqual(info.companyName, "")
        XCTAssertEqual(info.method, .none)
    }

    func testTextLayerDetection() {
        XCTAssertTrue(CompanyRecognition.hasUsableTextLayer(["Уведомление об удержании"]))
        XCTAssertFalse(CompanyRecognition.hasUsableTextLayer(["abc", "xyz 123"]))
    }

    // MARK: - Сопоставление с готовыми уведомлениями

    func testExactNormalisedMatchReturnsCandidateSpelling() {
        let candidates = ["ООО «Ромашка Финанс»", "ИП Смирнов А. В.", "ООО Вектор"]
        XCTAssertEqual(
            CompanyRecognition.bestCandidate(for: "ООО Ромашка Финанс", among: candidates),
            "ООО «Ромашка Финанс»"
        )
    }

    func testOcrTypoIsCorrectedByFuzzyMatch() {
        let candidates = ["ООО «Ромашка Финанс»", "ИП Смирнов А. В.", "ООО Вектор"]
        XCTAssertEqual(
            CompanyRecognition.bestCandidate(for: "ООО Ромашкз Финанс", among: candidates),
            "ООО «Ромашка Финанс»"
        )
    }

    func testUnknownCompanyHasNoCandidate() {
        let candidates = ["ООО «Ромашка Финанс»", "ИП Смирнов А. В.", "ООО Вектор"]
        XCTAssertNil(CompanyRecognition.bestCandidate(for: "ЗАО Неизвестная Компания", among: candidates))
    }

    func testEmptyNameHasNoCandidate() {
        XCTAssertNil(CompanyRecognition.bestCandidate(for: "", among: ["ООО Вектор"]))
    }

    func testPrefersExactCandidateOverPrefixOfAnother() {
        XCTAssertEqual(
            CompanyRecognition.bestCandidate(for: "ООО Альфа Трейд", among: ["ООО Альфа Трейд", "ООО Альфа"]),
            "ООО Альфа Трейд"
        )
    }
}
