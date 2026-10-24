import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("AnalyticsViewModel")
struct AnalyticsViewModelTests {
    // MARK: Yardımcılar

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func month(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }

    private static func model(
        _ repository: any PaymentRepository = InMemoryPaymentRepository(), today: Date? = nil
    ) -> AnalyticsViewModel {
        AnalyticsViewModel(repository: repository, today: today ?? date(2026, 10, 12), calendar: calendar)
    }

    private static func subscription(_ amount: Decimal, first: YearMonth) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: "Music", cardID: nil,
            subscription: Subscription(amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: first)!
        )!
    }

    private struct FailingRepository: PaymentRepository {
        struct Failure: Error {}
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

    // MARK: Yükleniyor

    @Test("Starts loading with no months and no summary")
    func startsLoading() {
        let model = Self.model()
        #expect(model.state == .loading)
        #expect(model.months.isEmpty)
        #expect(model.summary == nil)
        #expect(model.currentMonth == Self.month(2026, 10))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    // MARK: 12 ay

    @Test("Shows 12 consecutive months starting at the injected current month", arguments: [
        (2026, 10, 12), (2026, 1, 15), (2026, 12, 31), (2028, 2, 29),
    ])
    func twelveMonths(year: Int, month: Int, day: Int) throws {
        let model = Self.model(today: Self.date(year, month, day))
        model.reload()
        #expect(model.months.count == 12)
        #expect(AnalyticsViewModel.monthCount == 12)
        let start = Self.month(year, month)
        #expect(model.months.first?.month == start)
        for (offset, total) in model.months.enumerated() {
            #expect(total.month == start.adding(months: offset))
        }
    }

    @Test("Year boundary is crossed: from December the next month is January")
    func yearBoundary() {
        let model = Self.model(today: Self.date(2026, 12, 1))
        model.reload()
        #expect(model.months[1].month == Self.month(2027, 1))
        #expect(model.months[11].month == Self.month(2027, 11))
    }

    // MARK: Boş durum

    @Test("No payments gives the empty state, 12 zero months and a zero summary")
    func emptyState() throws {
        let model = Self.model()
        model.reload()
        #expect(model.state == .empty)
        #expect(model.months.count == 12)
        #expect(model.months.allSatisfy { $0.total.isZero })
        let summary = try #require(model.summary)
        #expect(summary.total.isZero)
        #expect(summary.month == Self.month(2026, 10))
    }

    @Test("A payment in any of the 12 months gives the loaded state")
    func loadedState() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Self.subscription(100, first: Self.month(2026, 10)))
        let model = Self.model(repository)
        model.reload()
        #expect(model.state == .loaded)
    }

    // MARK: Özet

    @Test("Summary starts on the current month with its parts adding up")
    func summaryOfCurrentMonth() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Self.subscription(100, first: Self.month(2026, 10)))
        let model = Self.model(repository)
        model.reload()
        let summary = try #require(model.summary)
        #expect(summary.month == Self.month(2026, 10))
        #expect(summary.title == "October 2026")
        #expect(summary.subscriptions == Money(100))
        #expect(summary.installments.isZero)
        #expect(summary.total == Money(100))
        #expect(summary.total == summary.installments + summary.subscriptions)
    }

    @Test("Summary follows the selected month")
    func summaryFollowsSelection() throws {
        let repository = InMemoryPaymentRepository()
        // Ekimde başlayan abonelik; Eylül (geçmiş) listede yok, Kasım var.
        try repository.save(Self.subscription(100, first: Self.month(2026, 11)))
        let model = Self.model(repository)
        model.reload()
        model.select(month: Self.month(2026, 11))
        #expect(model.selectedMonth == Self.month(2026, 11))
        let summary = try #require(model.summary)
        #expect(summary.month == Self.month(2026, 11))
        #expect(summary.title == "November 2026")
        #expect(summary.subscriptions == Money(100))
    }

    // MARK: Seçim

    @Test("Selecting a month outside the 12 is ignored", arguments: [(2026, 9), (2027, 10), (2030, 1)])
    func selectOutsideIgnored(year: Int, month: Int) {
        let model = Self.model()
        model.reload()
        model.select(month: Self.month(year, month))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    @Test("Selecting the first and the last month works")
    func selectEdges() {
        let model = Self.model()
        model.reload()
        model.select(month: Self.month(2027, 9))
        #expect(model.selectedMonth == Self.month(2027, 9))
        model.select(month: Self.month(2026, 10))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    @Test("Selecting before loading is ignored")
    func selectBeforeLoad() {
        let model = Self.model()
        model.select(month: Self.month(2026, 11))
        #expect(model.selectedMonth == Self.month(2026, 10))
    }

    @Test("Reload keeps the selected month")
    func reloadKeepsSelection() {
        let model = Self.model()
        model.reload()
        model.select(month: Self.month(2027, 2))
        model.reload()
        #expect(model.selectedMonth == Self.month(2027, 2))
    }

    @Test("Reload shows a payment added after the first load")
    func reloadPicksUpChanges() throws {
        let repository = InMemoryPaymentRepository()
        let model = Self.model(repository)
        model.reload()
        #expect(model.state == .empty)
        try repository.save(Self.subscription(100, first: Self.month(2026, 10)))
        model.reload()
        #expect(model.state == .loaded)
    }

    // MARK: Hata

    @Test("A failing repository gives the error state and no months")
    func errorState() {
        let model = Self.model(FailingRepository())
        model.reload()
        #expect(model.state == .error(message: AnalyticsViewModel.loadErrorMessage))
        #expect(model.months.isEmpty)
        #expect(model.summary == nil)
    }

    // MARK: Biçim

    @Test("Month titles and ids", arguments: [
        (2026, 5, "May 2026", "May", "2026-05"),
        (2027, 1, "January 2027", "Jan", "2027-01"),
        (2026, 12, "December 2026", "Dec", "2026-12"),
    ])
    func formatting(year: Int, month: Int, title: String, short: String, id: String) {
        let value = Self.month(year, month)
        #expect(AnalyticsViewModel.title(of: value) == title)
        #expect(AnalyticsViewModel.shortTitle(of: value) == short)
        #expect(AnalyticsViewModel.id(of: value) == id)
    }

    @Test("Bar accessibility label is the month and the formatted amount")
    func accessibilityLabel() {
        let total = SpendingAnalytics.MonthTotal(
            month: Self.month(2026, 5), installments: Money(Decimal(string: "3000.50")!), subscriptions: Money(1249.5)
        )
        #expect(AnalyticsViewModel.accessibilityLabel(for: total) == "May 2026, 4.250,00 TL")
    }

    // MARK: Kart dağılımı ve içgörü (#117)

    private static let nightID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let bonusID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private static let cityID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!

    // Ekstre 10, vade 20: taksit ekstre ayında ödenir.
    private static func card(_ name: String, id: UUID) -> Card {
        Card(id: id, name: name, statementDay: 10, dueDay: 20)!
    }

    // Ekstre 25, vade 5: vade sonraki aya düşer.
    private static func lateStatementCard(_ name: String, id: UUID) -> Card {
        Card(id: id, name: name, statementDay: 25, dueDay: 5)!
    }

    private static func cardSub(_ title: String, _ amount: Decimal, card: UUID?, first: YearMonth) -> SubscriptionItem {
        SubscriptionItem(
            id: UUID(), title: title, cardID: card,
            subscription: Subscription(amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: first)!
        )!
    }

    private static func installment(card: Card, total: Decimal, count: Int, first: YearMonth) -> InstallmentItem {
        InstallmentItem(
            id: UUID(), title: "Phone", cardID: card.id,
            plan: InstallmentPlan(total: Money(total), count: count, firstMonth: first)!
        )!
    }

    @Test("Card shares of the current month: amounts, percents, order and no-card share")
    func cardSharesCurrentMonth() throws {
        let repository = InMemoryPaymentRepository()
        let night = Self.card("Night", id: Self.nightID)
        let bonus = Self.card("Bonus", id: Self.bonusID)
        try repository.save(night)
        try repository.save(bonus)
        let october = Self.month(2026, 10)
        try repository.save(Self.cardSub("A", 300, card: night.id, first: october))
        try repository.save(Self.cardSub("B", 100, card: bonus.id, first: october))
        try repository.save(Self.cardSub("C", 100, card: nil, first: october))
        let model = Self.model(repository)
        model.reload()
        let shares = model.cardShares
        // 500 toplam: 60 / 20 / 20; eşit tutarda kart, kartsız paydan önce gelir.
        #expect(shares.map(\.id) == [night.id.uuidString, bonus.id.uuidString, AnalyticsViewModel.noCardID])
        #expect(shares.map(\.name) == ["Night", "Bonus", "No card"])
        #expect(shares.map(\.amount) == [Money(300), Money(100), Money(100)])
        #expect(shares.map(\.percent) == [60, 20, 20])
        #expect(shares[0].style == CardStyle.default(for: night.id))
        #expect(shares[2].style == nil)
        #expect(shares[0].accessibilityLabel == "Night, 300,00 TL, 60 percent")
        #expect(shares[2].accessibilityLabel == "No card, 100,00 TL, 20 percent")
    }

    @Test("Card shares follow the selected month")
    func cardSharesFollowSelection() throws {
        let repository = InMemoryPaymentRepository()
        let night = Self.card("Night", id: Self.nightID)
        try repository.save(night)
        try repository.save(Self.cardSub("A", 300, card: night.id, first: Self.month(2026, 10)))
        try repository.save(Self.cardSub("B", 100, card: nil, first: Self.month(2026, 12)))
        let model = Self.model(repository)
        model.reload()
        #expect(model.cardShares.map(\.percent) == [100])
        model.select(month: Self.month(2026, 12))
        #expect(model.cardShares.map(\.id) == [night.id.uuidString, AnalyticsViewModel.noCardID])
        #expect(model.cardShares.map(\.percent) == [75, 25])
        model.select(month: Self.month(2026, 11))
        #expect(model.cardShares.map(\.id) == [night.id.uuidString])
        #expect(model.cardShares.map(\.percent) == [100])
    }

    @Test("A month with nothing due, no data and the error state give no shares")
    func cardSharesEmpty() throws {
        let beforeLoad = Self.model()
        #expect(beforeLoad.cardShares.isEmpty)

        let repository = InMemoryPaymentRepository()
        try repository.save(Self.cardSub("A", 100, card: nil, first: Self.month(2026, 12)))
        let model = Self.model(repository)
        model.reload()
        #expect(model.cardShares.isEmpty)  // Ekim'de ödeme yok.
        model.select(month: Self.month(2026, 12))
        #expect(model.cardShares.map(\.percent) == [100])

        let failing = Self.model(FailingRepository())
        failing.reload()
        #expect(failing.cardShares.isEmpty)
        #expect(failing.insight == nil)
    }

    @Test("Three equal cards get 34, 33 and 33 percent and the sum stays 100")
    func thirdsSumToHundred() throws {
        let repository = InMemoryPaymentRepository()
        for (name, id) in [("Bonus", Self.bonusID), ("City", Self.cityID), ("Night", Self.nightID)] {
            let card = Self.card(name, id: id)
            try repository.save(card)
            try repository.save(Self.cardSub(name, 100, card: id, first: Self.month(2026, 10)))
        }
        let model = Self.model(repository)
        model.reload()
        // Eşit tutarlar ada göre sıralı; artan 1 puan ilk satıra gider.
        #expect(model.cardShares.map(\.name) == ["Bonus", "City", "Night"])
        #expect(model.cardShares.map(\.percent) == [34, 33, 33])
        #expect(model.cardShares.map(\.percent).reduce(0, +) == 100)
    }

    @Test("Percentages use the largest-remainder method", arguments: [
        ([1, 1, 1], [34, 33, 33]),
        ([1, 2], [33, 67]),
        ([1, 1, 1, 1, 1, 1, 1], [15, 15, 14, 14, 14, 14, 14]),
        ([1, 1, 2, 3], [14, 14, 29, 43]),
        ([5, 3, 3], [46, 27, 27]),
        ([50, 30, 20], [50, 30, 20]),
        ([1, 1], [50, 50]),
        ([7], [100]),
    ] as [([Int], [Int])])
    func largestRemainder(amounts: [Int], expected: [Int]) {
        let result = AnalyticsViewModel.percentages(of: amounts.map { Money(Decimal($0)) })
        #expect(result == expected)
        #expect(result.reduce(0, +) == 100)
    }

    @Test("Tiny share rounds down, the big one takes the rest")
    func tinyShare() {
        let result = AnalyticsViewModel.percentages(of: [Money(Decimal(string: "0.01")!), Money(Decimal(string: "99.99")!)])
        #expect(result == [0, 100])
    }

    @Test("Percentages of nothing or of zero amounts")
    func percentagesDegenerate() {
        #expect(AnalyticsViewModel.percentages(of: []).isEmpty)
        #expect(AnalyticsViewModel.percentages(of: [Money(0), Money(0)]) == [0, 0])
    }

    @Test("Percentages always sum to 100 for many awkward amounts", arguments: [
        [1, 1, 1, 1, 1, 1], [3, 3, 3, 1], [999, 1, 1], [13, 17, 19, 23, 29], [1, 2, 3, 4, 5, 6, 7, 8, 9],
    ])
    func alwaysHundred(amounts: [Int]) {
        let result = AnalyticsViewModel.percentages(of: amounts.map { Money(Decimal($0)) })
        #expect(result.count == amounts.count)
        #expect(result.reduce(0, +) == 100)
        #expect(result.allSatisfy { $0 >= 0 })
    }

    @Test("No installments hides the insight, even with subscriptions")
    func noInstallmentsNoInsight() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Self.cardSub("A", 100, card: nil, first: Self.month(2026, 10)))
        let model = Self.model(repository)
        #expect(model.insight == nil)
        model.reload()
        #expect(model.insight == nil)
    }

    @Test("Insight names the last installment month and the months remaining", arguments: [
        // (kart ekstre günü, vade günü, ilk ay, taksit sayısı, başlık, kalan ay, kalan metin)
        (10, 20, 10, 3, "Last installment payment: December 2026", 2, "2 months remaining"),
        (10, 20, 10, 2, "Last installment payment: November 2026", 1, "1 month remaining"),
        // Vadesi sonraki aya düşen kart: tek taksit Kasım'da ödenir.
        (25, 5, 10, 1, "Last installment payment: November 2026", 1, "1 month remaining"),
        // Yıl sınırı: Ekim 2026 + 12 taksit, son ekstre Eylül 2027.
        (10, 20, 10, 12, "Last installment payment: September 2027", 11, "11 months remaining"),
        // Geçmişte biten plan: kalan ay negatif olmaz.
        (10, 20, 1, 3, "Last installment payment: March 2026", 0, "Paid off"),
    ] as [(Int, Int, Int, Int, String, Int, String)])
    func insightText(
        statement: Int, due: Int, firstMonth: Int, count: Int, title: String, remaining: Int, text: String
    ) throws {
        let repository = InMemoryPaymentRepository()
        let card = Card(id: Self.nightID, name: "Night", statementDay: statement, dueDay: due)!
        try repository.save(card)
        try repository.save(Self.installment(card: card, total: Decimal(count) * 100, count: count, first: Self.month(2026, firstMonth)))
        let model = Self.model(repository)
        model.reload()
        let insight = try #require(model.insight)
        #expect(insight.title == title)
        #expect(insight.monthsRemaining == remaining)
        #expect(insight.remaining == text)
    }

    @Test("Insight uses the latest of several installments and ignores the selected month")
    func insightLatestAndSelectionIndependent() throws {
        let repository = InMemoryPaymentRepository()
        let card = Self.card("Night", id: Self.nightID)
        try repository.save(card)
        try repository.save(Self.installment(card: card, total: 200, count: 2, first: Self.month(2026, 10)))
        try repository.save(Self.installment(card: card, total: 600, count: 6, first: Self.month(2026, 11)))
        let model = Self.model(repository)
        model.reload()
        let before = model.insight
        #expect(before?.title == "Last installment payment: April 2027")
        #expect(before?.monthsRemaining == 6)
        model.select(month: Self.month(2027, 2))
        #expect(model.insight == before)
    }

    @Test("A last payment due this month is not reported as paid off")
    func lastPaymentThisMonth() throws {
        // Belirsiz: kriter "geçmişte bitmişse Paid off" der; bu ay hâlâ ödeme var.
        let repository = InMemoryPaymentRepository()
        let card = Self.card("Night", id: Self.nightID)
        try repository.save(card)
        try repository.save(Self.installment(card: card, total: 100, count: 1, first: Self.month(2026, 10)))
        let model = Self.model(repository)
        model.reload()
        let insight = try #require(model.insight)
        #expect(insight.title == "Last installment payment: October 2026")
        #expect(insight.monthsRemaining == 0)
        #expect(insight.remaining != "Paid off")
    }
}
