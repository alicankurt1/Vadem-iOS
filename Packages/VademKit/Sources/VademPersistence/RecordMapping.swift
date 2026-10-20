import Foundation
import VademCore

/// Errors raised when stored data cannot be turned back into `VademCore` values.
public enum PersistenceError: Error, Sendable, Hashable {
    /// A stored record breaks a `VademCore` rule (e.g. an empty name or an unreadable amount).
    /// `entity` is the record type, `id` the record's id.
    case invalidRecord(entity: String, id: UUID)
}

// Kayıt ↔ değer tipi eşlemesi. Okurken VademCore'un failable init'leri kullanılır;
// kurala uymayan saklı veri çökme yerine `PersistenceError.invalidRecord` fırlatır.

extension CardRecord {
    convenience init(_ card: Card) {
        self.init(id: card.id, name: card.name, statementDay: card.statementDay, dueDay: card.dueDay)
    }

    func update(from card: Card) {
        name = card.name
        statementDay = card.statementDay
        dueDay = card.dueDay
    }

    func value() throws -> Card {
        guard let card = Card(id: id, name: name, statementDay: statementDay, dueDay: dueDay) else {
            throw PersistenceError.invalidRecord(entity: "CardRecord", id: id)
        }
        return card
    }
}

extension InstallmentRecord {
    convenience init(_ item: InstallmentItem) {
        self.init(
            id: item.id, title: item.title, cardID: item.cardID, total: MoneyText.encode(item.plan.total),
            count: item.plan.count, firstYear: item.plan.firstMonth.year, firstMonth: item.plan.firstMonth.month
        )
    }

    func update(from item: InstallmentItem) {
        title = item.title
        cardID = item.cardID
        total = MoneyText.encode(item.plan.total)
        count = item.plan.count
        firstYear = item.plan.firstMonth.year
        firstMonth = item.plan.firstMonth.month
    }

    func value() throws -> InstallmentItem {
        guard let total = MoneyText.decode(total),
              let first = YearMonth(year: firstYear, month: firstMonth),
              let plan = InstallmentPlan(total: total, count: count, firstMonth: first),
              let item = InstallmentItem(id: id, title: title, cardID: cardID, plan: plan) else {
            throw PersistenceError.invalidRecord(entity: "InstallmentRecord", id: id)
        }
        return item
    }
}

extension SubscriptionRecord {
    convenience init(_ item: SubscriptionItem) {
        let subscription = item.subscription
        self.init(
            id: item.id, title: item.title, cardID: item.cardID, amount: MoneyText.encode(subscription.amount),
            period: subscription.period.rawValue, renewalDay: subscription.renewalDay,
            firstYear: subscription.firstMonth.year, firstMonth: subscription.firstMonth.month,
            lastYear: subscription.lastMonth?.year, lastMonth: subscription.lastMonth?.month
        )
    }

    func update(from item: SubscriptionItem) {
        let subscription = item.subscription
        title = item.title
        cardID = item.cardID
        amount = MoneyText.encode(subscription.amount)
        period = subscription.period.rawValue
        renewalDay = subscription.renewalDay
        firstYear = subscription.firstMonth.year
        firstMonth = subscription.firstMonth.month
        lastYear = subscription.lastMonth?.year
        lastMonth = subscription.lastMonth?.month
    }

    func value() throws -> SubscriptionItem {
        guard let amount = MoneyText.decode(amount),
              let period = Subscription.Period(rawValue: period),
              let first = YearMonth(year: firstYear, month: firstMonth),
              let last = storedLastMonth(),
              let subscription = Subscription(
                  amount: amount, period: period, renewalDay: renewalDay, firstMonth: first, lastMonth: last
              ),
              let item = SubscriptionItem(id: id, title: title, cardID: cardID, subscription: subscription) else {
            throw PersistenceError.invalidRecord(entity: "SubscriptionRecord", id: id)
        }
        return item
    }

    // Dış Optional "okunabildi mi", iç Optional "son ay var mı" demek.
    // Yıl ve ay ikisi de boş → aktif abonelik; yalnızca biri doluysa veya ay geçersizse → nil.
    private func storedLastMonth() -> YearMonth?? {
        switch (lastYear, lastMonth) {
        case (nil, nil):
            return .some(nil)
        case let (year?, month?):
            return YearMonth(year: year, month: month).map { .some($0) }
        default:
            return nil
        }
    }
}

// Tutar, yerel ayardan bağımsız tam ondalık metin olarak saklanır ("1234567.89").
// Okurken metin, yazdığımız biçimin aynısı olmalı; "12abc" gibi kısmen okunabilen
// ya da "1.005" gibi yuvarlanacak değerler sessizce kabul edilmez.
enum MoneyText {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func encode(_ money: Money) -> String {
        NSDecimalNumber(decimal: money.amount).description(withLocale: posixLocale)
    }

    static func decode(_ text: String) -> Money? {
        guard let value = Decimal(string: text, locale: posixLocale), !value.isNaN else { return nil }
        let money = Money(value)
        return encode(money) == text ? money : nil
    }
}
