import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("NotificationPlanner")
struct NotificationPlannerTests {
    // Sabit, Gregoryen takvim ve DST'siz saat dilimi (UTC+3).
    private static let zone = TimeZone(identifier: "Europe/Istanbul")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    // Kartsız aylık abonelik: her ay `day`. günü öder.
    private func monthly(
        _ title: String = "Rent", day: Int, amount: Decimal = 1000, first: YearMonth? = nil, id: UUID = UUID()
    ) throws -> SubscriptionItem {
        let value = try #require(Subscription(
            amount: Money(amount), period: .monthly, renewalDay: day, firstMonth: try first ?? Fixture.month(2026, 1)
        ))
        return try #require(SubscriptionItem(id: id, title: title, cardID: nil, subscription: value))
    }

    private func plan(
        now: Date, subscriptions: [SubscriptionItem], cards: [Card] = [], installments: [InstallmentItem] = [],
        lookahead: Int = NotificationPlanner.defaultLookaheadMonths
    ) -> [PlannedReminder] {
        NotificationPlanner.plan(
            now: now, calendar: calendar, cards: cards, installments: installments,
            subscriptions: subscriptions, lookaheadMonths: lookahead, formatAmount: { "TRY \($0.amount)" }
        )
    }

    @Test("Constants: 64 pending, 63 planned, 09:00")
    func constants() {
        #expect(NotificationPlanner.maxPending == 64)
        #expect(NotificationPlanner.windowSize == 63)
        #expect(NotificationPlanner.fireHour == 9)
    }

    @Test("Day before and due day fire at 09:00 local time")
    func dayBeforeAndDueDay() throws {
        let result = plan(now: try date(2026, 3, 10, 12), subscriptions: [try monthly(day: 15)])
        // Mart, Nisan, Mayıs için ikişer hatırlatma.
        #expect(result.count == 6)
        #expect(result[0].kind == .dayBefore)
        #expect(result[0].fireDate == (try date(2026, 3, 14, 9)))
        #expect(result[0].id == "due-2026-03-15-dayBefore")
        #expect(result[1].kind == .dueDay)
        #expect(result[1].fireDate == (try date(2026, 3, 15, 9)))
        #expect(result[1].id == "due-2026-03-15-today")
        #expect(result[0].dueDate == result[1].dueDate)
        #expect(result[0].dueDate.day == 15)
        #expect(result[5].fireDate == (try date(2026, 5, 15, 9)))
    }

    @Test("Fire hour follows the calendar's time zone")
    func otherTimeZone() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 0)))
        let result = NotificationPlanner.plan(
            now: now, calendar: newYork, cards: [], installments: [],
            subscriptions: [try monthly(day: 15)], formatAmount: { "\($0.amount)" }
        )
        let expected = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 9)))
        #expect(result.first { $0.kind == .dueDay }?.fireDate == expected)
    }

    @Test("Reminders in the past are dropped")
    func pastDropped() throws {
        // 15 Mart 10:00: 14 ve 15 Mart 09:00 geçmişte kaldı.
        let result = plan(now: try date(2026, 3, 15, 10), subscriptions: [try monthly(day: 15)])
        #expect(result.map(\.id) == [
            "due-2026-04-15-dayBefore", "due-2026-04-15-today",
            "due-2026-05-15-dayBefore", "due-2026-05-15-today",
        ])
        #expect(result.allSatisfy { $0.fireDate > (try! date(2026, 3, 15, 10)) })
    }

    @Test("Today before 09:00 still gets its due-day reminder")
    func todayBeforeNine() throws {
        let result = plan(now: try date(2026, 3, 15, 8, 59), subscriptions: [try monthly(day: 15)])
        #expect(result.first?.id == "due-2026-03-15-today")
        #expect(result.first?.fireDate == (try date(2026, 3, 15, 9)))
    }

    @Test("Today after 09:00 gets no due-day reminder", arguments: [(9, 1), (10, 0), (23, 59)])
    func todayAfterNine(hour: Int, minute: Int) throws {
        // Tam 09:00 da "geçmiş" sayılır (fire <= now elenir).
        let result = plan(now: try date(2026, 3, 15, hour, minute), subscriptions: [try monthly(day: 15)])
        #expect(!result.contains { $0.id == "due-2026-03-15-today" })
    }

    @Test("Exactly 09:00 is dropped")
    func exactlyNine() throws {
        let result = plan(now: try date(2026, 3, 15, 9), subscriptions: [try monthly(day: 15)])
        #expect(!result.contains { $0.id == "due-2026-03-15-today" })
    }

    @Test("Payment due tomorrow, now after 09:00 today: no day-before, but due-day stays")
    func dueTomorrowAfterNine() throws {
        let result = plan(now: try date(2026, 3, 15, 10), subscriptions: [try monthly(day: 16)])
        #expect(!result.contains { $0.id == "due-2026-03-16-dayBefore" })
        #expect(result.first?.id == "due-2026-03-16-today")
    }

    @Test("Payment due tomorrow, now before 09:00 today: day-before is kept")
    func dueTomorrowBeforeNine() throws {
        let result = plan(now: try date(2026, 3, 15, 8), subscriptions: [try monthly(day: 16)])
        #expect(result.first?.id == "due-2026-03-16-dayBefore")
        #expect(result.first?.fireDate == (try date(2026, 3, 15, 9)))
    }

    @Test("A single payment names itself")
    func singlePayment() throws {
        let result = plan(now: try date(2026, 3, 1), subscriptions: [try monthly("Rent", day: 20, amount: 15000)])
        let dueDay = try #require(result.first { $0.id == "due-2026-03-20-today" })
        let dayBefore = try #require(result.first { $0.id == "due-2026-03-20-dayBefore" })
        #expect(dueDay.body == "Rent due today, TRY 15000")
        #expect(dayBefore.body == "Rent due tomorrow, TRY 15000")
        #expect(dueDay.title == "Payment due today")
        #expect(dayBefore.title == "Payment due tomorrow")
        #expect(dueDay.entries.count == 1)
        #expect(dueDay.total == Money(15000))
    }

    @Test("Same-day payments group into one reminder per fire time with count and exact total")
    func grouping() throws {
        // 100,50 + 200 + 300,25 = 600,75 (Decimal, kuruş kaybı yok).
        let items = [
            try monthly("A", day: 20, amount: Decimal(string: "100.50")!),
            try monthly("B", day: 20, amount: 200),
            try monthly("C", day: 20, amount: Decimal(string: "300.25")!),
        ]
        let result = plan(now: try date(2026, 3, 1), subscriptions: items, lookahead: 1)
        // 3 ödeme, 2 hatırlatma (ödeme başına değil).
        #expect(result.count == 2)
        let dueDay = try #require(result.first { $0.kind == .dueDay })
        #expect(dueDay.entries.count == 3)
        #expect(dueDay.total == Money(Decimal(string: "600.75")!))
        #expect(dueDay.body == "3 payments due today, TRY 600.75 total")
        let dayBefore = try #require(result.first { $0.kind == .dayBefore })
        #expect(dayBefore.body == "3 payments due tomorrow, TRY 600.75 total")
    }

    @Test("Totals are exact for amounts that Double cannot represent")
    func exactTotal() throws {
        let items = [
            try monthly("A", day: 20, amount: Decimal(string: "0.10")!),
            try monthly("B", day: 20, amount: Decimal(string: "0.20")!),
        ]
        let result = plan(now: try date(2026, 3, 1), subscriptions: items, lookahead: 1)
        #expect(result.first?.total == Money(Decimal(string: "0.30")!))
    }

    @Test("Different days are not grouped")
    func differentDays() throws {
        let items = [try monthly("A", day: 20), try monthly("B", day: 22)]
        let result = plan(now: try date(2026, 3, 1), subscriptions: items, lookahead: 1)
        #expect(result.count == 4)
        #expect(result.allSatisfy { $0.entries.count == 1 })
    }

    @Test("Day-before and due-day reminders at the same 09:00 stay separate and are ordered by id")
    func sameFireTimeStaysSeparate() throws {
        // 20 Mart 09:00: 20'sinin vade günü ve 21'inin gün öncesi aynı anda çalar.
        let items = [try monthly("A", day: 20), try monthly("B", day: 21)]
        let result = plan(now: try date(2026, 3, 1), subscriptions: items, lookahead: 1)
        #expect(result.map(\.id) == [
            "due-2026-03-20-dayBefore",
            "due-2026-03-20-today",
            "due-2026-03-21-dayBefore",
            "due-2026-03-21-today",
        ])
        #expect(result[1].fireDate == result[2].fireDate)
    }

    @Test("Window keeps the nearest 63 by fire date; ties are broken by id; sorted")
    func window() throws {
        // 1..28. günler için 28 abonelik; Mart–Mayıs taranır, 63'ten çok hatırlatma çıkar.
        let items = try (1...28).map { try monthly("Item \($0)", day: $0) }
        let result = plan(now: try date(2026, 3, 1), subscriptions: items)
        #expect(result.count == NotificationPlanner.windowSize)
        // Elle: Mart 1-27 için her 09:00'da 2 (54), 28 Mart'ta 1 (55), 31 Mart (1 Nisan gün öncesi) 56,
        // 1/2/3 Nisan'da 2'şer (62), 4 Nisan 09:00'da iki aday var; 63. olan id'si küçük olan:
        // "due-2026-04-04-today" < "due-2026-04-05-dayBefore".
        #expect(result.last?.id == "due-2026-04-04-today")
        #expect(!result.contains { $0.id == "due-2026-04-05-dayBefore" })
        #expect(result.first?.id == "due-2026-03-01-today")
        // Sıralı: fire date, sonra id.
        for (a, b) in zip(result, result.dropFirst()) {
            #expect(a.fireDate < b.fireDate || (a.fireDate == b.fireDate && a.id < b.id))
        }
        #expect(Set(result.map(\.id)).count == result.count)
    }

    @Test("Fewer than 63 reminders are all returned")
    func belowWindow() throws {
        let items = try (1...5).map { try monthly("Item \($0)", day: $0 * 5) }
        let result = plan(now: try date(2026, 3, 1), subscriptions: items, lookahead: 1)
        // 5 gün × 2 hatırlatma, ama 5. gün (Mart 5) için gün öncesi 4 Mart 09:00 > now.
        #expect(result.count == 10)
    }

    @Test("Month and year boundary: Dec to Jan, due on the 1st fires on Dec 31")
    func decemberToJanuary() throws {
        let result = plan(
            now: try date(2026, 12, 20),
            subscriptions: [try monthly(day: 1, first: try Fixture.month(2026, 12))]
        )
        // Aralık 1 geçmişte; Ocak ve Şubat 1'leri kalır.
        #expect(result.map(\.id) == [
            "due-2027-01-01-dayBefore", "due-2027-01-01-today",
            "due-2027-02-01-dayBefore", "due-2027-02-01-today",
        ])
        #expect(result[0].fireDate == (try date(2026, 12, 31, 9)))
        #expect(result[1].fireDate == (try date(2027, 1, 1, 9)))
        #expect(result[2].fireDate == (try date(2027, 1, 31, 9)))
    }

    @Test("Due on the 1st fires the day before in the previous month", arguments: [
        (2026, 3, 2026, 2, 28), // artık olmayan yıl: Şubat 28
        (2028, 3, 2028, 2, 29), // artık yıl: Şubat 29
        (2026, 5, 2026, 4, 30), // 30 günlük ay
    ])
    func firstOfMonth(dueYear: Int, dueMonth: Int, fireYear: Int, fireMonth: Int, fireDay: Int) throws {
        let first = try Fixture.month(dueYear, dueMonth)
        let result = plan(
            now: try date(dueYear, dueMonth, 1).addingTimeInterval(-40 * 86_400),
            subscriptions: [try monthly(day: 1, first: first)], lookahead: 3
        )
        let dayBefore = try #require(result.first { $0.id == String(format: "due-%04d-%02d-01-dayBefore", dueYear, dueMonth) })
        #expect(dayBefore.fireDate == (try date(fireYear, fireMonth, fireDay, 9)))
    }

    @Test("Leap day: due on Feb 29 fires on Feb 28 and Feb 29")
    func leapDay() throws {
        let result = plan(now: try date(2028, 2, 1), subscriptions: [try monthly(day: 29)], lookahead: 1)
        #expect(result.map(\.id) == ["due-2028-02-29-dayBefore", "due-2028-02-29-today"])
        #expect(result[0].fireDate == (try date(2028, 2, 28, 9)))
        #expect(result[1].fireDate == (try date(2028, 2, 29, 9)))
    }

    @Test("Day 29 in a non-leap February is due on Feb 28")
    func nonLeapFebruary() throws {
        let result = plan(now: try date(2027, 2, 1), subscriptions: [try monthly(day: 29)], lookahead: 1)
        #expect(result.map(\.id) == ["due-2027-02-28-dayBefore", "due-2027-02-28-today"])
        #expect(result[0].fireDate == (try date(2027, 2, 27, 9)))
    }

    @Test("Last day of month: day 31 clamps in a 30-day month; a real 31st fires on the 30th and 31st")
    func lastDayOfMonth() throws {
        let april = plan(now: try date(2026, 4, 1), subscriptions: [try monthly(day: 31)], lookahead: 1)
        #expect(april.map(\.id) == ["due-2026-04-30-dayBefore", "due-2026-04-30-today"])
        #expect(april[1].fireDate == (try date(2026, 4, 30, 9)))
        let january = plan(now: try date(2026, 1, 1), subscriptions: [try monthly(day: 31)], lookahead: 1)
        #expect(january.map(\.id) == ["due-2026-01-31-dayBefore", "due-2026-01-31-today"])
        #expect(january[0].fireDate == (try date(2026, 1, 30, 9)))
        #expect(january[1].fireDate == (try date(2026, 1, 31, 9)))
    }

    @Test("Cardless subscription is planned from its renewal day")
    func cardless() throws {
        let result = plan(now: try date(2026, 3, 1), subscriptions: [try monthly("Streaming", day: 12, amount: 99)], lookahead: 1)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.entries.first?.cardID == nil })
        #expect(result[1].body == "Streaming due today, TRY 99")
    }

    @Test("Installment plan spanning months reminds in each month and groups with a card subscription")
    func installmentSpanningMonths() throws {
        // Kart: ekstre 10, vade 20 → taksit ayı M'in vadesi M'in 20'si.
        let card = try Fixture.card()
        let plan = try Fixture.plan(total: 1200, count: 3, first: try Fixture.month(2026, 11))
        let installment = try Fixture.installment("Phone", card: card.id, plan: plan)
        // 5'inde çekilen abonelik 10'undaki ekstreye girer → aynı ay 20'sinde ödenir.
        let sub = try Fixture.subscriptionItem("Music", card: card.id)
        let result = self.plan(
            now: try date(2026, 11, 1), subscriptions: [sub], cards: [card], installments: [installment]
        )
        // Kasım, Aralık, Ocak 20'leri; her biri 2 hatırlatma.
        #expect(result.filter { $0.kind == .dueDay }.map(\.id) == [
            "due-2026-11-20-today", "due-2026-12-20-today", "due-2027-01-20-today",
        ])
        let november = try #require(result.first { $0.id == "due-2026-11-20-today" })
        #expect(november.entries.count == 2)
        // 400 taksit + 99 abonelik.
        #expect(november.total == Money(499))
        #expect(november.body == "2 payments due today, TRY 499 total")
        let january = try #require(result.first { $0.id == "due-2027-01-20-today" })
        #expect(january.fireDate == (try date(2027, 1, 20, 9)))
    }

    @Test("Empty data plans nothing")
    func empty() throws {
        #expect(plan(now: try date(2026, 3, 1), subscriptions: []).isEmpty)
    }

    @Test("Zero lookahead plans nothing, even with data")
    func zeroLookahead() throws {
        #expect(plan(now: try date(2026, 3, 1), subscriptions: [try monthly(day: 15)], lookahead: 0).isEmpty)
    }

    @Test("Lookahead limits the months scanned")
    func lookaheadLimits() throws {
        let one = plan(now: try date(2026, 3, 1), subscriptions: [try monthly(day: 15)], lookahead: 1)
        #expect(one.count == 2)
        let twelve = plan(now: try date(2026, 3, 1), subscriptions: [try monthly(day: 15)], lookahead: 12)
        #expect(twelve.count == 24)
    }

    @Test("Planning is deterministic and ids are unique")
    func deterministic() throws {
        let items = try (1...20).map { try monthly("Item \($0)", day: $0) }
        let now = try date(2026, 3, 1)
        let first = plan(now: now, subscriptions: items)
        let second = plan(now: now, subscriptions: items.reversed())
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.fireDate) == second.map(\.fireDate))
        #expect(Set(first.map(\.id)).count == first.count)
    }
}
