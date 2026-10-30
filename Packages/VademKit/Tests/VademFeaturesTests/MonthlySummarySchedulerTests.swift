import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("ReminderScheduler monthly summary")
struct MonthlySummarySchedulerTests {
    private typealias Center = ReminderSchedulerTests.FakeCenter

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    // Sabit "şimdi": 10 Mart 2026 12:00; özet 1 Nisan 09:00'da çıkar.
    private static var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
    }

    private static func sub(_ title: String, _ amount: Decimal, from first: YearMonth) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: title, cardID: nil,
            subscription: Subscription(amount: Money(amount), period: .monthly, renewalDay: 15, firstMonth: first)!
        )!
    }

    // Nisan'da 1000 -> 1500 (+%50): özet var. Hatırlatmalar da var (aylık ödeme).
    private static func repositoryWithInsight() throws -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        try repository.save(sub("Rent", 1000, from: YearMonth(year: 2026, month: 1)!))
        try repository.save(sub("Gym", 500, from: YearMonth(year: 2026, month: 4)!))
        return repository
    }

    // Değişim yok: hatırlatma var, özet yok.
    private static func repositoryWithoutInsight() throws -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        try repository.save(sub("Rent", 1000, from: YearMonth(year: 2026, month: 1)!))
        return repository
    }

    private static func scheduler(
        _ repository: any PaymentRepository, _ center: Center, _ preferences: ReminderPreferences = .default
    ) -> ReminderScheduler {
        ReminderScheduler(
            repository: repository, center: center,
            preferences: InMemoryReminderPreferencesStore(preferences: preferences),
            calendar: calendar, now: { now }, formatAmount: { "TRY \($0.amount)" }
        )
    }

    private static var aprilFirst: Date {
        calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
    }

    @Test("Allowed with an insight: the summary is scheduled on the 1st at 09:00 with the reminders")
    func schedulesSummary() async throws {
        let center = Center(status: .allowed)
        await Self.scheduler(try Self.repositoryWithInsight(), center).refresh()
        #expect(center.replaced.count == 1)
        #expect(!(center.replaced.first ?? []).isEmpty)
        let summary = try #require(center.replacedSummaries.first ?? nil)
        #expect(summary.fireDate == Self.aprilFirst)
        #expect(summary.id == "insight-2026-04")
        #expect(summary.insight.detail == .totalChange(previous: Money(1000), current: Money(1500), percent: 50))
    }

    @Test("Refreshing twice replaces with the same single summary (one per month)")
    func atMostOnePerMonth() async throws {
        let center = Center(status: .allowed)
        let scheduler = Self.scheduler(try Self.repositoryWithInsight(), center)
        await scheduler.refresh()
        await scheduler.refresh()
        #expect(center.replacedSummaries.count == 2)
        #expect(center.replacedSummaries[0] == center.replacedSummaries[1])
        #expect(center.replacedSummaries[0]?.id == "insight-2026-04")
    }

    @Test("No insight: reminders are scheduled without a summary")
    func noInsight() async throws {
        let center = Center(status: .allowed)
        await Self.scheduler(try Self.repositoryWithoutInsight(), center).refresh()
        #expect(center.replaced.count == 1)
        #expect(!(center.replaced.first ?? []).isEmpty)
        #expect(center.replacedSummaries == [nil])
    }

    @Test("Summary off, reminders on: reminders are scheduled and the summary is cancelled")
    func summaryOff() async throws {
        let center = Center(status: .allowed)
        let off = ReminderPreferences(monthlySummaryEnabled: false)
        await Self.scheduler(try Self.repositoryWithInsight(), center, off).refresh()
        #expect(center.replaced.count == 1)
        #expect(!(center.replaced.first ?? []).isEmpty)
        #expect(center.replacedSummaries == [nil])
    }

    @Test("Summary on, reminders off: only the summary is scheduled")
    func remindersOff() async throws {
        let center = Center(status: .allowed)
        let preferences = ReminderPreferences(isEnabled: false, monthlySummaryEnabled: true)
        await Self.scheduler(try Self.repositoryWithInsight(), center, preferences).refresh()
        #expect(center.replaced == [[]])
        #expect(center.replacedSummaries.first??.fireDate == Self.aprilFirst)
    }

    @Test("Both switches off: pending cleared, permission never asked or read", arguments: [
        ReminderAuthorization.notDetermined, .allowed, .denied,
    ])
    func bothOff(status: ReminderAuthorization) async throws {
        let center = Center(status: status)
        let off = ReminderPreferences(isEnabled: false, monthlySummaryEnabled: false)
        await Self.scheduler(try Self.repositoryWithInsight(), center, off).refresh()
        #expect(center.replaced == [[]])
        #expect(center.replacedSummaries == [nil])
        #expect(center.requestCount == 0)
        #expect(center.statusQueries == 0)
    }

    @Test("Summary only, nothing to send: no permission prompt, pending cleared")
    func nothingToSendNoPrompt() async throws {
        let center = Center(status: .notDetermined)
        let preferences = ReminderPreferences(isEnabled: false, monthlySummaryEnabled: true)
        await Self.scheduler(try Self.repositoryWithoutInsight(), center, preferences).refresh()
        #expect(center.requestCount == 0)
        #expect(center.replaced == [[]])
        #expect(center.replacedSummaries == [nil])
    }

    @Test("Summary only with an insight and permission not asked: one request, then scheduling")
    func summaryAsksOnce() async throws {
        let center = Center(status: .notDetermined, requestResult: true)
        let preferences = ReminderPreferences(isEnabled: false, monthlySummaryEnabled: true)
        await Self.scheduler(try Self.repositoryWithInsight(), center, preferences).refresh()
        #expect(center.requestCount == 1)
        #expect(center.replacedSummaries.first??.id == "insight-2026-04")
    }

    @Test("Denied permission: the summary is not scheduled and nobody asks")
    func denied() async throws {
        let center = Center(status: .denied)
        await Self.scheduler(try Self.repositoryWithInsight(), center).refresh()
        #expect(center.replaced.isEmpty)
        #expect(center.requestCount == 0)
    }

    @Test("Turning the summary off after it was scheduled cancels it on the next refresh")
    func toggleOffCancels() async throws {
        let center = Center(status: .allowed)
        let store = InMemoryReminderPreferencesStore()
        let scheduler = ReminderScheduler(
            repository: try Self.repositoryWithInsight(), center: center, preferences: store,
            calendar: Self.calendar, now: { Self.now }, formatAmount: { "TRY \($0.amount)" }
        )
        await scheduler.refresh()
        #expect(center.replacedSummaries.last??.id == "insight-2026-04")
        var preferences = store.load()
        preferences.monthlySummaryEnabled = false
        store.save(preferences)
        await scheduler.refresh()
        #expect(center.replacedSummaries.count == 2)
        #expect(center.replacedSummaries[1] == nil)
    }
}
