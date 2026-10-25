import Foundation
import VademCore

/// VademFeatures' localized texts and the locale its dates are written in.
///
/// Every user-visible text of the module lives in its `Localizable.xcstrings` (source language
/// English) and is looked up in ``bundle``. Dates use ``locale``, the language the catalog
/// resolved for the user, so month names always match the surrounding texts.
public enum VademLocalization {
    /// The bundle that holds VademFeatures' `Localizable.xcstrings`.
    public static var bundle: Bundle { .module }

    /// The locale of the language the catalog resolved (e.g. `en`); dates are formatted with it.
    public static var locale: Locale {
        Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
    }

    /// The month as `"October 2026"` (pattern and month names from `locale`).
    public static func monthTitle(_ month: YearMonth, locale: Locale = VademLocalization.locale) -> String {
        // Desen katalogdan gelir; dil sırası değiştirebilir (ör. "LLLL y").
        let pattern = String(
            localized: "pattern.monthYear", defaultValue: "LLLL yyyy", bundle: .module,
            comment: "Date pattern for a month title, e.g. October 2026"
        )
        return format(day: 1, of: month, pattern: pattern, locale: locale)
    }

    /// The month's short name as `"Oct"` (pattern and month names from `locale`).
    public static func shortMonthTitle(_ month: YearMonth, locale: Locale = VademLocalization.locale) -> String {
        let pattern = String(
            localized: "pattern.monthShort", defaultValue: "LLL", bundle: .module,
            comment: "Date pattern for a short month name on the chart axis, e.g. Oct"
        )
        return format(day: 1, of: month, pattern: pattern, locale: locale)
    }

    /// A day of a month as `"12 October"` (pattern and month names from `locale`).
    public static func dayTitle(day: Int, of month: YearMonth, locale: Locale = VademLocalization.locale) -> String {
        let pattern = String(
            localized: "pattern.dayMonth", defaultValue: "d MMMM", bundle: .module,
            comment: "Date pattern for a day of a month, e.g. 12 October"
        )
        return format(day: day, of: month, pattern: pattern, locale: locale)
    }

    /// Short weekday names from Sunday to Saturday (e.g. `"Sun"`), from `locale`.
    public static func shortWeekdaySymbols(locale: Locale = VademLocalization.locale) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter.shortStandaloneWeekdaySymbols
    }

    // Tarih Gregoryen takvimle, sabit (GMT) saat diliminde öğlen kurulur; gün kaymaz.
    private static func format(day: Int, of month: YearMonth, pattern: String, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = locale
        let components = DateComponents(year: month.year, month: month.month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
