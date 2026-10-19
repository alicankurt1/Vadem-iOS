import Foundation

/// One monthly payment of an ``InstallmentPlan``.
public struct InstallmentPayment: Sendable, Hashable {
    /// 1-based position in the plan.
    public let number: Int
    /// The month this payment falls in.
    public let month: YearMonth
    /// The amount paid in ``month``.
    public let amount: Money
}

/// A purchase split into equal monthly payments (ADR-0001).
///
/// Each payment is `total / count` rounded down to kuruş; the leftover kuruş
/// go to the first payment, so the payments always add up to `total` exactly.
public struct InstallmentPlan: Sendable, Hashable {
    /// The supported installment counts.
    public static let supportedCounts: ClosedRange<Int> = 1...36

    /// The purchase total; always greater than zero.
    public let total: Money
    /// Number of monthly payments, in ``supportedCounts``.
    public let count: Int
    /// The month of the first payment.
    public let firstMonth: YearMonth

    /// Creates a plan, or returns `nil` unless `count` is in ``supportedCounts``,
    /// `total` is greater than zero and the last payment month is within
    /// ``YearMonth/supportedYears``.
    public init?(total: Money, count: Int, firstMonth: YearMonth) {
        guard InstallmentPlan.supportedCounts.contains(count), total > .zero else { return nil }
        // Son taksit desteklenen son ayı aşarsa lastMonth/payments çökerdi; planı baştan reddediyoruz.
        let lastSupported = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        guard firstMonth.months(until: lastSupported) >= count - 1 else { return nil }
        self.total = total
        self.count = count
        self.firstMonth = firstMonth
    }

    /// The month of the final payment.
    public var lastMonth: YearMonth {
        firstMonth.adding(months: count - 1)
    }

    /// All payments in order, starting at ``firstMonth``.
    public var payments: [InstallmentPayment] {
        let (first, rest) = amounts
        return (0..<count).map { offset in
            InstallmentPayment(
                number: offset + 1,
                month: firstMonth.adding(months: offset),
                amount: offset == 0 ? first : rest
            )
        }
    }

    /// The payment due in `month`, or ``Money/zero`` outside the plan.
    public func amount(in month: YearMonth) -> Money {
        let offset = firstMonth.months(until: month)
        guard (0..<count).contains(offset) else { return .zero }
        let (first, rest) = amounts
        return offset == 0 ? first : rest
    }

    // ADR-0001: taban taksit = total / count, kuruşa aşağı yuvarlanır;
    // artan kuruşlar ilk taksite eklenir. Toplam her zaman birebir tutar.
    private var amounts: (first: Money, rest: Money) {
        var quotient = total.amount / Decimal(count)
        var floored = Decimal()
        // Tutar pozitif olduğu için .down, aşağı yuvarlama (floor) ile aynıdır.
        NSDecimalRound(&floored, &quotient, 2, .down)
        let rest = Money(floored)
        let remainder = total.amount - floored * Decimal(count)
        return (Money(floored + remainder), rest)
    }
}

// Çözümlemede de aynı kurallar geçerli: geçersiz plan (ör. count 0) reddedilir.
// Hangi alanın hatalı olduğu tek başına belli olmayabilir (ör. firstMonth + count),
// bu yüzden hata tek bir anahtara değil, planın tamamına bağlanır.
extension InstallmentPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case total, count, firstMonth
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let total = try container.decode(Money.self, forKey: .total)
        let count = try container.decode(Int.self, forKey: .count)
        let firstMonth = try container.decode(YearMonth.self, forKey: .firstMonth)
        guard let plan = InstallmentPlan(total: total, count: count, firstMonth: firstMonth) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid installment plan: total \(total.amount), count \(count), "
                        + "firstMonth \(firstMonth.year)-\(firstMonth.month)"
                )
            )
        }
        self = plan
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(total, forKey: .total)
        try container.encode(count, forKey: .count)
        try container.encode(firstMonth, forKey: .firstMonth)
    }
}
