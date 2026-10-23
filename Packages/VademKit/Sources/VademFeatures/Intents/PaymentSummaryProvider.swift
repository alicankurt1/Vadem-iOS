import Foundation
import VademCore

/// Builds the spoken Siri / Shortcuts answers from the saved payments, via ``PaymentSummary``.
///
/// Free of AppIntents so it is testable on macOS; the app's intents only open the store and call it.
/// The answers never throw: on a repository error they return ``failureAnswer`` (Siri must always answer).
@MainActor
public struct PaymentSummaryProvider {
    /// The sentence both answers return when the payments cannot be loaded.
    public static let failureAnswer = "I could not open your payments."

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
        return summary.spokenMonthTotal(spokenAmount: AmountText.spokenLabel)
    }

    /// The next payment as a sentence (amount via ``AmountText/spokenLabel(_:)``), or ``failureAnswer``.
    public func nextPaymentAnswer() -> String {
        guard let summary = try? summary() else { return Self.failureAnswer }
        return summary.spokenNextPayment(spokenAmount: AmountText.spokenLabel)
    }
}
