import Foundation

/// A calendar month in the Gregorian calendar (year + month), with no day or time zone.
///
/// Installments and subscriptions are planned per month; this type is the key for that.
public struct YearMonth: Sendable, Hashable {
    /// The Gregorian year, e.g. `2026`.
    public let year: Int
    /// The month, `1...12`.
    public let month: Int

    /// Creates a value, or returns `nil` unless `month` is in `1...12`.
    public init?(year: Int, month: Int) {
        guard (1...12).contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    /// The month that contains `date` in `calendar`'s time zone.
    ///
    /// Only the calendar's time zone is used; the month is always Gregorian.
    public init(date: Date, calendar: Calendar) {
        // Gregorian dışı takvimlerde (ör. 13 aylı) ay numarası 1...12 dışına çıkabilir;
        // bu yüzden sadece saat dilimini alıp Gregoryen takvimle hesaplıyoruz.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month], from: date)
        self.year = components.year!
        self.month = components.month!
    }

    /// The month `months` after (or before, if negative) this one.
    public func adding(months: Int) -> YearMonth {
        // Ayları tek bir sayıya çevirip aşağı yuvarlayan bölme ile geri ayırıyoruz;
        // böylece negatif yönde de yıl geçişi doğru olur.
        let total = index + months
        let (quotient, remainder) = total.quotientAndRemainder(dividingBy: 12)
        let year = remainder < 0 ? quotient - 1 : quotient
        let month = (remainder < 0 ? remainder + 12 : remainder) + 1
        return YearMonth(uncheckedYear: year, month: month)
    }

    /// Signed number of months from this month to `other` (`2026-11 → 2027-02 = 3`).
    public func months(until other: YearMonth) -> Int {
        other.index - index
    }

    /// Number of days in this month, including Gregorian leap years.
    public var numberOfDays: Int {
        switch month {
        case 2:
            return isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    // 4'e bölünen yıllar artık; 100'e bölünenler değil; 400'e bölünenler yine artık.
    private var isLeapYear: Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    // Sıfırdan başlayan ay sırası: karşılaştırma ve aritmetik için tek ölçek.
    private var index: Int {
        year * 12 + (month - 1)
    }

    private init(uncheckedYear year: Int, month: Int) {
        self.year = year
        self.month = month
    }
}

extension YearMonth: Comparable {
    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        lhs.index < rhs.index
    }
}

// Kalıcı formatta "YYYY-MM" metni kullanılır (ör. "2026-03"): okunabilir ve
// sözlük sırası kronolojik sırayla aynıdır. Biçime tam uymayan metin reddedilir.
extension YearMonth: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = YearMonth(string: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid year-month (expected \"YYYY-MM\"): \(text)"
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    private var string: String {
        let yearText = String(year)
        let monthText = String(month)
        return String(repeating: "0", count: max(0, 4 - yearText.count)) + yearText
            + "-" + (month < 10 ? "0" : "") + monthText
    }

    // Tam olarak 4 rakam, '-', 2 rakam bekler; "2026-3" gibi kısa biçimler geçersiz.
    private init?(string text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 4, parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]) else {
            return nil
        }
        self.init(year: year, month: month)
    }
}
