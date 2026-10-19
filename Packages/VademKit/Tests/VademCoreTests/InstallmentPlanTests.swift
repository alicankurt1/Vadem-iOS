import Foundation
import Testing
import VademCore

// Double literal hassasiyet kaybını önlemek için tutarları string'den üretiyoruz.
private func money(_ string: String) -> Money {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        fatalError("Invalid decimal literal: \(string)")
    }
    return Money(value)
}

// Kuruş cinsinden tamsayıdan Money üretir (100 kuruş = 1 TL).
private func kurus(_ value: Int) -> Money {
    Money(Decimal(value) / 100)
}

// Test verisi için kısa yardımcı: geçersiz ay testin kendisinde bir hatadır.
private func ym(_ year: Int, _ month: Int) -> YearMonth {
    guard let value = YearMonth(year: year, month: month) else {
        fatalError("Invalid test month: \(year)-\(month)")
    }
    return value
}

// Derleme zamanı konformans kontrolü: InstallmentPlan bu kısıtları sağlamazsa derlenmez.
private func requiresConformances<T: Sendable & Hashable & Codable>(_: T.Type) -> Bool {
    true
}

// Codable'ı JSON nesnesi içinde test etmek için sarmalayıcı.
private struct Box: Codable, Equatable {
    let plan: InstallmentPlan
}

// ADR-0001'e göre beklenen tutarları kuruş tamsayılarıyla bağımsız hesaplar:
// her taksit aşağı yuvarlanmış eşit pay, artan kuruşlar ilk taksite.
private func expectedKurusAmounts(total: Int, count: Int) -> [Int] {
    let base = total / count
    let leftover = total % count
    return [base + leftover] + Array(repeating: base, count: count - 1)
}

private func sum(_ payments: [InstallmentPayment]) -> Money {
    payments.reduce(Money.zero) { $0 + $1.amount }
}

@Suite("InstallmentPlan")
struct InstallmentPlanTests {

    // MARK: - Tip ve saklama

    @Test("Conforms to Sendable, Hashable and Codable")
    func conformances() {
        #expect(requiresConformances(InstallmentPlan.self))
    }

    @Test("Keeps total, count and first month")
    func storesProperties() throws {
        let plan = try #require(InstallmentPlan(total: money("1000.00"), count: 3, firstMonth: ym(2026, 11)))
        #expect(plan.total == money("1000.00"))
        #expect(plan.count == 3)
        #expect(plan.firstMonth == ym(2026, 11))
    }

    @Test("Equal plans are equal and hash equally; different plans differ")
    func hashable() throws {
        let a = try #require(InstallmentPlan(total: money("100.00"), count: 3, firstMonth: ym(2026, 1)))
        let b = try #require(InstallmentPlan(total: money("100.00"), count: 3, firstMonth: ym(2026, 1)))
        let otherTotal = try #require(InstallmentPlan(total: money("100.01"), count: 3, firstMonth: ym(2026, 1)))
        let otherCount = try #require(InstallmentPlan(total: money("100.00"), count: 4, firstMonth: ym(2026, 1)))
        let otherMonth = try #require(InstallmentPlan(total: money("100.00"), count: 3, firstMonth: ym(2026, 2)))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b, otherTotal, otherCount, otherMonth]).count == 4)
    }

    // MARK: - Failable init

    @Test("Accepts every count in 1...36", arguments: 1...36)
    func acceptsValidCounts(count: Int) {
        #expect(InstallmentPlan(total: money("500.00"), count: count, firstMonth: ym(2026, 1)) != nil)
    }

    @Test("Rejects counts outside 1...36", arguments: [Int.min, -36, -1, 0, 37, 48, 100, Int.max])
    func rejectsInvalidCounts(count: Int) {
        #expect(InstallmentPlan(total: money("500.00"), count: count, firstMonth: ym(2026, 1)) == nil)
    }

    @Test("Rejects totals that are not greater than zero", arguments: ["0", "0.00", "-0.01", "-100.00", "-999999999.99"])
    func rejectsNonPositiveTotals(total: String) {
        #expect(InstallmentPlan(total: money(total), count: 3, firstMonth: ym(2026, 1)) == nil)
    }

    @Test("Rejects a total that rounds to zero kuruş")
    func rejectsTotalRoundingToZero() {
        // Money kuruşa yuvarlar: 0.004 → 0.00, yani sıfırdan büyük değil.
        #expect(InstallmentPlan(total: money("0.004"), count: 1, firstMonth: ym(2026, 1)) == nil)
    }

    @Test("Accepts the smallest positive total, 0.01")
    func acceptsOneKurus() {
        #expect(InstallmentPlan(total: money("0.01"), count: 1, firstMonth: ym(2026, 1)) != nil)
    }

    // MARK: - Ödeme listesi: sıra, numara, ay

    @Test("Payments have count items, 1-based numbers in order", arguments: [1, 2, 3, 6, 12, 24, 36])
    func numbering(count: Int) throws {
        let plan = try #require(InstallmentPlan(total: money("1234.56"), count: count, firstMonth: ym(2026, 5)))
        let payments = plan.payments
        #expect(payments.count == count)
        #expect(payments.map(\.number) == Array(1...count))
    }

    @Test("Months are consecutive with year rollover: 2026-11 × 6 ends in 2027-04")
    func monthsRollOverYear() throws {
        let plan = try #require(InstallmentPlan(total: money("600.00"), count: 6, firstMonth: ym(2026, 11)))
        #expect(plan.payments.map(\.month) == [
            ym(2026, 11), ym(2026, 12), ym(2027, 1), ym(2027, 2), ym(2027, 3), ym(2027, 4),
        ])
        #expect(plan.payments.last?.month == ym(2027, 4))
    }

    @Test("36 installments starting in December span four calendar years")
    func monthsSpanMultipleYears() throws {
        let plan = try #require(InstallmentPlan(total: money("3600.00"), count: 36, firstMonth: ym(2026, 12)))
        let months = plan.payments.map(\.month)
        #expect(months.first == ym(2026, 12))
        #expect(months[1] == ym(2027, 1))
        #expect(months[13] == ym(2028, 1))
        #expect(months.last == ym(2029, 11))
    }

    @Test("Single installment falls in the first month")
    func singleInstallmentMonth() throws {
        let plan = try #require(InstallmentPlan(total: money("999.99"), count: 1, firstMonth: ym(2028, 2)))
        #expect(plan.payments.map(\.month) == [ym(2028, 2)])
    }

    // MARK: - Tutarlar (ADR-0001)

    @Test(
        "Amounts follow ADR-0001: floor to kuruş, leftover on the first installment",
        arguments: [
            // Kabul kriterindeki örnekler
            ("1000.00", 3, ["333.34", "333.33", "333.33"]),
            ("100.00", 3, ["33.34", "33.33", "33.33"]),
            ("0.05", 3, ["0.03", "0.01", "0.01"]),
            ("1200.00", 12, Array(repeating: "100.00", count: 12)),
            ("999.99", 1, ["999.99"]),
            // Elle hesaplanan ek örnekler
            ("10.00", 3, ["3.34", "3.33", "3.33"]),
            ("100.00", 6, ["16.70", "16.66", "16.66", "16.66", "16.66", "16.66"]),
            ("0.02", 3, ["0.02", "0.00", "0.00"]),
            ("0.01", 2, ["0.01", "0.00"]),
            ("1.00", 7, ["0.16", "0.14", "0.14", "0.14", "0.14", "0.14", "0.14"]),
            ("99.99", 2, ["50.00", "49.99"]),
        ]
    )
    func amountsFollowADR(total: String, count: Int, expected: [String]) throws {
        let plan = try #require(InstallmentPlan(total: money(total), count: count, firstMonth: ym(2026, 1)))
        #expect(plan.payments.map(\.amount) == expected.map(money))
    }

    @Test("Leftover is count − 1 kuruş at most: 0.35 / 36")
    func maximumLeftover() throws {
        // 35 kuruş / 36 = 0 kalan 35 → ilk taksit 0.35, diğerleri 0.00.
        let plan = try #require(InstallmentPlan(total: money("0.35"), count: 36, firstMonth: ym(2026, 1)))
        let amounts = plan.payments.map(\.amount)
        #expect(amounts.first == money("0.35"))
        #expect(amounts.dropFirst().allSatisfy { $0 == Money.zero })
    }

    @Test("Very large total splits exactly: 999,999,999,999.99 / 36")
    func veryLargeTotal() throws {
        // 99_999_999_999_999 kuruş / 36 = 2_777_777_777_777 kalan 27.
        let plan = try #require(InstallmentPlan(total: money("999999999999.99"), count: 36, firstMonth: ym(2026, 1)))
        let amounts = plan.payments.map(\.amount)
        #expect(amounts.first == money("27777777777.77").adding(kurus: 27))
        #expect(amounts.dropFirst().allSatisfy { $0 == money("27777777777.77") })
        #expect(sum(plan.payments) == money("999999999999.99"))
    }

    // MARK: - Toplam her zaman eşit (geniş tarama)

    // Her taksit sayısı için 0.01 ... 20.00 arası tüm tutarlar + seçilmiş büyük tutarlar.
    private static let sweepTotals: [Int] =
        Array(1...2_000) + [
            9_999, 10_000, 10_001, 33_333, 99_999, 100_000, 123_457,
            1_000_000, 3_600_001, 99_999_999, 123_456_789, 999_999_999_999,
        ]

    @Test("Sum of payments equals total exactly, for every count and many totals", arguments: 1...36)
    func sumAlwaysEqualsTotal(count: Int) throws {
        for total in Self.sweepTotals {
            let plan = try #require(InstallmentPlan(total: kurus(total), count: count, firstMonth: ym(2026, 1)))
            let payments = plan.payments
            #expect(sum(payments) == kurus(total), "total \(total) kuruş / \(count)")
            #expect(payments.count == count)
        }
    }

    @Test("Every amount matches the ADR-0001 split, for every count and many totals", arguments: 1...36)
    func amountsMatchADRSweep(count: Int) throws {
        for total in Self.sweepTotals {
            let plan = try #require(InstallmentPlan(total: kurus(total), count: count, firstMonth: ym(2026, 1)))
            let expected = expectedKurusAmounts(total: total, count: count).map(kurus)
            #expect(plan.payments.map(\.amount) == expected, "total \(total) kuruş / \(count)")
        }
    }

    @Test("Amounts are whole kuruş and never negative", arguments: [1, 3, 7, 12, 36])
    func amountsAreWholeKurus(count: Int) throws {
        for total in [1, 2, 5, 99, 100, 101, 33_334, 100_003] {
            let plan = try #require(InstallmentPlan(total: kurus(total), count: count, firstMonth: ym(2026, 1)))
            for payment in plan.payments {
                // Money(amount) kuruşa yuvarlar; tam kuruş bir tutar değişmemeli.
                #expect(Money(payment.amount.amount) == payment.amount)
                #expect(!payment.amount.isNegative)
            }
        }
    }

    // MARK: - lastMonth

    @Test(
        "lastMonth is the month of the final installment",
        arguments: [
            (ym(2026, 11), 6, ym(2027, 4)),
            (ym(2026, 1), 1, ym(2026, 1)),
            (ym(2026, 1), 12, ym(2026, 12)),
            (ym(2026, 1), 13, ym(2027, 1)),
            (ym(2026, 12), 2, ym(2027, 1)),
            (ym(2026, 3), 36, ym(2029, 2)),
        ]
    )
    func lastMonth(first: YearMonth, count: Int, expected: YearMonth) throws {
        let plan = try #require(InstallmentPlan(total: money("100.00"), count: count, firstMonth: first))
        #expect(plan.lastMonth == expected)
        #expect(plan.lastMonth == plan.payments.last?.month)
    }

    // MARK: - amount(in:)

    @Test("amount(in:) returns each month's payment")
    func amountInPlanMonths() throws {
        let plan = try #require(InstallmentPlan(total: money("1000.00"), count: 3, firstMonth: ym(2026, 12)))
        #expect(plan.amount(in: ym(2026, 12)) == money("333.34"))
        #expect(plan.amount(in: ym(2027, 1)) == money("333.33"))
        #expect(plan.amount(in: ym(2027, 2)) == money("333.33"))
    }

    @Test(
        "amount(in:) is zero before the first and after the last installment",
        arguments: [ym(2026, 11), ym(2025, 12), ym(1, 1), ym(2027, 3), ym(2028, 2), ym(9999, 12)]
    )
    func amountOutsidePlan(month: YearMonth) throws {
        let plan = try #require(InstallmentPlan(total: money("1000.00"), count: 3, firstMonth: ym(2026, 12)))
        #expect(plan.amount(in: month) == Money.zero)
    }

    @Test("amount(in:) agrees with payments for every month of a 36-month plan")
    func amountInMatchesPayments() throws {
        let plan = try #require(InstallmentPlan(total: money("12345.67"), count: 36, firstMonth: ym(2026, 7)))
        for payment in plan.payments {
            #expect(plan.amount(in: payment.month) == payment.amount)
        }
        #expect(plan.amount(in: ym(2026, 6)) == Money.zero)
        #expect(plan.amount(in: ym(2029, 7)) == Money.zero)
    }

    // MARK: - Codable

    @Test(
        "Round-trips exactly through JSON",
        arguments: [
            ("1000.00", 3, ym(2026, 11)),
            ("0.01", 1, ym(1, 1)),
            ("0.05", 36, ym(2026, 12)),
            ("999999999999.99", 12, ym(2030, 6)),
        ]
    )
    func codableRoundTrip(total: String, count: Int, first: YearMonth) throws {
        let plan = try #require(InstallmentPlan(total: money(total), count: count, firstMonth: first))
        let data = try JSONEncoder().encode(Box(plan: plan))
        let decoded = try JSONDecoder().decode(Box.self, from: data)
        #expect(decoded.plan == plan)
        #expect(decoded.plan.total == money(total))
        #expect(decoded.plan.count == count)
        #expect(decoded.plan.firstMonth == first)
        #expect(decoded.plan.payments == plan.payments)
    }
}

private extension Money {
    // Büyük tutar testinde kuruş eklemek için yardımcı.
    func adding(kurus value: Int) -> Money {
        self + Money(Decimal(value) / 100)
    }
}
