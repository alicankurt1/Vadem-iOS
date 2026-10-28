import Foundation

/// The user's input for a new one-time payment, before it is valid.
///
/// ``errors`` lists every rule the draft breaks, one error per field at most;
/// ``makeItem(id:)`` returns a ``OneTimePaymentItem`` only when there are none.
/// The card is optional, and the draft does not check that ``cardID`` is a saved card;
/// saving through ``PaymentRepository`` rejects unknown cards.
public struct OneTimePaymentDraft: Sendable, Hashable {
    /// A field of the draft, so a form can show each error under its own field.
    public enum Field: Sendable, Hashable, CaseIterable {
        case title
        case card
        case amount
        case dueDate
    }

    /// A broken rule; each error belongs to one ``Field``.
    public enum ValidationError: Error, Sendable, Hashable {
        /// The title is empty or whitespace only.
        case titleEmpty
        /// The trimmed title is longer than ``OneTimePaymentItem/maxTitleLength``.
        case titleTooLong
        /// No amount was given (empty or not a number).
        case amountMissing
        /// The amount, rounded to kuruş, is zero or negative.
        case amountNotPositive
        /// The due day is not a day of the due month (e.g. 0, or 30 in February).
        case dueDayOutOfRange

        /// The field this error belongs to.
        public var field: Field {
            switch self {
            case .titleEmpty, .titleTooLong: return .title
            case .amountMissing, .amountNotPositive: return .amount
            case .dueDayOutOfRange: return .dueDate
            }
        }
    }

    /// The title as typed; trimmed when the item is made.
    public var title: String
    /// The card the payment is charged to, or `nil` when it is paid some other way.
    public var cardID: Card.ID?
    /// The amount in TRY, or `nil` when no valid number was entered.
    public var amount: Decimal?
    /// The month of the due date.
    public var dueMonth: YearMonth
    /// The day of ``dueMonth`` the payment is due on.
    public var dueDay: Int

    /// Creates a draft from raw form values.
    public init(title: String, cardID: Card.ID?, amount: Decimal?, dueMonth: YearMonth, dueDay: Int) {
        self.title = title
        self.cardID = cardID
        self.amount = amount
        self.dueMonth = dueMonth
        self.dueDay = dueDay
    }

    /// Every broken rule, in ``Field`` order; empty when the draft is valid.
    public var errors: [ValidationError] {
        var result: [ValidationError] = []
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            result.append(.titleEmpty)
        } else if trimmed.count > OneTimePaymentItem.maxTitleLength {
            result.append(.titleTooLong)
        }
        if let amount {
            // Money kuruşa yuvarladığı için 0,001 gibi değerler de sıfır sayılır.
            if Money(amount) <= .zero { result.append(.amountNotPositive) }
        } else {
            result.append(.amountMissing)
        }
        // Tek seferlik ödemede gün kırpılmaz: ayda olmayan gün (ör. 30 Şubat) hatadır.
        if !(1...dueMonth.numberOfDays).contains(dueDay) {
            result.append(.dueDayOutOfRange)
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

    /// The payment the draft describes, or `nil` while ``errors`` is not empty.
    public func makeItem(id: UUID = UUID()) -> OneTimePaymentItem? {
        guard isValid, let amount else { return nil }
        return OneTimePaymentItem(
            id: id, title: title, cardID: cardID, amount: Money(amount), dueMonth: dueMonth, dueDay: dueDay
        )
    }
}
