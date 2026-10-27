import Foundation
import Testing
import VademCore
import VademTestSupport

// Kartsız taksit (#155): kural çifti, kodlama, takvim, analiz, hatırlatma ve asistan.
@Suite("Card-less installment")
struct CardlessInstallmentTests {
    private func plan(total: Decimal = 300, count: Int = 3, first: YearMonth) throws -> InstallmentPlan {
        try #require(InstallmentPlan(total: Money(total), count: count, firstMonth: first))
    }

    private func cardless(
        _ title: String = "Okul", day: Int, total: Decimal = 300, count: Int = 3, first: YearMonth
    ) throws -> InstallmentItem {
        try #require(InstallmentItem(title: title, cardID: nil, paymentDay: day, plan: plan(total: total, count: count, first: first)))
    }

    // MARK: Kural çifti

    @Test("Exactly one of card and payment day is allowed; the day must be 1 to 31", arguments: [
        (true, Int?.none, true),
        (false, Int?.some(15), true),
        (false, Int?.some(1), true),
        (false, Int?.some(31), true),
        (true, Int?.some(15), false),
        (false, Int?.none, false),
        (false, Int?.some(0), false),
        (false, Int?.some(32), false),
        (false, Int?.some(-3), false),
    ])
    func pairRule(hasCard: Bool, day: Int?, isValid: Bool) throws {
        let p = try plan(first: Fixture.month(2026, 11))
        let item = InstallmentItem(title: "Telefon", cardID: hasCard ? Fixture.id(1) : nil, paymentDay: day, plan: p)
        #expect((item != nil) == isValid)
    }

    @Test("Supported payment days are 1 to 31")
    func supportedDays() {
        #expect(InstallmentItem.supportedPaymentDays == 1...31)
    }

    // MARK: Codable

    @Test("A card-less item round-trips through JSON")
    func codableRoundTrip() throws {
        let item = try cardless(day: 17, first: Fixture.month(2026, 11))
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(InstallmentItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.cardID == nil)
        #expect(decoded.paymentDay == 17)
    }

    @Test("A card item round-trips and an old JSON without paymentDay still decodes")
    func codableLegacy() throws {
        let item = try Fixture.installment(card: Fixture.id(1))
        let data = try JSONEncoder().encode(item)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["paymentDay"] == nil)
        #expect(object["cardID"] != nil)
        #expect(try JSONDecoder().decode(InstallmentItem.self, from: data) == item)
    }

    @Test("Decoding rejects a card together with a day and neither of them")
    func decodeRejectsBadPairs() throws {
        let item = try Fixture.installment(card: Fixture.id(1))
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object["paymentDay"] = 10
        let both = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(InstallmentItem.self, from: both) }
        object["paymentDay"] = nil
        object["cardID"] = nil
        let neither = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(InstallmentItem.self, from: neither) }
    }

    // MARK: Takvim

    @Test("A card-less payment is due in its own month on the payment day, clamped to the month end", arguments: [
        // (ilk ay yılı, ayı, ödeme günü, beklenen gün)
        (2026, 11, 15, 15),
        (2026, 11, 31, 30),
        (2026, 12, 31, 31),
        (2027, 2, 31, 28),
        (2028, 2, 30, 29),
        (2028, 2, 29, 29),
        (2027, 2, 1, 1),
    ])
    func dueDay(year: Int, month: Int, day: Int, expected: Int) throws {
        let first = try Fixture.month(year, month)
        let item = try cardless(day: day, total: 100, count: 1, first: first)
        let schedule = MonthlySchedule(month: first, cards: [], installments: [item], subscriptions: [])
        let entry = try #require(schedule.entries.first)
        #expect(schedule.entries.count == 1)
        #expect(entry.dueDate.month == first)
        #expect(entry.dueDate.day == expected)
        #expect(entry.cardID == nil)
        #expect(entry.amount == Money(100))
    }

    @Test("A card-less installment appears in each payment month only, with its number")
    func monthsAndNumbers() throws {
        let item = try cardless(day: 10, total: 300, count: 3, first: Fixture.month(2026, 11))
        func entries(_ y: Int, _ m: Int) throws -> [MonthlySchedule.Entry] {
            MonthlySchedule(month: try Fixture.month(y, m), cards: [], installments: [item], subscriptions: []).entries
        }
        #expect(try entries(2026, 10).isEmpty)
        #expect(try entries(2026, 11).first?.kind == .installment(number: 1, count: 3))
        #expect(try entries(2026, 12).first?.kind == .installment(number: 2, count: 3))
        #expect(try entries(2027, 1).first?.kind == .installment(number: 3, count: 3))
        #expect(try entries(2027, 2).isEmpty)
        #expect(try entries(2026, 12).first?.amount == Money(100))
    }

    @Test("Existing cards do not shift a card-less installment and the total adds both")
    func notShiftedByStatement() throws {
        // Ekstre 25 / vade 5 kartı kartlı taksiti sonraki aya kaydırırdı; kartsız taksit kaymaz.
        let card = try #require(Card(id: Fixture.id(1), name: "Gece", statementDay: 25, dueDay: 5))
        let nov = try Fixture.month(2026, 11)
        let free = try cardless(day: 20, total: 100, count: 1, first: nov)
        let withCard = try Fixture.installment("Kartlı", card: card.id, plan: plan(total: 50, count: 1, first: nov))
        let schedule = MonthlySchedule(month: nov, cards: [card], installments: [free, withCard], subscriptions: [])
        let freeEntry = try #require(schedule.entries.first { $0.itemID == free.id })
        #expect(freeEntry.dueDate.month == nov)
        #expect(freeEntry.dueDate.day == 20)
        // Kartlı taksit kasımın ekstresinde, vadesi aralık 5: kasım toplamında yok.
        #expect(schedule.total == Money(100))
        #expect(schedule.total(for: card.id) == .zero)
    }

    // MARK: Analiz

    @Test("Card-less installments form the no-card share in the card breakdown")
    func noCardShare() throws {
        let card = try Fixture.card("Bonus", id: Fixture.id(1))
        let nov = try Fixture.month(2026, 11)
        let free = try cardless(day: 20, total: 300, count: 1, first: nov)
        let sub = try Fixture.subscriptionItem(
            "Müzik", card: nil,
            subscription: #require(Subscription(amount: Money(50), period: .monthly, renewalDay: 5, firstMonth: nov))
        )
        let analytics = SpendingAnalytics(cards: [card], installments: [free], subscriptions: [sub])
        let shares = analytics.cardBreakdown(in: nov)
        #expect(shares.count == 1)
        #expect(shares.first?.isNoCard == true)
        // 300 (taksit) + 50 (abonelik) tek "kartsız" payda toplanır.
        #expect(shares.first?.total == Money(350))
        #expect(analytics.monthlyTotals(from: nov, count: 1).first?.total == Money(350))
    }

    @Test("A card-less installment counts for the last payment month, due in the last plan month")
    func lastPaymentMonth() throws {
        let item = try cardless(day: 31, total: 300, count: 3, first: Fixture.month(2026, 11))
        let analytics = SpendingAnalytics(cards: [], installments: [item], subscriptions: [])
        #expect(analytics.lastPaymentMonth == (try Fixture.month(2027, 1)))
    }

    @Test("The last payment month is the later of a card-less and a card installment")
    func lastPaymentMonthMixed() throws {
        let card = try Fixture.card("Bonus", id: Fixture.id(1)) // ekstre 10, vade 20: aynı ay
        let late = try cardless(day: 5, total: 600, count: 6, first: Fixture.month(2026, 11)) // son: 2027-04
        let early = try Fixture.installment("Telefon", card: card.id, plan: plan(first: Fixture.month(2026, 11))) // son: 2027-01
        let analytics = SpendingAnalytics(cards: [card], installments: [late, early], subscriptions: [])
        #expect(analytics.lastPaymentMonth == (try Fixture.month(2027, 4)))
    }

    // MARK: Hatırlatma

    @Test("Reminders are planned for a card-less installment on its payment day")
    func reminders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let item = try cardless("Okul", day: 15, total: 100, count: 1, first: Fixture.month(2026, 11))
        let result = NotificationPlanner.plan(
            now: now, calendar: calendar, cards: [], installments: [item], subscriptions: [],
            formatAmount: { "TRY \($0.amount)" }
        )
        #expect(result.count == 2)
        let dayBefore = try #require(result.first { $0.kind == .dayBefore })
        let dueDay = try #require(result.first { $0.kind == .dueDay })
        #expect(dayBefore.fireDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9)))
        #expect(dueDay.fireDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 9)))
        #expect(dueDay.entries.first?.cardID == nil)
        #expect(dueDay.total == Money(100))
    }

    // MARK: Asistan

    @Test("The assistant lists a card-less installment without a card name")
    func assistant() throws {
        let nov = try Fixture.month(2026, 11)
        let item = try cardless("Okul", day: 12, total: 300, count: 3, first: nov)
        let queries = AssistantQueries(cards: [], installments: [item], subscriptions: [])
        let payments = queries.payments(in: nov)
        #expect(payments.payments.count == 1)
        let payment = try #require(payments.payments.first)
        #expect(payment.cardName == nil)
        #expect(payment.kind == .installment)
        #expect(payment.installmentNumber == 1)
        #expect(payment.installmentCount == 3)
        #expect(payment.dueDate == "2026-11-12")
    }
}
