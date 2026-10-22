import Foundation
import VademCore

/// Parses typed amounts and builds the messages the forms show for them.
///
/// Shared by every form with an amount field, so they accept and reject the same text.
public enum AmountInput {
    /// The most digits ``parse(_:locale:)`` accepts before the decimal separator.
    public static let maxIntegerDigits = 12

    /// The most digits ``parse(_:locale:)`` accepts after the decimal separator.
    public static let maxFractionDigits = 6

    /// Parses `text` as a decimal number written with `locale`'s separators.
    ///
    /// Only ASCII digits, the locale's decimal separator (at most once) and a leading minus
    /// sign are accepted; surrounding whitespace is ignored. Returns `nil` for empty text or
    /// anything else, including grouping separators (`"1.499,90"` in Turkish), a `.` when
    /// the locale uses `,`, more than ``maxIntegerDigits`` digits before the separator
    /// (leading zeros count), more than ``maxFractionDigits`` digits after it (trailing
    /// zeros count) and a result that is NaN.
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        // Gruplama ayracı kabul edilmez: Türkçede "1499.90" sessizce 149990 olmasın, hata gösterilsin.
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = body.hasPrefix("-")
        if isNegative { body.removeFirst() }
        let parts = body.components(separatedBy: decimalSeparator)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.contains(where: { !$0.isEmpty }),
              // Çok uzun tam kısım reddedilir; Decimal'in sınırına yaklaşmadan hata gösterilir.
              parts[0].count <= maxIntegerDigits,
              // Kesir kısmı da sınırlanır; kuruş yuvarlaması için birkaç fazla hane yeterli.
              (parts.count < 2 || parts[1].count <= maxFractionDigits) else {
            return nil
        }
        // Locale'den bağımsız biçime çevrilip Decimal'e dönüştürülür; Double hiç kullanılmaz.
        let normalized = (isNegative ? "-" : "") + parts.map { $0.isEmpty ? "0" : $0 }.joined(separator: ".")
        // NaN doğrulamadan geçerdi (NaN <= 0 yanlış), bu yüzden burada elenir.
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else {
            return nil
        }
        return value
    }

    /// The message for an amount that is missing: empty `text`, or text that is not a number.
    static func missingMessage(for text: String, locale: Locale) -> String {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isEmpty ? "Enter an amount." : "Enter a number like 1499\(locale.decimalSeparator ?? ".")90."
    }

    /// The message for an amount that is zero or negative.
    static let notPositiveMessage = "Amount must be greater than zero."
}

// Seçim listelerinde sunulan aylar; iki form da aynı hesabı kullanır.
enum MonthOptions {
    // `month` çevresindeki aylar (önce `before`, sonra `after` ay); desteklenen aralığın dışına taşmaz.
    static func months(around month: YearMonth, before: Int, after: Int) -> [YearMonth] {
        let first = YearMonth(year: YearMonth.supportedYears.lowerBound, month: 1)!
        let last = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        let before = min(before, first.months(until: month))
        let after = min(after, month.months(until: last))
        return (-before...after).map { month.adding(months: $0) }
    }
}
