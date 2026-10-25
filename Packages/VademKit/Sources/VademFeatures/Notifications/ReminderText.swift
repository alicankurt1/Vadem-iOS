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
}
