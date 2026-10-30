import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("NotificationPlanner monthly summary")
struct MonthlySummaryPlannerTests {
    private static let zone = TimeZone(identifier: "Europe/Istanbul")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func sub(_ title: String, _ amount: Decimal, from first: YearMonth) throws -> SubscriptionItem {
        let value = try #require(Subscription(amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: first))
        return try #require(SubscriptionItem(id: UUID(), title: title, cardID: nil, subscription: value))
    }

    // Kasım 2026'da toplam 3200 -> 4800 (+%50): yalnızca Kasım'ın içgörüsü vardır.
    private func novemberRise() throws -> [SubscriptionItem] {
        [try sub("A", 3200, from: try Fixture.month(2026, 1)), try sub("B", 1600, from: try Fixture.month(2026, 11))]
    }

    private func plan(now: Date, _ subs: [SubscriptionItem]) -> PlannedMonthlySummary? {
        NotificationPlanner.planMonthlySummary(
            now: now, calendar: calendar, cards: [], installments: [], subscriptions: subs
        )
    }

    @Test("Mid-month: fires on the 1st of the next month at 09:00 with that month's insight")
    func nextFirst() throws {
        let result = try #require(plan(now: try date(2026, 10, 30, 12), try novemberRise()))
        #expect(result.fireDate == (try date(2026, 11, 1, 9)))
        #expect(result.id == "insight-2026-11")
        #expect(result.insight.id == "insight-2026-11-totalChange")
        #expect(result.insight.month == (try Fixture.month(2026, 11)))
        #expect(result.insight.detail == .totalChange(previous: Money(3200), current: Money(4800), percent: 50))
    }

    @Test("Fire hour constant is 09:00")
    func fireHour() {
        #expect(NotificationPlanner.fireHour == 9)
    }

    @Test("On the 1st before 09:00 the summary fires today for the current month")
    func firstBeforeFireHour() throws {
        let result = try #require(plan(now: try date(2026, 11, 1, 8, 59), try novemberRise()))
        #expect(result.fireDate == (try date(2026, 11, 1, 9)))
        #expect(result.id == "insight-2026-11")
    }

    @Test("At exactly 09:00 on the 1st the moment is not ahead: next month's summary is planned")
    func firstAtFireHour() throws {
        // Aralık'ın Kasım'a göre değişimi yok: içgörü yok.
        #expect(plan(now: try date(2026, 11, 1, 9), try novemberRise()) == nil)
    }

    @Test("After 09:00 on the 1st the next month is planned, never a past date")
    func firstAfterFireHour() throws {
        let subs = [
            try sub("A", 1000, from: try Fixture.month(2026, 1)),
            try sub("B", 1000, from: try Fixture.month(2026, 12)),
        ]
        let result = try #require(plan(now: try date(2026, 11, 1, 10), subs))
        #expect(result.fireDate == (try date(2026, 12, 1, 9)))
        #expect(result.id == "insight-2026-12")
        let now = try date(2026, 11, 1, 10)
        #expect(result.fireDate > now)
    }

    @Test("No insight for the target month gives no summary")
    func noInsight() throws {
        let steady = [try sub("A", 1000, from: try Fixture.month(2026, 1))]
        #expect(plan(now: try date(2026, 10, 30, 12), steady) == nil)
        #expect(plan(now: try date(2026, 10, 30, 12), []) == nil)
    }

    @Test("Year boundary: December plans January 1st of the next year")
    func yearBoundary() throws {
        let subs = [
            try sub("A", 1000, from: try Fixture.month(2026, 1)),
            try sub("B", 1000, from: try Fixture.month(2027, 1)),
        ]
        let result = try #require(plan(now: try date(2026, 12, 20, 12), subs))
        #expect(result.fireDate == (try date(2027, 1, 1, 9)))
        #expect(result.id == "insight-2027-01")
    }

    @Test("The summary is at most one value and equals the calculator's top insight")
    func matchesTopInsight() throws {
        let subs = try novemberRise()
        let result = try #require(plan(now: try date(2026, 10, 30, 12), subs))
        let top = MonthlyInsightCalculator.topInsight(
            for: try Fixture.month(2026, 11), cards: [], installments: [], subscriptions: subs
        )
        #expect(result.insight == top)
        // Aynı girdi iki kez planlanınca aynı değer (aynı kimlik: ay başına tek bildirim).
        #expect(plan(now: try date(2026, 10, 30, 12), subs) == result)
    }

    @Test("Fire time follows the calendar's time zone")
    func timeZone() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12)))
        let result = NotificationPlanner.planMonthlySummary(
            now: now, calendar: newYork, cards: [], installments: [], subscriptions: try novemberRise()
        )
        let expected = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
        #expect(result?.fireDate == expected)
    }

    @Test("Last supported month plans nothing and does not crash")
    func lastSupportedMonth() throws {
        let last = try #require(calendar.date(from: DateComponents(year: 9999, month: 12, day: 15, hour: 12)))
        #expect(plan(now: last, []) == nil)
    }
}
