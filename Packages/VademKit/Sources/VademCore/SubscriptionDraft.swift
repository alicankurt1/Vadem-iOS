import Foundation

/// The user's input for a new subscription, before it is valid.
///
/// ``errors`` lists every rule the draft breaks, one error per field at most;
/// ``makeItem(id:)`` returns a ``SubscriptionItem`` only when there are none.
/// The card is optional, and the draft does not check that ``cardID`` is a saved card;
/// saving through ``PaymentRepository`` rejects unknown cards.
public struct SubscriptionDraft: Sendable, Hashable {
    /// A field of the draft, so a form can show each error under its own field.
    public enum Field: Sendable, Hashable, CaseIterable {
        case title
        case card
        case amount
        case period
        case renewalDay
        case firstMonth
    }

    /// A broken rule; each error belongs to one ``Field``.
    public enum ValidationError: Error, Sendable, Hashable {
        /// The title is empty or whitespace only.
        case titleEmpty
        /// The trimmed title is longer than ``SubscriptionItem/maxTitleLength``.
        case titleTooLong
        /// No amount was given (empty or not a number).
        case amountMissing
        /// The amount, rounded to kuruş, is zero or negative.
        case amountNotPositive
        /// The renewal day is outside ``Subscription/supportedRenewalDays``.
        case renewalDayOutOfRange

        /// The field this error belongs to.
        public var field: Field {
            switch self {
            case .titleEmpty, .titleTooLong: return .title
            case .amountMissing, .amountNotPositive: return .amount
            case .renewalDayOutOfRange: return .renewalDay
            }
        }
    }

    /// The title as typed; trimmed when the item is made.
    public var title: String
    /// The card the subscription is charged to, or `nil` when it is paid some other way.
    public var cardID: Card.ID?
    /// The charged amount in TRY, or `nil` when no valid number was entered.
    public var amount: Decimal?
    /// How often the subscription charges.
    public var period: Subscription.Period
    /// The day of the month the charge renews on.
    public var renewalDay: Int
    /// The month of the first charge.
    public var firstMonth: YearMonth

    /// Creates a draft from raw form values.
    public init(
        title: String,
        cardID: Card.ID?,
        amount: Decimal?,
        period: Subscription.Period,
        renewalDay: Int,
        firstMonth: YearMonth
    ) {
        self.title = title
        self.cardID = cardID
        self.amount = amount
        self.period = period
        self.renewalDay = renewalDay
        self.firstMonth = firstMonth
    }

    /// Every broken rule, in ``Field`` order; empty when the draft is valid.
    public var errors: [ValidationError] {
        var result: [ValidationError] = []
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result.append(.titleEmpty)
        } else if trimmed.count > SubscriptionItem.maxTitleLength {
            result.append(.titleTooLong)
        }
        if let amount {
            // Money kuruşa yuvarladığı için 0,001 gibi değerler de sıfır sayılır.
            if Money(amount) <= .zero { result.append(.amountNotPositive) }
        } else {
            result.append(.amountMissing)
        }
        if !Subscription.supportedRenewalDays.contains(renewalDay) {
            result.append(.renewalDayOutOfRange)
        }
        return result
    }

    /// `true` when ``errors`` is empty.
    public var isValid: Bool {
        errors.isEmpty
    }

    /// The error of `field`, or `nil` when the field is valid.
    public func error(for field: Field) -> ValidationError? {
        errors.first { $0.field == field }
    }

    /// The subscription the draft describes, or `nil` while ``errors`` is not empty.
    public func makeItem(id: UUID = UUID()) -> SubscriptionItem? {
        guard isValid, let amount,
              let subscription = Subscription(
                  amount: Money(amount), period: period, renewalDay: renewalDay, firstMonth: firstMonth
              ) else {
            return nil
        }
        return SubscriptionItem(id: id, title: title, cardID: cardID, subscription: subscription)
    }
}
