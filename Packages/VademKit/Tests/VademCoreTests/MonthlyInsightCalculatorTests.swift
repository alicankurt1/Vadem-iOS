import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("MonthlyInsightCalculator")
struct MonthlyInsightCalculatorTests {
    // Test ayı: Kasım 2026 (önceki ay Ekim 2026).
    private static func november() throws -> YearMonth { try Fixture.month(2026, 11) }

    // Kartsız aylık abonelik; `first` ve `last` arasında her ay öder.
    private static func sub(
        _ title: String, _ amount: Decimal, from first: YearMonth, to last: YearMonth? = nil
    ) throws -> SubscriptionItem {
        let value = try #require(Subscription(
            amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: first, lastMonth: last
        ))
        return try #require(SubscriptionItem(id: UUID(), title: title, cardID: nil, subscription: value))
    }

    private static func installment(
        _ title: String, total: Decimal, count: Int, first: YearMonth
    ) throws -> InstallmentItem {
        try Fixture.installment(title, card: nil, plan: Fixture.plan(total: total, count: count, first: first))
    }

    private static func insights(
        _ month: YearMonth, subs: [SubscriptionItem] = [], installments: [InstallmentItem] = [],
        oneTime: [OneTimePaymentItem] = []
    ) -> [MonthlyInsight] {
        MonthlyInsightCalculator.insights(
            for: month, cards: [], installments: installments, subscriptions: subs, oneTimePayments: oneTime
        )
    }

    // MARK: Sabitler

    @Test("Threshold constant is 20%")
    func threshold() {
        #expect(MonthlyInsightCalculator.changeThreshold == Decimal(string: "0.2"))
    }

    // MARK: Artış / azalış

    @Test("Increase of 50% reports previous, current and percent")
    func increase() throws {
        let jan = try Fixture.month(2026, 1)
        let subs = [try Self.sub("A", 3200, from: jan), try Self.sub("B", 1600, from: try Self.november())]
        let result = Self.insights(try Self.november(), subs: subs)
        #expect(result.count == 1)
        #expect(result.first?.detail == .totalChange(previous: Money(3200), current: Money(4800), percent: 50))
    }

    @Test("Decrease of 50% reports a negative percent")
    func decrease() throws {
        let jan = try Fixture.month(2026, 1)
        let oct = try Fixture.month(2026, 10)
        let subs = [try Self.sub("A", 1000, from: jan), try Self.sub("B", 1000, from: jan, to: oct)]
        let result = Self.insights(try Self.november(), subs: subs)
        #expect(result.first?.detail == .totalChange(previous: Money(2000), current: Money(1000), percent: -50))
    }

    // MARK: Eşik

    struct ThresholdCase: Sendable {
        let current: String
        let reported: Bool
        var amount: Decimal { Decimal(string: current)! }
    }

    // Önceki ay 1000: tam %20 dahil, hemen altı (yuvarlanınca %20 görünse de) hariç.
    @Test("Threshold is applied to the exact ratio, inclusive at 20%", arguments: [
        ThresholdCase(current: "1200", reported: true),
        ThresholdCase(current: "1199", reported: false),
        ThresholdCase(current: "1199.9", reported: false),
        ThresholdCase(current: "1200.01", reported: true),
        ThresholdCase(current: "800", reported: true),
        ThresholdCase(current: "801", reported: false),
        ThresholdCase(current: "800.01", reported: false),
        ThresholdCase(current: "1000", reported: false),
        ThresholdCase(current: "1100", reported: false),
    ])
    func thresholdBoundary(_ testCase: ThresholdCase) throws {
        let oct = try Fixture.month(2026, 10)
        let jan = try Fixture.month(2026, 1)
        // Önceki ay tam 1000; bu ay `current`: tek abonelik Kasım'dan itibaren farklı tutarda.
        let subs = [
            try Self.sub("Old", 1000, from: jan, to: oct),
            try Self.sub("New", testCase.amount, from: try Self.november()),
        ]
        let result = Self.insights(try Self.november(), subs: subs)
        let changes = result.filter { $0.kind == .totalChange }
        #expect(changes.isEmpty == !testCase.reported)
    }

    struct RoundCase: Sendable {
        let previous: Int
        let current: String
        let percent: Int?
    }

    @Test("Percent rounds half away from zero; nil without a positive previous total", arguments: [
        RoundCase(previous: 8, current: "9", percent: 13),
        RoundCase(previous: 8, current: "7", percent: -13),
        RoundCase(previous: 3, current: "4", percent: 33),
        RoundCase(previous: 3, current: "2", percent: -33),
        RoundCase(previous: 1000, current: "1204.5", percent: 20),
        RoundCase(previous: 1000, current: "1205", percent: 21),
        RoundCase(previous: 1000, current: "1000", percent: 0),
        RoundCase(previous: 1000, current: "0", percent: -100),
        RoundCase(previous: 1000, current: "100000", percent: 9900),
        RoundCase(previous: 0, current: "500", percent: nil),
        RoundCase(previous: 0, current: "0", percent: nil),
    ])
    func percentRounding(_ testCase: RoundCase) {
        #expect(MonthlyInsightCalculator.percentChange(
            from: Money(Decimal(testCase.previous)), to: Money(Decimal(string: testCase.current)!)
        ) == testCase.percent)
    }

    @Test("Reported percent of a 19.99%-ish rise is not reported but a 20.5% rise shows 21")
    func roundedPercentInInsight() throws {
        let subs = [
            try Self.sub("Old", 1000, from: try Fixture.month(2026, 1), to: try Fixture.month(2026, 10)),
            try Self.sub("New", 1205, from: try Self.november()),
        ]
        let result = Self.insights(try Self.november(), subs: subs)
        #expect(result.first?.detail == .totalChange(previous: Money(1000), current: Money(1205), percent: 21))
    }

    // MARK: Önceki ay sıfır

    @Test("Zero previous total gives no percentage insight")
    func zeroPrevious() throws {
        let subs = [try Self.sub("New", 500, from: try Self.november())]
        #expect(Self.insights(try Self.november(), subs: subs).isEmpty)
    }

    @Test("No payments at all gives no insight")
    func empty() throws {
        #expect(Self.insights(try Self.november()).isEmpty)
        #expect(MonthlyInsightCalculator.topInsight(
            for: try Self.november(), cards: [], installments: [], subscriptions: []
        ) == nil)
    }

    @Test("The first supported month has no previous month and no insight")
    func firstSupportedMonth() throws {
        let first = try Fixture.month(YearMonth.supportedYears.lowerBound, 1)
        #expect(Self.insights(first).isEmpty)
    }

    // MARK: Biten taksit

    @Test("An installment whose last payment was last month is reported with that payment")
    func installmentEnded() throws {
        // 3 taksit: Ağu, Eyl, Eki (son). Abonelik 5000 sabit: toplam 6000 -> 5000 (-%16,7, eşik altı).
        let jan = try Fixture.month(2026, 1)
        let result = Self.insights(
            try Self.november(),
            subs: [try Self.sub("Rent", 5000, from: jan)],
            installments: [try Self.installment("Phone", total: 3000, count: 3, first: try Fixture.month(2026, 8))]
        )
        #expect(result.count == 1)
        #expect(result.first?.detail == .installmentEnded(titles: ["Phone"], amount: Money(1000)))
    }

    @Test("Several plans ending together give one insight with the exact sum")
    func severalEnded() throws {
        let aug = try Fixture.month(2026, 8)
        let result = Self.insights(
            try Self.november(),
            subs: [try Self.sub("Rent", 50_000, from: try Fixture.month(2026, 1))],
            installments: [
                try Self.installment("Phone", total: 3000, count: 3, first: aug),
                try Self.installment("Laptop", total: 1500, count: 3, first: aug),
            ]
        )
        let ended = result.filter { $0.kind == .installmentEnded }
        #expect(ended.count == 1)
        guard case .installmentEnded(let titles, let amount)? = ended.first?.detail else {
            Issue.record("expected installmentEnded")
            return
        }
        #expect(Set(titles) == ["Phone", "Laptop"])
        #expect(amount == Money(1500))
    }

    struct EndCase: Sendable {
        let year: Int
        let month: Int
        let count: Int
        let reported: Bool
    }

    @Test("Only plans whose last payment was last month are reported", arguments: [
        EndCase(year: 2026, month: 9, count: 3, reported: false),  // Eyl-Eki-Kas: son taksit bu ay
        EndCase(year: 2026, month: 7, count: 3, reported: false),  // Tem-Ağu-Eyl: iki ay önce bitti
        EndCase(year: 2026, month: 8, count: 4, reported: false),  // Ağu-Eyl-Eki-Kas: sürüyor
        EndCase(year: 2026, month: 9, count: 2, reported: true),  // Eyl-Eki: son taksit Ekim
        EndCase(year: 2026, month: 8, count: 3, reported: true),  // Ağu-Eyl-Eki
        EndCase(year: 2026, month: 11, count: 3, reported: false),  // henüz başlamadı
    ])
    func notEnded(_ testCase: EndCase) throws {
        let plan = try Self.installment(
            "Phone", total: 6000, count: testCase.count, first: try Fixture.month(testCase.year, testCase.month)
        )
        let result = Self.insights(
            try Self.november(),
            subs: [try Self.sub("Rent", 500_000, from: try Fixture.month(2026, 1))],
            installments: [plan]
        )
        #expect(result.contains { $0.kind == .installmentEnded } == testCase.reported)
    }

    @Test("A subscription ending last month is not an ended installment")
    func subscriptionEndIsNotInstallment() throws {
        let subs = [
            try Self.sub("Big", 100_000, from: try Fixture.month(2026, 1)),
            try Self.sub("Old", 10, from: try Fixture.month(2026, 1), to: try Fixture.month(2026, 10)),
        ]
        #expect(Self.insights(try Self.november(), subs: subs).isEmpty)
    }

    // MARK: Tek seferlik ödemeler

    @Test("A one-time payment counts in the month it is due")
    func oneTimeInDueMonth() throws {
        let subs = [try Self.sub("Rent", 1000, from: try Fixture.month(2026, 1))]
        let tax = try Fixture.oneTimePayment("Tax", card: nil, amount: 2000, due: try Self.november(), day: 3)
        let result = Self.insights(try Self.november(), subs: subs, oneTime: [tax])
        #expect(result.first?.detail == .totalChange(previous: Money(1000), current: Money(3000), percent: 200))
    }

    @Test("A one-time payment in the previous month raises the previous total only")
    func oneTimeInPreviousMonth() throws {
        let subs = [try Self.sub("Rent", 1000, from: try Fixture.month(2026, 1))]
        let tax = try Fixture.oneTimePayment("Tax", card: nil, amount: 1000, due: try Fixture.month(2026, 10), day: 20)
        let result = Self.insights(try Self.november(), subs: subs, oneTime: [tax])
        #expect(result.first?.detail == .totalChange(previous: Money(2000), current: Money(1000), percent: -50))
    }

    @Test("A one-time payment in another month changes nothing")
    func oneTimeElsewhere() throws {
        let subs = [try Self.sub("Rent", 1000, from: try Fixture.month(2026, 1))]
        let tax = try Fixture.oneTimePayment("Tax", card: nil, amount: 9000, due: try Fixture.month(2026, 12), day: 3)
        #expect(Self.insights(try Self.november(), subs: subs, oneTime: [tax]).isEmpty)
    }

    // MARK: Kimlik

    @Test("Insight id is kind plus zero-padded month and is stable")
    func identity() throws {
        let subs = [
            try Self.sub("A", 3200, from: try Fixture.month(2026, 1)),
            try Self.sub("B", 1600, from: try Self.november()),
        ]
        let first = Self.insights(try Self.november(), subs: subs)
        let second = Self.insights(try Self.november(), subs: subs)
        #expect(first == second)
        #expect(first.first?.id == "insight-2026-11-totalChange")
        #expect(MonthlyInsight.id(of: .installmentEnded, in: try Fixture.month(2026, 3)) == "insight-2026-03-installmentEnded")
        #expect(MonthlyInsight.idPrefix(for: try Fixture.month(2026, 3)) == "insight-2026-03")
    }

    @Test("Same kind in different months has different ids; different kinds in a month differ")
    func identityDistinct() throws {
        let nov = try Fixture.month(2026, 11)
        let dec = try Fixture.month(2026, 12)
        #expect(MonthlyInsight.id(of: .totalChange, in: nov) != MonthlyInsight.id(of: .totalChange, in: dec))
        #expect(MonthlyInsight.id(of: .totalChange, in: nov) != MonthlyInsight.id(of: .installmentEnded, in: nov))
    }

    @Test("January compares with December of the previous year")
    func yearBoundary() throws {
        let subs = [
            try Self.sub("A", 1000, from: try Fixture.month(2025, 1)),
            try Self.sub("B", 1000, from: try Fixture.month(2026, 1)),
        ]
        let result = Self.insights(try Fixture.month(2026, 1), subs: subs)
        #expect(result.first?.id == "insight-2026-01-totalChange")
        #expect(result.first?.detail == .totalChange(previous: Money(1000), current: Money(2000), percent: 100))
    }

    // MARK: Sıralama

    @Test("Total change ranks above ended installment; top insight is the most important")
    func ranking() throws {
        // Ekim: taksit 1000 + abonelik 1000 = 2000; Kasım: abonelik 1000 = 1000 (-%50) ve taksit bitti.
        let result = Self.insights(
            try Self.november(),
            subs: [try Self.sub("Rent", 1000, from: try Fixture.month(2026, 1))],
            installments: [try Self.installment("Phone", total: 3000, count: 3, first: try Fixture.month(2026, 8))]
        )
        #expect(result.map(\.kind) == [.totalChange, .installmentEnded])
        let top = MonthlyInsightCalculator.topInsight(
            for: try Self.november(), cards: [],
            installments: [try Self.installment("Phone", total: 3000, count: 3, first: try Fixture.month(2026, 8))],
            subscriptions: [try Self.sub("Rent", 1000, from: try Fixture.month(2026, 1))]
        )
        #expect(top?.kind == .totalChange)
        #expect(MonthlyInsight.Kind.totalChange < .installmentEnded)
        #expect(MonthlyInsight.Kind.totalChange.rank < MonthlyInsight.Kind.installmentEnded.rank)
    }

    @Test("Top insight falls back to the ended installment when the change is small")
    func topFallback() throws {
        let top = MonthlyInsightCalculator.topInsight(
            for: try Self.november(), cards: [],
            installments: [try Self.installment("Phone", total: 3000, count: 3, first: try Fixture.month(2026, 8))],
            subscriptions: [try Self.sub("Rent", 5000, from: try Fixture.month(2026, 1))]
        )
        #expect(top?.kind == .installmentEnded)
    }
}
