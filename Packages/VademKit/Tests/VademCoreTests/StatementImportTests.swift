import Foundation
import Testing
import VademCore

@Suite("StatementImport")
struct StatementImportTests {
    private static let october = YearMonth(year: 2026, month: 10)!

    private static func candidate(
        _ merchant: String = "MAGAZA", amount: Decimal = 100, current: Int, total: Int
    ) -> InstallmentCandidate {
        InstallmentCandidate(merchant: merchant, installmentAmount: amount, currentInstallment: current, totalInstallments: total)
    }

    // MARK: İlk ay, kalan, bitiş

    struct MonthCase: Sendable {
        let current: Int
        let total: Int
        let first: YearMonth
        let end: YearMonth
        let remaining: Int
    }

    @Test("Current installment falls in the statement month; first and end month follow", arguments: [
        // 3/6, ekstre Ekim 2026: ilk taksit Ağustos, son Mart 2027, kalan 4 (3,4,5,6).
        MonthCase(current: 3, total: 6, first: YearMonth(year: 2026, month: 8)!, end: YearMonth(year: 2027, month: 1)!, remaining: 4),
        // 1/12: ilk taksit ekstre ayı, son 11 ay sonra (Eylül 2027).
        MonthCase(current: 1, total: 12, first: YearMonth(year: 2026, month: 10)!, end: YearMonth(year: 2027, month: 9)!, remaining: 12),
        // Son taksit: kalan 1, bitiş ekstre ayı.
        MonthCase(current: 6, total: 6, first: YearMonth(year: 2026, month: 5)!, end: YearMonth(year: 2026, month: 10)!, remaining: 1),
        // Yıl sınırını geriye aşar: 11/12 → Aralık 2025'te başlar.
        MonthCase(current: 11, total: 12, first: YearMonth(year: 2025, month: 12)!, end: YearMonth(year: 2026, month: 11)!, remaining: 2),
        MonthCase(current: 1, total: 1, first: YearMonth(year: 2026, month: 10)!, end: YearMonth(year: 2026, month: 10)!, remaining: 1),
    ])
    func months(_ c: MonthCase) {
        let candidate = Self.candidate(current: c.current, total: c.total)
        #expect(candidate.firstMonth(statementMonth: Self.october) == c.first)
        #expect(candidate.endMonth(statementMonth: Self.october) == c.end)
        #expect(candidate.remainingInstallments == c.remaining)
    }

    @Test("Invalid installment numbers give no plan", arguments: [
        (0, 6), (7, 6), (-1, 6), (3, 0), (1, 37), (1, -2),
    ])
    func invalidNumbers(current: Int, total: Int) {
        let candidate = Self.candidate(current: current, total: total)
        #expect(!candidate.hasValidInstallmentNumbers)
        #expect(candidate.remainingInstallments == 0)
        #expect(candidate.firstMonth(statementMonth: Self.october) == nil)
        #expect(candidate.endMonth(statementMonth: Self.october) == nil)
        #expect(candidate.draft(cardID: nil, paymentDay: 10, statementMonth: Self.october) == nil)
        #expect(candidate.makeItem(cardID: nil, statementMonth: Self.october) == nil)
    }

    @Test("Valid numbers at the supported limits", arguments: [(1, 36), (36, 36), (1, 1)])
    func validLimits(current: Int, total: Int) {
        #expect(Self.candidate(current: current, total: total).hasValidInstallmentNumbers)
    }

    @Test("Plan outside the supported years gives no item")
    func outOfRange() {
        let early = YearMonth(year: YearMonth.supportedYears.lowerBound, month: 2)!
        #expect(Self.candidate(current: 5, total: 6).makeItem(cardID: nil, statementMonth: early) == nil)
        let late = YearMonth(year: YearMonth.supportedYears.upperBound, month: 11)!
        #expect(Self.candidate(current: 1, total: 6).makeItem(cardID: nil, statementMonth: late) == nil)
    }

    // MARK: Taksit kalemi

    @Test("Item has the trimmed title, plan total = amount x count and the given card and day")
    func makeItem() throws {
        let card = UUID()
        let item = try #require(
            Self.candidate("  ORNEK   MAGAZA \n", amount: Decimal(string: "1234.56")!, current: 3, total: 6)
                .makeItem(cardID: card, paymentDay: 12, statementMonth: Self.october)
        )
        #expect(item.title == "ORNEK MAGAZA")
        #expect(item.cardID == card)
        // 1234,56 × 6 = 7407,36
        #expect(item.plan.total.amount == Decimal(string: "7407.36")!)
        #expect(item.plan.count == 6)
        #expect(item.plan.firstMonth == YearMonth(year: 2026, month: 8)!)
        #expect(item.plan.lastMonth == YearMonth(year: 2027, month: 1)!)
        // Taksit ekstre ayında tam ekstredeki tutardır.
        #expect(item.plan.amount(in: Self.october).amount == Decimal(string: "1234.56")!)
    }

    @Test("Amount is rounded to kuruş before multiplying, so each payment equals the statement amount")
    func roundsAmountFirst() throws {
        // 100,005 → 100,01 (yarım yukarı); × 3 = 300,03
        let item = try #require(
            Self.candidate(amount: Decimal(string: "100.005")!, current: 1, total: 3)
                .makeItem(cardID: nil, statementMonth: Self.october)
        )
        #expect(item.plan.total.amount == Decimal(string: "300.03")!)
    }

    @Test("Card-less item keeps the payment day")
    func cardless() throws {
        let item = try #require(Self.candidate(current: 1, total: 2).makeItem(cardID: nil, paymentDay: 20, statementMonth: Self.october))
        #expect(item.cardID == nil)
        #expect(item.paymentDay == 20)
    }

    @Test("Empty merchant gives an empty title and a draft with a title error, no item")
    func emptyTitle() throws {
        let candidate = Self.candidate("   ", current: 1, total: 3)
        #expect(candidate.suggestedTitle.isEmpty)
        let draft = try #require(candidate.draft(cardID: nil, paymentDay: 5, statementMonth: Self.october))
        #expect(draft.errors.contains(.titleEmpty))
        #expect(candidate.makeItem(cardID: nil, statementMonth: Self.october) == nil)
    }

    @Test("Zero amount is not addable")
    func zeroAmount() {
        #expect(Self.candidate(amount: 0, current: 1, total: 3).makeItem(cardID: nil, statementMonth: Self.october) == nil)
    }

    // MARK: Başlık

    @Test("Title: whitespace collapsed, trimmed", arguments: [
        ("  A   B  ", "A B"), ("A\tB\nC", "A B C"), ("", ""), ("   ", ""), ("ABC", "ABC"),
    ])
    func titleCleaning(input: String, expected: String) {
        #expect(StatementImport.title(fromMerchant: input) == expected)
    }

    @Test("Title is cut to the maximum length and not left with a trailing space")
    func titleCut() {
        let long = String(repeating: "A", count: InstallmentItem.maxTitleLength + 10)
        #expect(StatementImport.title(fromMerchant: long).count == InstallmentItem.maxTitleLength)
        // 59 harf + boşluk + devamı: kesim boşlukta biter, sonda boşluk kalmaz.
        let spaced = String(repeating: "A", count: InstallmentItem.maxTitleLength - 1) + " BBBB"
        let cut = StatementImport.title(fromMerchant: spaced)
        #expect(cut == String(repeating: "A", count: InstallmentItem.maxTitleLength - 1))
    }

    // MARK: Benzer başlık

    @Test("Similar titles", arguments: [
        ("Migros", "MIGROS", true),
        ("Migros Market", "migros", true),
        ("ISTANBUL ELEKTRONIK", "İstanbul", true),
        ("ığdır", "IGDIR", true),
        ("Café", "cafe", true),
        ("  a   b ", "A B", true),
        ("Migros", "Teknosa", false),
        ("", "Migros", false),
        ("Migros", "   ", false),
        ("", "", false),
    ])
    func similarTitles(a: String, b: String, expected: Bool) {
        #expect(StatementImport.isSimilarTitle(a, b) == expected)
        #expect(StatementImport.isSimilarTitle(b, a) == expected)
    }

    // MARK: Olası tekrar

    private static func existing(
        title: String, amount: Decimal, count: Int, card: UUID?, first: YearMonth = october
    ) -> InstallmentItem {
        InstallmentItem(
            title: title, cardID: card, paymentDay: card == nil ? 10 : nil,
            plan: InstallmentPlan(total: Money(amount * Decimal(count)), count: count, firstMonth: first)!
        )!
    }

    @Test("Duplicate: same card, similar name, same amount and count")
    func duplicate() {
        let card = UUID()
        let saved = [Self.existing(title: "Ornek Elektronik", amount: 500, count: 6, card: card)]
        let candidate = Self.candidate("ORNEK ELEKTRONIK", amount: 500, current: 2, total: 6)
        #expect(candidate.isPossibleDuplicate(of: saved, cardID: card))
    }

    @Test("Not a duplicate when one of card, name, amount or count differs")
    func notDuplicate() {
        let card = UUID()
        let saved = [Self.existing(title: "Ornek Elektronik", amount: 500, count: 6, card: card)]
        #expect(!Self.candidate("ORNEK ELEKTRONIK", amount: 500, current: 2, total: 6).isPossibleDuplicate(of: saved, cardID: UUID()))
        #expect(!Self.candidate("ORNEK ELEKTRONIK", amount: 500, current: 2, total: 6).isPossibleDuplicate(of: saved, cardID: nil))
        #expect(!Self.candidate("BASKA YER", amount: 500, current: 2, total: 6).isPossibleDuplicate(of: saved, cardID: card))
        #expect(!Self.candidate("ORNEK ELEKTRONIK", amount: 501, current: 2, total: 6).isPossibleDuplicate(of: saved, cardID: card))
        #expect(!Self.candidate("ORNEK ELEKTRONIK", amount: 500, current: 2, total: 12).isPossibleDuplicate(of: saved, cardID: card))
        #expect(!Self.candidate("ORNEK ELEKTRONIK", amount: 500, current: 2, total: 6).isPossibleDuplicate(of: [], cardID: card))
    }

    @Test("Card-less candidate matches card-less items only")
    func duplicateCardless() {
        let saved = [Self.existing(title: "Laptop", amount: 400, count: 12, card: nil)]
        #expect(Self.candidate("LAPTOP", amount: 400, current: 4, total: 12).isPossibleDuplicate(of: saved, cardID: nil))
        #expect(!Self.candidate("LAPTOP", amount: 400, current: 4, total: 12).isPossibleDuplicate(of: saved, cardID: UUID()))
    }

    @Test("Duplicate with a plan whose first payment carries the extra kuruş")
    func duplicateWithRemainder() {
        // 100,00 / 3 = 33,33 + 33,33 + 33,34: yarım kuruşlu toplamdan gelen plan hâlâ aynı taksit tutarını eşler.
        let card = UUID()
        let item = InstallmentItem(
            title: "Kulaklik", cardID: card,
            plan: InstallmentPlan(total: Money(Decimal(string: "100.00")!), count: 3, firstMonth: Self.october)!
        )!
        let candidate = Self.candidate("KULAKLIK", amount: Decimal(string: "33.33")!, current: 1, total: 3)
        #expect(candidate.isPossibleDuplicate(of: [item], cardID: card))
    }
}
