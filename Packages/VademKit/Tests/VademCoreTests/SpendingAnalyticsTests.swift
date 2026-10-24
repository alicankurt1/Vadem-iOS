import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("SpendingAnalytics")
struct SpendingAnalyticsTests {
    // MARK: Yardımcılar

    private func ym(_ year: Int, _ month: Int) throws -> YearMonth {
        try Fixture.month(year, month)
    }

    // Ekstre 10, vade 20: taksit ekstre ayının içinde (aynı ay) ödenir.
    private func sameMonthCard(_ name: String = "Bonus", id: UUID = UUID()) throws -> Card {
        try Fixture.card(name, id: id)
    }

    // Ekstre 25, vade 5: vade sonraki aya düşer.
    private func nextMonthCard(_ name: String = "Gece", id: UUID = UUID()) throws -> Card {
        try #require(Card(id: id, name: name, statementDay: 25, dueDay: 5))
    }

    private func installment(
        card: Card, total: Decimal, count: Int, first: YearMonth, title: String = "Telefon"
    ) throws -> InstallmentItem {
        try Fixture.installment(title, card: card.id, plan: Fixture.plan(total: total, count: count, first: first))
    }

    private func sub(
        card: Card?, amount: Decimal, first: YearMonth, last: YearMonth? = nil,
        period: Subscription.Period = .monthly, title: String = "Müzik"
    ) throws -> SubscriptionItem {
        let value = try #require(Subscription(
            amount: Money(amount), period: period, renewalDay: 5, firstMonth: first, lastMonth: last
        ))
        return try Fixture.subscriptionItem(title, card: card?.id, subscription: value)
    }

    private func analytics(
        cards: [Card] = [], installments: [InstallmentItem] = [], subscriptions: [SubscriptionItem] = []
    ) -> SpendingAnalytics {
        SpendingAnalytics(cards: cards, installments: installments, subscriptions: subscriptions)
    }

    // MARK: monthlyTotals

    @Test("Empty input gives zero totals for each month")
    func emptyTotals() throws {
        let start = try ym(2026, 1)
        let totals = analytics().monthlyTotals(from: start, count: 3)
        #expect(totals.count == 3)
        #expect(totals.map(\.month) == [start, try ym(2026, 2), try ym(2026, 3)])
        for total in totals {
            #expect(total.installments == .zero)
            #expect(total.subscriptions == .zero)
            #expect(total.total == .zero)
        }
    }

    @Test("Non-positive count returns an empty array", arguments: [0, -1, -100])
    func nonPositiveCount(count: Int) throws {
        let card = try sameMonthCard()
        let sut = analytics(cards: [card], installments: [try installment(card: card, total: 300, count: 3, first: try ym(2026, 1))])
        #expect(sut.monthlyTotals(from: try ym(2026, 1), count: count).isEmpty)
    }

    @Test("Months are consecutive from start across a year boundary")
    func consecutiveMonths() throws {
        let totals = analytics().monthlyTotals(from: try ym(2026, 11), count: 4)
        #expect(totals.map(\.month) == [try ym(2026, 11), try ym(2026, 12), try ym(2027, 1), try ym(2027, 2)])
    }

    @Test("Totals split into installments and subscriptions with hand-computed values")
    func splitValues() throws {
        let card = try sameMonthCard()
        // 1200 / 3 = 400 (Oca, Şub, Mar); abonelik 99 her ay.
        let sut = analytics(
            cards: [card],
            installments: [try installment(card: card, total: 1200, count: 3, first: try ym(2026, 1))],
            subscriptions: [try sub(card: card, amount: 99, first: try ym(2026, 1))]
        )
        let totals = sut.monthlyTotals(from: try ym(2026, 1), count: 4)
        #expect(totals.map(\.installments) == [Money(400), Money(400), Money(400), .zero])
        #expect(totals.map(\.subscriptions) == [Money(99), Money(99), Money(99), Money(99)])
        #expect(totals.map(\.total) == [Money(499), Money(499), Money(499), Money(99)])
    }

    @Test("Totals equal MonthlySchedule total and parts sum exactly, even with uneven splits")
    func matchesMonthlySchedule() throws {
        let bonus = try sameMonthCard("Bonus")
        let night = try nextMonthCard("Gece")
        let cards = [bonus, night]
        let installments = [
            try installment(card: bonus, total: 1000, count: 3, first: try ym(2026, 1), title: "A"),  // 333.33 / 333.33 / 333.34
            try installment(card: night, total: 100.01, count: 7, first: try ym(2026, 2), title: "B"),
        ]
        let subscriptions = [
            try sub(card: bonus, amount: 9.99, first: try ym(2026, 1), title: "C"),
            try sub(card: nil, amount: 120.50, first: try ym(2026, 3), period: .yearly, title: "D"),
            try sub(card: night, amount: 33.33, first: try ym(2026, 2), last: try ym(2026, 6), title: "E"),
        ]
        let sut = analytics(cards: cards, installments: installments, subscriptions: subscriptions)
        let totals = sut.monthlyTotals(from: try ym(2025, 12), count: 16)
        #expect(totals.count == 16)
        for item in totals {
            let schedule = MonthlySchedule(month: item.month, cards: cards, installments: installments, subscriptions: subscriptions)
            #expect(item.total == schedule.total, "month \(item.month)")
            #expect(item.installments + item.subscriptions == item.total, "month \(item.month)")
        }
    }

    @Test("Items with an unknown card are skipped like in MonthlySchedule")
    func unknownCardSkippedInTotals() throws {
        let known = try sameMonthCard()
        let stranger = try sameMonthCard("Yabancı")
        let sut = analytics(
            cards: [known],
            installments: [try installment(card: stranger, total: 300, count: 3, first: try ym(2026, 1))],
            subscriptions: [try sub(card: stranger, amount: 50, first: try ym(2026, 1))]
        )
        let totals = sut.monthlyTotals(from: try ym(2026, 1), count: 3)
        #expect(totals.allSatisfy { $0.total == .zero && $0.installments == .zero && $0.subscriptions == .zero })
    }

    @Test("Range running past the last supported month is cut instead of trapping")
    func rangeClampedAtSupportedEnd() throws {
        let start = try ym(9999, 11)
        let totals = analytics().monthlyTotals(from: start, count: 10)
        #expect(totals.map(\.month) == [start, try ym(9999, 12)])
    }

    // MARK: cardBreakdown

    @Test("Empty input gives an empty breakdown")
    func emptyBreakdown() throws {
        #expect(analytics().cardBreakdown(in: try ym(2026, 1)).isEmpty)
        let card = try sameMonthCard()
        #expect(analytics(cards: [card]).cardBreakdown(in: try ym(2026, 1)).isEmpty)
    }

    @Test("Cards are ordered largest first and shares sum to the month total")
    func largestFirstAndSums() throws {
        let small = try sameMonthCard("Küçük")
        let big = try sameMonthCard("Büyük")
        let mid = try sameMonthCard("Orta")
        let month = try ym(2026, 1)
        let installments = [
            try installment(card: small, total: 100, count: 1, first: month),
            try installment(card: big, total: 900, count: 1, first: month),
            try installment(card: mid, total: 500, count: 1, first: month),
        ]
        let subscriptions = [try sub(card: nil, amount: 30, first: month)]
        let cards = [small, big, mid]
        let sut = analytics(cards: cards, installments: installments, subscriptions: subscriptions)
        let shares = sut.cardBreakdown(in: month)
        #expect(shares.map { $0.card?.name } == ["Büyük", "Orta", "Küçük", nil].map { $0 })
        // noCard (30) en küçük olduğu için sonda.
        #expect(shares.map(\.total) == [Money(900), Money(500), Money(100), Money(30)])
        let schedule = MonthlySchedule(month: month, cards: cards, installments: installments, subscriptions: subscriptions)
        #expect(shares.reduce(Money.zero) { $0 + $1.total } == schedule.total)
    }

    @Test("Payments without a card form exactly one noCard share")
    func singleNoCardShare() throws {
        let month = try ym(2026, 1)
        let sut = analytics(subscriptions: [
            try sub(card: nil, amount: 40, first: month, title: "A"),
            try sub(card: nil, amount: 2.5, first: month, title: "B"),
        ])
        let shares = sut.cardBreakdown(in: month)
        #expect(shares.count == 1)
        #expect(shares.first?.isNoCard == true)
        #expect(shares.first?.card == nil)
        #expect(shares.first?.total == Money(42.5))
    }

    @Test("A card with nothing due in the month is left out; isNoCard is false for cards")
    func idleCardOmitted() throws {
        let busy = try sameMonthCard("Meşgul")
        let idle = try sameMonthCard("Boş")
        let month = try ym(2026, 1)
        let sut = analytics(cards: [busy, idle], installments: [try installment(card: busy, total: 100, count: 2, first: month)])
        let shares = sut.cardBreakdown(in: month)
        #expect(shares.count == 1)
        #expect(shares[0].card == busy)
        #expect(shares[0].isNoCard == false)
        #expect(shares[0].total == Money(50))
    }

    @Test("Breakdown follows the due-date month rule (ADR-0002)")
    func dueDateRule() throws {
        let night = try nextMonthCard()  // ekstre 25, vade 5 → ilk taksit Nisan'da
        let sut = analytics(cards: [night], installments: [try installment(card: night, total: 300, count: 3, first: try ym(2026, 3))])
        #expect(sut.cardBreakdown(in: try ym(2026, 3)).isEmpty)
        #expect(sut.cardBreakdown(in: try ym(2026, 4)).first?.total == Money(100))
    }

    @Test("Items with an unknown card are skipped in the breakdown")
    func unknownCardSkippedInBreakdown() throws {
        let known = try sameMonthCard()
        let stranger = try sameMonthCard("Yabancı")
        let month = try ym(2026, 1)
        let sut = analytics(
            cards: [known],
            installments: [try installment(card: stranger, total: 300, count: 1, first: month)],
            subscriptions: [try sub(card: stranger, amount: 50, first: month)]
        )
        #expect(sut.cardBreakdown(in: month).isEmpty)
    }

    @Test("Ties are ordered by card name case-insensitively, then by id")
    func tieOrdering() throws {
        let month = try ym(2026, 1)
        let zed = try sameMonthCard("zeynep", id: Fixture.id(1))
        let alpha = try sameMonthCard("Alp", id: Fixture.id(2))
        let beta = try sameMonthCard("beta", id: Fixture.id(3))
        // Aynı adlı iki kart: id sırası belirler.
        let twinB = try sameMonthCard("Çift", id: Fixture.id(5))
        let twinA = try sameMonthCard("Çift", id: Fixture.id(4))
        let cards = [zed, twinB, alpha, twinA, beta]
        let sut = analytics(cards: cards, installments: try cards.map { try installment(card: $0, total: 100, count: 1, first: month) })
        let names = sut.cardBreakdown(in: month).map { $0.card!.name }
        #expect(names == ["Alp", "beta", "Çift", "Çift", "zeynep"])
        #expect(sut.cardBreakdown(in: month).map { $0.card!.id } == [alpha.id, beta.id, twinA.id, twinB.id, zed.id])
    }

    @Test("Ordering does not depend on input order")
    func orderIndependentOfInput() throws {
        let month = try ym(2026, 1)
        let a = try sameMonthCard("A", id: Fixture.id(1))
        let b = try sameMonthCard("B", id: Fixture.id(2))
        let items = try [a, b].map { try installment(card: $0, total: 100, count: 1, first: month) }
        let forward = analytics(cards: [a, b], installments: items).cardBreakdown(in: month)
        let backward = analytics(cards: [b, a], installments: items.reversed()).cardBreakdown(in: month)
        #expect(forward == backward)
    }

    @Test("noCard share ties come after cards with the same total")
    func noCardAfterEqualCards() throws {
        let month = try ym(2026, 1)
        let card = try sameMonthCard("Bonus")
        let sut = analytics(
            cards: [card],
            installments: [try installment(card: card, total: 50, count: 1, first: month)],
            subscriptions: [try sub(card: nil, amount: 50, first: month)]
        )
        let shares = sut.cardBreakdown(in: month)
        #expect(shares.count == 2)
        #expect(shares[0].card == card)
        #expect(shares[1].isNoCard)
    }

    @Test("Uneven installment splits still sum exactly in the breakdown")
    func noRoundingDriftInBreakdown() throws {
        let card = try sameMonthCard()
        let plan = try Fixture.plan(total: 1000, count: 3, first: try ym(2026, 1))
        let item = try Fixture.installment("X", card: card.id, plan: plan)
        let sut = analytics(cards: [card], installments: [item])
        var sum = Money.zero
        for offset in 0..<3 {
            let month = try ym(2026, 1).adding(months: offset)
            let shares = sut.cardBreakdown(in: month)
            #expect(shares.count == 1)
            #expect(shares[0].total == plan.amount(in: month))
            sum = sum + shares[0].total
        }
        #expect(sum == Money(1000))
    }

    // MARK: lastPaymentMonth

    @Test("lastPaymentMonth is nil without installments")
    func lastMonthNil() throws {
        #expect(analytics().lastPaymentMonth == nil)
        let card = try sameMonthCard()
        let sut = analytics(cards: [card], subscriptions: [try sub(card: card, amount: 10, first: try ym(2026, 1))])
        #expect(sut.lastPaymentMonth == nil)
    }

    @Test("lastPaymentMonth is the last due month of the installments")
    func lastMonthSameMonthCard() throws {
        let card = try sameMonthCard()
        // 3 taksit: Oca, Şub, Mar → son vade Mart.
        let short = try installment(card: card, total: 300, count: 3, first: try ym(2026, 1))
        let long = try installment(card: card, total: 600, count: 6, first: try ym(2026, 2))  // Şub..Tem
        #expect(analytics(cards: [card], installments: [short]).lastPaymentMonth == (try ym(2026, 3)))
        #expect(analytics(cards: [card], installments: [short, long]).lastPaymentMonth == (try ym(2026, 7)))
    }

    @Test("lastPaymentMonth uses the due month when the due date falls in the following month")
    func lastMonthNextMonthCard() throws {
        let night = try nextMonthCard()
        let item = try installment(card: night, total: 300, count: 3, first: try ym(2026, 3))  // vadeler Nis, May, Haz
        let sut = analytics(cards: [night], installments: [item])
        #expect(sut.lastPaymentMonth == (try ym(2026, 6)))
    }

    @Test("lastPaymentMonth ignores installments of unknown cards and subscriptions")
    func lastMonthIgnoresUnknown() throws {
        let known = try sameMonthCard()
        let stranger = try sameMonthCard("Yabancı")
        let sut = analytics(
            cards: [known],
            installments: [
                try installment(card: known, total: 200, count: 2, first: try ym(2026, 1)),
                try installment(card: stranger, total: 1200, count: 12, first: try ym(2026, 1)),
            ],
            subscriptions: [try sub(card: known, amount: 10, first: try ym(2026, 1))]
        )
        #expect(sut.lastPaymentMonth == (try ym(2026, 2)))
    }

    @Test("lastPaymentMonth has a payment due in that month and none after")
    func lastMonthConsistentWithTotals() throws {
        let a = try sameMonthCard("A")
        let b = try nextMonthCard("B")
        let items = [
            try installment(card: a, total: 400, count: 4, first: try ym(2026, 5)),
            try installment(card: b, total: 500, count: 5, first: try ym(2026, 4)),
        ]
        let sut = analytics(cards: [a, b], installments: items)
        let last = try #require(sut.lastPaymentMonth)
        let totals = sut.monthlyTotals(from: try ym(2026, 1), count: 24)
        let lastWithInstallments = try #require(totals.last { !$0.installments.isZero })
        #expect(last == lastWithInstallments.month)
    }

    // MARK: Hashable / Sendable

    @Test("Value types are Hashable and Sendable")
    func conformances() throws {
        func requires<T: Sendable & Hashable>(_: T.Type) {}
        requires(SpendingAnalytics.self)
        requires(SpendingAnalytics.MonthTotal.self)
        requires(SpendingAnalytics.CardShare.self)
        let card = try sameMonthCard()
        let one = analytics(cards: [card])
        #expect(one == analytics(cards: [card]))
    }
}
