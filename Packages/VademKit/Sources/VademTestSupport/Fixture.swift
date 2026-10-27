import Foundation
import Testing
import VademCore

// Kalem ve depo testleri için ortak, geçerli test verisi üreticileri.
// Geçersiz değer üretirlerse sorun testin kurulumundadır, kodda değil.
public enum Fixture {
    public static func month(_ year: Int, _ month: Int) throws -> YearMonth {
        try #require(YearMonth(year: year, month: month))
    }

    public static func card(_ name: String = "Bonus", id: UUID = UUID()) throws -> Card {
        try #require(Card(id: id, name: name, statementDay: 10, dueDay: 20))
    }

    public static func plan(total: Decimal = 1200, count: Int = 3, first: YearMonth? = nil) throws -> InstallmentPlan {
        let firstMonth = try first ?? month(2026, 1)
        return try #require(InstallmentPlan(total: Money(total), count: count, firstMonth: firstMonth))
    }

    public static func subscription(amount: Decimal = 99, period: Subscription.Period = .monthly) throws -> Subscription {
        try #require(Subscription(amount: Money(amount), period: period, renewalDay: 5, firstMonth: month(2026, 1)))
    }

    public static func installment(
        _ title: String = "Telefon",
        id: UUID = UUID(),
        card: Card.ID?,
        paymentDay: Int = 15,
        plan: InstallmentPlan? = nil
    ) throws -> InstallmentItem {
        let value = try plan ?? Fixture.plan()
        // Ödeme günü yalnızca kartsız taksitte verilir; kartlıda karttan gelir.
        return try #require(InstallmentItem(
            id: id, title: title, cardID: card, paymentDay: card == nil ? paymentDay : nil, plan: value
        ))
    }

    public static func subscriptionItem(
        _ title: String = "Müzik",
        id: UUID = UUID(),
        card: Card.ID?,
        subscription: Subscription? = nil
    ) throws -> SubscriptionItem {
        let value = try subscription ?? Fixture.subscription()
        return try #require(SubscriptionItem(id: id, title: title, cardID: card, subscription: value))
    }

    // Sabit, sıralaması belli UUID'ler: hem bayt hem metin karşılaştırmasında 1 < 2 < 3.
    public static func id(_ last: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", last))!
    }
}
