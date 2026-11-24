import Foundation

/// Дата без времени и часового пояса — всё, что нужно для периода и даты письма.
public struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    /// Создаёт дату, если такая существует в григорианском календаре.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Сегодняшняя дата по локальному часовому поясу.
    public static func today(calendar: Calendar = .current) -> CalendarDate {
        CalendarDate(Date(), calendar: calendar)
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// Дата в полночь по локальному времени (для DatePicker).
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// Последний день того же месяца.
    public var endOfMonth: CalendarDate {
        CalendarDate(year: year, month: month, day: Self.daysInMonth(year: year, month: month))!
    }

    /// Дата из порядкового номера Excel (1900-система): 46054 → 2026-02-01.
    public init(excelSerial: Double) {
        let days = Int(excelSerial.rounded(.down))
        // 1899-12-30 — эпоха Excel с учётом его «високосного» 1900 года.
        self = CalendarDate(daysSinceUnixEpoch: days + Self.excelEpochOffset)
    }

    private static let excelEpochOffset = -25569

    private init(daysSinceUnixEpoch z0: Int) {
        // Алгоритм Говарда Хиннанта civil_from_days.
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        month = m
        day = d
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
