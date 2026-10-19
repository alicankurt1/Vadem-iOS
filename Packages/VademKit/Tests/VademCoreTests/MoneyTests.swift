import Foundation
import Testing
import VademCore

// Double literal hassasiyet kaybını önlemek için Decimal'ları string'den üretiyoruz.
private func dec(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        fatalError("Invalid decimal literal: \(string)")
    }
    return value
}

// Derleme zamanı konformans kontrolü: Money bu kısıtları sağlamazsa derlenmez.
private func requiresConformances<T: Sendable & Hashable & Comparable & Codable>(_: T.Type) -> Bool {
    true
}

@Suite("Money")
struct MoneyTests {

    // MARK: - Tip ve saklama

    @Test("Conforms to Sendable, Hashable, Comparable and Codable")
    func conformances() {
        #expect(requiresConformances(Money.self))
    }

    @Test("Exposes the amount as Decimal")
    func amountIsDecimal() {
        let amount: Decimal = Money(dec("12.34")).amount
        #expect(amount == dec("12.34"))
    }

    // MARK: - Yuvarlama (2 hane, sıfırdan uzağa yarım)

    @Test(
        "Rounds to 2 fraction digits, half away from zero",
        arguments: [
            // Kabul kriterindeki örnekler
            ("1.005", "1.01"),
            ("-1.005", "-1.01"),
            ("1.004", "1.00"),
            // Sınır ve kenar durumları
            ("-1.004", "-1.00"),
            ("0.005", "0.01"),
            ("-0.005", "-0.01"),
            ("2.675", "2.68"),
            ("-2.675", "-2.68"),
            ("0.995", "1.00"),
            ("-0.995", "-1.00"),
            ("1.0049999", "1.00"),
            ("1.0050001", "1.01"),
            ("1.015", "1.02"),
            ("1.025", "1.03"),
            ("3.133", "3.13"),
            ("0.1", "0.10"),
            ("5", "5.00"),
            ("0", "0.00"),
            ("-0.01", "-0.01"),
            ("1234567.89", "1234567.89"),
            ("999999999999.995", "1000000000000.00"),
            ("-999999999999.995", "-1000000000000.00"),
            ("123456789012345678.125", "123456789012345678.13"),
        ]
    )
    func rounding(input: String, expected: String) {
        let money = Money(dec(input))
        #expect(money.amount == dec(expected))
        #expect(money == Money(dec(expected)))
    }

    @Test("Values that round to the same kuruş are equal and hash equally")
    func equalityAfterRounding() {
        let a = Money(dec("1.005"))
        let b = Money(dec("1.01"))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b, Money(dec("1.0099"))]).count == 1)
    }

    @Test("Rounding is idempotent")
    func roundingIsIdempotent() {
        let once = Money(dec("7.4449"))
        let twice = Money(once.amount)
        #expect(once == twice)
        #expect(twice.amount == dec("7.44"))
    }

    // MARK: - zero, isZero, isNegative

    @Test("Money.zero is zero and not negative")
    func zeroConstant() {
        #expect(Money.zero.amount == 0)
        #expect(Money.zero.isZero)
        #expect(!Money.zero.isNegative)
        #expect(Money.zero == Money(0))
    }

    @Test(
        "isZero and isNegative reflect the rounded amount",
        arguments: [
            ("0", true, false),
            ("0.01", false, false),
            ("-0.01", false, true),
            ("100", false, false),
            ("-100", false, true),
            // Sıfıra yuvarlanan küçük değerler: sıfırdır ve negatif değildir
            ("0.004", true, false),
            ("-0.004", true, false),
        ]
    )
    func flags(input: String, isZero: Bool, isNegative: Bool) {
        let money = Money(dec(input))
        #expect(money.isZero == isZero)
        #expect(money.isNegative == isNegative)
    }

    // MARK: - Toplama / çıkarma

    @Test(
        "Addition is exact at kuruş precision",
        arguments: [
            ("0.10", "0.20", "0.30"),
            ("0.01", "0.02", "0.03"),
            ("1.99", "0.01", "2.00"),
            ("-5.00", "5.00", "0.00"),
            ("-0.10", "-0.20", "-0.30"),
            ("1234567.89", "0.11", "1234568.00"),
            ("0", "0", "0"),
        ]
    )
    func addition(lhs: String, rhs: String, expected: String) {
        let sum = Money(dec(lhs)) + Money(dec(rhs))
        #expect(sum.amount == dec(expected))
        #expect(sum == Money(dec(expected)))
    }

    @Test(
        "Subtraction is exact at kuruş precision",
        arguments: [
            ("0.30", "0.10", "0.20"),
            ("0.10", "0.20", "-0.10"),
            ("1.00", "0.01", "0.99"),
            ("5.00", "5.00", "0.00"),
            ("-1.00", "-1.00", "0.00"),
            ("0", "0.01", "-0.01"),
        ]
    )
    func subtraction(lhs: String, rhs: String, expected: String) {
        let difference = Money(dec(lhs)) - Money(dec(rhs))
        #expect(difference.amount == dec(expected))
    }

    @Test("Summing 0.10 ten times gives exactly 1.00")
    func repeatedAdditionHasNoDrift() {
        let total = (0..<10).reduce(Money.zero) { sum, _ in sum + Money(dec("0.10")) }
        #expect(total == Money(dec("1.00")))
        #expect(total.amount == 1)
    }

    @Test("Subtracting a larger amount yields a negative value")
    func subtractionToNegative() {
        let result = Money(dec("10.00")) - Money(dec("10.01"))
        #expect(result.isNegative)
        #expect(result.amount == dec("-0.01"))
    }

    @Test("Adding then subtracting returns the original value")
    func addSubtractInverse() {
        let a = Money(dec("123.45"))
        let b = Money(dec("67.89"))
        #expect((a + b) - b == a)
    }

    // MARK: - Comparable

    @Test(
        "Orders by amount",
        arguments: [
            ("0.01", "0.02"),
            ("-0.02", "-0.01"),
            ("-0.01", "0"),
            ("0", "0.01"),
            ("9.99", "10.00"),
            ("-1000000", "1000000"),
        ]
    )
    func ordering(smaller: String, larger: String) {
        let a = Money(dec(smaller))
        let b = Money(dec(larger))
        #expect(a < b)
        #expect(b > a)
        #expect(!(b < a))
        #expect(a <= b)
    }

    @Test("Equal amounts are neither less nor greater")
    func orderingEqual() {
        let a = Money(dec("1.004"))
        let b = Money(dec("1.00"))
        #expect(!(a < b))
        #expect(!(b < a))
        #expect(a <= b && a >= b)
    }

    @Test("Sorting orders values ascending by amount")
    func sorting() {
        let values = ["3.50", "-2.00", "0", "0.01", "-0.01", "100"].map { Money(dec($0)) }
        let sorted = values.sorted().map(\.amount)
        let expected = ["-2.00", "-0.01", "0", "0.01", "3.50", "100"].map(dec)
        #expect(sorted == expected)
        #expect(values.min() == Money(dec("-2.00")))
        #expect(values.max() == Money(dec("100")))
    }

    // MARK: - Codable

    @Test(
        "JSON round-trips exactly",
        arguments: [
            ("0.1", "0.10"),
            ("3.133", "3.13"),
            ("1234567.89", "1234567.89"),
            ("-0.01", "-0.01"),
            ("0", "0"),
            ("1.005", "1.01"),
            ("-1.005", "-1.01"),
            ("0.30", "0.30"),
            ("999999999999.99", "999999999999.99"),
        ]
    )
    func jsonRoundTrip(input: String, expected: String) throws {
        let original = Money(dec(input))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Money.self, from: data)
        #expect(decoded == original)
        #expect(decoded.amount == dec(expected))
    }

    @Test("JSON round-trips inside a collection")
    func jsonRoundTripCollection() throws {
        let originals = ["0.1", "3.133", "1234567.89", "-0.01"].map { Money(dec($0)) }
        let data = try JSONEncoder().encode(originals)
        let decoded = try JSONDecoder().decode([Money].self, from: data)
        #expect(decoded == originals)
        #expect(decoded.map(\.amount) == ["0.10", "3.13", "1234567.89", "-0.01"].map(dec))
    }

    @Test("Encoding is stable: encode → decode → encode yields the same bytes")
    func jsonEncodingIsStable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let original = Money(dec("1234567.89"))
        let first = try encoder.encode(original)
        let second = try encoder.encode(try JSONDecoder().decode(Money.self, from: first))
        #expect(first == second)
    }
}
