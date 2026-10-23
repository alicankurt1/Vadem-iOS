import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("ReminderScheduler")
struct ReminderSchedulerTests {
    // MARK: Yardımcılar

    private struct Failure: Error {}

    // Çağrıları kaydeden sahte merkez.
    @MainActor
    private final class FakeCenter: ReminderCenter {
        var status: ReminderAuthorization
        var requestResult: Bool
        var throwsOnRequest = false
        var throwsOnReplace = false
        // İstek sırasında kaç kez askıya alınacağı (eşzamanlılık testi için).
        var requestSuspensions = 0

        private(set) var statusQueries = 0
        private(set) var requestCount = 0
        private(set) var replaced: [[PlannedReminder]] = []

        init(status: ReminderAuthorization, requestResult: Bool = true) {
            self.status = status
            self.requestResult = requestResult
        }

        func authorizationStatus() async -> ReminderAuthorization {
            statusQueries += 1
            return status
        }

        func requestAuthorization() async throws -> Bool {
            requestCount += 1
            for _ in 0..<requestSuspensions { await Task.yield() }
            if throwsOnRequest { throw Failure() }
            return requestResult
        }

        func replacePending(_ reminders: [PlannedReminder]) async throws {
            replaced.append(reminders)
            if throwsOnReplace { throw Failure() }
        }
    }

    private struct FailingRepository: PaymentRepository {
        func cards() throws -> [Card] { throw Failure() }
        func save(_ card: Card) throws { throw Failure() }
        func deleteCard(id: Card.ID) throws { throw Failure() }
        func installments() throws -> [InstallmentItem] { throw Failure() }
        func save(_ item: InstallmentItem) throws { throw Failure() }
        func deleteInstallment(id: InstallmentItem.ID) throws { throw Failure() }
        func subscriptions() throws -> [SubscriptionItem] { throw Failure() }
        func save(_ item: SubscriptionItem) throws { throw Failure() }
        func deleteSubscription(id: SubscriptionItem.ID) throws { throw Failure() }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    // Sabit "şimdi": 10 Mart 2026 12:00 (İstanbul).
    private static var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
    }

    private static func format(_ money: Money) -> String { "TRY \(money.amount)" }

    // Her ayın 15'inde ödenen kartsız abonelik: now'dan sonra hatırlatma üretir.
    private static func monthlySubscription() -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: "Rent", cardID: nil,
            subscription: Subscription(
                amount: Money(1000), period: .monthly, renewalDay: 15, firstMonth: YearMonth(year: 2026, month: 1)!
            )!
        )!
    }

    private static func repositoryWithPayment() throws -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        try repository.save(monthlySubscription())
        return repository
    }

    private static func scheduler(_ repository: any PaymentRepository, _ center: FakeCenter) -> ReminderScheduler {
        ReminderScheduler(
            repository: repository, center: center, calendar: calendar, now: { now }, formatAmount: format
        )
    }

    // Bağımsız beklenen plan: aynı girdilerle planlayıcının çıktısı.
    private static func expectedPlan(_ repository: InMemoryPaymentRepository) throws -> [PlannedReminder] {
        NotificationPlanner.plan(
            now: now, calendar: calendar, cards: try repository.cards(),
            installments: try repository.installments(), subscriptions: try repository.subscriptions(),
            formatAmount: format
        )
    }

    // MARK: İzin durumuna göre

    @Test("Allowed: pending reminders are replaced with exactly the planner's output")
    func allowedReplaces() async throws {
        let repository = try Self.repositoryWithPayment()
        let center = FakeCenter(status: .allowed)
        await Self.scheduler(repository, center).refresh()
        let expected = try Self.expectedPlan(repository)
        #expect(!expected.isEmpty)
        #expect(center.replaced == [expected])
        #expect(center.requestCount == 0)
    }

    @Test("Denied: nothing is scheduled and the user is not asked")
    func deniedDoesNothing() async throws {
        let center = FakeCenter(status: .denied)
        await Self.scheduler(try Self.repositoryWithPayment(), center).refresh()
        #expect(center.replaced.isEmpty)
        #expect(center.requestCount == 0)
    }

    @Test("Not determined with reminders and granted: one request, then scheduling")
    func notDeterminedGranted() async throws {
        let repository = try Self.repositoryWithPayment()
        let center = FakeCenter(status: .notDetermined, requestResult: true)
        await Self.scheduler(repository, center).refresh()
        #expect(center.requestCount == 1)
        #expect(center.replaced == [try Self.expectedPlan(repository)])
    }

    @Test("Not determined with reminders and refused: one request, nothing scheduled")
    func notDeterminedRefused() async throws {
        let center = FakeCenter(status: .notDetermined, requestResult: false)
        await Self.scheduler(try Self.repositoryWithPayment(), center).refresh()
        #expect(center.requestCount == 1)
        #expect(center.replaced.isEmpty)
    }

    @Test("Not determined with nothing to plan: no request, pending cleared")
    func notDeterminedEmpty() async {
        let center = FakeCenter(status: .notDetermined)
        await Self.scheduler(InMemoryPaymentRepository(), center).refresh()
        #expect(center.requestCount == 0)
        #expect(center.replaced == [[]])
    }

    @Test("Empty plan clears pending reminders for every status", arguments: [
        ReminderAuthorization.allowed, .denied, .notDetermined,
    ])
    func emptyPlanClears(status: ReminderAuthorization) async {
        let center = FakeCenter(status: status)
        await Self.scheduler(InMemoryPaymentRepository(), center).refresh()
        #expect(center.replaced == [[]])
        #expect(center.requestCount == 0)
    }

    @Test("Payments that are all in the past plan nothing and clear pending")
    func onlyPastPayments() async throws {
        // Aylık abonelik sürekli devam ettiği için gelecekte hep ödemesi olur.
        // Bu yüzden geçmişte bitmiş bir taksit kullanılır: tek taksit, Ocak 2026 (şimdi: Mart 2026).
        let plan = try #require(InstallmentPlan(total: Money(100), count: 1, firstMonth: YearMonth(year: 2026, month: 1)!))
        let card = try #require(Card(id: UUID(), name: "Bonus", statementDay: 10, dueDay: 20))
        let item = try #require(InstallmentItem(id: UUID(), title: "Old", cardID: card.id, plan: plan))
        let repository = InMemoryPaymentRepository()
        try repository.save(card)
        try repository.save(item)
        let center = FakeCenter(status: .allowed)
        await Self.scheduler(repository, center).refresh()
        #expect(try Self.expectedPlan(repository).isEmpty)
        #expect(center.replaced == [[]])
    }

    // MARK: Tekrar ve eşzamanlılık

    @Test("A second refresh after a refusal does not ask again")
    func noSecondRequestAfterRefusal() async throws {
        let center = FakeCenter(status: .notDetermined, requestResult: false)
        let scheduler = Self.scheduler(try Self.repositoryWithPayment(), center)
        await scheduler.refresh()
        await scheduler.refresh()
        #expect(center.requestCount == 1)
        #expect(center.replaced.isEmpty)
    }

    @Test("A second refresh after the status turned denied does not ask or schedule")
    func noSecondRequestAfterDenied() async throws {
        let center = FakeCenter(status: .notDetermined, requestResult: false)
        let scheduler = Self.scheduler(try Self.repositoryWithPayment(), center)
        await scheduler.refresh()
        center.status = .denied
        await scheduler.refresh()
        #expect(center.requestCount == 1)
        #expect(center.replaced.isEmpty)
    }

    @Test("Refresh after a grant, once the status is allowed, replaces again")
    func refreshAgainWhenAllowed() async throws {
        let repository = try Self.repositoryWithPayment()
        let center = FakeCenter(status: .notDetermined, requestResult: true)
        let scheduler = Self.scheduler(repository, center)
        await scheduler.refresh()
        center.status = .allowed
        await scheduler.refresh()
        #expect(center.requestCount == 1)
        #expect(center.replaced == [try Self.expectedPlan(repository), try Self.expectedPlan(repository)])
    }

    @Test("Concurrent refreshes never open two authorization requests")
    func concurrentRefreshes() async throws {
        let center = FakeCenter(status: .notDetermined, requestResult: false)
        center.requestSuspensions = 5
        let scheduler = Self.scheduler(try Self.repositoryWithPayment(), center)
        let first = Task { await scheduler.refresh() }
        let second = Task { await scheduler.refresh() }
        let third = Task { await scheduler.refresh() }
        await first.value
        await second.value
        await third.value
        #expect(center.requestCount == 1)
    }

    @Test("A refresh arriving while a pass is suspended is not lost")
    func refreshMidPassIsNotLost() async throws {
        let repository = try Self.repositoryWithPayment()
        let center = FakeCenter(status: .notDetermined, requestResult: true)
        center.requestSuspensions = 5
        let scheduler = Self.scheduler(repository, center)

        let first = Task { await scheduler.refresh() }
        // İlk tur izin isteğinde askıdayken veri değişir ve izin verilmiş olur.
        await Task.yield()
        let gym = SubscriptionItem(
            id: UUID(), title: "Gym", cardID: nil,
            subscription: Subscription(
                amount: Money(250), period: .monthly, renewalDay: 25, firstMonth: YearMonth(year: 2026, month: 1)!
            )!
        )!
        try repository.save(gym)
        center.status = .allowed
        let second = Task { await scheduler.refresh() }
        await first.value
        await second.value

        let finalPlan = try Self.expectedPlan(repository)
        #expect(center.requestCount == 1)
        #expect(center.replaced.last == finalPlan)
        #expect(finalPlan.contains { $0.entries.contains { $0.title == "Gym" } })
    }

    // MARK: Hatalar

    @Test("A failing repository does not crash, ask or schedule", arguments: [
        ReminderAuthorization.allowed, .denied, .notDetermined,
    ])
    func repositoryFailure(status: ReminderAuthorization) async {
        let center = FakeCenter(status: status)
        await Self.scheduler(FailingRepository(), center).refresh()
        #expect(center.requestCount == 0)
        #expect(center.replaced.isEmpty)
    }

    @Test("A throwing center does not crash")
    func centerFailures() async throws {
        let repository = try Self.repositoryWithPayment()

        let replaceFails = FakeCenter(status: .allowed)
        replaceFails.throwsOnReplace = true
        await Self.scheduler(repository, replaceFails).refresh()
        #expect(replaceFails.replaced.count == 1)

        // İstek hata verirse reddedilmiş sayılır: zamanlama yok, tekrar sorulmaz.
        let requestFails = FakeCenter(status: .notDetermined)
        requestFails.throwsOnRequest = true
        let scheduler = Self.scheduler(repository, requestFails)
        await scheduler.refresh()
        await scheduler.refresh()
        #expect(requestFails.requestCount == 1)
        #expect(requestFails.replaced.isEmpty)

        let clearFails = FakeCenter(status: .allowed)
        clearFails.throwsOnReplace = true
        await Self.scheduler(InMemoryPaymentRepository(), clearFails).refresh()
        #expect(clearFails.replaced == [[]])
    }
}

@MainActor
@Suite("HomeViewModel onDataChanged")
struct HomeViewModelHookTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    }

    private static func item(day: Int) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: "Music", cardID: nil,
            subscription: Subscription(
                amount: Money(100), period: .monthly, renewalDay: day, firstMonth: YearMonth(year: 2026, month: 1)!
            )!
        )!
    }

    @Test("reloadAfterChange reloads first, then calls onDataChanged once")
    func reloadThenHook() throws {
        let repository = InMemoryPaymentRepository()
        var calls = 0
        var rowsSeenInHook: Int?
        var modelRef: HomeViewModel?
        let model = HomeViewModel(
            repository: repository, today: Self.today, calendar: Self.calendar,
            onDataChanged: {
                calls += 1
                rowsSeenInHook = modelRef?.rows.count
            }
        )
        modelRef = model
        #expect(model.rows.isEmpty)
        try repository.save(Self.item(day: 20))
        #expect(model.rows.isEmpty)
        model.reloadAfterChange()
        #expect(calls == 1)
        #expect(model.rows.count == 1)
        #expect(rowsSeenInHook == 1)
    }

    @Test("A nil hook is fine")
    func nilHook() {
        let model = HomeViewModel(repository: InMemoryPaymentRepository(), today: Self.today, calendar: Self.calendar)
        model.reloadAfterChange()
        #expect(model.state == .empty)
    }

    @Test("select, updateToday, month navigation and reload do not call the hook")
    func otherActionsDoNotCallHook() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Self.item(day: 20))
        var calls = 0
        let model = HomeViewModel(
            repository: repository, today: Self.today, calendar: Self.calendar, onDataChanged: { calls += 1 }
        )
        model.select(day: 20)
        model.select(month: YearMonth(year: 2026, month: 11)!)
        model.showNextMonth()
        model.showPreviousMonth()
        model.updateToday(Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!)
        model.reload()
        #expect(calls == 0)
    }

    @Test("Each reloadAfterChange calls the hook once")
    func hookPerChange() {
        var calls = 0
        let model = HomeViewModel(
            repository: InMemoryPaymentRepository(), today: Self.today, calendar: Self.calendar,
            onDataChanged: { calls += 1 }
        )
        model.reloadAfterChange()
        model.reloadAfterChange()
        #expect(calls == 2)
    }
}
