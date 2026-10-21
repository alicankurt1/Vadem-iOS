import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("UpcomingMonths")
struct UpcomingMonthsTests {
    private func ym(_ year: Int, _ month: Int) throws -> YearMonth {
        try Fixture.month(year, month)
    }

    // Kartsız aylık abonelik: her ay çekim gününde ödenir, tutar sabit.
    private func rent(first: YearMonth, last: YearMonth? = nil, amount: Decimal = 1000) throws -> SubscriptionItem {
        let value = try #require(Subscription(
            amount: Money(amount), period: .monthly, renewalDay: 10, firstMonth: first, lastMonth: last
        ))
        return try #require(SubscriptionItem(id: UUID(), title: "Rent", cardID: nil, subscription: value))
    }

    @Test("Default count is 6")
    func defaultCount() {
        #expect(UpcomingMonths.defaultCount == 6)
    }

    @Test("Builds 6 consecutive months from the start, across the year boundary")
    func yearBoundary() throws {
        let upcoming = UpcomingMonths(
            start: try ym(2026, 11), cards: [], installments: [], subscriptions: []
        )
        #expect(upcoming.start == (try ym(2026, 11)))
        #expect(upcoming.months == [
            try ym(2026, 11), try ym(2026, 12), try ym(2027, 1),
            try ym(2027, 2), try ym(2027, 3), try ym(2027, 4),
        ])
    }

    @Test("Empty months are kept with a zero total")
    func emptyMonthsKept() throws {
        let upcoming = UpcomingMonths(start: try ym(2026, 1), cards: [], installments: [], subscriptions: [])
        #expect(upcoming.schedules.count == 6)
        #expect(upcoming.schedules.allSatisfy { $0.total == .zero })
    }

    @Test("Each total equals MonthlySchedule.total; months outside the subscription are zero")
    func totalsMatch() throws {
        // Elle: Mart–Mayıs 2026 arası 1000 ₺; diğer aylar 0.
        let item = try rent(first: try ym(2026, 3), last: try ym(2026, 5))
        let upcoming = UpcomingMonths(
            start: try ym(2026, 2), cards: [], installments: [], subscriptions: [item]
        )
        #expect(upcoming.schedules.map(\.total) == [
            .zero, Money(1000), Money(1000), Money(1000), .zero, .zero,
        ])
        for schedule in upcoming.schedules {
            let direct = MonthlySchedule(month: schedule.month, cards: [], installments: [], subscriptions: [item])
            #expect(schedule == direct)
            #expect(schedule.total == direct.total)
        }
    }

    @Test("Custom count", arguments: [0, 1, 3, 12])
    func customCount(count: Int) throws {
        let upcoming = UpcomingMonths(
            start: try ym(2026, 6), count: count, cards: [], installments: [], subscriptions: []
        )
        #expect(upcoming.schedules.count == count)
        #expect(upcoming.months.first == (count > 0 ? try ym(2026, 6) : nil))
    }

    @Test("Months after the last supported month are left out instead of trapping")
    func clampsAtLastSupportedMonth() throws {
        let last = try ym(YearMonth.supportedYears.upperBound, 12)
        let upcoming = UpcomingMonths(start: last, cards: [], installments: [], subscriptions: [])
        #expect(upcoming.months == [last])
    }
}
