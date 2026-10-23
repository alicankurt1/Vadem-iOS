import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("PaymentSummaryProvider")
struct PaymentSummaryProviderTests {
    // MARK: Yardımcılar

    private struct Failure: Error, Equatable {}

    // Her okuması hata fırlatan depo.
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

    // Ekim 2026, öğlen (İstanbul).
    private static func october(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    // Her ay `day`. günü ödenen, kartsız aylık abonelik.
    private static func sub(_ title: String, day: Int, amount: Decimal) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: title, cardID: nil,
            subscription: Subscription(
                amount: Money(amount), period: .monthly, renewalDay: day,
                firstMonth: YearMonth(year: 2026, month: 1)!
            )!
        )!
    }

    private static func provider(
        _ items: [SubscriptionItem], today: Int = 12
    ) throws -> PaymentSummaryProvider {
        let repository = InMemoryPaymentRepository()
        for item in items { try repository.save(item) }
        return PaymentSummaryProvider(repository: repository, calendar: calendar, now: { october(today) })
    }

    private static func failing() -> PaymentSummaryProvider {
        PaymentSummaryProvider(repository: FailingRepository(), calendar: calendar, now: { october(12) })
    }

    // MARK: Ay toplamı

    @Test("Month total with an amount still to go")
    func monthTotalWithRemaining() throws {
        // 1000 (5.) geçti; 250,50 (15.) + 99 (20.) kaldı: toplam 1349,50, kalan 349,50.
        let provider = try Self.provider([
            Self.sub("Rent", day: 5, amount: 1000),
            Self.sub("Gym", day: 15, amount: 250.50),
            Self.sub("Music", day: 20, amount: 99),
        ])
        #expect(provider.monthTotalAnswer()
            == "You pay 1.349,50 Türk lirası in October 2026, 349,50 Türk lirası still to go.")
    }

    @Test("Month total omits still-to-go when nothing is paid yet")
    func monthTotalRemainingEqualsTotal() throws {
        // Ayın 1'inde her şey kalan; kalan = toplam olduğu için ikinci kısım yok.
        let provider = try Self.provider([
            Self.sub("Rent", day: 5, amount: 1000),
            Self.sub("Gym", day: 15, amount: 250.50),
        ], today: 1)
        #expect(provider.monthTotalAnswer() == "You pay 1.250,50 Türk lirası in October 2026.")
    }

    @Test("Month total of an empty month")
    func monthTotalEmpty() throws {
        let provider = try Self.provider([])
        #expect(provider.monthTotalAnswer() == "Nothing is due in October 2026.")
    }

    @Test("Month total when every payment is already past")
    func monthTotalOnlyPast() throws {
        let provider = try Self.provider([Self.sub("Rent", day: 5, amount: 1000)])
        #expect(provider.monthTotalAnswer() == "You pay 1.000,00 Türk lirası in October 2026.")
    }

    @Test("Payment due today still counts as remaining")
    func monthTotalDueTodayIsRemaining() throws {
        let provider = try Self.provider([
            Self.sub("Rent", day: 5, amount: 1000),
            Self.sub("Gym", day: 12, amount: 200),
        ])
        #expect(provider.monthTotalAnswer()
            == "You pay 1.200,00 Türk lirası in October 2026, 200,00 Türk lirası still to go.")
    }

    // MARK: Sıradaki ödeme

    @Test("Next payment reads the day relative to today", arguments: [
        (12, "today"),
        (13, "tomorrow"),
        (14, "in 2 days"),
        (18, "in 6 days"),
        (19, "on 19 October"),
        (30, "on 30 October"),
    ])
    func nextPaymentDay(day: Int, expected: String) throws {
        let provider = try Self.provider([Self.sub("Rent", day: day, amount: 1000)])
        #expect(provider.nextPaymentAnswer() == "Next: Rent, 1.000,00 Türk lirası, \(expected).")
    }

    @Test("Next payment reaches into the following month")
    func nextPaymentNextMonth() throws {
        // 12 Ekim -> 5 Kasım: 19 + 5 = 24 gün, yani "on 5 November".
        let provider = try Self.provider([Self.sub("Rent", day: 5, amount: 1234.5)])
        #expect(provider.nextPaymentAnswer() == "Next: Rent, 1.234,50 Türk lirası, on 5 November.")
    }

    @Test("Next payment picks the earliest of several")
    func nextPaymentEarliest() throws {
        let provider = try Self.provider([
            Self.sub("Later", day: 25, amount: 10),
            Self.sub("Sooner", day: 13, amount: 99),
        ])
        #expect(provider.nextPaymentAnswer() == "Next: Sooner, 99,00 Türk lirası, tomorrow.")
    }

    @Test("Next payment with nothing stored")
    func nextPaymentNone() throws {
        let provider = try Self.provider([])
        #expect(provider.nextPaymentAnswer() == "No upcoming payments.")
    }

    // MARK: Tutar okunuşu

    @Test("Amounts are spoken in words, never with the lira sign")
    func noLiraSign() throws {
        let provider = try Self.provider([
            Self.sub("Rent", day: 5, amount: 1000),
            Self.sub("Gym", day: 15, amount: 250.50),
        ])
        for answer in [provider.monthTotalAnswer(), provider.nextPaymentAnswer()] {
            #expect(!answer.contains("₺"))
            #expect(answer.contains("Türk lirası"))
        }
    }

    // MARK: Hata

    @Test("Both answers fall back to the fixed sentence when loading fails")
    func failureAnswers() {
        let provider = Self.failing()
        #expect(PaymentSummaryProvider.failureAnswer == "I could not open your payments.")
        #expect(provider.monthTotalAnswer() == PaymentSummaryProvider.failureAnswer)
        #expect(provider.nextPaymentAnswer() == PaymentSummaryProvider.failureAnswer)
    }

    @Test("summary() rethrows the repository error")
    func summaryRethrows() {
        let provider = Self.failing()
        #expect(throws: Failure.self) { try provider.summary() }
    }

    @Test("summary() reflects the clock and stored items")
    func summaryContent() throws {
        let provider = try Self.provider([Self.sub("Rent", day: 15, amount: 100)])
        let summary = try provider.summary()
        #expect(summary.month == YearMonth(year: 2026, month: 10))
        #expect(summary.monthTotal == Money(100))
        #expect(summary.next.first?.daysUntil == 3)
    }
}
