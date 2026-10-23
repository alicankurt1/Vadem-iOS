import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("PaymentSummary")
struct PaymentSummaryTests {
    // Sabit, Gregoryen takvim ve DST'siz saat dilimi (UTC+3).
    private static let zone = TimeZone(identifier: "Europe/Istanbul")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    // Kartsız aylık abonelik: her ay `day`. günü öder.
    private func monthly(
        _ title: String = "Rent", day: Int, amount: Decimal = 100, id: UUID = UUID(),
        first: YearMonth? = nil, last: YearMonth? = nil
    ) throws -> SubscriptionItem {
        let value = try #require(Subscription(
            amount: Money(amount), period: .monthly, renewalDay: day,
            firstMonth: try first ?? Fixture.month(2026, 1), lastMonth: last
        ))
        return try #require(SubscriptionItem(id: id, title: title, cardID: nil, subscription: value))
    }

    private func summary(
        _ now: Date, subs: [SubscriptionItem] = [], cards: [Card] = [],
        installments: [InstallmentItem] = [], limit: Int = PaymentSummary.defaultLimit
    ) -> PaymentSummary {
        PaymentSummary(
            now: now, calendar: calendar, cards: cards, installments: installments,
            subscriptions: subs, limit: limit
        )
    }

    private let fake: (Money) -> String = { "<\($0.amount)>" }
    // AmountText.spokenLabel gibi: sembol yok, sözcüklerle okunur.
    private let lira: (Money) -> String = { "\($0.amount) lira" }

    // MARK: Ay toplamı ve kalan

    @Test("Default limit is 3")
    func defaultLimit() {
        #expect(PaymentSummary.defaultLimit == 3)
    }

    @Test("Month total, remaining and count; due today counts, past days do not")
    func totals() throws {
        let subs = [
            try monthly("A", day: 5, amount: 100),
            try monthly("B", day: 15, amount: 200),
            try monthly("C", day: 20, amount: 300.50),
        ]
        let result = summary(try date(2026, 10, 15), subs: subs)
        #expect(result.month == (try Fixture.month(2026, 10)))
        #expect(result.monthTotal == Money(600.50))
        #expect(result.remaining == Money(500.50))
        #expect(result.remainingCount == 2)
    }

    @Test("Due-today payment is remaining even late in the day, and early on the next day it is not")
    func dueTodayBoundaries() throws {
        let subs = [try monthly(day: 15, amount: 100)]
        let late = summary(try date(2026, 10, 15, 23, 59), subs: subs)
        #expect(late.remaining == Money(100))
        #expect(late.remainingCount == 1)
        let nextDay = summary(try date(2026, 10, 16, 0, 0), subs: subs)
        #expect(nextDay.remaining == .zero)
        #expect(nextDay.remainingCount == 0)
    }

    @Test("Empty data gives an empty month and no upcoming payments")
    func emptyData() throws {
        let result = summary(try date(2026, 10, 15))
        #expect(result.monthTotal == .zero)
        #expect(result.remaining == .zero)
        #expect(result.remainingCount == 0)
        #expect(result.next.isEmpty)
    }

    @Test("Empty month still lists the next month's payment")
    func emptyMonthWithLaterData() throws {
        // Abonelik Kasım'da başlıyor; Ekim boş.
        let sub = try monthly(day: 10, first: try Fixture.month(2026, 11))
        let result = summary(try date(2026, 10, 15), subs: [sub], limit: 1)
        #expect(result.monthTotal == .zero)
        #expect(result.remainingCount == 0)
        #expect(result.next.map(\.dueDate.day) == [10])
        #expect(result.next.first?.dueDate.month == (try Fixture.month(2026, 11)))
        #expect(result.next.first?.daysUntil == 26)
    }

    @Test("A month whose payments are all in the past has no remaining")
    func allPast() throws {
        let subs = [try monthly("A", day: 3, amount: 100), try monthly("B", day: 14, amount: 50)]
        let result = summary(try date(2026, 10, 15), subs: subs, limit: 2)
        #expect(result.monthTotal == Money(150))
        #expect(result.remaining == .zero)
        #expect(result.remainingCount == 0)
        // Sıradaki ödemeler Kasım'dan.
        #expect(result.next.map(\.title) == ["A", "B"])
        #expect(result.next.allSatisfy { $0.dueDate.month == (try! Fixture.month(2026, 11)) })
    }

    @Test("Month follows the calendar's time zone, not UTC")
    func timeZoneMonth() throws {
        // 31 Ekim 22:00 UTC = 1 Kasım 01:00 İstanbul.
        let now = Date(timeIntervalSince1970: 1_793_484_000)
        #expect(calendar.component(.month, from: now) == 11)
        let result = summary(now, subs: [try monthly(day: 1, amount: 70)])
        #expect(result.month == (try Fixture.month(2026, 11)))
        #expect(result.remaining == Money(70))
        #expect(result.next.first?.daysUntil == 0)
    }

    @Test("Totals are exact decimals")
    func exactDecimals() throws {
        let subs = [try monthly("A", day: 20, amount: 0.10), try monthly("B", day: 21, amount: 0.20)]
        let result = summary(try date(2026, 10, 15), subs: subs)
        #expect(result.monthTotal.amount == Decimal(string: "0.3"))
        #expect(result.remaining.amount == Decimal(string: "0.3"))
    }

    // MARK: next

    @Test("Next is sorted by due date, then title ignoring case, then item id")
    func sortingAndTieBreaks() throws {
        let subs = [
            try monthly("banana", day: 20, id: Fixture.id(1)),
            try monthly("Apple", day: 20, id: Fixture.id(3)),
            try monthly("apple", day: 20, id: Fixture.id(2)),
            try monthly("Zeta", day: 18, id: Fixture.id(4)),
        ]
        let result = summary(try date(2026, 10, 15), subs: subs, limit: 10)
        #expect(result.next.map(\.title) == ["Zeta", "apple", "Apple", "banana", "Zeta", "apple", "Apple", "banana", "Zeta", "apple"])
        #expect(result.next.prefix(4).map(\.itemID) == [Fixture.id(4), Fixture.id(2), Fixture.id(3), Fixture.id(1)])
    }

    @Test("Same-day payments are separate rows with the same days-until")
    func sameDayRows() throws {
        let subs = [try monthly("A", day: 20, amount: 10), try monthly("B", day: 20, amount: 20)]
        let result = summary(try date(2026, 10, 15), subs: subs)
        #expect(result.next.count == 3)
        #expect(result.next[0].daysUntil == 5)
        #expect(result.next[1].daysUntil == 5)
        #expect(result.next[0].amount == Money(10))
        #expect(result.next[1].amount == Money(20))
    }

    @Test("Next fields: id, title, amount, due date, days until", arguments: [0, 1])
    func rowFields(_ offset: Int) throws {
        let id = UUID()
        let sub = try monthly("Rent", day: 15 + offset, amount: 1250.75, id: id)
        let row = try #require(summary(try date(2026, 10, 15), subs: [sub]).next.first)
        #expect(row.itemID == id)
        #expect(row.title == "Rent")
        #expect(row.amount == Money(1250.75))
        #expect(row.dueDate.day == 15 + offset)
        #expect(row.dueDate.month == (try Fixture.month(2026, 10)))
        #expect(row.daysUntil == offset)
    }

    @Test("Limit caps the list", arguments: [
        (0, 0), (1, 1), (2, 2), (3, 3), (5, 5), (-1, 0), (-100, 0),
    ])
    func limit(_ limit: Int, _ expected: Int) throws {
        let subs = [try monthly("A", day: 20), try monthly("B", day: 21)]
        let result = summary(try date(2026, 10, 15), subs: subs, limit: limit)
        #expect(result.next.count == expected)
    }

    @Test("Default limit gives at most 3 rows; limit 1 gives the earliest")
    func defaultAndOne() throws {
        let subs = [try monthly("A", day: 20), try monthly("B", day: 18)]
        let result = summary(try date(2026, 10, 15), subs: subs)
        #expect(result.next.count == 3)
        let one = summary(try date(2026, 10, 15), subs: subs, limit: 1)
        #expect(one.next.map(\.title) == ["B"])
        #expect(one.next.first?.daysUntil == 3)
    }

    @Test("A huge limit is bounded by the look-ahead window")
    func hugeLimit() throws {
        let result = summary(try date(2026, 10, 15), subs: [try monthly(day: 20)], limit: 1000)
        // Ekim, Kasım, Aralık: üç ay.
        #expect(PaymentSummary.lookaheadMonths == 3)
        #expect(result.next.count == 3)
    }

    @Test("Limit does not change the month figures")
    func limitKeepsTotals() throws {
        let subs = [try monthly("A", day: 20, amount: 10), try monthly("B", day: 21, amount: 20)]
        let result = summary(try date(2026, 10, 15), subs: subs, limit: 0)
        #expect(result.monthTotal == Money(30))
        #expect(result.remaining == Money(30))
        #expect(result.remainingCount == 2)
    }

    @Test("Payments before today are never listed")
    func pastExcluded() throws {
        let subs = [try monthly("Past", day: 5), try monthly("Later", day: 25)]
        let result = summary(try date(2026, 10, 15), subs: subs, limit: 2)
        #expect(result.next.map(\.title) == ["Later", "Past"])
        #expect(result.next.map(\.daysUntil) == [10, 21])
        #expect(result.next.allSatisfy { $0.daysUntil >= 0 })
    }

    // (şimdi, ödeme günü, beklenen ilk satır ay, gün, daysUntil)
    @Test("Spills into the following month with the right days-until", arguments: [
        ((2026, 12, 28), 5, (2027, 1, 5), 8),   // Aralık -> Ocak
        ((2026, 12, 31), 1, (2027, 1, 1), 1),   // yıl sonu
        ((2026, 10, 31), 1, (2026, 11, 1), 1),  // ay sonu
        ((2026, 10, 15), 14, (2026, 11, 14), 30),
        ((2026, 11, 20), 31, (2026, 11, 30), 10), // 30 günlük ay: gün kırpılır
        ((2027, 2, 27), 1, (2027, 3, 1), 2),    // artık olmayan yıl
        ((2028, 2, 27), 1, (2028, 3, 1), 3),    // artık yıl
        ((2028, 2, 1), 29, (2028, 2, 29), 28),  // artık gün
        ((2028, 2, 28), 29, (2028, 2, 29), 1),
        ((2028, 2, 29), 28, (2028, 3, 28), 28), // artık günden sonra
        ((2028, 1, 31), 29, (2028, 2, 29), 29), // Ocak sonu -> artık Şubat
        ((2027, 1, 31), 29, (2027, 2, 28), 28), // artık olmayan Şubat'ta gün kırpılır
    ])
    func spill(
        _ now: (Int, Int, Int), _ day: Int, _ expected: (Int, Int, Int), _ days: Int
    ) throws {
        // Sabit bir aboneliğin yalnızca bir kez çekildiği durum: önceki ay bitişli.
        let sub = try monthly(day: day, last: nil)
        let result = summary(try date(now.0, now.1, now.2), subs: [sub], limit: 1)
        let row = try #require(result.next.first)
        #expect(row.dueDate.month == (try Fixture.month(expected.0, expected.1)))
        #expect(row.dueDate.day == expected.2)
        #expect(row.daysUntil == days)
    }

    @Test("Days-until across a leap day and following months")
    func leapSequence() throws {
        // Aylık 29. gün: 29 Şubat (2 gün), 29 Mart (+29), 29 Nisan (+31).
        let result = summary(try date(2028, 2, 27), subs: [try monthly(day: 29)], limit: 3)
        #expect(result.next.map(\.daysUntil) == [2, 31, 62])
    }

    @Test("Month end: last day of month shows today and next month's payments")
    func monthEndToday() throws {
        let subs = [try monthly("Last", day: 31), try monthly("First", day: 1)]
        let result = summary(try date(2026, 10, 31), subs: subs, limit: 3)
        #expect(result.next.map(\.title) == ["Last", "First", "Last"])
        #expect(result.next.map(\.daysUntil) == [0, 1, 30])
    }

    @Test("Cardless subscription is listed")
    func cardless() throws {
        let sub = try monthly("Music", day: 18, amount: 49.99)
        let result = summary(try date(2026, 10, 15), subs: [sub])
        #expect(result.next.first?.title == "Music")
        #expect(result.next.first?.amount == Money(49.99))
        #expect(result.monthTotal == Money(49.99))
    }

    @Test("Installment plan spanning months appears in each month")
    func installmentSpanning() throws {
        let card = try Fixture.card()  // ekstre 10, son ödeme 20
        let plan = try Fixture.plan(total: 300, count: 3, first: try Fixture.month(2026, 9))
        let item = try Fixture.installment("Phone", card: card.id, plan: plan)
        let result = summary(try date(2026, 10, 15), cards: [card], installments: [item], limit: 5)
        #expect(result.monthTotal == Money(100))
        #expect(result.remaining == Money(100))
        #expect(result.remainingCount == 1)
        // 20 Ekim (5 gün) ve 20 Kasım (16 + 20 = 36 gün); Eylül geçmişte.
        #expect(result.next.map(\.title) == ["Phone", "Phone"])
        #expect(result.next.map(\.daysUntil) == [5, 36])
        #expect(result.next.allSatisfy { $0.amount == Money(100) && $0.itemID == item.id })
    }

    @Test("Installment and subscription mix, sorted together")
    func mixed() throws {
        let card = try Fixture.card()
        let item = try Fixture.installment(
            "Phone", card: card.id, plan: try Fixture.plan(total: 300, count: 3, first: try Fixture.month(2026, 10))
        )
        let sub = try monthly("Rent", day: 17, amount: 5)
        let result = summary(try date(2026, 10, 15), subs: [sub], cards: [card], installments: [item], limit: 2)
        #expect(result.next.map(\.title) == ["Rent", "Phone"])
        #expect(result.monthTotal == Money(105))
    }

    @Test("Subscription that has ended is not listed")
    func endedSubscription() throws {
        let ended = try monthly("Old", day: 20, last: try Fixture.month(2026, 9))
        let result = summary(try date(2026, 10, 15), subs: [ended])
        #expect(result.next.isEmpty)
        #expect(result.monthTotal == .zero)
    }

    // MARK: Konuşma metinleri

    @Test("Month total: with still-to-go part")
    func spokenMonthTotalPartial() throws {
        let subs = [try monthly("A", day: 5, amount: 100), try monthly("B", day: 20, amount: 300)]
        let text = summary(try date(2026, 10, 15), subs: subs).spokenMonthTotal(spokenAmount: fake)
        #expect(text == "You pay <400> in October 2026, <300> still to go.")
    }

    @Test("Month total: no still-to-go part when remaining equals total")
    func spokenMonthTotalAllRemaining() throws {
        let subs = [try monthly("A", day: 20, amount: 100)]
        let text = summary(try date(2026, 10, 15), subs: subs).spokenMonthTotal(spokenAmount: fake)
        #expect(text == "You pay <100> in October 2026.")
    }

    @Test("Month total: no still-to-go part when remaining is zero")
    func spokenMonthTotalNothingRemaining() throws {
        let subs = [try monthly("A", day: 3, amount: 100)]
        let text = summary(try date(2026, 10, 15), subs: subs).spokenMonthTotal(spokenAmount: fake)
        #expect(text == "You pay <100> in October 2026.")
    }

    @Test("Month total: empty month")
    func spokenMonthTotalEmpty() throws {
        let text = summary(try date(2026, 10, 15)).spokenMonthTotal(spokenAmount: fake)
        #expect(text == "Nothing is due in October 2026.")
    }

    @Test("Month names are English and the year is plain", arguments: [
        (1, "January"), (2, "February"), (3, "March"), (4, "April"), (5, "May"), (6, "June"),
        (7, "July"), (8, "August"), (9, "September"), (10, "October"), (11, "November"), (12, "December"),
    ])
    func monthNames(_ month: Int, _ name: String) throws {
        let text = summary(try date(2026, month, 15)).spokenMonthTotal(spokenAmount: fake)
        #expect(text == "Nothing is due in \(name) 2026.")
    }

    @Test("Next payment wording by days until", arguments: [
        (15, "Next: Rent, <100>, today."),
        (16, "Next: Rent, <100>, tomorrow."),
        (17, "Next: Rent, <100>, in 2 days."),
        (20, "Next: Rent, <100>, in 5 days."),
        (21, "Next: Rent, <100>, in 6 days."),
        (22, "Next: Rent, <100>, on 22 October."),
        (28, "Next: Rent, <100>, on 28 October."),
    ])
    func spokenNext(_ day: Int, _ expected: String) throws {
        let sub = try monthly("Rent", day: day)
        let text = summary(try date(2026, 10, 15), subs: [sub]).spokenNextPayment(spokenAmount: fake)
        #expect(text == expected)
    }

    @Test("Next payment on a date in the following month and year")
    func spokenNextDate() throws {
        let nov = summary(try date(2026, 10, 28), subs: [try monthly("Rent", day: 4)])
        #expect(nov.next.first?.daysUntil == 7)
        #expect(nov.spokenNextPayment(spokenAmount: fake) == "Next: Rent, <100>, on 4 November.")
        let jan = summary(try date(2026, 12, 20), subs: [try monthly("Rent", day: 3)])
        #expect(jan.spokenNextPayment(spokenAmount: fake) == "Next: Rent, <100>, on 3 January.")
    }

    @Test("Next payment reads only the first row")
    func spokenNextFirstOnly() throws {
        let subs = [try monthly("Later", day: 25), try monthly("Soon", day: 16, amount: 7)]
        let text = summary(try date(2026, 10, 15), subs: subs).spokenNextPayment(spokenAmount: fake)
        #expect(text == "Next: Soon, <7>, tomorrow.")
    }

    @Test("Next payment: none upcoming")
    func spokenNextNone() throws {
        #expect(summary(try date(2026, 10, 15)).spokenNextPayment(spokenAmount: fake) == "No upcoming payments.")
        // limit 0 de listeyi boşaltır.
        let sub = try monthly(day: 20)
        #expect(summary(try date(2026, 10, 15), subs: [sub], limit: 0).spokenNextPayment(spokenAmount: fake)
            == "No upcoming payments.")
    }

    @Test("Spoken texts use the injected closure and never contain the lira sign")
    func noLiraSign() throws {
        let subs = [try monthly("Rent", day: 5, amount: 1250.5), try monthly("Gym", day: 20, amount: 300)]
        let result = summary(try date(2026, 10, 15), subs: subs)
        let texts = [
            result.spokenMonthTotal(spokenAmount: lira),
            result.spokenNextPayment(spokenAmount: lira),
            result.spokenMonthTotal(spokenAmount: fake),
            result.spokenNextPayment(spokenAmount: fake),
            summary(try date(2026, 10, 15)).spokenMonthTotal(spokenAmount: lira),
            summary(try date(2026, 10, 15)).spokenNextPayment(spokenAmount: lira),
        ]
        #expect(texts.allSatisfy { !$0.contains("₺") })
        #expect(texts[0] == "You pay 1550.5 lira in October 2026, 300 lira still to go.")
        #expect(texts[1] == "Next: Gym, 300 lira, in 5 days.")
    }

    @Test("Summary is deterministic")
    func deterministic() throws {
        let subs = [try monthly("A", day: 20, id: Fixture.id(1)), try monthly("B", day: 3, id: Fixture.id(2))]
        let now = try date(2026, 10, 15)
        #expect(summary(now, subs: subs) == summary(now, subs: subs))
    }
}
