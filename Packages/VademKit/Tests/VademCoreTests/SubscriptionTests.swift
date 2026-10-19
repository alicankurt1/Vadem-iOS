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

// Test verisi için kısa yardımcı: geçersiz ay testin kendisinde bir hatadır.
private func ym(_ year: Int, _ month: Int) -> YearMonth {
    guard let value = YearMonth(year: year, month: month) else {
        fatalError("Invalid test month: \(year)-\(month)")
    }
    return value
}

// Geçerli olması beklenen abonelik; nil dönerse test kurulumu hatalıdır.
private func subscription(
    _ amount: String,
    _ period: Subscription.Period,
    day: Int,
    from first: YearMonth,
    to last: YearMonth? = nil
) throws -> Subscription {
    try #require(Subscription(amount: money(amount), period: period, renewalDay: day, firstMonth: first, lastMonth: last))
}

// Derleme zamanı konformans kontrolü: Subscription bu kısıtları sağlamazsa derlenmez.
private func requiresConformances<T: Sendable & Hashable & Codable>(_: T.Type) -> Bool {
    true
}

// Codable'ı JSON nesnesi içinde test etmek için sarmalayıcı.
private struct Box: Codable, Equatable {
    let subscription: Subscription
}

@Suite("Subscription")
struct SubscriptionTests {

    // MARK: - Tip ve saklama

    @Test("Conforms to Sendable, Hashable and Codable")
    func conformances() {
        #expect(requiresConformances(Subscription.self))
    }

    @Test("Keeps amount, period, renewal day, first and last month")
    func storesProperties() throws {
        let sub = try subscription("99.99", .yearly, day: 31, from: ym(2026, 1), to: ym(2028, 6))
        #expect(sub.amount == money("99.99"))
        #expect(sub.period == .yearly)
        #expect(sub.renewalDay == 31)
        #expect(sub.firstMonth == ym(2026, 1))
        #expect(sub.lastMonth == ym(2028, 6))
    }

    @Test("Last month defaults to nil")
    func lastMonthDefaultsToNil() throws {
        let sub = try #require(Subscription(amount: money("10.00"), period: .monthly, renewalDay: 5, firstMonth: ym(2026, 1)))
        #expect(sub.lastMonth == nil)
    }

    @Test("Equal values are equal and hash the same")
    func hashable() throws {
        let a = try subscription("49.90", .monthly, day: 10, from: ym(2026, 3))
        let b = try subscription("49.90", .monthly, day: 10, from: ym(2026, 3))
        let c = try subscription("49.90", .yearly, day: 10, from: ym(2026, 3))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    // MARK: - Doğrulama

    @Test(
        "Rejects non-positive amounts",
        arguments: ["0", "0.00", "-0.01", "-99.99"]
    )
    func rejectsNonPositiveAmount(amount: String) {
        #expect(Subscription(amount: money(amount), period: .monthly, renewalDay: 1, firstMonth: ym(2026, 1)) == nil)
    }

    @Test(
        "Rejects renewal days outside 1...31",
        arguments: [Int.min, -1, 0, 32, 100, Int.max]
    )
    func rejectsInvalidRenewalDay(day: Int) {
        #expect(Subscription(amount: money("10.00"), period: .monthly, renewalDay: day, firstMonth: ym(2026, 1)) == nil)
        #expect(Subscription(amount: money("10.00"), period: .yearly, renewalDay: day, firstMonth: ym(2026, 1)) == nil)
    }

    @Test("Accepts the renewal-day bounds 1 and 31 and the smallest amount")
    func acceptsBounds() {
        #expect(Subscription(amount: money("0.01"), period: .monthly, renewalDay: 1, firstMonth: ym(2026, 1)) != nil)
        #expect(Subscription(amount: money("0.01"), period: .yearly, renewalDay: 31, firstMonth: ym(2026, 1)) != nil)
    }

    @Test(
        "Rejects a last month before the first month",
        arguments: [
            (ym(2026, 1), ym(2025, 12)),  // yıl sınırı
            (ym(2026, 6), ym(2026, 5)),   // bir ay önce
            (ym(2026, 3), ym(2025, 3)),   // aynı ay numarası, önceki yıl
        ]
    )
    func rejectsLastBeforeFirst(first: YearMonth, last: YearMonth) {
        #expect(Subscription(amount: money("10.00"), period: .monthly, renewalDay: 1, firstMonth: first, lastMonth: last) == nil)
        #expect(Subscription(amount: money("10.00"), period: .yearly, renewalDay: 1, firstMonth: first, lastMonth: last) == nil)
    }

    @Test("Accepts a last month equal to the first month")
    func acceptsLastEqualToFirst() {
        #expect(Subscription(amount: money("10.00"), period: .monthly, renewalDay: 1, firstMonth: ym(2026, 4), lastMonth: ym(2026, 4)) != nil)
    }

    // MARK: - Aylık

    @Test(
        "Monthly 99.99 from 2026-01 with no end",
        arguments: [
            (ym(2025, 12), "0"),
            (ym(2026, 1), "99.99"),
            (ym(2026, 2), "99.99"),
            (ym(2030, 7), "99.99"),
            (ym(9999, 12), "99.99"),
        ]
    )
    func monthlyOpenEnded(month: YearMonth, expected: String) throws {
        let sub = try subscription("99.99", .monthly, day: 15, from: ym(2026, 1))
        #expect(sub.amount(in: month) == money(expected))
        #expect(sub.charges(in: month) == (expected != "0"))
    }

    @Test(
        "Monthly from 2026-01 ending 2026-06",
        arguments: [
            (ym(2025, 12), false),
            (ym(2026, 1), true),
            (ym(2026, 3), true),
            (ym(2026, 6), true),
            (ym(2026, 7), false),
            (ym(2027, 1), false),
        ]
    )
    func monthlyWithEnd(month: YearMonth, charges: Bool) throws {
        let sub = try subscription("25.50", .monthly, day: 1, from: ym(2026, 1), to: ym(2026, 6))
        #expect(sub.charges(in: month) == charges)
        #expect(sub.amount(in: month) == (charges ? money("25.50") : .zero))
    }

    @Test("Monthly with first == last charges in exactly that month")
    func monthlySingleMonth() throws {
        let sub = try subscription("10.00", .monthly, day: 1, from: ym(2026, 4), to: ym(2026, 4))
        #expect(!sub.charges(in: ym(2026, 3)))
        #expect(sub.charges(in: ym(2026, 4)))
        #expect(!sub.charges(in: ym(2026, 5)))
    }

    // MARK: - Yıllık

    @Test(
        "Yearly 1,200.00 from 2026-03",
        arguments: [
            (ym(2026, 2), "0"),
            (ym(2026, 3), "1200.00"),
            (ym(2026, 4), "0"),
            (ym(2027, 2), "0"),
            (ym(2027, 3), "1200.00"),
            (ym(2027, 4), "0"),
            (ym(2040, 3), "1200.00"),
            (ym(2025, 3), "0"),  // ilk aydan önceki yılın aynı ayı
        ]
    )
    func yearlyOpenEnded(month: YearMonth, expected: String) throws {
        let sub = try subscription("1200.00", .yearly, day: 10, from: ym(2026, 3))
        #expect(sub.amount(in: month) == money(expected))
        #expect(sub.charges(in: month) == (expected != "0"))
    }

    @Test(
        "Yearly from 2026-03 ending 2029-06 stops after the last month",
        arguments: [
            (ym(2029, 3), true),
            (ym(2029, 6), false),  // aralıkta ama ay numarası farklı
            (ym(2030, 3), false),  // ay numarası aynı ama aralık dışı
        ]
    )
    func yearlyWithEnd(month: YearMonth, charges: Bool) throws {
        let sub = try subscription("1200.00", .yearly, day: 10, from: ym(2026, 3), to: ym(2029, 6))
        #expect(sub.charges(in: month) == charges)
    }

    @Test("Yearly ending just before its next anniversary does not charge that year")
    func yearlyEndBeforeAnniversary() throws {
        let sub = try subscription("1200.00", .yearly, day: 10, from: ym(2026, 3), to: ym(2029, 2))
        #expect(sub.charges(in: ym(2028, 3)))
        #expect(!sub.charges(in: ym(2029, 3)))
    }

    @Test("Yearly starting in December charges every December only")
    func yearlyDecember() throws {
        let sub = try subscription("300.00", .yearly, day: 31, from: ym(2026, 12))
        #expect(sub.charges(in: ym(2026, 12)))
        #expect(!sub.charges(in: ym(2027, 1)))
        #expect(!sub.charges(in: ym(2027, 11)))
        #expect(sub.charges(in: ym(2027, 12)))
    }

    // MARK: - Ödeme günü (ay sonu sıkıştırma)

    @Test(
        "Renewal day 31 clamps to the month's last day",
        arguments: [
            (ym(2026, 1), 31),
            (ym(2026, 2), 28),
            (ym(2028, 2), 29),  // artık yıl
            (ym(2100, 2), 28),  // 100'e bölünür, 400'e bölünmez: artık yıl değil
            (ym(2400, 2), 29),  // 400'e bölünür: artık yıl
            (ym(2026, 4), 30),
            (ym(2026, 5), 31),
            (ym(2026, 6), 30),
            (ym(2026, 9), 30),
            (ym(2026, 11), 30),
            (ym(2026, 12), 31),
        ]
    )
    func clampsDay31(month: YearMonth, expected: Int) throws {
        let sub = try subscription("10.00", .monthly, day: 31, from: ym(2026, 1))
        #expect(sub.chargeDay(in: month) == expected)
    }

    @Test(
        "Renewal days 29 and 30 clamp in February",
        arguments: [
            (29, ym(2026, 2), 28),
            (29, ym(2028, 2), 29),
            (30, ym(2026, 2), 28),
            (30, ym(2028, 2), 29),
            (30, ym(2026, 3), 30),
            (30, ym(2026, 4), 30),
            (29, ym(2026, 4), 29),
        ]
    )
    func clampsDays29And30(day: Int, month: YearMonth, expected: Int) throws {
        let sub = try subscription("10.00", .monthly, day: day, from: ym(2026, 1))
        #expect(sub.chargeDay(in: month) == expected)
    }

    @Test(
        "Renewal days that fit every month are not changed",
        arguments: [1, 15, 28]
    )
    func unclampedDays(day: Int) throws {
        let sub = try subscription("10.00", .monthly, day: day, from: ym(2026, 1))
        #expect(sub.chargeDay(in: ym(2026, 2)) == day)
        #expect(sub.chargeDay(in: ym(2028, 2)) == day)
        #expect(sub.chargeDay(in: ym(2026, 4)) == day)
        #expect(sub.chargeDay(in: ym(2026, 5)) == day)
    }

    @Test("Charge day is nil before the first month and after the last month")
    func chargeDayNilOutsideRange() throws {
        let sub = try subscription("10.00", .monthly, day: 31, from: ym(2026, 1), to: ym(2026, 6))
        #expect(sub.chargeDay(in: ym(2025, 12)) == nil)
        #expect(sub.chargeDay(in: ym(2026, 1)) == 31)
        #expect(sub.chargeDay(in: ym(2026, 6)) == 30)
        #expect(sub.chargeDay(in: ym(2026, 7)) == nil)
    }

    @Test("Yearly charge day clamps in February and is nil in other months")
    func yearlyChargeDay() throws {
        let sub = try subscription("1200.00", .yearly, day: 31, from: ym(2024, 2))
        #expect(sub.chargeDay(in: ym(2024, 2)) == 29)
        #expect(sub.chargeDay(in: ym(2025, 2)) == 28)
        #expect(sub.chargeDay(in: ym(2028, 2)) == 29)
        #expect(sub.chargeDay(in: ym(2025, 3)) == nil)
        #expect(sub.chargeDay(in: ym(2024, 1)) == nil)
    }

    // MARK: - Codable

    @Test(
        "Round-trips exactly through JSON",
        arguments: [
            ("99.99", Subscription.Period.monthly, 31, ym(2026, 1), YearMonth?.none),
            ("1200.00", .yearly, 15, ym(2026, 3), ym(2030, 3)),
            ("0.01", .monthly, 1, ym(2026, 4), ym(2026, 4)),
            ("1234567.89", .yearly, 29, ym(2028, 2), nil),
        ]
    )
    func roundTrip(amount: String, period: Subscription.Period, day: Int, first: YearMonth, last: YearMonth?) throws {
        let sub = try subscription(amount, period, day: day, from: first, to: last)
        let data = try JSONEncoder().encode(Box(subscription: sub))
        let decoded = try JSONDecoder().decode(Box.self, from: data).subscription
        #expect(decoded == sub)
        #expect(decoded.amount == money(amount))
        #expect(decoded.period == period)
        #expect(decoded.renewalDay == day)
        #expect(decoded.firstMonth == first)
        #expect(decoded.lastMonth == last)
    }

    @Test("Decodes hand-written valid JSON, with and without a last month")
    func decodesHandWrittenValidJSON() throws {
        // Elle yazılan JSON'un şekli doğru olmalı; aksi halde aşağıdaki throw testleri anlamsız olur.
        let open = #"{"subscription":{"amount":"99.99","period":"monthly","renewalDay":31,"firstMonth":"2026-01"}}"#
        let decodedOpen = try JSONDecoder().decode(Box.self, from: Data(open.utf8)).subscription
        #expect(decodedOpen == (try subscription("99.99", .monthly, day: 31, from: ym(2026, 1))))

        let ended = #"{"subscription":{"amount":"1200.00","period":"yearly","renewalDay":15,"firstMonth":"2026-03","lastMonth":"2030-03"}}"#
        let decodedEnded = try JSONDecoder().decode(Box.self, from: Data(ended.utf8)).subscription
        #expect(decodedEnded == (try subscription("1200.00", .yearly, day: 15, from: ym(2026, 3), to: ym(2030, 3))))
    }

    @Test(
        "Decoding invalid values throws",
        arguments: [
            // tutar sıfır / negatif / sayı değil
            #"{"subscription":{"amount":"0","period":"monthly","renewalDay":1,"firstMonth":"2026-01"}}"#,
            #"{"subscription":{"amount":"-5.00","period":"monthly","renewalDay":1,"firstMonth":"2026-01"}}"#,
            #"{"subscription":{"amount":"abc","period":"monthly","renewalDay":1,"firstMonth":"2026-01"}}"#,
            // yenileme günü aralık dışı
            #"{"subscription":{"amount":"10.00","period":"monthly","renewalDay":0,"firstMonth":"2026-01"}}"#,
            #"{"subscription":{"amount":"10.00","period":"yearly","renewalDay":32,"firstMonth":"2026-01"}}"#,
            // son ay ilk aydan önce
            #"{"subscription":{"amount":"10.00","period":"monthly","renewalDay":1,"firstMonth":"2026-01","lastMonth":"2025-12"}}"#,
            // desteklenmeyen periyot
            #"{"subscription":{"amount":"10.00","period":"weekly","renewalDay":1,"firstMonth":"2026-01"}}"#,
            // geçersiz ay metni
            #"{"subscription":{"amount":"10.00","period":"monthly","renewalDay":1,"firstMonth":"2026-13"}}"#,
            // zorunlu alanlar eksik
            #"{"subscription":{"period":"monthly","renewalDay":1,"firstMonth":"2026-01"}}"#,
            #"{"subscription":{"amount":"10.00","renewalDay":1,"firstMonth":"2026-01"}}"#,
            #"{"subscription":{"amount":"10.00","period":"monthly","firstMonth":"2026-01"}}"#,
            #"{"subscription":{"amount":"10.00","period":"monthly","renewalDay":1}}"#,
        ]
    )
    func decodingInvalidThrows(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Box.self, from: Data(json.utf8))
        }
    }
}
