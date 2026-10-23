import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("WidgetTimelineBuilder")
struct WidgetTimelineBuilderTests {
    // MARK: Yardımcılar

    private struct Failure: Error {}

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

    // Yalnızca kartlar okunabilir; abonelik okuması hata verir (kısmi hata).
    private struct SubscriptionsFailingRepository: PaymentRepository {
        let base = InMemoryPaymentRepository()
        func cards() throws -> [Card] { try base.cards() }
        func save(_ card: Card) throws { try base.save(card) }
        func deleteCard(id: Card.ID) throws { try base.deleteCard(id: id) }
        func installments() throws -> [InstallmentItem] { try base.installments() }
        func save(_ item: InstallmentItem) throws { try base.save(item) }
        func deleteInstallment(id: InstallmentItem.ID) throws { try base.deleteInstallment(id: id) }
        func subscriptions() throws -> [SubscriptionItem] { throw Failure() }
        func save(_ item: SubscriptionItem) throws { try base.save(item) }
        func deleteSubscription(id: SubscriptionItem.ID) throws { try base.deleteSubscription(id: id) }
    }

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static let istanbul = calendar("Europe/Istanbul")
    private static let newYork = calendar("America/New_York")

    private static func date(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    // Her ay `day`. günü ödenen, kartsız aylık abonelik.
    private static func sub(
        _ title: String, day: Int, amount: Decimal, last: YearMonth? = nil
    ) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: title, cardID: nil,
            subscription: Subscription(
                amount: Money(amount), period: .monthly, renewalDay: day,
                firstMonth: YearMonth(year: 2026, month: 1)!, lastMonth: last
            )!
        )!
    }

    private static func repository(_ items: [SubscriptionItem]) throws -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        for item in items { try repository.save(item) }
        return repository
    }

    private static func builder(_ repository: any PaymentRepository, _ calendar: Calendar) -> WidgetTimelineBuilder {
        WidgetTimelineBuilder(repository: repository, calendar: calendar)
    }

    private static func summary(_ entry: WidgetTimelineBuilder.Entry) throws -> PaymentSummary {
        guard case .summary(let summary) = entry.content else {
            throw Failure()
        }
        return summary
    }

    // 10 Mart 2026 12:00 İstanbul; A: 11'i 1000, B: 15'i 500.
    private static var march10: Date { date(istanbul, 2026, 3, 10, hour: 12) }
    private static func marchItems() -> [SubscriptionItem] {
        [sub("A", day: 11, amount: 1000), sub("B", day: 15, amount: 500)]
    }

    // MARK: Girdi tarihleri ve yeniden yükleme

    @Test("Entries are now plus the next three local midnights; reload is the midnight after")
    func entryDates() throws {
        let result = Self.builder(try Self.repository(Self.marchItems()), Self.istanbul).timeline(now: Self.march10)
        #expect(result.entries.map(\.date) == [
            Self.march10,
            Self.date(Self.istanbul, 2026, 3, 11),
            Self.date(Self.istanbul, 2026, 3, 12),
            Self.date(Self.istanbul, 2026, 3, 13),
        ])
        #expect(result.reloadDate == Self.date(Self.istanbul, 2026, 3, 14))
        #expect(WidgetTimelineBuilder.daysAhead == 3)
    }

    @Test("Summary of each entry is computed at that entry's day")
    func summariesAdvanceWithDays() throws {
        let result = Self.builder(try Self.repository(Self.marchItems()), Self.istanbul).timeline(now: Self.march10)
        let summaries = try result.entries.map(Self.summary)
        // Her girdi için elle hesaplanan beklenenler: (kalan, kalan sayı, sıradaki başlık, kalan gün).
        // 10 Mart: A yarın (1), B 5 gün; 11 Mart: A bugün; 12-13 Mart: yalnızca B kalır.
        #expect(summaries.map(\.monthTotal) == Array(repeating: Money(1500), count: 4))
        #expect(summaries.map(\.remaining) == [Money(1500), Money(1500), Money(500), Money(500)])
        #expect(summaries.map(\.remainingCount) == [2, 2, 1, 1])
        #expect(summaries.map { $0.next[0].title } == ["A", "A", "B", "B"])
        #expect(summaries.map { $0.next[0].daysUntil } == [1, 0, 3, 2])
        #expect(summaries.map { $0.next[1].title } == ["B", "B", "A", "A"])
        // 12 Mart'tan A'nın Nisan 11'i: 31 - 12 + 11 = 30 gün; 13 Mart'ta 29.
        #expect(summaries.map { $0.next[1].daysUntil } == [5, 4, 30, 29])
    }

    @Test("A payment due tomorrow reads today at the first midnight")
    func tomorrowBecomesToday() throws {
        let repository = try Self.repository([Self.sub("Rent", day: 11, amount: 1000)])
        let result = Self.builder(repository, Self.istanbul).timeline(now: Self.march10)
        #expect(try Self.summary(result.entries[0]).next.first?.daysUntil == 1)
        #expect(try Self.summary(result.entries[1]).next.first?.daysUntil == 0)
        #expect(try Self.summary(result.entries[1]).remaining == Money(1000))
        #expect(try Self.summary(result.entries[2]).remaining == Money.zero)
    }

    @Test("Now exactly at midnight: first entry is now, then the next three midnights")
    func nowAtMidnight() throws {
        let now = Self.date(Self.istanbul, 2026, 3, 10)
        let result = Self.builder(try Self.repository(Self.marchItems()), Self.istanbul).timeline(now: now)
        #expect(result.entries.map(\.date) == [
            now,
            Self.date(Self.istanbul, 2026, 3, 11),
            Self.date(Self.istanbul, 2026, 3, 12),
            Self.date(Self.istanbul, 2026, 3, 13),
        ])
        #expect(result.reloadDate == Self.date(Self.istanbul, 2026, 3, 14))
    }

    @Test("One second before midnight: second entry is one second later")
    func nowJustBeforeMidnight() throws {
        let now = Self.date(Self.istanbul, 2026, 3, 10, hour: 23, minute: 59, second: 59)
        let result = Self.builder(try Self.repository(Self.marchItems()), Self.istanbul).timeline(now: now)
        #expect(result.entries[1].date == now.addingTimeInterval(1))
        #expect(result.entries.count == 4)
        #expect(result.reloadDate == Self.date(Self.istanbul, 2026, 3, 14))
    }

    @Test("Entry dates are strictly increasing and the first is now")
    func sortedDates() throws {
        let result = Self.builder(try Self.repository(Self.marchItems()), Self.istanbul).timeline(now: Self.march10)
        let dates = result.entries.map(\.date)
        #expect(dates.first == Self.march10)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(result.reloadDate > dates.last!)
    }

    // MARK: Hata, boş veri

    @Test("Repository failure: one unavailable entry at now, retry in one hour")
    func failure() {
        let result = Self.builder(FailingRepository(), Self.istanbul).timeline(now: Self.march10)
        #expect(result.entries == [.init(date: Self.march10, content: .unavailable)])
        #expect(result.reloadDate == Self.march10.addingTimeInterval(3600))
        #expect(WidgetTimelineBuilder.retryInterval == 3600)
    }

    @Test("A failure reading only subscriptions is also unavailable")
    func partialFailure() {
        let result = Self.builder(SubscriptionsFailingRepository(), Self.istanbul).timeline(now: Self.march10)
        #expect(result.entries == [.init(date: Self.march10, content: .unavailable)])
        #expect(result.reloadDate == Self.march10.addingTimeInterval(3600))
    }

    @Test("No data: every entry is empty, reload at the same midnight")
    func emptyData() {
        let result = Self.builder(InMemoryPaymentRepository(), Self.istanbul).timeline(now: Self.march10)
        #expect(result.entries.count == 4)
        #expect(result.entries.allSatisfy { $0.content == .empty })
        #expect(result.entries.map(\.date) == [
            Self.march10,
            Self.date(Self.istanbul, 2026, 3, 11),
            Self.date(Self.istanbul, 2026, 3, 12),
            Self.date(Self.istanbul, 2026, 3, 13),
        ])
        #expect(result.reloadDate == Self.date(Self.istanbul, 2026, 3, 14))
    }

    @Test("Month total not zero but nothing upcoming is still a summary")
    func totalWithoutUpcoming() throws {
        // Abonelik yalnızca Mart'ta, ayın 5'inde: 10 Mart'ta geçmişte, sonrası yok.
        let item = Self.sub("Old", day: 5, amount: 300, last: YearMonth(year: 2026, month: 3)!)
        let result = Self.builder(try Self.repository([item]), Self.istanbul).timeline(now: Self.march10)
        for entry in result.entries {
            let summary = try Self.summary(entry)
            #expect(summary.monthTotal == Money(300))
            #expect(summary.remaining == Money.zero)
            #expect(summary.next.isEmpty)
        }
    }

    @Test("Entries cross into a month with nothing due: empty after the month ends")
    func becomesEmptyWhenMonthChanges() throws {
        // Son gün 31 Mart; abonelik yalnızca Mart. 30 Mart'ta başlayan zaman çizelgesi 1 Nisan'a taşar.
        let item = Self.sub("Old", day: 31, amount: 300, last: YearMonth(year: 2026, month: 3)!)
        let now = Self.date(Self.istanbul, 2026, 3, 30, hour: 12)
        let result = Self.builder(try Self.repository([item]), Self.istanbul).timeline(now: now)
        #expect(try Self.summary(result.entries[0]).monthTotal == Money(300))
        #expect(try Self.summary(result.entries[1]).remaining == Money(300))
        #expect(result.entries[2].content == .empty)   // 1 Nisan
        #expect(result.entries[3].content == .empty)   // 2 Nisan
    }

    // MARK: Yıl / ay geçişi

    @Test("Dec 31 to Jan 1 rollover changes the month and the days left")
    func yearRollover() throws {
        let items = [Self.sub("A", day: 31, amount: 1000), Self.sub("B", day: 2, amount: 500)]
        let now = Self.date(Self.istanbul, 2026, 12, 30, hour: 12)
        let result = Self.builder(try Self.repository(items), Self.istanbul).timeline(now: now)
        #expect(result.entries.map(\.date) == [
            now,
            Self.date(Self.istanbul, 2026, 12, 31),
            Self.date(Self.istanbul, 2027, 1, 1),
            Self.date(Self.istanbul, 2027, 1, 2),
        ])
        #expect(result.reloadDate == Self.date(Self.istanbul, 2027, 1, 3))
        let summaries = try result.entries.map(Self.summary)
        let december = YearMonth(year: 2026, month: 12)!
        let january = YearMonth(year: 2027, month: 1)!
        #expect(summaries.map(\.month) == [december, december, january, january])
        #expect(summaries.map(\.monthTotal) == Array(repeating: Money(1500), count: 4))
        // Aralık: yalnızca A (31'i) kalır; Ocak başında ikisi de (2'si ve 31'i) henüz gelmemiştir.
        #expect(summaries.map(\.remaining) == [Money(1000), Money(1000), Money(1500), Money(1500)])
        #expect(summaries.map(\.remainingCount) == [1, 1, 2, 2])
        #expect(summaries.map { $0.next[0].title } == ["A", "A", "B", "B"])
        #expect(summaries.map { $0.next[0].daysUntil } == [1, 0, 1, 0])
        // 30 Aralık'tan B'nin 2 Ocak'ı: 3 gün; 31 Aralık'tan: 2 gün.
        #expect(summaries[0].next[1].title == "B")
        #expect(summaries[0].next[1].daysUntil == 3)
        #expect(summaries[1].next[1].daysUntil == 2)
    }

    @Test("Leap day: Feb 28 2028 reaches Feb 29 and Mar 1")
    func leapYear() throws {
        let item = Self.sub("A", day: 1, amount: 100)
        let now = Self.date(Self.istanbul, 2028, 2, 28, hour: 12)
        let result = Self.builder(try Self.repository([item]), Self.istanbul).timeline(now: now)
        #expect(result.entries.map(\.date) == [
            now,
            Self.date(Self.istanbul, 2028, 2, 29),
            Self.date(Self.istanbul, 2028, 3, 1),
            Self.date(Self.istanbul, 2028, 3, 2),
        ])
        #expect(result.reloadDate == Self.date(Self.istanbul, 2028, 3, 3))
        // 28 Şubat'tan 1 Mart'a: 2028 Şubat 29 gün, yani 2 gün; 29 Şubat'ta 1; 1 Mart'ta 0.
        let summaries = try result.entries.map(Self.summary)
        #expect(summaries.map { $0.next[0].daysUntil } == [2, 1, 0, 30])
    }

    // MARK: Yaz saati

    @Test("Spring forward (New York, 8 Mar 2026): entries land on local midnights, the day is 23 hours")
    func springForward() throws {
        let now = Self.date(Self.newYork, 2026, 3, 7, hour: 12)
        let items = [Self.sub("A", day: 9, amount: 100)]
        let result = Self.builder(try Self.repository(items), Self.newYork).timeline(now: now)
        let expected = [
            now,
            Self.date(Self.newYork, 2026, 3, 8),
            Self.date(Self.newYork, 2026, 3, 9),
            Self.date(Self.newYork, 2026, 3, 10),
        ]
        #expect(result.entries.map(\.date) == expected)
        #expect(result.reloadDate == Self.date(Self.newYork, 2026, 3, 11))
        // 8 Mart gecesi 23 saat sürer.
        #expect(expected[2].timeIntervalSince(expected[1]) == 23 * 3600)
        // Her girdi gerçekten yerel gece yarısı.
        for date in expected.dropFirst() + [result.reloadDate] {
            let parts = Self.newYork.dateComponents([.hour, .minute, .second], from: date)
            #expect(parts.hour == 0 && parts.minute == 0 && parts.second == 0)
        }
        // Günler: 7 Mart'ta 2, 8'inde 1, 9'unda 0 gün; 10'unda sonraki ay.
        let summaries = try result.entries.map(Self.summary)
        #expect(summaries.map { $0.next[0].daysUntil } == [2, 1, 0, 30])
    }

    @Test("Fall back (New York, 1 Nov 2026): entries land on local midnights, the day is 25 hours")
    func fallBack() throws {
        let now = Self.date(Self.newYork, 2026, 10, 31, hour: 12)
        let items = [Self.sub("A", day: 3, amount: 100)]
        let result = Self.builder(try Self.repository(items), Self.newYork).timeline(now: now)
        let expected = [
            now,
            Self.date(Self.newYork, 2026, 11, 1),
            Self.date(Self.newYork, 2026, 11, 2),
            Self.date(Self.newYork, 2026, 11, 3),
        ]
        #expect(result.entries.map(\.date) == expected)
        #expect(result.reloadDate == Self.date(Self.newYork, 2026, 11, 4))
        // 1 Kasım 25 saat sürer; sabit 24 saat eklenseydi gece yarısı kaçardı.
        #expect(expected[2].timeIntervalSince(expected[1]) == 25 * 3600)
        for date in expected.dropFirst() + [result.reloadDate] {
            let parts = Self.newYork.dateComponents([.hour, .minute, .second], from: date)
            #expect(parts.hour == 0 && parts.minute == 0 && parts.second == 0)
        }
        // 31 Ekim'den 3 Kasım: 3 gün; sonra 2, 1, 0.
        let summaries = try result.entries.map(Self.summary)
        #expect(summaries.map { $0.next[0].daysUntil } == [3, 2, 1, 0])
        #expect(summaries.map(\.month) == [
            YearMonth(year: 2026, month: 10)!, YearMonth(year: 2026, month: 11)!,
            YearMonth(year: 2026, month: 11)!, YearMonth(year: 2026, month: 11)!,
        ])
    }

    @Test("Now on the DST day itself still yields local midnights", arguments: [
        (2026, 3, 8), (2026, 11, 1),
    ])
    func nowOnDstDay(year: Int, month: Int, day: Int) throws {
        let now = Self.date(Self.newYork, year, month, day, hour: 12)
        let result = Self.builder(InMemoryPaymentRepository(), Self.newYork).timeline(now: now)
        #expect(result.entries.count == 4)
        for entry in result.entries.dropFirst() {
            let parts = Self.newYork.dateComponents([.hour, .minute], from: entry.date)
            #expect(parts.hour == 0 && parts.minute == 0)
        }
        let reload = Self.newYork.dateComponents([.hour, .minute, .day], from: result.reloadDate)
        #expect(reload.hour == 0 && reload.minute == 0 && reload.day == day + 4)
    }
}
