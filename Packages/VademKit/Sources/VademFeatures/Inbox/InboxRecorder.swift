import Foundation
import VademCore

/// Adds the insights of a month to the inbox (``InboxPlanner`` on the saved payments).
///
/// Runs whether or not notifications are allowed: the inbox does not depend on the system
/// permission. The repository ignores ids it has already seen, so recording the same month
/// again (e.g. on every launch) adds nothing new and never brings back a deleted entry.
/// Best effort: repository errors are ignored.
@MainActor
public struct InboxRecorder {
    private let payments: any PaymentRepository
    private let inbox: any InboxRepository
    private let text: (MonthlyInsight) -> InboxPlanner.Text

    /// Creates a recorder; `text` gives an insight's title and body (default: the string catalog).
    public init(
        payments: any PaymentRepository,
        inbox: any InboxRepository,
        text: @escaping (MonthlyInsight) -> InboxPlanner.Text = { ReminderText.inboxText(for: $0) }
    ) {
        self.payments = payments
        self.inbox = inbox
        self.text = text
    }

    /// Adds one entry per insight about `month`, created at `date`; returns the number added.
    @discardableResult
    public func record(month: YearMonth, at date: Date) -> Int {
        let entries: [InboxEntry]
        do {
            entries = InboxPlanner.entries(
                for: month,
                createdAt: date,
                cards: try payments.cards(),
                installments: try payments.installments(),
                subscriptions: try payments.subscriptions(),
                oneTimePayments: try payments.oneTimePayments(),
                text: text
            )
        } catch {
            // Veri okunamazsa gelen kutusuna dokunulmaz.
            return 0
        }
        // Biri eklenemezse diğerleri yine denenir.
        return entries.reduce(0) { count, entry in
            count + (((try? inbox.add(entry)) ?? false) ? 1 : 0)
        }
    }
}
