import XCTest
@testable import ShtrafinatorCore

final class SequenceMatcherTests: XCTestCase {
    func testIdenticalStringsHaveRatioOne() {
        XCTAssertEqual(SequenceMatcher("абв", "абв").ratio, 1.0)
        XCTAssertEqual(SequenceMatcher("ООО Вектор", "ООО Вектор").ratio, 1.0)
    }

    func testBothEmptyHaveRatioOne() {
        XCTAssertEqual(SequenceMatcher("", "").ratio, 1.0)
    }

    func testEmptyAgainstNonEmptyHasRatioZero() {
        XCTAssertEqual(SequenceMatcher("", "abc").ratio, 0.0)
        XCTAssertEqual(SequenceMatcher("abc", "").ratio, 0.0)
    }

    func testDisjointStringsHaveRatioZero() {
        XCTAssertEqual(SequenceMatcher("abc", "xyz").ratio, 0.0)
    }

    func testKnownDifflibRatios() {
        // значения, которые даёт difflib.SequenceMatcher(None, a, b).ratio()
        XCTAssertEqual(SequenceMatcher("abcd", "bcda").ratio, 0.75, accuracy: 1e-12)
        XCTAssertEqual(
            SequenceMatcher("ооо ромашкз финанс", "ооо ромашка финанс").ratio,
            0.9444444444444444, accuracy: 1e-12
        )
    }

    func testRatioIsBetweenZeroAndOne() {
        let ratio = SequenceMatcher("ЗАО Неизвестная Компания", "ООО Вектор").ratio
        XCTAssertGreaterThanOrEqual(ratio, 0.0)
        XCTAssertLessThanOrEqual(ratio, 1.0)
    }

    func testLongStringsUseAutojunkWithoutCrashing() {
        // длинные строки (≥200 символов): популярные символы выкидываются, как в difflib
        let a = String(repeating: "x", count: 250) + "yz"
        let b = String(repeating: "x", count: 250) + "zy" + String(repeating: "q", count: 30)
        // значение difflib.SequenceMatcher(None, a, b).ratio() для этих же строк
        XCTAssertEqual(SequenceMatcher(a, b).ratio, 0.9400749063670412, accuracy: 1e-12)
    }
}
