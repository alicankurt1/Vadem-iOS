import Foundation

/// Bir tutar: modele alıntılaması için biçimli metin, kesin değer olarak `Decimal` metni.
///
/// Model hesap yapmaz; yalnızca ``formatted`` metnini aktarır. ``exact`` locale'den
/// bağımsızdır (`"1234.50"`) ve testlerde/kayıtlarda birebir karşılaştırma içindir.
public struct AssistantAmount: Sendable, Hashable, Codable {
    /// The amount for display, Turkish lira with Turkish separators, e.g. `"₺1.234,50"`.
    public let formatted: String
    /// The exact `Decimal` as locale-independent text, e.g. `"1234.50"`.
    public let exact: String

    /// Describes `money`.
    public init(_ money: Money) {
        self.exact = NSDecimalNumber(decimal: money.amount).description(withLocale: Locale(identifier: "en_US_POSIX"))
        self.formatted = AssistantAmount.format(money)
    }

    // Foundation biçimleyicisi locale verisine bağlı; sabit çıktı için elle yazılır.
    private static func format(_ money: Money) -> String {
        let cents = NSDecimalNumber(decimal: money.amount * 100).int64Value
        let magnitude = cents.magnitude
        let whole = String(magnitude / 100)
        let fraction = magnitude % 100
        var grouped = ""
        for (offset, digit) in whole.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { grouped.append(".") }
            grouped.append(digit)
        }
        let sign = cents < 0 ? "-" : ""
        return "\(sign)₺\(String(grouped.reversed())),\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

/// One payment as the assistant sees it.
public struct AssistantPayment: Sendable, Hashable, Codable {
    /// What kind of item the payment comes from.
    public enum Kind: String, Sendable, Hashable, Codable {
        /// A payment of an installment plan.
        case installment
        /// A subscription charge.
        case subscription
    }

    /// The item's title, made prompt-safe.
    public let title: PromptSafeText
    /// The amount due.
    public let amount: AssistantAmount
    /// The due date as `"YYYY-MM-DD"`.
    public let dueDate: String
    /// The card's name, made prompt-safe; `nil` for a payment without a card.
    public let cardName: PromptSafeText?
    /// Installment or subscription.
    public let kind: Kind
    /// For installments: the payment number (1-based); otherwise `nil`.
    public let installmentNumber: Int?
    /// For installments: the number of payments in the plan; otherwise `nil`.
    public let installmentCount: Int?

    init(entry: MonthlySchedule.Entry, cardNames: [Card.ID: String]) {
        self.title = PromptSafeText(entry.title)
        self.amount = AssistantAmount(entry.amount)
        self.dueDate = AssistantPayment.string(of: entry.dueDate)
        self.cardName = entry.cardID.flatMap { cardNames[$0] }.map(PromptSafeText.init)
        switch entry.kind {
        case .installment(let number, let count):
            self.kind = .installment
            self.installmentNumber = number
            self.installmentCount = count
        case .subscription:
            self.kind = .subscription
            self.installmentNumber = nil
            self.installmentCount = nil
        }
    }

    static func string(of date: Card.DueDate) -> String {
        "\(AssistantPayment.string(of: date.month))-\(date.day < 10 ? "0" : "")\(date.day)"
    }

    static func string(of month: YearMonth) -> String {
        let year = String(month.year)
        return String(repeating: "0", count: max(0, 4 - year.count)) + year
            + (month.month < 10 ? "-0" : "-") + String(month.month)
    }
}

/// Answer of ``AssistantQueries/monthTotal(_:)``.
public struct AssistantMonthTotal: Sendable, Hashable, Codable {
    /// The month as `"YYYY-MM"`.
    public let month: String
    /// The exact sum of everything due in the month; zero when nothing is due.
    public let total: AssistantAmount
    /// The number of payments due in the month.
    public let entryCount: Int
}

/// Answer of ``AssistantQueries/payments(in:)``.
public struct AssistantPayments: Sendable, Hashable, Codable {
    /// The month as `"YYYY-MM"`.
    public let month: String
    /// The first payments of the month, at most ``AssistantQueries/maxPayments``, in schedule order.
    public let payments: [AssistantPayment]
    /// The number of payments due in the month, including those left out of ``payments``.
    public let totalCount: Int
    /// `true` when ``payments`` is shorter than ``totalCount``.
    public var isTruncated: Bool { payments.count < totalCount }
}

/// Answer of ``AssistantQueries/nextPayment(after:calendar:)``.
public struct AssistantNextPayment: Sendable, Hashable, Codable {
    /// The payment.
    public let payment: AssistantPayment
    /// Whole days from the given day to the due date; `0` means the same day.
    public let daysUntil: Int
}

/// What one card is due in a month.
public struct AssistantCardTotal: Sendable, Hashable, Codable {
    /// The card's name, made prompt-safe.
    public let cardName: PromptSafeText
    /// The month as `"YYYY-MM"`.
    public let month: String
    /// The exact sum due on the card in the month; zero when nothing is due.
    public let total: AssistantAmount
    /// The number of payments due on the card in the month.
    public let entryCount: Int
}

/// Answer of ``AssistantQueries/cardTotal(cardNamed:in:)``: a total or an explicit "no such card".
public enum AssistantCardResult: Sendable, Hashable, Codable {
    /// A card with that name exists.
    case total(AssistantCardTotal)
    /// No card has that name; the assistant must say so instead of guessing.
    case notFound(requestedName: PromptSafeText)
}

/// Answer of ``AssistantQueries/debtFreeMonth``.
public struct AssistantDebtFreeMonth: Sendable, Hashable, Codable {
    /// The last month with an installment payment as `"YYYY-MM"`, or `nil` when there are none.
    public let month: String?
}
