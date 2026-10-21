import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("HomeViewModel")
struct HomeViewModelTests {
    // MARK: Yardımcılar

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func sub(
        _ title: String, day: Int, card: Card? = nil, amount: Decimal = 100, first: YearMonth
    ) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: title, cardID: card?.id,
            subscription: Subscription(amount: Money(amount), period: .monthly, renewalDay: day, firstMonth: first)!
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

    // MARK: Ay ve gezinme

    @Test("Starts on the month of the injected today")
    func startsOnTodayMonth() {
        let model = HomeViewModel(repository: InMemoryPaymentRepository(), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.month == YearMonth(year: 2026, month: 10))
        #expect(model.monthTitle == "October 2026")
    }

    @Test("Next and previous month cross the year boundary", arguments: [
        (2026, 12, 1, 2027, 1, "January 2027"),
        (2026, 1, -1, 2025, 12, "December 2025"),
        (2026, 10, 1, 2026, 11, "November 2026"),
        (2026, 10, -1, 2026, 9, "September 2026"),
    ])
    func navigation(year: Int, month: Int, step: Int, expectedYear: Int, expectedMonth: Int, title: String) {
        let model = HomeViewModel(repository: InMemoryPaymentRepository(), today: Self.date(year, month, 15), calendar: Self.calendar)
        if step > 0 { model.showNextMonth() } else { model.showPreviousMonth() }
        #expect(model.month == YearMonth(year: expectedYear, month: expectedMonth))
        #expect(model.monthTitle == title)
    }

    // MARK: Toplam, alt toplam, satırlar (örnek veri: 12 Ekim 2026)

    @Test("Total, subtotals and rows equal the MonthlySchedule of the month")
    func matchesSchedule() throws {
        let repository = HomeSampleData.makeRepository()
        let model = HomeViewModel(repository: repository, today: HomeSampleData.today, calendar: HomeSampleData.calendar)
        let schedule = MonthlySchedule(
            month: YearMonth(year: 2026, month: 10)!,
            cards: try repository.cards(), installments: try repository.installments(),
            subscriptions: try repository.subscriptions()
        )
        #expect(model.state == .loaded)
        #expect(model.total == schedule.total)
        #expect(model.rows.map(\.entry) == schedule.entries)
        for subtotal in model.cardSubtotals {
            #expect(subtotal.amount == schedule.total(for: subtotal.id))
        }
        // Kart sırası depodaki gibi (ada göre). Elle: 4000 (Laptop 48000/12) + 900 + 249,99 + 25000
        #expect(model.total == Money(Decimal(3_014_999) / 100))
        #expect(model.cardSubtotals.map(\.name) == ["Everyday card", "Shopping card", "Travel card"])
        #expect(model.cardSubtotals.map(\.amount) == [Money(4000), Money(Decimal(24_999) / 100), Money(900)])
    }

    @Test("Rows show title, card, installment text, due text and chip")
    func rowContents() {
        let model = HomeSampleData.makeViewModel()
        #expect(model.rows.map(\.title) == ["Laptop", "Gym", "Netflix", "Rent"])
        #expect(model.rows.map(\.cardText) == ["Everyday card", "Travel card", "Shopping card", "No card"])
        #expect(model.rows.map(\.installmentText) == ["3/12", nil, nil, nil])
        #expect(model.rows.map(\.dueText) == ["8 October", "12 October", "15 October", "25 October"])
        #expect(model.rows.map(\.chipKind) == [.overdue, .today, .soon, .later])
    }

    @Test("Each row reads as one VoiceOver label")
    func accessibilityLabels() {
        let model = HomeSampleData.makeViewModel()
        let netflix = model.rows.first { $0.title == "Netflix" }
        #expect(netflix?.accessibilityLabel == "Netflix, 249,99 Türk lirası, due 15 October, Shopping card, In 3 days")
        let rent = model.rows.first { $0.title == "Rent" }
        #expect(rent?.accessibilityLabel.contains("25.000,00 Türk lirası, due 25 October, No card") == true)
    }

    @Test("Row ids are unique")
    func uniqueIDs() {
        let model = HomeSampleData.makeViewModel()
        #expect(Set(model.rows.map(\.id)).count == model.rows.count)
    }

    // MARK: Çip türü

    @Test("Past month is all overdue, future month all later")
    func wholeMonths() {
        let model = HomeSampleData.makeViewModel()
        model.showPreviousMonth()
        #expect(!model.rows.isEmpty)
        #expect(model.rows.allSatisfy { $0.chipKind == .overdue })
        model.showNextMonth()
        model.showNextMonth()
        #expect(!model.rows.isEmpty)
        #expect(model.rows.allSatisfy { $0.chipKind == .later })
    }

    // Bugün 31 Ekim; Kasım'daki kartsız abonelik vade günü = yenileme günü.
    @Test("Chip kind by day distance across a month end", arguments: [
        (1, DueChip.Kind.soon, "Tomorrow"),
        (2, .soon, "In 2 days"),
        (3, .soon, "In 3 days"),
        (4, .later, "Later"),
    ])
    func soonBoundary(renewalDay: Int, kind: DueChip.Kind, text: String) {
        let repository = InMemoryPaymentRepository()
        try! repository.save(Self.sub("Test", day: renewalDay, first: YearMonth(year: 2026, month: 9)!))
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 31), calendar: Self.calendar)
        model.showNextMonth()
        #expect(model.rows.count == 1)
        #expect(model.rows.first?.chipKind == kind)
        #expect(model.rows.first?.chipText == text)
    }

    @Test("Due on the injected day is today; the day before is overdue")
    func todayAndOverdue() {
        let repository = InMemoryPaymentRepository()
        try! repository.save(Self.sub("A", day: 14, first: YearMonth(year: 2026, month: 9)!))
        try! repository.save(Self.sub("B", day: 15, first: YearMonth(year: 2026, month: 9)!))
        try! repository.save(Self.sub("C", day: 16, first: YearMonth(year: 2026, month: 9)!))
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 15), calendar: Self.calendar)
        let kinds = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.title, $0.chipKind) })
        #expect(kinds == ["A": .overdue, "B": .today, "C": .soon])
    }

    // MARK: Boş ve hata durumu

    @Test("Empty data gives the empty state with zero total")
    func emptyState() {
        let model = HomeViewModel(repository: InMemoryPaymentRepository(), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.state == .empty)
        #expect(model.total == .zero)
        #expect(model.rows.isEmpty)
        #expect(model.cardSubtotals.isEmpty)
    }

    @Test("A repository error gives the error state, not an empty list")
    func errorState() {
        let model = HomeViewModel(repository: FailingRepository(), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.state == .error(message: HomeViewModel.loadErrorMessage))
        #expect(model.state != .empty)
        #expect(model.total == .zero)
        #expect(model.rows.isEmpty)
        #expect(model.schedule == nil)
    }

    @Test("Reload picks up new data and leaves the error state when the repository recovers")
    func reloadPicksUpChanges() throws {
        let repository = InMemoryPaymentRepository()
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.state == .empty)
        try repository.save(Self.sub("Late", day: 20, amount: 10, first: YearMonth(year: 2026, month: 9)!))
        model.reload()
        #expect(model.state == .loaded)
        #expect(model.total == Money(10))
    }
}
