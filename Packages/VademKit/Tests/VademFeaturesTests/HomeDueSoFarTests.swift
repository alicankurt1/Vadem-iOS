import Foundation
import Testing
import VademCore
@testable import VademFeatures

@MainActor
@Suite("HomeViewModel.dueSoFar")
struct HomeDueSoFarTests {
    // MARK: Yardımcılar

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func ym(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }

    private static func money(_ value: Decimal) -> Money { Money(value) }

    private static func sub(_ title: String, day: Int, amount: Decimal) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: title, cardID: nil,
            subscription: Subscription(amount: Money(amount), period: .monthly, renewalDay: day, firstMonth: ym(2026, 1))!
        )!
    }

    // Ekim 2026: 5. gün 100, 12. gün 200, 20. gün 400 (toplam 700).
    private static func repository(_ items: [(String, Int, Decimal)]) -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        for (title, day, amount) in items { try! repository.save(sub(title, day: day, amount: amount)) }
        return repository
    }

    private static let october: [(String, Int, Decimal)] = [("A", 5, 100), ("B", 12, 200), ("C", 20, 400)]

    private static func entries(_ items: [(String, Int, Decimal)], month: YearMonth) -> [MonthlySchedule.Entry] {
        MonthlySchedule(month: month, cards: [], installments: [], subscriptions: items.map { sub($0.0, day: $0.1, amount: $0.2) }).entries
    }

    // MARK: Görünüm modeli

    @Test("Current month counts payments up to and including today", arguments: [
        // (bugün, beklenen)
        (4, Decimal(0)),     // henüz hiçbiri
        (5, Decimal(100)),   // bugün vadesi gelen sayılır
        (11, Decimal(100)),
        (12, Decimal(300)),  // bugün sınırı
        (19, Decimal(300)),
        (20, Decimal(700)),
        (31, Decimal(700)),
    ])
    func currentMonth(day: Int, expected: Decimal) {
        let model = HomeViewModel(repository: Self.repository(Self.october), today: Self.date(2026, 10, day), calendar: Self.calendar)
        #expect(model.total == Money(700))
        #expect(model.dueSoFar == Money(expected))
    }

    @Test("A past month is due in full")
    func pastMonth() {
        let model = HomeViewModel(repository: Self.repository(Self.october), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.showPreviousMonth()
        #expect(model.total == Money(700))
        #expect(model.dueSoFar == model.total)
    }

    @Test("A future month has nothing due yet")
    func futureMonth() {
        let model = HomeViewModel(repository: Self.repository(Self.october), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.showNextMonth()
        #expect(model.total == Money(700))
        #expect(model.dueSoFar == .zero)
    }

    @Test("An empty month is zero")
    func emptyMonth() {
        let model = HomeViewModel(repository: InMemoryPaymentRepository(), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.dueSoFar == .zero)
    }

    @Test("Selecting a day does not change the hero value")
    func daySelectionIgnored() {
        let model = HomeViewModel(repository: Self.repository(Self.october), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        let before = model.dueSoFar
        model.select(day: 20)
        #expect(model.rows.count == 1)
        #expect(model.dueSoFar == before)
        #expect(model.dueSoFar == Money(300))
        model.select(day: 5)
        #expect(model.dueSoFar == Money(300))
        model.clearSelectedDay()
        #expect(model.dueSoFar == Money(300))
    }

    @Test("Navigating back to the current month restores the value")
    func navigationRoundTrip() {
        let model = HomeViewModel(repository: Self.repository(Self.october), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.showNextMonth()
        model.showPreviousMonth()
        #expect(model.dueSoFar == Money(300))
    }

    @Test("Follows the injected today when it moves to the next day")
    func updateToday() {
        let model = HomeViewModel(repository: Self.repository(Self.october), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        model.updateToday(Self.date(2026, 10, 20))
        #expect(model.dueSoFar == Money(700))
    }

    @Test("A load error resets it to zero")
    func errorState() {
        struct Failure: Error {}
        struct Failing: PaymentRepository {
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
        let model = HomeViewModel(repository: Failing(), today: Self.date(2026, 10, 12), calendar: Self.calendar)
        #expect(model.dueSoFar == .zero)
    }

    // MARK: Saf fonksiyon

    @Test("Pure function: month relative to today", arguments: [
        // (ay, bugünün ayı, bugünün günü, beklenen)
        (9, 10, 1, Decimal(700)),    // geçmiş ay: hepsi
        (9, 10, 31, Decimal(700)),
        (12, 10, 31, Decimal(0)),    // gelecek ay: hiçbiri
        (11, 10, 31, Decimal(0)),
        (10, 10, 4, Decimal(0)),
        (10, 10, 5, Decimal(100)),
        (10, 10, 12, Decimal(300)),
        (10, 10, 20, Decimal(700)),
    ])
    func pure(month: Int, todayMonth: Int, day: Int, expected: Decimal) {
        let target = Self.ym(2026, month)
        let list = Self.entries(Self.october, month: target)
        let result = HomeViewModel.dueSoFar(of: list, month: target, todayMonth: Self.ym(2026, todayMonth), todayDay: day)
        #expect(result == Money(expected))
    }

    @Test("Pure function: year boundaries")
    func pureYearBoundary() {
        let december = Self.ym(2026, 12)
        let list = Self.entries(Self.october, month: december)
        #expect(HomeViewModel.dueSoFar(of: list, month: december, todayMonth: Self.ym(2027, 1), todayDay: 1) == Money(700))
        #expect(HomeViewModel.dueSoFar(of: list, month: Self.ym(2027, 1), todayMonth: december, todayDay: 31) == .zero)
    }

    @Test("Pure function: empty entries are zero in every case", arguments: [8, 10, 12])
    func pureEmpty(month: Int) {
        #expect(HomeViewModel.dueSoFar(of: [], month: Self.ym(2026, month), todayMonth: Self.ym(2026, 10), todayDay: 15) == .zero)
    }

    @Test("Pure function: kuruş amounts add exactly")
    func pureKurus() {
        let target = Self.ym(2026, 10)
        let list = Self.entries([("A", 1, Decimal(string: "0.10")!), ("B", 2, Decimal(string: "0.20")!), ("C", 3, Decimal(string: "0.01")!)], month: target)
        let result = HomeViewModel.dueSoFar(of: list, month: target, todayMonth: target, todayDay: 2)
        #expect(result == Money(Decimal(string: "0.30")!))
    }
}
