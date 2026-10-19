import Foundation

/// A recurring charge, billed monthly or yearly on a fixed renewal day.
///
/// In months shorter than ``renewalDay`` the charge falls on the month's last day
/// (day 31 → Feb 28, or Feb 29 in leap years; Apr 30).
public struct Subscription: Sendable, Hashable {
    /// How often a ``Subscription`` charges.
    public enum Period: String, Sendable, Hashable, Codable {
        /// Every month.
        case monthly
        /// Once a year, in the month number of ``Subscription/firstMonth``.
        case yearly
    }

    /// The supported renewal days.
    public static let supportedRenewalDays: ClosedRange<Int> = 1...31

    /// The charged amount; always greater than zero.
    public let amount: Money
    /// How often the subscription charges.
    public let period: Period
    /// The day of the month the charge renews on, in ``supportedRenewalDays``.
    public let renewalDay: Int
    /// The month of the first charge.
    public let firstMonth: YearMonth
    /// The month of the last charge after cancelling, or `nil` while active.
    public let lastMonth: YearMonth?

    /// Creates a subscription, or returns `nil` unless `amount` is greater than zero,
    /// `renewalDay` is in ``supportedRenewalDays`` and `lastMonth` (if set)
    /// is not before `firstMonth`.
    public init?(amount: Money, period: Period, renewalDay: Int, firstMonth: YearMonth, lastMonth: YearMonth? = nil) {
        guard amount > .zero, Subscription.supportedRenewalDays.contains(renewalDay) else { return nil }
        if let lastMonth, lastMonth < firstMonth { return nil }
        self.amount = amount
        self.period = period
        self.renewalDay = renewalDay
        self.firstMonth = firstMonth
        self.lastMonth = lastMonth
    }

    /// `true` when the subscription charges in `month`.
    public func charges(in month: YearMonth) -> Bool {
        guard month >= firstMonth else { return false }
        if let lastMonth, month > lastMonth { return false }
        switch period {
        case .monthly:
            return true
        case .yearly:
            // Yıllık abonelik her yıl ilk ödemenin yapıldığı ay numarasında çekilir.
            return month.month == firstMonth.month
        }
    }

    /// The charge in `month`, or ``Money/zero`` when it does not charge.
    public func amount(in month: YearMonth) -> Money {
        charges(in: month) ? amount : .zero
    }

    /// The day of `month` the charge falls on, clamped to the month's last day,
    /// or `nil` when it does not charge.
    public func chargeDay(in month: YearMonth) -> Int? {
        guard charges(in: month) else { return nil }
        // Kısa aylarda yenileme günü ayın son gününe kayar (ör. 31 → Şubat 28/29).
        return min(renewalDay, month.numberOfDays)
    }
}

// Çözümlemede de failable init'in kuralları geçerli: geçersiz abonelik reddedilir.
// Hata (ör. lastMonth < firstMonth) birden fazla alana bağlı olabildiği için
// tek bir anahtara değil, aboneliğin tamamına bağlanır.
extension Subscription: Codable {
    private enum CodingKeys: String, CodingKey {
        case amount, period, renewalDay, firstMonth, lastMonth
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Money.self, forKey: .amount)
        let period = try container.decode(Period.self, forKey: .period)
        let renewalDay = try container.decode(Int.self, forKey: .renewalDay)
        let firstMonth = try container.decode(YearMonth.self, forKey: .firstMonth)
        let lastMonth = try container.decodeIfPresent(YearMonth.self, forKey: .lastMonth)
        guard let subscription = Subscription(
            amount: amount, period: period, renewalDay: renewalDay,
            firstMonth: firstMonth, lastMonth: lastMonth
        ) else {
            let lastText = lastMonth.map { "\($0.year)-\($0.month)" } ?? "nil"
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid subscription: amount \(amount.amount), renewalDay \(renewalDay), "
                        + "firstMonth \(firstMonth.year)-\(firstMonth.month), lastMonth \(lastText)"
                )
            )
        }
        self = subscription
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        try container.encode(period, forKey: .period)
        try container.encode(renewalDay, forKey: .renewalDay)
        try container.encode(firstMonth, forKey: .firstMonth)
        try container.encodeIfPresent(lastMonth, forKey: .lastMonth)
    }
}
