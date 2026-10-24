import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("AnalyticsViewModel")
struct AnalyticsViewModelTests {
    // MARK: Yardımcılar

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func month(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }

    private static func model(
        _ repository: any PaymentRepository = InMemoryPaymentRepository(), today: Date? = nil
    ) -> AnalyticsViewModel {
        AnalyticsViewModel(repository: repository, today: today ?? date(2026, 10, 12), calendar: calendar)
    }

    private static func subscription(_ amount: Decimal, first: YearMonth) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: "Music", cardID: nil,
            subscription: Subscription(amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: first)!
        )!
    }

    private struct FailingRepository: PaymentRepository {
        struct Failure: Error {}
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

    // MARK: Yükleniyor

    @Test("Starts loading with no months and no summary")
    func startsLoading() {
        let model = Self.model()
        #expect(model.state == .loading)
        #expect(model.months.isEmpty)
        #expect(model.summary == nil)
        #expect(model.currentMonth == Self.month(2026, 10))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    // MARK: 12 ay

    @Test("Shows 12 consecutive months starting at the injected current month", arguments: [
        (2026, 10, 12), (2026, 1, 15), (2026, 12, 31), (2028, 2, 29),
    ])
    func twelveMonths(year: Int, month: Int, day: Int) throws {
        let model = Self.model(today: Self.date(year, month, day))
        model.reload()
        #expect(model.months.count == 12)
        #expect(AnalyticsViewModel.monthCount == 12)
        let start = Self.month(year, month)
        #expect(model.months.first?.month == start)
        for (offset, total) in model.months.enumerated() {
            #expect(total.month == start.adding(months: offset))
        }
    }

    @Test("Year boundary is crossed: from December the next month is January")
    func yearBoundary() {
        let model = Self.model(today: Self.date(2026, 12, 1))
        model.reload()
        #expect(model.months[1].month == Self.month(2027, 1))
        #expect(model.months[11].month == Self.month(2027, 11))
    }

    // MARK: Boş durum

    @Test("No payments gives the empty state, 12 zero months and a zero summary")
    func emptyState() throws {
        let model = Self.model()
        model.reload()
        #expect(model.state == .empty)
        #expect(model.months.count == 12)
        #expect(model.months.allSatisfy { $0.total.isZero })
        let summary = try #require(model.summary)
        #expect(summary.total.isZero)
        #expect(summary.month == Self.month(2026, 10))
    }

    @Test("A payment in any of the 12 months gives the loaded state")
    func loadedState() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Self.subscription(100, first: Self.month(2026, 10)))
        let model = Self.model(repository)
        model.reload()
        #expect(model.state == .loaded)
    }

    // MARK: Özet

    @Test("Summary starts on the current month with its parts adding up")
    func summaryOfCurrentMonth() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Self.subscription(100, first: Self.month(2026, 10)))
        let model = Self.model(repository)
        model.reload()
        let summary = try #require(model.summary)
        #expect(summary.month == Self.month(2026, 10))
        #expect(summary.title == "October 2026")
        #expect(summary.subscriptions == Money(100))
        #expect(summary.installments.isZero)
        #expect(summary.total == Money(100))
        #expect(summary.total == summary.installments + summary.subscriptions)
    }

    @Test("Summary follows the selected month")
    func summaryFollowsSelection() throws {
        let repository = InMemoryPaymentRepository()
        // Ekimde başlayan abonelik; Eylül (geçmiş) listede yok, Kasım var.
        try repository.save(Self.subscription(100, first: Self.month(2026, 11)))
        let model = Self.model(repository)
        model.reload()
        model.select(month: Self.month(2026, 11))
        #expect(model.selectedMonth == Self.month(2026, 11))
        let summary = try #require(model.summary)
        #expect(summary.month == Self.month(2026, 11))
        #expect(summary.title == "November 2026")
        #expect(summary.subscriptions == Money(100))
    }

    // MARK: Seçim

    @Test("Selecting a month outside the 12 is ignored", arguments: [(2026, 9), (2027, 10), (2030, 1)])
    func selectOutsideIgnored(year: Int, month: Int) {
        let model = Self.model()
        model.reload()
        model.select(month: Self.month(year, month))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    @Test("Selecting the first and the last month works")
    func selectEdges() {
        let model = Self.model()
        model.reload()
        model.select(month: Self.month(2027, 9))
        #expect(model.selectedMonth == Self.month(2027, 9))
        model.select(month: Self.month(2026, 10))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    @Test("Selecting before loading is ignored")
    func selectBeforeLoad() {
        let model = Self.model()
        model.select(month: Self.month(2026, 11))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    @Test("Reload keeps the selected month")
    func reloadKeepsSelection() {
        let model = Self.model()
        model.reload()
        model.select(month: Self.month(2027, 2))
        model.reload()
        #expect(model.selectedMonth == Self.month(2027, 2))
    }

    @Test("Reload shows a payment added after the first load")
    func reloadPicksUpChanges() throws {
        let repository = InMemoryPaymentRepository()
        let model = Self.model(repository)
        model.reload()
        #expect(model.state == .empty)
        try repository.save(Self.subscription(100, first: Self.month(2026, 10)))
        model.reload()
        #expect(model.state == .loaded)
    }

    // MARK: Hata

    @Test("A failing repository gives the error state and no months")
    func errorState() {
        let model = Self.model(FailingRepository())
        model.reload()
        #expect(model.state == .error(message: AnalyticsViewModel.loadErrorMessage))
        #expect(model.months.isEmpty)
        #expect(model.summary == nil)
    }

    // MARK: Biçim

    @Test("Month titles and ids", arguments: [
        (2026, 5, "May 2026", "May", "2026-05"),
        (2027, 1, "January 2027", "Jan", "2027-01"),
        (2026, 12, "December 2026", "Dec", "2026-12"),
    ])
    func formatting(year: Int, month: Int, title: String, short: String, id: String) {
        let value = Self.month(year, month)
        #expect(AnalyticsViewModel.title(of: value) == title)
        #expect(AnalyticsViewModel.shortTitle(of: value) == short)
        #expect(AnalyticsViewModel.id(of: value) == id)
    }

    @Test("Bar accessibility label is the month and the formatted amount")
    func accessibilityLabel() {
        let total = SpendingAnalytics.MonthTotal(
            month: Self.month(2026, 5), installments: Money(Decimal(string: "3000.50")!), subscriptions: Money(1249.5)
        )
        #expect(AnalyticsViewModel.accessibilityLabel(for: total) == "May 2026, 4.250,00 TL")
    }
}
