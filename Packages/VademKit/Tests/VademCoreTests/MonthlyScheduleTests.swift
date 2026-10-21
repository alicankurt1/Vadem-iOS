import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("MonthlySchedule")
struct MonthlyScheduleTests {
    // MARK: Yardımcılar

    private func ym(_ year: Int, _ month: Int) throws -> YearMonth {
        try Fixture.month(year, month)
    }

    private func card(statement: Int, due: Int, id: UUID = UUID()) throws -> Card {
        try #require(Card(id: id, name: "Kart", statementDay: statement, dueDay: due))
    }

    private func installment(
        _ title: String = "Telefon", id: UUID = UUID(), card: Card, total: Decimal = 300,
        count: Int = 3, first: YearMonth
    ) throws -> InstallmentItem {
        let plan = try #require(InstallmentPlan(total: Money(total), count: count, firstMonth: first))
        return try #require(InstallmentItem(id: id, title: title, cardID: card.id, plan: plan))
    }

    private func sub(
        _ title: String = "Müzik", id: UUID = UUID(), card: Card?, amount: Decimal = 50,
        period: Subscription.Period = .monthly, day: Int, first: YearMonth, last: YearMonth? = nil
    ) throws -> SubscriptionItem {
        let value = try #require(Subscription(
            amount: Money(amount), period: period, renewalDay: day, firstMonth: first, lastMonth: last
        ))
        return try #require(SubscriptionItem(id: id, title: title, cardID: card?.id, subscription: value))
    }

    private func schedule(
        _ month: YearMonth, cards: [Card] = [], installments: [InstallmentItem] = [],
        subscriptions: [SubscriptionItem] = []
    ) -> MonthlySchedule {
        MonthlySchedule(month: month, cards: cards, installments: installments, subscriptions: subscriptions)
    }

    // MARK: Boş girdi

    @Test("Empty input gives an empty schedule with zero total")
    func empty() throws {
        let result = schedule(try ym(2026, 3))
        #expect(result.entries.isEmpty)
        #expect(result.total == .zero)
        #expect(result.total(for: UUID()) == .zero)
    }

    // MARK: Taksit

    struct InstallmentCase: Sendable, CustomTestStringConvertible {
        let statement: Int
        let due: Int
        let firstYear: Int
        let firstMonth: Int
        let queryYear: Int
        let queryMonth: Int
        let expectedNumber: Int?  // nil = beklenen giriş yok
        let expectedDay: Int
        var testDescription: String {
            "stmt \(statement) due \(due) first \(firstYear)-\(firstMonth) query \(queryYear)-\(queryMonth)"
        }
    }

    @Test("Installment lands in the due-date month", arguments: [
        // vade ekstre gününden sonra: aynı ay
        InstallmentCase(statement: 10, due: 20, firstYear: 2026, firstMonth: 1, queryYear: 2026, queryMonth: 2,
                        expectedNumber: 2, expectedDay: 20),
        InstallmentCase(statement: 10, due: 20, firstYear: 2026, firstMonth: 1, queryYear: 2026, queryMonth: 1,
                        expectedNumber: 1, expectedDay: 20),
        // vade ekstre gününden önce: sonraki ay
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 3, queryYear: 2026, queryMonth: 3,
                        expectedNumber: nil, expectedDay: 0),
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 3, queryYear: 2026, queryMonth: 4,
                        expectedNumber: 1, expectedDay: 5),
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 3, queryYear: 2026, queryMonth: 6,
                        expectedNumber: 3, expectedDay: 5),
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 3, queryYear: 2026, queryMonth: 7,
                        expectedNumber: nil, expectedDay: 0),
        // vade ekstre gününe eşit: sonraki ay
        InstallmentCase(statement: 15, due: 15, firstYear: 2026, firstMonth: 3, queryYear: 2026, queryMonth: 3,
                        expectedNumber: nil, expectedDay: 0),
        InstallmentCase(statement: 15, due: 15, firstYear: 2026, firstMonth: 3, queryYear: 2026, queryMonth: 4,
                        expectedNumber: 1, expectedDay: 15),
        // Aralık ekstresi Ocak'a (yıl değişimi)
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 11, queryYear: 2026, queryMonth: 12,
                        expectedNumber: 1, expectedDay: 5),
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 11, queryYear: 2027, queryMonth: 1,
                        expectedNumber: 2, expectedDay: 5),
        InstallmentCase(statement: 25, due: 5, firstYear: 2026, firstMonth: 11, queryYear: 2026, queryMonth: 11,
                        expectedNumber: nil, expectedDay: 0),
        // ay sonu kırpma: Şubat'ta vade 31 -> 28 (2027) ve 29 (2028, artık yıl)
        InstallmentCase(statement: 10, due: 31, firstYear: 2027, firstMonth: 2, queryYear: 2027, queryMonth: 2,
                        expectedNumber: 1, expectedDay: 28),
        InstallmentCase(statement: 10, due: 31, firstYear: 2028, firstMonth: 2, queryYear: 2028, queryMonth: 2,
                        expectedNumber: 1, expectedDay: 29),
    ])
    func installmentInclusion(_ c: InstallmentCase) throws {
        let kart = try card(statement: c.statement, due: c.due)
        let item = try installment(card: kart, first: try ym(c.firstYear, c.firstMonth))
        let query = try ym(c.queryYear, c.queryMonth)
        let result = schedule(query, cards: [kart], installments: [item])

        if let number = c.expectedNumber {
            #expect(result.entries.count == 1)
            let entry = try #require(result.entries.first)
            #expect(entry.kind == .installment(number: number, count: 3))
            #expect(entry.dueDate.month == query)
            #expect(entry.dueDate.day == c.expectedDay)
            #expect(entry.itemID == item.id)
            #expect(entry.cardID == kart.id)
            #expect(entry.amount == Money(100))
        } else {
            #expect(result.entries.isEmpty)
            #expect(result.total == .zero)
        }
    }

    // MARK: Kartlı abonelik

    struct CardSubCase: Sendable, CustomTestStringConvertible {
        let statement: Int
        let due: Int
        let renewal: Int
        let queryYear: Int
        let queryMonth: Int
        let expectedDay: Int
        var expectedCount = 1
        var testDescription: String {
            "stmt \(statement) due \(due) renewal \(renewal) query \(queryYear)-\(queryMonth)"
        }
    }

    // Abonelik 2026-01'den başlar, aylık, 50.
    @Test("Subscription on a card lands in the right due month", arguments: [
        // ekstre gününden önce: aynı ekstre, aynı ay vade
        CardSubCase(statement: 10, due: 20, renewal: 5, queryYear: 2026, queryMonth: 3, expectedDay: 20),
        // tam ekstre günü: o ekstreye dahil
        CardSubCase(statement: 10, due: 20, renewal: 10, queryYear: 2026, queryMonth: 3, expectedDay: 20),
        // ekstre gününden sonra: sonraki ekstre, sonraki ay vade
        CardSubCase(statement: 10, due: 20, renewal: 11, queryYear: 2026, queryMonth: 4, expectedDay: 20),
        // 20 Şubat çekimi (ekstre 25) Mart ekstresine girmez, 5 Mart'ta ödenir; Mart'ta bu giriş görünür
        CardSubCase(statement: 25, due: 5, renewal: 20, queryYear: 2026, queryMonth: 3, expectedDay: 5),
        // çekim M-2'de, vade M'de
        CardSubCase(statement: 25, due: 5, renewal: 28, queryYear: 2026, queryMonth: 5, expectedDay: 5),
        // ay sonu kırpma: 31 -> Şubat 28, ekstre günü de 28'e kırpılır, dahil; vade Mart 15
        CardSubCase(statement: 31, due: 15, renewal: 31, queryYear: 2026, queryMonth: 3, expectedDay: 15),
        // artık yıl: Şubat 2028, çekim 29, ekstre 29, vade Mart 10
        CardSubCase(statement: 29, due: 10, renewal: 31, queryYear: 2028, queryMonth: 3, expectedDay: 10,
                   expectedCount: 2),  // Ocak 31 (>29) ve Şubat 29 (=29) çekimleri aynı Şubat ekstresinde
        // yıl değişimi: Aralık çekimi Ocak'ta ödenir
        CardSubCase(statement: 25, due: 5, renewal: 20, queryYear: 2027, queryMonth: 1, expectedDay: 5),
    ])
    func cardSubscriptionInclusion(_ c: CardSubCase) throws {
        let kart = try card(statement: c.statement, due: c.due)
        let item = try sub(card: kart, day: c.renewal, first: try ym(2026, 1))
        let query = try ym(c.queryYear, c.queryMonth)
        let result = schedule(query, cards: [kart], subscriptions: [item])

        let day = c.expectedDay
        #expect(result.entries.count == c.expectedCount)
        for entry in result.entries {
            #expect(entry.kind == .subscription)
            #expect(entry.dueDate.month == query)
            #expect(entry.dueDate.day == day)
            #expect(entry.amount == Money(50))
            #expect(entry.cardID == kart.id)
        }
        #expect(result.total == Money(Decimal(50 * c.expectedCount)))
    }

    @Test("A charge due next month is absent from the charge month and present next month")
    func chargeDueNextMonth() throws {
        // Kart: ekstre 25, vade 5. 20 Mart çekimi 5 Nisan'da ödenir.
        let kart = try card(statement: 25, due: 5)
        let item = try sub(card: kart, day: 20, first: try ym(2026, 3), last: try ym(2026, 3))
        #expect(schedule(try ym(2026, 3), cards: [kart], subscriptions: [item]).entries.isEmpty)
        let april = schedule(try ym(2026, 4), cards: [kart], subscriptions: [item])
        #expect(april.entries.count == 1)
        #expect(april.total == Money(50))
    }

    @Test("Charge after statement day is not due in the charge month")
    func lateChargeNotInChargeMonth() throws {
        // Ekstre 10, vade 20; 11 Mart çekimi Nisan ekstresinde, 20 Nisan'da ödenir.
        let kart = try card(statement: 10, due: 20)
        let item = try sub(card: kart, day: 11, first: try ym(2026, 3), last: try ym(2026, 3))
        #expect(schedule(try ym(2026, 3), cards: [kart], subscriptions: [item]).entries.isEmpty)
        #expect(schedule(try ym(2026, 4), cards: [kart], subscriptions: [item]).entries.count == 1)
        #expect(schedule(try ym(2026, 5), cards: [kart], subscriptions: [item]).entries.isEmpty)
    }

    @Test("Each monthly card subscription appears exactly once per month")
    func monthlyOncePerMonth() throws {
        let kart = try card(statement: 25, due: 5)
        let item = try sub(card: kart, day: 28, first: try ym(2026, 1))
        // Şubat'ta giriş yok (Aralık 2025 çekimi yok); Mart'tan itibaren her ay tam bir giriş var.
        #expect(schedule(try ym(2026, 2), cards: [kart], subscriptions: [item]).entries.isEmpty)
        for month in 3...12 {
            let result = schedule(try ym(2026, month), cards: [kart], subscriptions: [item])
            #expect(result.entries.count == 1, "month \(month)")
        }
    }

    // MARK: Kartsız abonelik

    @Test("Subscription without a card is due on the charge date", arguments: [
        (2026, 3, 15, 15), (2026, 2, 31, 28), (2028, 2, 31, 29), (2026, 4, 31, 30),
    ])
    func cardlessSubscription(year: Int, month: Int, renewal: Int, expectedDay: Int) throws {
        let item = try sub(card: nil, day: renewal, first: try ym(2026, 1))
        let query = try ym(year, month)
        let result = schedule(query, subscriptions: [item])
        let entry = try #require(result.entries.first)
        #expect(result.entries.count == 1)
        #expect(entry.dueDate.month == query)
        #expect(entry.dueDate.day == expectedDay)
        #expect(entry.cardID == nil)
        #expect(entry.kind == .subscription)
    }

    @Test("Yearly subscription appears only in its month")
    func yearly() throws {
        let item = try sub(card: nil, period: .yearly, day: 15, first: try ym(2026, 3))
        #expect(schedule(try ym(2026, 3), subscriptions: [item]).entries.count == 1)
        #expect(schedule(try ym(2026, 4), subscriptions: [item]).entries.isEmpty)
        #expect(schedule(try ym(2027, 3), subscriptions: [item]).entries.count == 1)
        #expect(schedule(try ym(2027, 2), subscriptions: [item]).entries.isEmpty)
        #expect(schedule(try ym(2026, 2), subscriptions: [item]).entries.isEmpty)
    }

    @Test("Cancelled cardless subscription stops after lastMonth")
    func cancelledCardless() throws {
        let item = try sub(card: nil, day: 15, first: try ym(2026, 1), last: try ym(2026, 3))
        #expect(schedule(try ym(2026, 3), subscriptions: [item]).entries.count == 1)
        #expect(schedule(try ym(2026, 4), subscriptions: [item]).entries.isEmpty)
        #expect(schedule(try ym(2026, 1), subscriptions: [item]).entries.count == 1)
        #expect(schedule(try ym(2025, 12), subscriptions: [item]).entries.isEmpty)
    }

    @Test("Last charge on a card is still paid after lastMonth, then stops")
    func cancelledOnCard() throws {
        // Ekstre 10, vade 20; son çekim 15 Mart -> Nisan ekstresi -> 20 Nisan.
        let kart = try card(statement: 10, due: 20)
        let item = try sub(card: kart, day: 15, first: try ym(2026, 1), last: try ym(2026, 3))
        #expect(schedule(try ym(2026, 4), cards: [kart], subscriptions: [item]).entries.count == 1)
        #expect(schedule(try ym(2026, 5), cards: [kart], subscriptions: [item]).entries.isEmpty)
    }

    // MARK: Bilinmeyen kart

    @Test("Items with an unknown card are skipped")
    func unknownCard() throws {
        let known = try card(statement: 10, due: 20)
        let ghost = try card(statement: 10, due: 20)
        let query = try ym(2026, 2)
        let result = schedule(
            query, cards: [known],
            installments: [try installment(card: ghost, first: try ym(2026, 1))],
            subscriptions: [try sub(card: ghost, day: 5, first: try ym(2026, 1))]
        )
        #expect(result.entries.isEmpty)
        #expect(result.total == .zero)
    }

    // MARK: Sıralama ve toplam

    @Test("Orders by due day, then title case-insensitively, then id")
    func ordering() throws {
        let kart = try card(statement: 10, due: 20)
        let month = try ym(2026, 3)
        let items = [
            try sub("cherry", id: Fixture.id(1), card: nil, day: 5, first: try ym(2026, 1)),
            try sub("banana", id: Fixture.id(2), card: nil, day: 5, first: try ym(2026, 1)),
            try sub("Apple", id: Fixture.id(3), card: nil, day: 5, first: try ym(2026, 1)),
            try sub("Zeta", id: Fixture.id(4), card: nil, day: 2, first: try ym(2026, 1)),
            // Aynı başlık, id belirler
            try sub("same", id: Fixture.id(6), card: nil, day: 5, first: try ym(2026, 1)),
            try sub("SAME", id: Fixture.id(5), card: nil, day: 5, first: try ym(2026, 1)),
        ]
        let inst = try installment("Telefon", id: Fixture.id(7), card: kart, first: try ym(2026, 3))
        let result = schedule(month, cards: [kart], installments: [inst], subscriptions: items)
        #expect(result.entries.map(\.title) == ["Zeta", "Apple", "banana", "cherry", "SAME", "same", "Telefon"])
        #expect(result.entries.map(\.dueDate.day) == [2, 5, 5, 5, 5, 5, 20])
    }

    @Test("Order does not depend on input order")
    func inputOrderIndependent() throws {
        let items = [
            try sub("b", id: Fixture.id(1), card: nil, day: 5, first: try ym(2026, 1)),
            try sub("a", id: Fixture.id(2), card: nil, day: 5, first: try ym(2026, 1)),
            try sub("c", id: Fixture.id(3), card: nil, day: 1, first: try ym(2026, 1)),
        ]
        let month = try ym(2026, 3)
        let forward = schedule(month, subscriptions: items).entries.map(\.itemID)
        let backward = schedule(month, subscriptions: items.reversed()).entries.map(\.itemID)
        #expect(forward == backward)
        #expect(forward == [Fixture.id(3), Fixture.id(2), Fixture.id(1)])
    }

    @Test("Total is the exact Decimal sum and total(for:) filters by card")
    func totals() throws {
        let a = try card(statement: 10, due: 20)
        let b = try card(statement: 10, due: 20)
        let month = try ym(2026, 3)
        let result = schedule(
            month, cards: [a, b],
            subscriptions: [
                try sub("x", card: a, amount: Decimal(string: "0.1")!, day: 5, first: try ym(2026, 1)),
                try sub("y", card: a, amount: Decimal(string: "0.2")!, day: 5, first: try ym(2026, 1)),
                try sub("z", card: b, amount: Decimal(string: "10.05")!, day: 5, first: try ym(2026, 1)),
                try sub("w", card: nil, amount: Decimal(string: "1.01")!, day: 5, first: try ym(2026, 1)),
            ]
        )
        #expect(result.total == Money(Decimal(string: "11.36")!))
        #expect(result.total(for: a.id) == Money(Decimal(string: "0.3")!))
        #expect(result.total(for: b.id) == Money(Decimal(string: "10.05")!))
        #expect(result.total(for: UUID()) == .zero)
        #expect(result.total == result.entries.reduce(Money.zero) { $0 + $1.amount })
    }

    @Test("Installment and subscription entries are combined with their amounts")
    func combined() throws {
        let kart = try card(statement: 10, due: 20)
        let month = try ym(2026, 2)
        let inst = try installment(card: kart, total: 300, count: 3, first: try ym(2026, 1))
        let item = try sub(card: kart, amount: Decimal(string: "49.9")!, day: 3, first: try ym(2026, 1))
        let result = schedule(month, cards: [kart], installments: [inst], subscriptions: [item])
        #expect(result.entries.count == 2)
        #expect(result.total == Money(Decimal(string: "149.9")!))
        #expect(result.total(for: kart.id) == result.total)
        #expect(result.month == month)
    }

    @Test("Extreme months do not crash and give the expected entries")
    func extremes() throws {
        let kart = try card(statement: 10, due: 5)
        let last = try ym(9999, 12)
        let late = try sub(card: kart, day: 31, first: try ym(9999, 1))
        // Vadesi 10000. yıla düşen taksit temsil edilemez, atlanır.
        let inst = try installment(card: kart, total: 100, count: 1, first: last)
        let result = schedule(last, cards: [kart], installments: [inst], subscriptions: [late])
        // Yalnızca Ekim çekimi (31 > 10, Kasım ekstresi) 5 Aralık 9999'da ödenir.
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.kind == .subscription)
        #expect(result.entries.first?.dueDate.month == last)
        #expect(result.entries.first?.dueDate.day == 5)
        #expect(result.total == Money(50))

        // 0001-01 çekimi (5 <= 10) Ocak ekstresinde, 5 Şubat'ta ödenir.
        let early = try sub(card: kart, day: 5, first: try ym(1, 1))
        #expect(schedule(try ym(1, 1), cards: [kart], subscriptions: [early]).entries.isEmpty)
        let feb = schedule(try ym(1, 2), cards: [kart], subscriptions: [early])
        #expect(feb.entries.count == 1)
        #expect(feb.entries.first?.dueDate.day == 5)
    }

    @Test("Yearly subscription on a card is due in the month after a late charge")
    func yearlyOnCard() throws {
        // Ekstre 10, vade 20; 15 Mart çekimi Nisan ekstresinde, 20 Nisan'da ödenir.
        let kart = try card(statement: 10, due: 20)
        let item = try sub(card: kart, period: .yearly, day: 15, first: try ym(2026, 3))
        for (year, month, count) in [(2026, 3, 0), (2026, 4, 1), (2026, 5, 0), (2027, 3, 0), (2027, 4, 1), (2026, 12, 0)] {
            let result = schedule(try ym(year, month), cards: [kart], subscriptions: [item])
            #expect(result.entries.count == count, "\(year)-\(month)")
        }
        let entry = try #require(schedule(try ym(2026, 4), cards: [kart], subscriptions: [item]).entries.first)
        #expect(entry.dueDate.day == 20)
        #expect(entry.amount == Money(50))
    }
}
