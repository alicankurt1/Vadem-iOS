import Foundation
import VademCore

/// The localized notification text of a ``PlannedReminder``, built from its kind, payments and total.
///
/// ``VademCore`` stays free of UI text: the planner gives the facts, the words come from
/// VademFeatures' string catalog. English reads like the planner's own `title` / `body`.
public enum ReminderText {
    /// The notification title: `"Payment due today"` or `"Payment due tomorrow"`.
    public static func title(for reminder: PlannedReminder) -> String {
        switch reminder.kind {
        case .dueDay: String(localized: "Payment due today", bundle: .module, comment: "Notification title")
        case .dayBefore: String(localized: "Payment due tomorrow", bundle: .module, comment: "Notification title")
        }
    }

    /// The notification body: `"Rent due today, ₺15.000,00"` for one payment,
    /// `"3 payments due tomorrow, ₺1.234,00 total"` for more (plural from the catalog).
    public static func body(
        for reminder: PlannedReminder, formatAmount: (Money) -> String = AmountText.format
    ) -> String {
        // Tek ödeme kendi adını söyler; birden fazlası sayı ve toplamla tek bildirimde toplanır.
        if reminder.entries.count == 1, let entry = reminder.entries.first {
            let title = entry.title
            let amount = formatAmount(entry.amount)
            return switch reminder.kind {
            case .dueDay:
                String(localized: "\(title) due today, \(amount)", bundle: .module, comment: "Notification body: title, amount")
            case .dayBefore:
                String(localized: "\(title) due tomorrow, \(amount)", bundle: .module, comment: "Notification body: title, amount")
            }
        }
        let count = reminder.entries.count
        let total = formatAmount(reminder.total)
        return switch reminder.kind {
        case .dueDay:
            String(
                localized: "\(count) payments due today, \(total) total", bundle: .module,
                comment: "Notification body: number of payments, total amount"
            )
        case .dayBefore:
            String(
                localized: "\(count) payments due tomorrow, \(total) total", bundle: .module,
                comment: "Notification body: number of payments, total amount"
            )
        }
    }

    /// The monthly summary title: `"Monthly summary"`.
    public static func title(for summary: PlannedMonthlySummary) -> String {
        String(localized: "Monthly summary", bundle: .module, comment: "Notification title of the monthly summary")
    }

    /// The monthly summary body, from its insight: e.g.
    /// `"Your payments rose 50% this month (₺3.200,00 → ₺4.800,00)"` or
    /// `"Laptop: installment ended; you pay ₺500,00 less this month"`.
    public static func body(
        for summary: PlannedMonthlySummary,
        formatAmount: (Money) -> String = AmountText.format,
        locale: Locale = VademLocalization.locale
    ) -> String {
        body(for: summary.insight, formatAmount: formatAmount, locale: locale)
    }

    /// The text of `insight`, as in the monthly summary body;
    /// the percentage is written with `locale` (e.g. `50%`, Turkish `%50`).
    public static func body(
        for insight: MonthlyInsight,
        formatAmount: (Money) -> String = AmountText.format,
        locale: Locale = VademLocalization.locale
    ) -> String {
        switch insight.detail {
        case .totalChange(let previous, let current, let percent):
            // Yüzde işaretsiz yazılır; yön cümlenin fiilinden anlaşılır.
            let change = (Decimal(abs(percent)) / 100).formatted(.percent.locale(locale))
            let from = formatAmount(previous)
            let to = formatAmount(current)
            return percent >= 0
                ? String(
                    localized: "Your payments rose \(change) this month (\(from) → \(to))", bundle: .module,
                    comment: "Monthly summary body: percentage, last month's total, this month's total"
                )
                : String(
                    localized: "Your payments fell \(change) this month (\(from) → \(to))", bundle: .module,
                    comment: "Monthly summary body: percentage, last month's total, this month's total"
                )
        case .installmentEnded(let titles, let amount):
            let less = formatAmount(amount)
            // Tek plan adıyla söylenir; birden fazlası sayıyla.
            if titles.count == 1, let title = titles.first {
                return String(
                    localized: "\(title): installment ended; you pay \(less) less this month", bundle: .module,
                    comment: "Monthly summary body: installment title, amount paid less"
                )
            }
            let count = titles.count
            return String(
                localized: "\(count) installments ended; you pay \(less) less this month", bundle: .module,
                comment: "Monthly summary body: number of ended installments, amount paid less"
            )
        }
    }
}
