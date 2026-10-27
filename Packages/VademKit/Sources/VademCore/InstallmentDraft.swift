import Foundation

/// The user's input for a new installment plan, before it is valid.
///
/// ``errors`` lists every rule the draft breaks, one error per field at most;
/// ``makeItem(id:)`` returns an ``InstallmentItem`` only when there are none.
/// The card is optional: without a card the draft needs a valid ``paymentDay``; with a card
/// the card decides the due day and ``paymentDay`` is ignored. The draft does not check that
/// ``cardID`` is a saved card; saving through ``PaymentRepository`` rejects unknown cards.
public struct InstallmentDraft: Sendable, Hashable {
    /// A field of the draft, so a form can show each error under its own field.
    public enum Field: Sendable, Hashable, CaseIterable {
        case title
        case card
        case paymentDay
        case amount
        case count
        case firstMonth
    }

    /// A broken rule; each error belongs to one ``Field``.
    public enum ValidationError: Error, Sendable, Hashable {
        /// The title is empty or whitespace only.
        case titleEmpty
        /// The trimmed title is longer than ``InstallmentItem/maxTitleLength``.
        case titleTooLong
        /// No card is chosen and the payment day is outside ``InstallmentItem/supportedPaymentDays``.
        case paymentDayOutOfRange
        /// No amount was given (empty or not a number).
        case amountMissing
        /// The amount, rounded to kuruş, is zero or negative.
        case amountNotPositive
        /// The count is outside ``InstallmentPlan/supportedCounts``.
        case countOutOfRange
        /// The last payment would fall after the last supported month (December 9999).
        case firstMonthOutOfRange

        /// The field this error belongs to.
        public var field: Field {
            switch self {
            case .titleEmpty, .titleTooLong: return .title
            case .paymentDayOutOfRange: return .paymentDay
            case .amountMissing, .amountNotPositive: return .amount
            case .countOutOfRange: return .count
            case .firstMonthOutOfRange: return .firstMonth
            }
        }
    }

    /// The title as typed; trimmed when the item is made.
    public var title: String
    /// The chosen card, or `nil` when the installment is paid some other way.
    public var cardID: Card.ID?
    /// The day of the month a card-less installment is paid on; ignored while ``cardID`` is set.
    public var paymentDay: Int
    /// The purchase total in TRY, or `nil` when no valid number was entered.
    public var total: Decimal?
    /// The number of monthly payments.
    public var count: Int
    /// The month of the first payment.
    public var firstMonth: YearMonth

    /// Creates a draft from raw form values.
    public init(
        title: String,
        cardID: Card.ID?,
        paymentDay: Int = InstallmentItem.supportedPaymentDays.lowerBound,
        total: Decimal?,
        count: Int,
        firstMonth: YearMonth
    ) {
        self.title = title
        self.cardID = cardID
        self.paymentDay = paymentDay
        self.total = total
        self.count = count
        self.firstMonth = firstMonth
    }

    /// Every broken rule, in ``Field`` order; empty when the draft is valid.
    public var errors: [ValidationError] {
        var result: [ValidationError] = []
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result.append(.titleEmpty)
        } else if trimmed.count > InstallmentItem.maxTitleLength {
            result.append(.titleTooLong)
        }
        // Kart seçiliyse vade günü karttan gelir; ödeme günü yalnızca kartsızken denetlenir.
        if cardID == nil, !InstallmentItem.supportedPaymentDays.contains(paymentDay) {
            result.append(.paymentDayOutOfRange)
        }
        if let total {
            // Money kuruşa yuvarladığı için 0,001 gibi değerler de sıfır sayılır.
            if Money(total) <= .zero { result.append(.amountNotPositive) }
        } else {
            result.append(.amountMissing)
        }
        if !InstallmentPlan.supportedCounts.contains(count) {
            result.append(.countOutOfRange)
        } else if firstMonth.months(until: Self.lastSupportedMonth) < count - 1 {
            // Ay kontrolü ancak taksit sayısı geçerliyse anlamlı.
            result.append(.firstMonthOutOfRange)
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

    /// The installment the draft describes, or `nil` while ``errors`` is not empty.
    public func makeItem(id: UUID = UUID()) -> InstallmentItem? {
        guard isValid, let total,
              let plan = InstallmentPlan(total: Money(total), count: count, firstMonth: firstMonth) else {
            return nil
        }
        return InstallmentItem(
            id: id, title: title, cardID: cardID, paymentDay: cardID == nil ? paymentDay : nil, plan: plan
        )
    }

    private static let lastSupportedMonth = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
}
