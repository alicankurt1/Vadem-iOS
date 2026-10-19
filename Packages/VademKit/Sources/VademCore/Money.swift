import Foundation

/// A TRY amount kept at kuruş (2 fraction digits) precision.
///
/// The amount is always a `Decimal`, never a `Double`. Every initializer rounds
/// to 2 fraction digits, half away from zero (`1.005 → 1.01`, `-1.005 → -1.01`).
public struct Money: Sendable, Hashable, Comparable {
    /// The rounded amount in TRY.
    public let amount: Decimal

    /// Creates a value rounded to 2 fraction digits, half away from zero.
    public init(_ amount: Decimal) {
        self.amount = Money.rounded(amount)
    }

    /// Zero TRY.
    public static let zero = Money(0)

    /// `true` when the amount is exactly zero.
    public var isZero: Bool { amount.isZero }

    /// `true` when the amount is below zero.
    public var isNegative: Bool { amount < 0 }

    /// Exact sum of two amounts.
    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount + rhs.amount)
    }

    /// Exact difference of two amounts.
    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount - rhs.amount)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }

    // .plain modu yarımda sıfırdan uzağa yuvarlar (negatiflerde de simetrik).
    private static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}

// JSON'da Decimal sayı olarak yazılırsa çözümleme Double üzerinden geçebilir
// ve 0.1 gibi değerler bozulabilir. Bu yüzden tutar, locale'den bağımsız
// bir metin olarak ("1234567.89") kodlanır; böylece gidiş-dönüş birebir olur.
extension Money: Codable {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Decimal(string: text, locale: Money.posixLocale), !value.isNaN else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid money amount: \(text)"
            )
        }
        self.init(value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: amount).description(withLocale: Money.posixLocale))
    }
}
