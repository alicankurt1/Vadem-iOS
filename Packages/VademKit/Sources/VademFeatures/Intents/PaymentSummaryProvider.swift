import Foundation
import VademCore

/// Builds the spoken Siri / Shortcuts answers from the saved payments, via ``PaymentSummary``.
///
/// Free of AppIntents so it is testable on macOS; the app's intents only open the store and call it.
/// The answers never throw: on a repository error they return ``failureAnswer`` (Siri must always answer).
@MainActor
public struct PaymentSummaryProvider {
    /// The sentence both answers return when the payments cannot be loaded.
    public static var failureAnswer: String { String(localized: "I could not open your payments.", bundle: .module) }

    private let repository: any PaymentRepository
    private let calendar: Calendar
    private let now: () -> Date

    /// Creates a provider; `calendar` gives the time zone of "today" and `now` is the clock.
    public init(
        repository: any PaymentRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    /// Loads cards, installments and subscriptions and builds the summary for `now`.
    /// - Throws: Any error of the repository.
    public func summary() throws -> PaymentSummary {
        PaymentSummary(
            now: now(),
            calendar: calendar,
            cards: try repository.cards(),
            installments: try repository.installments(),
            subscriptions: try repository.subscriptions()
        )
    }

    /// The month total as a sentence (amounts via ``AmountText/spokenLabel(_:)``), or ``failureAnswer``.
    public func monthTotalAnswer() -> String {
        // Hata fırlatılmaz; Siri her durumda bir cümle söyler.
        guard let summary = try? summary() else { return Self.failureAnswer }
        return Self.monthTotalSentence(for: summary)
    }

    /// The next payment as a sentence (amount via ``AmountText/spokenLabel(_:)``), or ``failureAnswer``.
    public func nextPaymentAnswer() -> String {
        guard let summary = try? summary() else { return Self.failureAnswer }
        return Self.nextPaymentSentence(for: summary)
    }

    /// The month total of `summary` as a localized sentence:
    /// `"You pay <amount> in October 2026, <amount> still to go."`.
    ///
    /// The "still to go" part is left out when nothing or everything is still to pay;
    /// a month with nothing due reads `"Nothing is due in October 2026."`.
    /// - Parameter spokenAmount: Speaks an amount; defaults to ``AmountText/spokenLabel(_:)``.
    public static func monthTotalSentence(
        for summary: PaymentSummary, spokenAmount: (Money) -> String = AmountText.spokenLabel
    ) -> String {
        let monthText = VademLocalization.monthTitle(summary.month)
        guard !summary.monthTotal.isZero else {
            return String(localized: "Nothing is due in \(monthText).", bundle: .module, comment: "Siri answer; the argument is a month")
        }
        let total = spokenAmount(summary.monthTotal)
        if summary.remaining.isZero || summary.remaining == summary.monthTotal {
            return String(localized: "You pay \(total) in \(monthText).", bundle: .module, comment: "Siri answer: amount, month")
        }
        let remainingText = spokenAmount(summary.remaining)
        return String(
            localized: "You pay \(total) in \(monthText), \(remainingText) still to go.", bundle: .module,
            comment: "Siri answer: month total, month, amount still to pay"
        )
    }

    /// The first upcoming payment of `summary` as a localized sentence: `"Next: Rent, <amount>, today."`.
    ///
    /// The day reads today, tomorrow, in N days (2–6) or on a date (7 or more days);
    /// `"No upcoming payments."` when there is none.
    /// - Parameter spokenAmount: Speaks an amount; defaults to ``AmountText/spokenLabel(_:)``.
    public static func nextPaymentSentence(
        for summary: PaymentSummary, spokenAmount: (Money) -> String = AmountText.spokenLabel
    ) -> String {
        guard let first = summary.next.first else {
            return String(localized: "No upcoming payments.", bundle: .module, comment: "Siri answer")
        }
        let title = first.title
        let amount = spokenAmount(first.amount)
        let days = first.daysUntil
        switch days {
        case ...0:
            return String(localized: "Next: \(title), \(amount), today.", bundle: .module, comment: "Siri answer: title, amount")
        case 1:
            return String(localized: "Next: \(title), \(amount), tomorrow.", bundle: .module, comment: "Siri answer: title, amount")
        case 2..<7:
            return String(
                localized: "Next: \(title), \(amount), in \(days) days.", bundle: .module,
                comment: "Siri answer: title, amount, days until the payment"
            )
        default:
            let date = VademLocalization.dayTitle(day: first.dueDate.day, of: first.dueDate.month)
            return String(
                localized: "Next: \(title), \(amount), on \(date).", bundle: .module,
                comment: "Siri answer: title, amount, due date (e.g. 3 November)"
            )
        }
    }
}
