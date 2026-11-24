import Foundation

/// Суммы прописью, форматирование полей уведомления и склонение ФИО.
public enum RussianText {
    static let monthsNominative = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь",
    ]

    private static let unitsMasculine = ["", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
    private static let unitsFeminine = ["", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
    private static let teens = [
        "десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать",
        "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать",
    ]
    private static let tens = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто"]
    private static let hundreds = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот"]

    /// Разряды от младшего к старшему: формы для 1 / 2 / 5 и женский ли род.
    private static let scales: [(forms: (String, String, String), feminine: Bool)] = [
        (("рубль", "рубля", "рублей"), false),
        (("тысяча", "тысячи", "тысяч"), true),
        (("миллион", "миллиона", "миллионов"), false),
        (("миллиард", "миллиарда", "миллиардов"), false),
        (("триллион", "триллиона", "триллионов"), false),
    ]

    public static let maxFine: Int64 = 999_999_999_999_999

    // MARK: - Числа

    /// Форма слова для количества n: рубль / рубля / рублей.
    public static func pluralForm(_ n: Int64, _ forms: (String, String, String)) -> String {
        if (11...14).contains(n % 100) { return forms.2 }
        switch n % 10 {
        case 1: return forms.0
        case 2...4: return forms.1
        default: return forms.2
        }
    }

    private static func triadWords(_ n: Int, feminine: Bool) -> [String] {
        let units = feminine ? unitsFeminine : unitsMasculine
        var words: [String] = []
        if n / 100 > 0 { words.append(hundreds[n / 100]) }
        let rest = n % 100
        if (10...19).contains(rest) {
            words.append(teens[rest - 10])
        } else {
            if rest / 10 > 0 { words.append(tens[rest / 10]) }
            if rest % 10 > 0 { words.append(units[rest % 10]) }
        }
        return words
    }

    /// 243322 → «двести сорок три тысячи триста двадцать два рубля».
    public static func rublesInWords(_ amount: Int64) throws -> String {
        if amount < 0 { throw ShtrafinatorError.fineNegative(amount) }
        if amount > maxFine { throw ShtrafinatorError.fineTooLarge(amount) }
        if amount == 0 { return "ноль рублей" }

        var triads: [Int] = []
        var n = amount
        while n > 0 {
            triads.append(Int(n % 1000))
            n /= 1000
        }

        var words: [String] = []
        for index in stride(from: triads.count - 1, through: 0, by: -1) {
            let triad = triads[index]
            guard triad > 0 else { continue }
            let scale = scales[index]
            words += triadWords(triad, feminine: scale.feminine)
            words.append(pluralForm(Int64(triad), scale.forms))
        }
        // Нулевая младшая триада (1 000 000): «рублей» выше не добавилось.
        if triads[0] == 0 { words.append(scales[0].forms.2) }
        return words.joined(separator: " ")
    }

    /// Целые рубли с разделителем-пробелом: 1234567 → «1 234 567».
    static func groupThousands(_ value: Int64) -> String {
        let digits = String(value.magnitude)
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        return (value < 0 ? "-" : "") + groups.joined(separator: " ")
    }

    /// «243 322 руб. (двести сорок три тысячи … рубля 00 копеек).»
    /// Штраф округляется до целых по-банковски, как и раньше: 1000,5 → 1000.
    public static func formatFine(_ value: Double) throws -> String {
        let rounded = value.rounded(.toNearestOrEven)
        guard rounded.isFinite else { throw ShtrafinatorError.fineMissing }
        guard rounded <= Double(maxFine) else {
            throw ShtrafinatorError.fineTooLarge(rounded < 9e18 ? Int64(rounded) : .max)
        }
        let rubles = Int64(rounded)
        return "\(groupThousands(rubles)) руб. (\(try rublesInWords(rubles)) 00 копеек)."
    }

    /// 0.0186 → «1,86».
    public static func formatFraudShare(_ value: Double) -> String {
        String(format: "%.2f", value * 100).replacingOccurrences(of: ".", with: ",")
    }

    /// «февраль 2026».
    public static func formatPeriod(_ date: CalendarDate) -> String {
        "\(monthsNominative[date.month - 1]) \(date.year)"
    }

    /// «б/н от 01.02.2026г.»
    public static func formatLetterDate(_ date: CalendarDate) -> String {
        String(format: "б/н от %02d.%02d.%04dг.", date.day, date.month, date.year)
    }

    // MARK: - Склонение ФИО в дательный падеж

    /// «Иванов Иван Иванович» → «Иванову Ивану Ивановичу».
    public static func declineToDative(_ fullName: String) -> String {
        let parts = fullName.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return fullName }

        let lastName = parts[0]
        let firstName = parts[1]
        let patronymic = parts.count > 2 ? parts[2] : ""
        let tail = parts.count > 3 ? Array(parts[3...]) : []

        let feminine = isFeminine(lastName: lastName, firstName: firstName, patronymic: patronymic)

        var result = [
            lastName.split(separator: "-", omittingEmptySubsequences: false)
                .map { declineWord(String($0), feminine: feminine, rule: declineLastName) }
                .joined(separator: "-"),
            declineWord(firstName, feminine: feminine, rule: declineFirstName),
        ]
        if !patronymic.isEmpty {
            result.append(declineWord(patronymic, feminine: feminine, rule: declinePatronymic))
        }
        result += tail
        return result.joined(separator: " ")
    }

    private static func isInitials(_ word: String) -> Bool {
        word.contains(".") || word.count == 1
    }

    private static func isFeminine(lastName: String, firstName: String, patronymic: String) -> Bool {
        let p = patronymic.lowercased()
        if !p.isEmpty && !isInitials(patronymic) {
            if p.hasSuffix("на") || p.hasSuffix("кызы") { return true }
            return false
        }
        // Нет отчества (или только инициалы) — сначала смотрим на фамилию, она надёжнее имени.
        let l = lastName.lowercased()
        if ["ова", "ева", "ёва", "ина", "ына", "ая"].contains(where: l.hasSuffix) { return true }
        if ["ов", "ев", "ёв", "ин", "ын", "ий", "ый", "ой"].contains(where: l.hasSuffix) { return false }
        if isInitials(firstName) { return false }
        let f = firstName.lowercased()
        return f.hasSuffix("а") || f.hasSuffix("я") || f.hasSuffix("и")
    }

    /// Правило: (слово в нижнем регистре, женский род) → (сколько букв отрезать, что добавить).
    private typealias Rule = (String, Bool) -> (drop: Int, add: String)

    /// Применяет правило, сохраняя регистр исходного слова (ИВАНОВ → ИВАНОВУ). Инициалы не трогает.
    private static func declineWord(_ word: String, feminine: Bool, rule: Rule) -> String {
        guard !word.isEmpty, !isInitials(word) else { return word }
        let (drop, add) = rule(word.lowercased(), feminine)
        guard drop > 0 || !add.isEmpty else { return word }
        let stem = String(word.dropLast(drop))
        let isUpper = word.count > 1 && word == word.uppercased() && word != word.lowercased()
        return stem + (isUpper ? add.uppercased() : add)
    }

    private static let indeclinableVowels: [String] = ["о", "е", "э", "и", "ы", "у", "ю"]

    private static func declineLastName(_ w: String, _ feminine: Bool) -> (drop: Int, add: String) {
        if w.hasSuffix("ко") { return (0, "") }
        if feminine {
            if w.hasSuffix("ая") { return (2, "ой") }
            if w.hasSuffix("яя") { return (2, "ей") }
            if ["ова", "ева", "ёва", "ина", "ына"].contains(where: w.hasSuffix) { return (1, "ой") }
            if w.hasSuffix("а") || w.hasSuffix("я") { return (1, "е") }
            return (0, "")  // Женские фамилии на согласную не склоняются.
        }
        if w.hasSuffix("ых") || w.hasSuffix("их") { return (0, "") }
        if w.hasSuffix("ый") || w.hasSuffix("ий") || w.hasSuffix("ой") { return (2, "ому") }
        if w.hasSuffix("й") || w.hasSuffix("ь") { return (1, "ю") }
        if w.hasSuffix("а") || w.hasSuffix("я") { return (1, "е") }
        if indeclinableVowels.contains(where: w.hasSuffix) { return (0, "") }
        return (0, "у")
    }

    private static func declineFirstName(_ w: String, _ feminine: Bool) -> (drop: Int, add: String) {
        if feminine {
            if w.hasSuffix("ия") { return (1, "и") }
            if w.hasSuffix("а") || w.hasSuffix("я") { return (1, "е") }
            if w.hasSuffix("ь") { return (1, "и") }
            return (0, "")
        }
        if w.hasSuffix("й") || w.hasSuffix("ь") { return (1, "ю") }
        if w.hasSuffix("а") || w.hasSuffix("я") { return (1, "е") }
        if indeclinableVowels.contains(where: w.hasSuffix) { return (0, "") }
        return (0, "у")
    }

    private static func declinePatronymic(_ w: String, _ feminine: Bool) -> (drop: Int, add: String) {
        if feminine { return w.hasSuffix("на") ? (1, "е") : (0, "") }
        return w.hasSuffix("ич") ? (0, "у") : (0, "")
    }
}
