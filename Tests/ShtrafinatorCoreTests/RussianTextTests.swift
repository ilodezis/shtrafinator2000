import XCTest
@testable import ShtrafinatorCore

final class RussianTextTests: XCTestCase {
    private func assertRubles(
        _ amount: Int64, _ expected: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(try RussianText.rublesInWords(amount), expected, file: file, line: line)
    }

    // MARK: - Сумма прописью

    func testRubleEndingDependsOnLastDigit() {
        assertRubles(0, "ноль рублей")
        assertRubles(1, "один рубль")
        assertRubles(2, "два рубля")
        assertRubles(4, "четыре рубля")
        assertRubles(5, "пять рублей")
        assertRubles(9, "девять рублей")
    }

    func testTeensAlwaysTakeGenitivePlural() {
        assertRubles(11, "одиннадцать рублей")
        assertRubles(12, "двенадцать рублей")
        assertRubles(13, "тринадцать рублей")
        assertRubles(14, "четырнадцать рублей")
        assertRubles(15, "пятнадцать рублей")
        assertRubles(111, "сто одиннадцать рублей")
        assertRubles(112, "сто двенадцать рублей")
        // 21 и 22 исключением уже не являются
        assertRubles(21, "двадцать один рубль")
        assertRubles(22, "двадцать два рубля")
    }

    func testThousandsAreFeminine() {
        assertRubles(1000, "одна тысяча рублей")
        assertRubles(2000, "две тысячи рублей")
        assertRubles(5000, "пять тысяч рублей")
        assertRubles(21000, "двадцать одна тысяча рублей")
        assertRubles(22000, "двадцать две тысячи рублей")
        assertRubles(11000, "одиннадцать тысяч рублей")
        assertRubles(14000, "четырнадцать тысяч рублей")
        // рубли мужского рода, тысячи женского — в одном числе
        assertRubles(1001, "одна тысяча один рубль")
        assertRubles(2002, "две тысячи два рубля")
    }

    func testMillionsAndBillionsAreMasculine() {
        assertRubles(1_000_000, "один миллион рублей")
        assertRubles(2_000_000, "два миллиона рублей")
        assertRubles(5_000_000, "пять миллионов рублей")
        assertRubles(1_000_000_000, "один миллиард рублей")
        assertRubles(2_000_000_001, "два миллиарда один рубль")
    }

    func testZeroTriadsAreSkippedButRublesRemain() {
        assertRubles(100, "сто рублей")
        assertRubles(1_000_100, "один миллион сто рублей")
        assertRubles(30000, "тридцать тысяч рублей")
        assertRubles(2_500_000, "два миллиона пятьсот тысяч рублей")
        assertRubles(
            999_999_999,
            "девятьсот девяносто девять миллионов девятьсот девяносто девять тысяч "
                + "девятьсот девяносто девять рублей"
        )
    }

    func testRejectsOutOfRangeAmounts() {
        XCTAssertThrowsError(try RussianText.rublesInWords(-5)) { error in
            XCTAssertEqual(error as? ShtrafinatorError, ShtrafinatorError.fineNegative(-5))
        }
        let tooLarge: Int64 = 1_000_000_000_000_000 // 10^15
        XCTAssertThrowsError(try RussianText.rublesInWords(tooLarge)) { error in
            XCTAssertEqual(error as? ShtrafinatorError, ShtrafinatorError.fineTooLarge(tooLarge))
        }
    }

    // MARK: - Форматирование штрафа

    func testFormatFineWithWords() throws {
        XCTAssertEqual(try RussianText.formatFine(243322), "243 322 руб. (двести сорок три тысячи триста двадцать два рубля 00 копеек).")
        XCTAssertEqual(try RussianText.formatFine(30000.0), "30 000 руб. (тридцать тысяч рублей 00 копеек).")
        XCTAssertEqual(try RussianText.formatFine(1), "1 руб. (один рубль 00 копеек).")
    }

    func testFineKopecksRoundToWholeRublesConsistently() throws {
        XCTAssertEqual(try RussianText.formatFine(1000.49), "1 000 руб. (одна тысяча рублей 00 копеек).")
        // банковское округление: 1000,5 → 1000, 1001,5 → 1002
        XCTAssertEqual(try RussianText.formatFine(1000.5), "1 000 руб. (одна тысяча рублей 00 копеек).")
        XCTAssertEqual(try RussianText.formatFine(1001.5), "1 002 руб. (одна тысяча два рубля 00 копеек).")
        XCTAssertEqual(try RussianText.formatFine(2.5), "2 руб. (два рубля 00 копеек).")
    }

    func testFineWithNonFiniteValueThrows() {
        XCTAssertThrowsError(try RussianText.formatFine(.nan)) { error in
            XCTAssertEqual(error as? ShtrafinatorError, ShtrafinatorError.fineMissing)
        }
    }

    func testFormatFraudShare() {
        XCTAssertEqual(RussianText.formatFraudShare(0.0186), "1,86")
        XCTAssertEqual(RussianText.formatFraudShare(0.01), "1,00")
        XCTAssertEqual(RussianText.formatFraudShare(0.12345), "12,35")
        XCTAssertEqual(RussianText.formatFraudShare(1.0), "100,00")
        XCTAssertEqual(RussianText.formatFraudShare(0.0), "0,00")
    }

    // MARK: - Склонение ФИО (дательный падеж)

    func testDeclinesMaleNames() {
        XCTAssertEqual(RussianText.declineToDative("Завгороднев Григорий Викторович"), "Завгородневу Григорию Викторовичу")
        XCTAssertEqual(RussianText.declineToDative("Романюк Максим Юрьевич"), "Романюку Максиму Юрьевичу")
        XCTAssertEqual(RussianText.declineToDative("Толкачёв Виктор Григорьевич"), "Толкачёву Виктору Григорьевичу")
        XCTAssertEqual(RussianText.declineToDative("Фомин Сергей Петрович"), "Фомину Сергею Петровичу")
    }

    func testMaleSurnamesOnYAndSoftSign() {
        XCTAssertEqual(RussianText.declineToDative("Нагорный Роман Дмитриевич"), "Нагорному Роману Дмитриевичу")
        XCTAssertEqual(RussianText.declineToDative("Гоголь Иван Петрович"), "Гоголю Ивану Петровичу")
    }

    func testIndeclinableSurnamesStayAsIs() {
        XCTAssertEqual(RussianText.declineToDative("Боваренко Сергей Владимирович"), "Боваренко Сергею Владимировичу")
        XCTAssertEqual(RussianText.declineToDative("Онипко Анна Витальевна"), "Онипко Анне Витальевне")
        // -ых / -их и заканчивающиеся на гласную о/е/и/у/ы/ю/э не склоняются
        XCTAssertEqual(RussianText.declineToDative("Черных Иван Петрович"), "Черных Ивану Петровичу")
        XCTAssertEqual(RussianText.declineToDative("Дурново Иван Петрович"), "Дурново Ивану Петровичу")
    }

    func testMaleSurnameOnA() {
        XCTAssertEqual(RussianText.declineToDative("Сорока Иван Петрович"), "Сороке Ивану Петровичу")
    }

    func testFemaleNames() {
        XCTAssertEqual(RussianText.declineToDative("Алехина Елена Сергеевна"), "Алехиной Елене Сергеевне")
        XCTAssertEqual(RussianText.declineToDative("Губанихина Юлия Николаевна"), "Губанихиной Юлии Николаевне")
        XCTAssertEqual(RussianText.declineToDative("Садовникова Полина Витальевна"), "Садовниковой Полине Витальевне")
        // женская фамилия на -а, не -ова/-ина/-ая, → -е
        XCTAssertEqual(RussianText.declineToDative("Сорока Анна Ивановна"), "Сороке Анне Ивановне")
    }

    func testInitialsAreNotTouched() {
        XCTAssertEqual(RussianText.declineToDative("Смирнов А. В."), "Смирнову А. В.")
        XCTAssertEqual(RussianText.declineToDative("Петров П.П."), "Петрову П.П.")
    }

    func testCapitalsArePreserved() {
        XCTAssertEqual(RussianText.declineToDative("ИВАНОВ ИВАН ИВАНОВИЧ"), "ИВАНОВУ ИВАНУ ИВАНОВИЧУ")
    }

    func testHyphenatedSurnamesDeclineEachPart() {
        XCTAssertEqual(RussianText.declineToDative("Смирнова-Иванова Анна Сергеевна"), "Смирновой-Ивановой Анне Сергеевне")
        XCTAssertEqual(RussianText.declineToDative("Иванов-Петров Иван Иванович"), "Иванову-Петрову Ивану Ивановичу")
    }

    func testGenderWithoutPatronymicIsGuessedFromSurname() {
        // фамилия решает раньше имени: «Анна» женское имя, но фамилия мужская
        XCTAssertEqual(RussianText.declineToDative("Иванова Анна"), "Ивановой Анне")
        XCTAssertEqual(RussianText.declineToDative("Иванов Анна"), "Иванову Анне")
        XCTAssertEqual(RussianText.declineToDative("Иванов Иван"), "Иванову Ивану")
    }

    func testSingleWordIsReturnedUnchanged() {
        XCTAssertEqual(RussianText.declineToDative("Иванов"), "Иванов")
    }
}
