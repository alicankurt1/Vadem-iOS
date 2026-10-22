import Foundation
import Observation
import VademCore

/// Drives the add-subscription form: field values, per-field errors and saving through ``PaymentRepository``.
///
/// Validation comes from ``SubscriptionDraft``. A field's error is shown only after the field
/// was changed, or after ``showAllErrors()`` / a failed ``save()``. The card is optional.
@MainActor
@Observable
public final class AddSubscriptionViewModel: Identifiable {
    /// The message shown when the cards could not be loaded.
    public nonisolated static let cardsLoadErrorMessage = "Your cards could not be loaded."
    /// The message shown when saving failed.
    public nonisolated static let saveErrorMessage = "The subscription could not be saved. Please try again."
    /// How many months before the initial month the first-month picker offers.
    public nonisolated static let monthsBefore = 60
    /// How many months after the initial month the first-month picker offers.
    public nonisolated static let monthsAfter = 12
    /// The periods the form offers, in order.
    public nonisolated static let periods: [Subscription.Period] = [.monthly, .yearly]

    /// The title as typed.
    public var title: String = "" { didSet { touched.insert(.title) } }
    /// The chosen card, or `nil` when the subscription is not charged to a card.
    public var cardID: Card.ID? { didSet { touched.insert(.card) } }
    /// The amount as typed, with the locale's decimal separator (e.g. `"149,90"` in Turkish).
    public var amountText: String = "" { didSet { touched.insert(.amount) } }
    /// How often the subscription charges.
    public var period: Subscription.Period = .monthly { didSet { touched.insert(.period) } }
    /// The day of the month the charge renews on.
    public var renewalDay: Int { didSet { touched.insert(.renewalDay) } }
    /// The month of the first charge.
    public var firstMonth: YearMonth { didSet { touched.insert(.firstMonth) } }

    /// The cards to choose from, in the repository's order.
    public private(set) var cards: [Card] = []
    /// The months the first-month picker offers, in order; contains the initial month.
    public let firstMonthOptions: [YearMonth]
    /// A message for a load or save failure, or `nil`.
    public private(set) var failureMessage: String?

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let locale: Locale
    // Değiştirilmiş alanlar; hata sadece bunlarda (veya hepsi açılınca) gösterilir.
    private var touched: Set<SubscriptionDraft.Field> = []
    private var showsAllErrors = false

    /// Creates an empty form whose first month is `initialMonth` and renewal day is
    /// `initialRenewalDay`, and loads the cards.
    ///
    /// `locale` decides the decimal separator of ``amountText``.
    public init(
        repository: any PaymentRepository,
        initialMonth: YearMonth,
        initialRenewalDay: Int = Subscription.supportedRenewalDays.lowerBound,
        locale: Locale = .current
    ) {
        self.repository = repository
        self.locale = locale
        self.firstMonth = initialMonth
        self.renewalDay = initialRenewalDay
        self.cardID = nil
        self.firstMonthOptions = MonthOptions.months(
            around: initialMonth, before: Self.monthsBefore, after: Self.monthsAfter
        )
        do {
            cards = try repository.cards()
        } catch {
            failureMessage = Self.cardsLoadErrorMessage
        }
    }

    /// The draft built from the current field values.
    public var draft: SubscriptionDraft {
        SubscriptionDraft(
            title: title,
            cardID: cardID,
            amount: AmountInput.parse(amountText, locale: locale),
            period: period,
            renewalDay: renewalDay,
            firstMonth: firstMonth
        )
    }

    /// `true` when the draft is valid, so Save can be enabled.
    public var canSave: Bool {
        draft.isValid
    }

    /// The error message to show under `field`, or `nil` when it is valid or not yet shown.
    public func errorMessage(for field: SubscriptionDraft.Field) -> String? {
        guard showsAllErrors || touched.contains(field), let error = draft.error(for: field) else { return nil }
        return message(for: error)
    }

    /// Shows the errors of every field, touched or not.
    public func showAllErrors() {
        showsAllErrors = true
    }

    /// Saves the draft as a new subscription.
    ///
    /// Returns `true` on success. An invalid draft shows every error and returns `false`;
    /// a repository error sets ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        guard let item = draft.makeItem() else {
            showAllErrors()
            return false
        }
        do {
            try repository.save(item)
            failureMessage = nil
            return true
        } catch {
            failureMessage = Self.saveErrorMessage
            return false
        }
    }

    /// The month as `"October 2026"`, like Home.
    public func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    /// The period as shown in the form: `"Monthly"` or `"Yearly"`.
    public nonisolated static func title(of period: Subscription.Period) -> String {
        switch period {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    private func message(for error: SubscriptionDraft.ValidationError) -> String {
        switch error {
        case .titleEmpty:
            return "Enter a title."
        case .titleTooLong:
            return "Use at most \(SubscriptionItem.maxTitleLength) characters."
        case .amountMissing:
            return AmountInput.missingMessage(for: amountText, locale: locale)
        case .amountNotPositive:
            return AmountInput.notPositiveMessage
        case .renewalDayOutOfRange:
            let days = Subscription.supportedRenewalDays
            return "Choose a renewal day from \(days.lowerBound) to \(days.upperBound)."
        }
    }
}
