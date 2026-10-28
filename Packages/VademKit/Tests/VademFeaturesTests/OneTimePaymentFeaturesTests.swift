import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

// #191: tek seferlik ödemeler Home, Analytics, hatırlatma, widget ve Siri/Shortcuts özetinde görünür.
// Ödemeler depo üzerinden eklenir (henüz oluşturma arayüzü yok).
@MainActor
@Suite("One-time payments in features")
struct OneTimePaymentFeaturesTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func ym(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }

    // 12 Ekim 2026'da: Kasım'da 1500 kartsız, Ekim'de 40 kartlı ödeme.
    private static func seeded() throws -> (InMemoryPaymentRepository, Card) {
        let repository = InMemoryPaymentRepository()
        let card = try Fixture.card("Bonus")
        try repository.save(card)
        try repository.save(Fixture.oneTimePayment("Dentist", card: nil, amount: 1500, due: ym(2026, 11), day: 20))
        try repository.save(Fixture.oneTimePayment("Tax", card: card.id, amount: 40, due: ym(2026, 10), day: 28))
        return (repository, card)
    }

    // MARK: Home

    @Test("Home: monthly total, rows, calendar day and card subtotal include the payment in its own month")
    func homeOwnMonth() throws {
        let (repository, card) = try Self.seeded()
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.state == .loaded)
        #expect(model.total == Money(40))
        #expect(model.rows.map(\.title) == ["Tax"])
        #expect(model.rows.first?.installmentText == nil)
        #expect(model.cardSubtotals.map(\.amount) == [Money(40)])
        #expect(model.cardSubtotals.first?.id == card.id)
        let day = try #require(model.calendarDays.first { $0.day == 28 })
        #expect(day.hasPayments)
        #expect(day.total == Money(40))
        #expect(day.paymentCount == 1)
        #expect(model.calendarDays.filter(\.hasPayments).count == 1)
    }

    @Test("Home: upcoming strip shows the payment only in its due month")
    func homeUpcoming() throws {
        let (repository, _) = try Self.seeded()
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        let totals = Dictionary(uniqueKeysWithValues: model.upcoming.map { ($0.month, $0.total) })
        #expect(totals[Self.ym(2026, 10)] == Money(40))
        #expect(totals[Self.ym(2026, 11)] == Money(1500))
        #expect(totals[Self.ym(2026, 12)] == Money.zero)
    }

    @Test("Home: selecting the due month lists the card-less payment with its day and no card")
    func homeNextMonth() throws {
        let (repository, _) = try Self.seeded()
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.showNextMonth()
        #expect(model.month == Self.ym(2026, 11))
        #expect(model.state == .loaded)
        #expect(model.total == Money(1500))
        let row = try #require(model.rows.first)
        #expect(row.title == "Dentist")
        #expect(row.cardText == HomeViewModel.noCardText)
        #expect(row.entry.kind == .oneTime)
        #expect(row.entry.dueDate.day == 20)
        #expect(row.accessibilityLabel.contains("Dentist"))
        #expect(model.cardSubtotals.isEmpty)
        model.select(day: 20)
        #expect(model.rows.count == 1)
        model.select(day: 20)
        model.select(day: 19)
        #expect(model.rows.isEmpty)
    }

    @Test("Home: a month with only a one-time payment is not empty")
    func homeNotEmpty() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.oneTimePayment(card: nil, amount: 10, due: Self.ym(2026, 10), day: 31))
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.state == .loaded)
        #expect(model.total == Money(10))
    }

    @Test("Home: sample data holds a one-time payment in November 2026 and leaves October unchanged")
    func sampleData() throws {
        let model = HomeViewModel(
            repository: HomeSampleData.makeRepository(), today: HomeSampleData.today, calendar: HomeSampleData.calendar
        )
        // Ekim toplamı: 4000 + 900 + 249,99 + 25000 (HomeCalendarTests'teki ödemeler).
        #expect(model.total == Money(Decimal(string: "30149.99")!))
        model.showNextMonth()
        #expect(model.rows.contains { $0.title == "Dentist" && $0.entry.kind == .oneTime })
        #expect(model.rows.first { $0.title == "Dentist" }?.amount == Money(1500))
    }

    // MARK: Analytics

    @Test("Analytics: bars, summary part and card breakdown count the payment")
    func analytics() throws {
        let (repository, card) = try Self.seeded()
        let model = AnalyticsViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.reload()
        #expect(model.state == .loaded)
        let november = try #require(model.months.first { $0.month == Self.ym(2026, 11) })
        #expect(november.oneTimePayments == Money(1500))
        #expect(november.total == Money(1500))
        let october = try #require(model.months.first { $0.month == Self.ym(2026, 10) })
        #expect(october.oneTimePayments == Money(40))
        // Seçili ay Ekim: özet ve kart dağılımı.
        #expect(model.summary?.oneTimePayments == Money(40))
        #expect(model.summary?.total == Money(40))
        #expect(model.cardShares.map(\.name) == ["Bonus"])
        #expect(model.cardShares.first?.percent == 100)
        #expect(model.cardShares.first?.id == card.id.uuidString)
    }

    @Test("Analytics: only a one-time payment makes the screen loaded, not empty")
    func analyticsNotEmpty() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.oneTimePayment(card: nil, amount: 5, due: Self.ym(2027, 1), day: 2))
        let model = AnalyticsViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.reload()
        #expect(model.state == .loaded)
    }

    // MARK: Hatırlatmalar

    private static func scheduler(
        _ repository: InMemoryPaymentRepository, _ center: ReminderSchedulerTests.FakeCenter, timing: ReminderTiming
    ) -> ReminderScheduler {
        ReminderScheduler(
            repository: repository, center: center,
            preferences: InMemoryReminderPreferencesStore(preferences: ReminderPreferences(isEnabled: true, timing: timing)),
            calendar: calendar, now: { date(2026, 3, 10) }, formatAmount: { "TRY \($0.amount)" }
        )
    }

    @Test("ReminderScheduler schedules one-time payments and respects the timing", arguments: ReminderTiming.allCases)
    func reminderScheduler(timing: ReminderTiming) async throws {
        let repository = InMemoryPaymentRepository()
        let item = try Fixture.oneTimePayment("Dentist", card: nil, amount: 900, due: Self.ym(2026, 3), day: 20)
        try repository.save(item)
        let center = ReminderSchedulerTests.FakeCenter(status: .allowed)
        await Self.scheduler(repository, center, timing: timing).refresh()

        let reminders = try #require(center.replaced.last)
        // Sadece tek seferlik ödeme var; planlanan, zamanlamanın türleri kadardır.
        #expect(Set(reminders.map(\.kind)) == timing.kinds)
        #expect(reminders.count == timing.kinds.count)
        #expect(reminders.allSatisfy { $0.dueDate.day == 20 && $0.entries.map(\.itemID) == [item.id] })
    }

    // MARK: Widget

    @Test("Widget timeline counts one-time payments")
    func widget() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.oneTimePayment("Dentist", card: nil, amount: 1500, due: Self.ym(2026, 3), day: 11))
        let builder = WidgetTimelineBuilder(repository: repository, calendar: Self.calendar)
        let result = builder.timeline(now: Self.date(2026, 3, 10))
        guard case .summary(let first) = try #require(result.entries.first).content else {
            Issue.record("expected a summary, not empty")
            return
        }
        #expect(first.monthTotal == Money(1500))
        #expect(first.next.map(\.title) == ["Dentist"])
        #expect(first.next.first?.daysUntil == 1)
    }

    @Test("Widget shows a one-time payment due in a later month")
    func widgetLater() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.oneTimePayment("Far", card: nil, amount: 70, due: Self.ym(2026, 5), day: 3))
        let builder = WidgetTimelineBuilder(repository: repository, calendar: Self.calendar)
        let result = builder.timeline(now: Self.date(2026, 3, 10))
        guard case .summary(let summary) = try #require(result.entries.first).content else {
            Issue.record("a payment due later must not make the widget empty")
            return
        }
        #expect(summary.monthTotal == .zero)
        #expect(summary.next.map(\.title) == ["Far"])
    }

    // MARK: Siri / Shortcuts

    @Test("PaymentSummaryProvider includes one-time payments")
    func provider() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.oneTimePayment("Dentist", card: nil, amount: 1500, due: Self.ym(2026, 10), day: 20))
        let provider = PaymentSummaryProvider(
            repository: repository, calendar: Self.calendar, now: { Self.date(2026, 10, 12) }
        )
        let summary = try provider.summary()
        #expect(summary.monthTotal == Money(1500))
        #expect(summary.remaining == Money(1500))
        #expect(summary.next.map(\.title) == ["Dentist"])
    }
}
