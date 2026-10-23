import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("AppRefresh")
struct AppRefreshTests {
    // MARK: Yardımcılar

    // Çağrıları sayan sahte widget yenileyici.
    @MainActor
    private final class FakeWidgets: WidgetReloading {
        private(set) var reloadCount = 0
        func reloadTimelines() { reloadCount += 1 }
    }

    private typealias Center = ReminderSchedulerTests.FakeCenter

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private static var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
    }

    // Her ayın 15'inde ödenen abonelik: now'dan sonra hatırlatma üretir.
    private static func repository() throws -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        try repository.save(SubscriptionItem(
            id: UUID(), title: "Rent", cardID: nil,
            subscription: Subscription(
                amount: Money(1000), period: .monthly, renewalDay: 15, firstMonth: YearMonth(year: 2026, month: 1)!
            )!
        )!)
        return repository
    }

    // Gerçek UserDefaults'a dokunmamak için bellek içi tercih deposu.
    private static func scheduler(_ center: Center) throws -> ReminderScheduler {
        ReminderScheduler(
            repository: try repository(), center: center,
            preferences: InMemoryReminderPreferencesStore(preferences: .default),
            calendar: calendar, now: { now }, formatAmount: { "TRY \($0.amount)" }
        )
    }

    // Yenileme ayrı bir Task'ta çalışır; bitmesi için ana aktörü birkaç kez bırakırız.
    private static func settle(until condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        // Fazladan çağrı olursa görünsün diye biraz daha bekle.
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: Testler

    @Test("dataChanged reloads the widgets once and refreshes the reminders once")
    func dataChanged() async throws {
        let widgets = FakeWidgets()
        let center = Center(status: .allowed)
        let refresh = AppRefresh(reminders: try Self.scheduler(center), widgets: widgets)
        refresh.dataChanged()
        #expect(widgets.reloadCount == 1)
        await Self.settle { !center.replaced.isEmpty }
        #expect(center.replaced.count == 1)
        #expect(widgets.reloadCount == 1)
    }

    @Test("sceneBecameActive reloads the widgets once and refreshes the reminders once")
    func sceneBecameActive() async throws {
        let widgets = FakeWidgets()
        let center = Center(status: .allowed)
        let refresh = AppRefresh(reminders: try Self.scheduler(center), widgets: widgets)
        refresh.sceneBecameActive()
        #expect(widgets.reloadCount == 1)
        await Self.settle { !center.replaced.isEmpty }
        #expect(center.replaced.count == 1)
        #expect(widgets.reloadCount == 1)
    }

    @Test("Each call reloads again")
    func repeatedCalls() async {
        let widgets = FakeWidgets()
        let refresh = AppRefresh(reminders: nil, widgets: widgets)
        refresh.dataChanged()
        refresh.sceneBecameActive()
        refresh.dataChanged()
        #expect(widgets.reloadCount == 3)
    }

    @Test("Without a scheduler the widgets are still reloaded")
    func noScheduler() {
        let widgets = FakeWidgets()
        let refresh = AppRefresh(reminders: nil, widgets: widgets)
        refresh.dataChanged()
        refresh.sceneBecameActive()
        #expect(widgets.reloadCount == 2)
    }

    @Test("none does nothing and does not crash")
    func noneDoesNothing() async {
        let refresh = AppRefresh.none
        refresh.dataChanged()
        refresh.sceneBecameActive()
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("NoWidgetReloading is a no-op")
    func noWidgetReloading() {
        NoWidgetReloading().reloadTimelines()
    }
}
