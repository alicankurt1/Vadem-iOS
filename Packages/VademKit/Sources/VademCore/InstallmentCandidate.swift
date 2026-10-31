import Foundation

/// A calendar day printed on a statement (day, month, year), with no time or time zone.
///
/// Only real Gregorian dates exist: `31.04.2026` or `29.02.2025` cannot be created.
/// ``StatementParser`` makes one only from a four-digit year; a two-digit year (`12.10.26`) gives no date.
public struct StatementDate: Sendable, Hashable {
    /// The Gregorian year, in ``YearMonth/supportedYears``.
    public let year: Int
    /// The month, `1...12`.
    public let month: Int
    /// The day of the month, `1...` the number of days in ``month``.
    public let day: Int

    /// Creates a date, or returns `nil` unless it is a real Gregorian date
    /// with `year` in ``YearMonth/supportedYears``.
    public init?(year: Int, month: Int, day: Int) {
        guard YearMonth.supportedYears.contains(year), (1...12).contains(month) else { return nil }
        guard (1...StatementDate.daysIn(month: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The month this date falls in.
    public var yearMonth: YearMonth {
        // init yıl ve ayı zaten doğruladı; bu yüzden YearMonth her zaman oluşur.
        YearMonth(year: year, month: month)!
    }

    // Gregoryen artık yıl kuralı: 4'e bölünen, 100'e bölünmeyen ya da 400'e bölünen yıllar.
    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return isLeap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

/// An installment line found in a statement, before the user confirms it.
///
/// Every field is a `var` so the review screen can correct OCR mistakes before saving.
/// ``id`` only tells candidates apart in a list; it carries no meaning.
///
/// - Note: The synthesized `==` and `hash(into:)` include ``id``, which is random for every parsed
///   candidate. Two parses of the same text are therefore never equal; compare the other fields
///   (merchant, amount, installments, date) when checking parse results.
public struct InstallmentCandidate: Sendable, Hashable, Identifiable {
    /// A unique id for list identity; a new one is made for every candidate.
    public var id: UUID
    /// The merchant text left on the line after the date, marker and amounts are removed.
    public var merchant: String
    /// The amount paid for this installment, in TRY.
    public var installmentAmount: Decimal
    /// The installment this line is for, e.g. `3` in `3/6`.
    public var currentInstallment: Int
    /// The number of installments, e.g. `6` in `3/6`.
    public var totalInstallments: Int
    /// The date printed on the line, if there was one.
    public var date: StatementDate?

    /// Creates a candidate; `id` defaults to a new UUID.
    public init(
        id: UUID = UUID(), merchant: String, installmentAmount: Decimal,
        currentInstallment: Int, totalInstallments: Int, date: StatementDate? = nil
    ) {
        self.id = id
        self.merchant = merchant
        self.installmentAmount = installmentAmount
        self.currentInstallment = currentInstallment
        self.totalInstallments = totalInstallments
        self.date = date
    }
}
