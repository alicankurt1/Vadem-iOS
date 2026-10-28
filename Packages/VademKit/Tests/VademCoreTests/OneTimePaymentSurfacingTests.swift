import Foundation
import Testing
import VademCore
import VademTestSupport

// #191: tek seferlik ödemeler çekirdek hesaplarda (takvim, yaklaşanlar, analiz, hatırlatma,
// özet, asistan) vade ayında görünür. Beklenen değerler kabul ölçütlerinden elle hesaplandı.
@Suite("One-time payments across core calculations")
struct OneTimePaymentSurfacingTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private static func ym(_ year: Int, _ month: Int) throws -> YearMonth { try Fixture.month(year, month) }

    // MARK: MonthlySchedule

    @Test("Card-less one-time payment is due on its exact day in its own month")
    func cardlessInOwnMonth() throws {
        let item = try Fixture.oneTimePayment("Dentist", card: nil, amount: 1500, due: Self.ym(2026, 11), day: 20)
        let schedule = MonthlySchedule(
            month: try Self.ym(2026, 11), cards: [], installments: [], subscriptions: [], oneTimePayments: [item]
        )
        #expect(schedule.entries.count == 1)
        let entry = try #require(schedule.entries.first)
        #expect(entry.kind == .oneTime)
        #expect(entry.itemID == item.id)
        #expect(entry.cardID == nil)
        #expect(entry.dueDate.day == 20)
        #expect(entry.dueDate.month == (try Self.ym(2026, 11)))
        #expect(schedule.total == Money(1500))
    }

    @Test("One-time payment is not due in other months", arguments: [(2026, 10), (2026, 12), (2025, 11), (2027, 11)])
    func notInOtherMonths(year: Int, month: Int) throws {
        let item = try Fixture.oneTimePayment(card: nil, due: Self.ym(2026, 11), day: 20)
        let schedule = MonthlySchedule(
            month: try Self.ym(year, month), cards: [], installments: [], subscriptions: [], oneTimePayments: [item]
        )
        #expect(schedule.entries.isEmpty)
        #expect(schedule.total == .zero)
    }

    @Test("Card one-time payment has no statement shift")
    func cardNoStatementShift() throws {
        // Ekstre günü 10, vade 20; 15. gün ekstre sonrası ama tek seferlik ödeme yine 15'inde ödenir.
        let card = try Fixture.card("Bonus")
        let item = try Fixture.oneTimePayment(card: card.id, amount: 80, due: Self.ym(2026, 6), day: 15)
        let june = MonthlySchedule(
            month: try Self.ym(2026, 6), cards: [card], installments: [], subscriptions: [], oneTimePayments: [item]
        )
        #expect(june.entries.map(\.dueDate.day) == [15])
        #expect(june.entries.first?.cardID == card.id)
        let july = MonthlySchedule(
            month: try Self.ym(2026, 7), cards: [card], installments: [], subscriptions: [], oneTimePayments: [item]
        )
        #expect(july.entries.isEmpty)
    }

    @Test("One-time payment with an unknown card is skipped")
    func unknownCardSkipped() throws {
        let known = try Fixture.card("Known")
        let item = try Fixture.oneTimePayment(card: UUID(), amount: 500, due: Self.ym(2026, 6), day: 15)
        let schedule = MonthlySchedule(
            month: try Self.ym(2026, 6), cards: [known], installments: [], subscriptions: [], oneTimePayments: [item]
        )
        #expect(schedule.entries.isEmpty)
        #expect(schedule.total == .zero)
    }

    @Test("Default oneTimePayments is empty: existing callers are unchanged")
    func emptyDefault() throws {
        let sub = try Fixture.subscriptionItem(card: nil)
        let schedule = MonthlySchedule(month: try Self.ym(2026, 6), cards: [], installments: [], subscriptions: [sub])
        #expect(schedule.entries.count == 1)
        #expect(schedule.entries.first?.kind == .subscription)
    }

    @Test("Month-end days stay on their day in short months", arguments: [
        // yıl, ay, gün
        (2026, 2, 28), (2028, 2, 29), (2026, 4, 30), (2026, 1, 31), (2026, 12, 31),
    ])
    func monthEndDays(year: Int, month: Int, day: Int) throws {
        let item = try Fixture.oneTimePayment(card: nil, due: Self.ym(year, month), day: day)
        let schedule = MonthlySchedule(
            month: try Self.ym(year, month), cards: [], installments: [], subscriptions: [], oneTimePayments: [item]
        )
        #expect(schedule.entries.map(\.dueDate.day) == [day])
    }

    @Test("Mixes with installments and subscriptions: sums exactly and sorts by day")
    func mixedTotalAndOrder() throws {
        let card = try Fixture.card("Bonus")
        // Taksit: 3 x 400,00 başlangıç Haziran, ekstre 10 / vade 20 -> Haziran'da 20'sinde.
        let installment = try Fixture.installment(
            card: card.id, plan: try Fixture.plan(total: 1200, count: 3, first: Self.ym(2026, 6))
        )
        let early = try Fixture.oneTimePayment("Early", card: nil, amount: 10.50, due: Self.ym(2026, 6), day: 2)
        let late = try Fixture.oneTimePayment("Late", card: card.id, amount: 0.25, due: Self.ym(2026, 6), day: 28)
        let schedule = MonthlySchedule(
            month: try Self.ym(2026, 6), cards: [card], installments: [installment], subscriptions: [],
            oneTimePayments: [late, early]
        )
        #expect(schedule.entries.map(\.title) == ["Early", "Telefon", "Late"])
        #expect(schedule.total == Money(Decimal(string: "410.75")!))
    }

    // MARK: UpcomingMonths

    @Test("Upcoming months include the payment only in its due month")
    func upcomingMonths() throws {
        let item = try Fixture.oneTimePayment(card: nil, amount: 700, due: Self.ym(2026, 12), day: 5)
        let upcoming = UpcomingMonths(
            start: try Self.ym(2026, 10), count: 4, cards: [], installments: [], subscriptions: [],
            oneTimePayments: [item]
        )
        #expect(upcoming.schedules.map(\.total) == [.zero, .zero, Money(700), .zero])
    }

    // MARK: SpendingAnalytics

    @Test("Analytics counts one-time payments in its own part and in the total")
    func analyticsTotals() throws {
        let sub = try Fixture.subscriptionItem(card: nil, subscription: try Fixture.subscription(amount: 100))
        let item = try Fixture.oneTimePayment(card: nil, amount: 250, due: Self.ym(2026, 7), day: 3)
        let analytics = SpendingAnalytics(
            cards: [], installments: [], subscriptions: [sub], oneTimePayments: [item]
        )
        let totals = analytics.monthlyTotals(from: try Self.ym(2026, 6), count: 3)
        #expect(totals.map(\.oneTimePayments) == [.zero, Money(250), .zero])
        #expect(totals.map(\.subscriptions) == [Money(100), Money(100), Money(100)])
        #expect(totals.map(\.total) == [Money(100), Money(350), Money(100)])
        #expect(totals.map(\.installments) == [.zero, .zero, .zero])
    }

    @Test("MonthTotal.total is the sum of the three parts")
    func monthTotalSum() throws {
        let total = SpendingAnalytics.MonthTotal(
            month: try Self.ym(2026, 6), installments: Money(1), subscriptions: Money(20), oneTimePayments: Money(300)
        )
        #expect(total.total == Money(321))
        // Varsayılan: tek seferlik ödeme yok.
        let legacy = SpendingAnalytics.MonthTotal(month: try Self.ym(2026, 6), installments: Money(1), subscriptions: Money(20))
        #expect(legacy.oneTimePayments == .zero)
        #expect(legacy.total == Money(21))
    }

    @Test("Card breakdown: carded and card-less one-time payments get shares")
    func analyticsBreakdown() throws {
        let card = try Fixture.card("Bonus")
        let withCard = try Fixture.oneTimePayment("A", card: card.id, amount: 300, due: Self.ym(2026, 7), day: 3)
        let noCard = try Fixture.oneTimePayment("B", card: nil, amount: 500, due: Self.ym(2026, 7), day: 4)
        let unknown = try Fixture.oneTimePayment("C", card: UUID(), amount: 900, due: Self.ym(2026, 7), day: 5)
        let analytics = SpendingAnalytics(
            cards: [card], installments: [], subscriptions: [], oneTimePayments: [withCard, noCard, unknown]
        )
        let shares = analytics.cardBreakdown(in: try Self.ym(2026, 7))
        // En büyükten küçüğe: kartsız 500, Bonus 300; bilinmeyen kart atlanır.
        #expect(shares.map(\.total) == [Money(500), Money(300)])
        #expect(shares.map(\.isNoCard) == [true, false])
        #expect(shares[1].card?.id == card.id)
        #expect(analytics.cardBreakdown(in: try Self.ym(2026, 8)).isEmpty)
    }

    @Test("Debt-free month is about installments only: a one-time payment does not move it")
    func lastPaymentMonth() throws {
        let item = try Fixture.oneTimePayment(card: nil, due: Self.ym(2027, 3), day: 9)
        let analytics = SpendingAnalytics(cards: [], installments: [], subscriptions: [], oneTimePayments: [item])
        #expect(analytics.lastPaymentMonth == nil)
    }

    // MARK: NotificationPlanner

    private static func plan(
        _ items: [OneTimePaymentItem], now: Date, cards: [Card] = [],
        kinds: Set<PlannedReminder.Kind> = [.dayBefore, .dueDay]
    ) -> [PlannedReminder] {
        NotificationPlanner.plan(
            now: now, calendar: calendar, cards: cards, installments: [], subscriptions: [],
            oneTimePayments: items, kinds: kinds, formatAmount: { "TRY \($0.amount)" }
        )
    }

    @Test("Planner schedules day-before and due-day reminders at 09:00")
    func plannerBothKinds() throws {
        let item = try Fixture.oneTimePayment(card: nil, amount: 900, due: Self.ym(2026, 3), day: 20)
        let result = Self.plan([item], now: try Self.date(2026, 3, 10))
        #expect(result.map(\.kind) == [.dayBefore, .dueDay])
        #expect(result.map(\.fireDate) == [try Self.date(2026, 3, 19, 9), try Self.date(2026, 3, 20, 9)])
        #expect(result.allSatisfy { $0.dueDate.day == 20 && $0.entries.map(\.itemID) == [item.id] })
    }

    @Test("Planner respects the timing: kinds filter", arguments: [
        (Set<PlannedReminder.Kind>([.dueDay]), [PlannedReminder.Kind.dueDay]),
        (Set<PlannedReminder.Kind>([.dayBefore]), [PlannedReminder.Kind.dayBefore]),
    ])
    func plannerTiming(kinds: Set<PlannedReminder.Kind>, expected: [PlannedReminder.Kind]) throws {
        let item = try Fixture.oneTimePayment(card: nil, due: Self.ym(2026, 3), day: 20)
        let result = Self.plan([item], now: try Self.date(2026, 3, 10), kinds: kinds)
        #expect(result.map(\.kind) == expected)
    }

    @Test("Planner does not remind about past or out-of-window one-time payments")
    func plannerPastAndFar() throws {
        let past = try Fixture.oneTimePayment("Past", card: nil, due: Self.ym(2026, 3), day: 5)
        let far = try Fixture.oneTimePayment("Far", card: nil, due: Self.ym(2028, 3), day: 5)
        #expect(Self.plan([past, far], now: try Self.date(2026, 3, 10)).isEmpty)
    }

    @Test("Planner skips a one-time payment on an unknown card")
    func plannerUnknownCard() throws {
        let item = try Fixture.oneTimePayment(card: UUID(), due: Self.ym(2026, 3), day: 20)
        #expect(Self.plan([item], now: try Self.date(2026, 3, 10)).isEmpty)
    }

    @Test("Planner without one-time payments is unchanged (default)")
    func plannerDefault() throws {
        let result = NotificationPlanner.plan(
            now: try Self.date(2026, 3, 10), calendar: Self.calendar, cards: [], installments: [],
            subscriptions: [], formatAmount: { "\($0.amount)" }
        )
        #expect(result.isEmpty)
    }

    // MARK: PaymentSummary

    @Test("Summary counts one-time payments in total, remaining and next")
    func summary() throws {
        let item = try Fixture.oneTimePayment("Dentist", card: nil, amount: 1500, due: Self.ym(2026, 10), day: 20)
        let past = try Fixture.oneTimePayment("Past", card: nil, amount: 40, due: Self.ym(2026, 10), day: 3)
        let later = try Fixture.oneTimePayment("Later", card: nil, amount: 60, due: Self.ym(2026, 12), day: 1)
        let summary = PaymentSummary(
            now: try Self.date(2026, 10, 12), calendar: Self.calendar, cards: [], installments: [],
            subscriptions: [], oneTimePayments: [item, past, later]
        )
        #expect(summary.monthTotal == Money(1540))
        #expect(summary.remaining == Money(1500))
        #expect(summary.remainingCount == 1)
        #expect(summary.next.map(\.title) == ["Dentist", "Later"])
        #expect(summary.next.first?.daysUntil == 8)
        #expect(summary.next.first?.itemID == item.id)
    }

    // MARK: AssistantQueries

    @Test("Assistant month total, payments, next payment and card total include one-time payments")
    func assistant() throws {
        let card = try Fixture.card("Bonus")
        let cardless = try Fixture.oneTimePayment("Dentist", card: nil, amount: 1500, due: Self.ym(2026, 11), day: 20)
        let carded = try Fixture.oneTimePayment("Tax", card: card.id, amount: 250.50, due: Self.ym(2026, 11), day: 5)
        let queries = AssistantQueries(
            cards: [card], installments: [], subscriptions: [], oneTimePayments: [cardless, carded]
        )
        let november = try Self.ym(2026, 11)
        let total = queries.monthTotal(november)
        #expect(total.entryCount == 2)
        #expect(total.total.exact == "1750.5")

        let payments = queries.payments(in: november)
        #expect(payments.totalCount == 2)
        #expect(payments.payments.map(\.kind) == [.oneTime, .oneTime])
        #expect(payments.payments.map(\.dueDate) == ["2026-11-05", "2026-11-20"])
        #expect(payments.payments.map(\.installmentNumber) == [nil, nil])
        #expect(payments.payments.map(\.installmentCount) == [nil, nil])
        #expect(payments.payments[0].cardName != nil)
        #expect(payments.payments[1].cardName == nil)

        let next = try #require(queries.nextPayment(after: try Self.date(2026, 10, 28), calendar: Self.calendar))
        #expect(next.payment.kind == .oneTime)
        #expect(next.payment.dueDate == "2026-11-05")
        #expect(next.daysUntil == 8)

        #expect(queries.monthTotal(try Self.ym(2026, 10)).entryCount == 0)
        let result = queries.cardTotal(cardNamed: "Bonus", in: november)
        #expect("\(result)".contains("250.5"))
    }

    @Test("Assistant default has no one-time payments")
    func assistantDefault() throws {
        let queries = AssistantQueries(cards: [], installments: [], subscriptions: [])
        #expect(queries.monthTotal(try Self.ym(2026, 11)).entryCount == 0)
    }

    @Test("Assistant payment kind round-trips through Codable as oneTime")
    func assistantKindCodable() throws {
        let item = try Fixture.oneTimePayment("Tax", card: nil, due: Self.ym(2026, 11), day: 5)
        let queries = AssistantQueries(cards: [], installments: [], subscriptions: [], oneTimePayments: [item])
        let payment = try #require(queries.payments(in: try Self.ym(2026, 11)).payments.first)
        let data = try JSONEncoder().encode(payment)
        #expect(String(decoding: data, as: UTF8.self).contains("\"oneTime\""))
        #expect(try JSONDecoder().decode(AssistantPayment.self, from: data) == payment)
    }
}
