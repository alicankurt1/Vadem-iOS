import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("MonthlySchedule day grouping")
struct MonthlyScheduleDaysTests {
    // MARK: Yardımcılar

    private func sub(_ title: String, amount: Decimal, day: Int, first: YearMonth) throws -> SubscriptionItem {
        let value = try #require(Subscription(amount: Money(amount), period: .monthly, renewalDay: day, firstMonth: first))
        return try #require(SubscriptionItem(title: title, cardID: nil, subscription: value))
    }

    private func schedule(_ items: [SubscriptionItem], month: YearMonth) -> MonthlySchedule {
        MonthlySchedule(month: month, cards: [], installments: [], subscriptions: items)
    }

    // MARK: Gruplama

    @Test("Groups entries by due day, ordered by day, with exact totals")
    func groupsByDay() throws {
        let october = try Fixture.month(2026, 10)
        let items = [
            try sub("A", amount: 50, day: 20, first: october),
            try sub("B", amount: 100, day: 5, first: october),
            try sub("C", amount: Decimal(5050) / 100, day: 5, first: october),
        ]
        let schedule = schedule(items, month: october)
        #expect(schedule.days.map(\.day) == [5, 20])
        #expect(schedule.days.map(\.entries.count) == [2, 1])
        // Elle: 100 + 50,50 = 150,50
        #expect(schedule.days.map(\.total) == [Money(Decimal(15050) / 100), Money(50)])
        #expect(schedule.days.allSatisfy { !$0.entries.isEmpty })
    }

    @Test("Day totals add up to the month total and cover every entry")
    func dayTotalsMatchMonthTotal() throws {
        let october = try Fixture.month(2026, 10)
        let items = [
            try sub("A", amount: Decimal(1) / 3 * 3 + Decimal(1) / 100, day: 1, first: october),
            try sub("B", amount: Decimal(2999) / 100, day: 1, first: october),
            try sub("C", amount: 7, day: 31, first: october),
        ]
        let schedule = schedule(items, month: october)
        #expect(schedule.days.flatMap(\.entries) == schedule.entries)
        #expect(schedule.days.map(\.total).reduce(Money.zero) { Money($0.amount + $1.amount) } == schedule.total)
    }

    @Test("An empty month has no days")
    func emptyMonth() throws {
        let schedule = schedule([], month: try Fixture.month(2026, 10))
        #expect(schedule.days.isEmpty)
        #expect(schedule.entries(onDay: 1).isEmpty)
        #expect(schedule.total(onDay: 1) == .zero)
    }

    @Test("entries(onDay:) and total(onDay:) match the group; other days are empty and zero")
    func perDayAccessors() throws {
        let october = try Fixture.month(2026, 10)
        let schedule = schedule([
            try sub("A", amount: 10, day: 7, first: october),
            try sub("B", amount: 15, day: 7, first: october),
        ], month: october)
        #expect(schedule.entries(onDay: 7) == schedule.entries)
        #expect(schedule.total(onDay: 7) == Money(25))
        #expect(schedule.entries(onDay: 8).isEmpty)
        #expect(schedule.total(onDay: 8) == .zero)
        #expect(schedule.entries(onDay: 0).isEmpty)
        #expect(schedule.entries(onDay: 32).isEmpty)
    }
}

@Suite("YearMonth weekdayOfFirstDay")
struct YearMonthWeekdayTests {
    // 1 = Pazar … 7 = Cumartesi. Beklenenler takvimden elle okundu.
    @Test("First weekday of known months", arguments: [
        (2026, 10, 5),  // 1 Ekim 2026 Perşembe
        (2026, 9, 3),   // Salı
        (2025, 12, 2),  // Pazartesi
        (2024, 2, 5),   // Artık yıl Şubat: Perşembe
        (2024, 3, 6),   // Cuma (Şubat 29 gün)
        (2023, 2, 4),   // Çarşamba
        (2000, 1, 7),   // Cumartesi
        (2100, 2, 2),   // 2100 artık değil: Pazartesi
        (2100, 3, 2),   // Pazartesi (Şubat 28 gün)
    ])
    func knownMonths(year: Int, month: Int, weekday: Int) throws {
        #expect(try Fixture.month(year, month).weekdayOfFirstDay == weekday)
    }

    @Test("Agrees with Foundation's Gregorian calendar for modern years")
    func matchesFoundation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for year in 1990...2060 {
            for month in 1...12 {
                let date = try #require(calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)))
                #expect(try Fixture.month(year, month).weekdayOfFirstDay == calendar.component(.weekday, from: date), "\(year)-\(month)")
            }
        }
    }
}
