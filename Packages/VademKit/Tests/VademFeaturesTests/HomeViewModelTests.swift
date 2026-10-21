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

    // MARK: İnceleme turu 1: ek senaryolar (kendi veri kümeleriyle)

    // Sabit içerik döndüren depo: gerçek depo bilinmeyen kartı kaydetmeyi reddeder, bu yüzden
    // bu durumlara sadece protokol üzerinden ulaşılır.
    private struct StubRepository: PaymentRepository {
        var storedCards: [Card] = []
        var storedInstallments: [InstallmentItem] = []
        var storedSubscriptions: [SubscriptionItem] = []
        func cards() throws -> [Card] { storedCards }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { storedInstallments }
        func save(_ item: InstallmentItem) throws {}
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { storedSubscriptions }
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
    }

    @Test("Payments whose card is missing are skipped, not shown and not counted")
    func unknownCardSkipped() {
        let ghost = Card(name: "Ghost", statementDay: 1, dueDay: 10)!
        let orphan = Self.sub("Orphan", day: 5, card: ghost, amount: 500, first: YearMonth(year: 2026, month: 8)!)
        let free = Self.sub("Free", day: 20, amount: 70, first: YearMonth(year: 2026, month: 8)!)
        let plan = InstallmentPlan(total: Money(300), count: 3, firstMonth: YearMonth(year: 2026, month: 9)!)!
        let orphanInstallment = InstallmentItem(id: UUID(), title: "OrphanPlan", cardID: ghost.id, plan: plan)!
        let repository = StubRepository(
            storedInstallments: [orphanInstallment], storedSubscriptions: [orphan, free]
        )
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.title) == ["Free"])
        #expect(model.total == Money(70))
        #expect(model.cardSubtotals.isEmpty)
    }

    @Test("Only orphaned payments leave the empty state")
    func onlyUnknownCardIsEmpty() {
        let ghost = Card(name: "Ghost", statementDay: 1, dueDay: 10)!
        let orphan = Self.sub("Orphan", day: 5, card: ghost, first: YearMonth(year: 2026, month: 8)!)
        let model = HomeViewModel(
            repository: StubRepository(storedSubscriptions: [orphan]),
            today: Self.date(2026, 10, 12), calendar: Self.calendar
        )
        #expect(model.state == .empty)
        #expect(model.total == .zero)
    }

    @Test("One item with two payments in a month gives two rows with unique ids")
    func twoPaymentsSameMonth() throws {
        // Ekstre 29, vade 30: Şubat 2027'de (28 gün) vade 28 <= ekstre 28 olduğundan Mart 30'a kayar;
        // Mart ekstresi de Mart 30'da öder. İki taksit de Mart 30'da.
        let card = Card(name: "Edge", statementDay: 29, dueDay: 30)!
        let plan = InstallmentPlan(total: Money(200), count: 2, firstMonth: YearMonth(year: 2027, month: 2)!)!
        let item = InstallmentItem(id: UUID(), title: "Sofa", cardID: card.id, plan: plan)!
        let repository = InMemoryPaymentRepository()
        try repository.save(card)
        try repository.save(item)
        let model = HomeViewModel(repository: repository, today: Self.date(2027, 3, 1), calendar: Self.calendar)
        #expect(model.rows.count == 2)
        #expect(Set(model.rows.map(\.id)).count == 2)
        #expect(model.rows.map(\.installmentText) == ["1/2", "2/2"])
        #expect(model.rows.map(\.dueText) == ["30 March", "30 March"])
        #expect(model.total == Money(200))
        #expect(model.cardSubtotals.map(\.amount) == [Money(200)])
    }

    @Test("Today is the calendar's local day, not the UTC day")
    func nonUTCCalendar() {
        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        // 14 Ekim 22:00 UTC = 15 Ekim 01:00 İstanbul (UTC+3).
        let instant = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 22))!
        let repository = InMemoryPaymentRepository()
        try! repository.save(Self.sub("Due15", day: 15, first: YearMonth(year: 2026, month: 9)!))
        try! repository.save(Self.sub("Due14", day: 14, first: YearMonth(year: 2026, month: 9)!))
        let model = HomeViewModel(repository: repository, today: instant, calendar: istanbul)
        let kinds = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.title, $0.chipKind) })
        #expect(kinds == ["Due15": .today, "Due14": .overdue])
    }

    @Test("The starting month follows the calendar's local date")
    func nonUTCMonth() {
        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        // 30 Eylül 22:00 UTC = 1 Ekim 01:00 İstanbul.
        let instant = Self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 22))!
        let model = HomeViewModel(repository: InMemoryPaymentRepository(), today: instant, calendar: istanbul)
        #expect(model.month == YearMonth(year: 2026, month: 10))
    }

    @Test("Duplicate card ids from the repository show one subtotal, first card wins")
    func duplicateCardIDs() {
        let id = UUID()
        let first = Card(id: id, name: "First", statementDay: 1, dueDay: 10)!
        let second = Card(id: id, name: "Second", statementDay: 1, dueDay: 10)!
        let item = Self.sub("Svc", day: 1, card: first, amount: 40, first: YearMonth(year: 2026, month: 9)!)
        let repository = StubRepository(storedCards: [first, second], storedSubscriptions: [item])
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.cardSubtotals.count == 1)
        #expect(model.cardSubtotals.first?.name == "First")
        #expect(model.cardSubtotals.first?.amount == Money(40))
        #expect(model.rows.first?.cardText == "First")
    }

    // MARK: updateToday(_:)

    @Test("updateToday follows the current month when it was selected, across a month rollover", arguments: [
        ((2026, 10, 31), (2026, 11, 1), (2026, 11)),
        ((2026, 12, 31), (2027, 1, 1), (2027, 1)),
        ((2026, 10, 12), (2026, 10, 13), (2026, 10)),
    ])
    func updateTodayFollowsCurrentMonth(
        old: (Int, Int, Int), new: (Int, Int, Int), expected: (Int, Int)
    ) {
        let model = HomeViewModel(
            repository: InMemoryPaymentRepository(),
            today: Self.date(old.0, old.1, old.2), calendar: Self.calendar
        )
        model.updateToday(Self.date(new.0, new.1, new.2))
        #expect(model.month == YearMonth(year: expected.0, month: expected.1))
    }

    @Test("updateToday keeps a month the user navigated to")
    func updateTodayKeepsNavigatedMonth() {
        let model = HomeViewModel(
            repository: InMemoryPaymentRepository(), today: Self.date(2026, 10, 31), calendar: Self.calendar
        )
        model.showPreviousMonth()
        model.updateToday(Self.date(2026, 11, 1))
        #expect(model.month == YearMonth(year: 2026, month: 9))
    }

    @Test("updateToday recomputes chip kinds from the new day")
    func updateTodayRecomputesChips() throws {
        let repository = InMemoryPaymentRepository()
        let first = YearMonth(year: 2026, month: 9)!
        try repository.save(Self.sub("A", day: 15, first: first))
        try repository.save(Self.sub("B", day: 16, first: first))
        try repository.save(Self.sub("C", day: 25, first: first))
        let model = HomeViewModel(repository: repository, today: Self.date(2026, 10, 15), calendar: Self.calendar)
        func kinds() -> [String: DueChip.Kind] {
            Dictionary(uniqueKeysWithValues: model.rows.map { ($0.title, $0.chipKind) })
        }
        #expect(kinds() == ["A": .today, "B": .soon, "C": .later])
        model.updateToday(Self.date(2026, 10, 16))
        #expect(model.month == YearMonth(year: 2026, month: 10))
        #expect(kinds() == ["A": .overdue, "B": .today, "C": .later])
        // Chip metni de yeni güne göre: C artık 9 gün sonra, 22'sinde 3 gün.
        model.updateToday(Self.date(2026, 10, 22))
        #expect(kinds()["C"] == .soon)
        #expect(model.rows.first { $0.title == "C" }?.chipText == "In 3 days")
    }
}
