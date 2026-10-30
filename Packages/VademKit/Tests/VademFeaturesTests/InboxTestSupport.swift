import Foundation
import Testing
import VademCore
import VademFeatures

// Gelen kutusu testlerinin ortak yardımcıları: sabit takvim, örnek ödemeler, hata veren depo.
@MainActor
enum InboxTestSupport {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Kasım 2026 için bir içgörü verir: Ekim 5000, Kasım 6500 (+%30). Başka içgörü yok.
    static func paymentsWithOneInsight() throws -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        func sub(_ title: String, _ amount: Decimal, from month: Int) throws -> SubscriptionItem {
            let value = try #require(Subscription(
                amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: YearMonth(year: 2026, month: month)!
            ))
            return try #require(SubscriptionItem(id: UUID(), title: title, cardID: nil, subscription: value))
        }
        try repository.save(sub("Rent", 5000, from: 1))
        try repository.save(sub("Gym", 1500, from: 11))
        return repository
    }

    static let november = YearMonth(year: 2026, month: 11)!

    /// Her çağrıda hata veren gelen kutusu.
    final class FailingInbox: InboxRepository {
        struct Failure: Error {}
        func entries() throws -> [InboxEntry] { throw Failure() }
        func add(_ entry: InboxEntry) throws -> Bool { throw Failure() }
        func markAllRead() throws { throw Failure() }
        func delete(id: InboxEntry.ID) throws { throw Failure() }
        func unreadCount() throws -> Int { throw Failure() }
    }
}
