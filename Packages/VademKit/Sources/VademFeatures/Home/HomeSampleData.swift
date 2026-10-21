#if DEBUG
import Foundation
import VademCore

/// Fixed sample data for previews and the UI check (`-ui-sample-data`), with a fixed "today".
///
/// On 12 October 2026 the month covers every chip kind: overdue, today, soon and later,
/// a cardless subscription and an installment.
@MainActor
public enum HomeSampleData {
    /// The launch argument that opens Home on the sample data.
    public static let launchArgument = "-ui-sample-data"

    /// The fixed calendar: Gregorian, UTC.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// The fixed today: 12 October 2026, noon UTC.
    public static var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    }

    /// A new in-memory repository filled with the sample cards, installments and subscriptions.
    public static func makeRepository() -> InMemoryPaymentRepository {
        let repository = InMemoryPaymentRepository()
        // Sabit id'ler: her açılışta aynı sıra ve aynı ekran görüntüsü.
        // Everyday: Eylül 28 ekstresi → 8 Ekim vadesi (gecikmiş).
        let everyday = Card(id: id(1), name: "Everyday card", statementDay: 28, dueDay: 8)!
        // Travel: 2 Ekim ekstresi → 12 Ekim vadesi (bugün).
        let travel = Card(id: id(2), name: "Travel card", statementDay: 2, dueDay: 12)!
        // Shopping: 5 Ekim ekstresi → 15 Ekim vadesi (3 gün sonra).
        let shopping = Card(id: id(3), name: "Shopping card", statementDay: 5, dueDay: 15)!
        let september = YearMonth(year: 2026, month: 9)!
        let july = YearMonth(year: 2026, month: 7)!

        let items: [() throws -> Void] = [
            { try repository.save(everyday) },
            { try repository.save(travel) },
            { try repository.save(shopping) },
            // Eylül ekstresindeki 3. taksit Ekim'de ödenir: "3/12".
            { try repository.save(InstallmentItem(
                id: id(11), title: "Laptop", cardID: everyday.id,
                plan: InstallmentPlan(total: Money(Decimal(4_800_000) / 100), count: 12, firstMonth: july)!
            )!) },
            { try repository.save(SubscriptionItem(
                id: id(21), title: "Gym", cardID: travel.id,
                subscription: Subscription(amount: Money(900), period: .monthly, renewalDay: 1, firstMonth: september)!
            )!) },
            { try repository.save(SubscriptionItem(
                id: id(22), title: "Netflix", cardID: shopping.id,
                subscription: Subscription(
                    amount: Money(Decimal(24_999) / 100), period: .monthly, renewalDay: 3, firstMonth: september
                )!
            )!) },
            // Kartsız abonelik çekim gününde ödenir: 25 Ekim (sonra).
            { try repository.save(SubscriptionItem(
                id: id(23), title: "Rent", cardID: nil,
                subscription: Subscription(amount: Money(25_000), period: .monthly, renewalDay: 25, firstMonth: september)!
            )!) },
        ]
        // Örnek veri geçerli; kayıt hatası programlama hatasıdır.
        for save in items {
            try! save()
        }
        return repository
    }

    /// A view model on ``makeRepository()`` with the fixed ``today`` and ``calendar``.
    public static func makeViewModel() -> HomeViewModel {
        HomeViewModel(repository: makeRepository(), today: today, calendar: calendar)
    }

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
}
#endif
