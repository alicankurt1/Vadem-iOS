import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

// Ekstre borcu teklifi (#256): ekstre toplamı − (seçili satırlar + olası tekrarlar) kuralı, canlı güncelleme, kaydetme.
@MainActor
@Suite("StatementReviewViewModel: statement total offer")
struct StatementTotalReviewTests {
    private static let october = YearMonth(year: 2026, month: 10)!
    private static let november = YearMonth(year: 2026, month: 11)!
    private static let english = Locale(identifier: "en_US")

    private static func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    private static func summary(_ total: String = "12500") -> StatementSummary {
        StatementSummary(total: dec(total), dueDate: StatementDate(year: 2026, month: 11, day: 2)!)
    }

    private static func store(lastUsed: Card.ID? = nil) -> LastUsedCardStore {
        let name = "vadem.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = LastUsedCardStore(defaults: defaults)
        store.cardID = lastUsed
        return store
    }

    private static func card(_ name: String) -> Card { Card(id: UUID(), name: name, statementDay: 5, dueDay: 15)! }

    // Satırlar: 1234,56 + 450,00 + 400,00 = 2.084,56
    private static func candidates() -> [InstallmentCandidate] {
        [
            InstallmentCandidate(merchant: "ORNEK ELEKTRONIK", installmentAmount: dec("1234.56"), currentInstallment: 3, totalInstallments: 6),
            InstallmentCandidate(merchant: "ORNEK GIYIM", installmentAmount: 450, currentInstallment: 2, totalInstallments: 4),
            InstallmentCandidate(merchant: "LAPTOP", installmentAmount: 400, currentInstallment: 4, totalInstallments: 12),
        ]
    }

    // Kayıtlı "Ornek Giyim": 1800 / 4 = 450 aylık; ORNEK GIYIM satırının olası tekrarı.
    private static func savedGiyim(on card: Card) -> InstallmentItem {
        InstallmentItem(
            title: "Ornek Giyim", cardID: card.id,
            plan: InstallmentPlan(total: Money(1800), count: 4, firstMonth: YearMonth(year: 2026, month: 9)!)!
        )!
    }

    private static func makeModel(
        summary: StatementSummary? = summary(),
        cards: [Card] = [],
        lastUsed: Card.ID? = nil,
        saved: [InstallmentItem] = [],
        repository: InMemoryPaymentRepository = InMemoryPaymentRepository()
    ) throws -> (StatementReviewViewModel, InMemoryPaymentRepository) {
        for card in cards { try repository.save(card) }
        for item in saved { try repository.save(item) }
        let model = StatementReviewViewModel(
            candidates: candidates(), summary: summary, repository: repository, todayMonth: october, todayDay: 17,
            lastUsedCard: store(lastUsed: lastUsed), locale: english
        )
        return (model, repository)
    }

    // MARK: Kural

    @Test("Offer is total minus the selected rows' amounts")
    func initialOffer() throws {
        let (model, _) = try Self.makeModel()
        #expect(model.statementTotalDeduction.amount == Self.dec("2084.56"))
        #expect(model.statementTotalRemainder?.amount == Self.dec("10415.44"))
        #expect(model.isStatementTotalOffered)
        #expect(model.isStatementTotalSelected)
        #expect(model.willAddStatementTotal)
        let breakdown = try #require(model.statementTotalBreakdown)
        #expect(breakdown.contains("="))
        #expect(model.statementDueDateText != nil)
    }

    @Test("Toggling a row updates the offer live and back")
    func toggleRowUpdates() throws {
        let (model, _) = try Self.makeModel()
        model.toggleSelection(at: 1)
        #expect(model.statementTotalDeduction.amount == Self.dec("1634.56"))
        #expect(model.statementTotalRemainder?.amount == Self.dec("10865.44"))
        model.toggleSelection(at: 1)
        #expect(model.statementTotalRemainder?.amount == Self.dec("10415.44"))
        for index in model.rows.indices { model.toggleSelection(at: index) }
        #expect(model.statementTotalRemainder?.amount == 12500)
    }

    @Test("Editing a row amount changes the deduction; an invalid amount counts zero")
    func editedAmount() throws {
        let (model, _) = try Self.makeModel()
        model.rows[0].amountText = "1000"
        #expect(model.statementTotalDeduction.amount == 1850)
        model.rows[0].amountText = "abc"
        #expect(model.statementTotalDeduction.amount == 850)
    }

    @Test("Possible duplicates of saved installments are subtracted even when unselected")
    func duplicatesSubtracted() throws {
        let card = Self.card("Akbank")
        let (model, _) = try Self.makeModel(cards: [card], saved: [Self.savedGiyim(on: card)])
        #expect(model.rows.map(\.isSelected) == [true, false, true])
        // 1234,56 + 400 seçili, 450 olası tekrar: hepsi düşer.
        #expect(model.statementTotalDeduction.amount == Self.dec("2084.56"))
        #expect(model.statementTotalRemainder?.amount == Self.dec("10415.44"))
    }

    @Test("A row that is both selected and a duplicate counts once")
    func selectedDuplicateCountsOnce() throws {
        let card = Self.card("Akbank")
        let (model, _) = try Self.makeModel(cards: [card], saved: [Self.savedGiyim(on: card)])
        model.toggleSelection(at: 1)
        #expect(model.rows[1].isSelected)
        #expect(model.statementTotalDeduction.amount == Self.dec("2084.56"))
    }

    @Test("Changing the card re-evaluates duplicates and the offer")
    func cardChange() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, _) = try Self.makeModel(cards: [a, b], lastUsed: b.id, saved: [Self.savedGiyim(on: a)])
        #expect(model.rows.allSatisfy { $0.isSelected })
        model.toggleSelection(at: 1)
        #expect(model.statementTotalDeduction.amount == Self.dec("1634.56"))
        // Akbank'ta Giyim olası tekrar olur: seçimi kalkar ama toplamdan yine düşer.
        model.cardID = a.id
        #expect(!model.rows[1].isSelected)
        #expect(model.statementTotalDeduction.amount == Self.dec("2084.56"))
        model.cardID = b.id
        #expect(model.statementTotalDeduction.amount == Self.dec("2084.56"))
    }

    @Test("No offer when the remainder is zero or less", arguments: ["2084.56", "2000", "1"])
    func noOfferWhenCovered(total: String) throws {
        let (model, repository) = try Self.makeModel(summary: Self.summary(total))
        #expect(!model.isStatementTotalOffered)
        #expect(!model.willAddStatementTotal)
        #expect(model.save())
        #expect(try repository.oneTimePayments().isEmpty)
        #expect(try repository.installments().count == 3)
        // Seçimi kaldırınca teklif geri gelir.
        for index in model.rows.indices { model.toggleSelection(at: index) }
        #expect(model.isStatementTotalOffered)
    }

    @Test("A remainder of one kuruş is still offered")
    func smallestRemainder() throws {
        let (model, _) = try Self.makeModel(summary: Self.summary("2084.57"))
        #expect(model.statementTotalRemainder?.amount == Self.dec("0.01"))
        #expect(model.isStatementTotalOffered)
    }

    @Test("Without a summary there is no offer and no breakdown")
    func noSummary() throws {
        let (model, repository) = try Self.makeModel(summary: nil)
        #expect(model.statementTotalRemainder == nil)
        #expect(model.statementTotalBreakdown == nil)
        #expect(model.statementDueDateText == nil)
        #expect(!model.isStatementTotalOffered)
        #expect(model.save())
        #expect(try repository.oneTimePayments().isEmpty)
    }

    // MARK: Kaydetme

    @Test("Nothing is saved before Add, whatever the user toggles")
    func nothingBeforeAdd() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, repository) = try Self.makeModel(cards: [a, b])
        model.toggleSelection(at: 0)
        model.toggleStatementTotal()
        model.toggleStatementTotal()
        model.cardID = b.id
        #expect(try repository.oneTimePayments().isEmpty)
        #expect(try repository.installments().isEmpty)
    }

    @Test("Add saves the installments and one one-time payment on the due date, on the chosen card")
    func saveBoth() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, repository) = try Self.makeModel(cards: [a, b], lastUsed: a.id)
        model.cardID = b.id
        model.toggleSelection(at: 1)
        #expect(model.save())
        #expect(try repository.installments().count == 2)
        let payments = try repository.oneTimePayments()
        #expect(payments.count == 1)
        let payment = try #require(payments.first)
        // 12.500 − (1234,56 + 400) = 10.865,44
        #expect(payment.amount.amount == Self.dec("10865.44"))
        #expect(payment.cardID == b.id)
        #expect(payment.dueMonth == Self.november)
        #expect(payment.dueDay == 2)
        #expect(payment.title == StatementReviewViewModel.statementTotalTitle)
    }

    @Test("Unselecting the statement total saves installments only")
    func statementTotalOptOut() throws {
        let (model, repository) = try Self.makeModel()
        model.toggleStatementTotal()
        #expect(!model.isStatementTotalSelected)
        #expect(!model.willAddStatementTotal)
        #expect(model.save())
        #expect(try repository.oneTimePayments().isEmpty)
        #expect(try repository.installments().count == 3)
    }

    @Test("The statement total alone can be added; with nothing at all Add is disabled")
    func statementTotalAlone() throws {
        let (model, repository) = try Self.makeModel()
        for index in model.rows.indices { model.toggleSelection(at: index) }
        #expect(model.selectedCount == 0)
        #expect(model.canSave)
        #expect(model.save())
        #expect(try repository.installments().isEmpty)
        #expect(try repository.oneTimePayments().first?.amount.amount == 12500)

        let (other, otherRepository) = try Self.makeModel()
        for index in other.rows.indices { other.toggleSelection(at: index) }
        other.toggleStatementTotal()
        #expect(!other.canSave)
        #expect(!other.save())
        #expect(try otherRepository.oneTimePayments().isEmpty)
    }

    @Test("An invalid selected row blocks the whole save, statement total included")
    func invalidRowBlocksAll() throws {
        let (model, repository) = try Self.makeModel()
        model.rows[0].amountText = ""
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
        #expect(try repository.oneTimePayments().isEmpty)
    }

    // MARK: Hepsi ya da hiçbiri

    private final class FailingStatementPayment: PaymentRepository, @unchecked Sendable {
        struct Failure: Error {}
        let inner = InMemoryPaymentRepository()
        func cards() throws -> [Card] { try inner.cards() }
        func save(_ card: Card) throws { try inner.save(card) }
        func deleteCard(id: Card.ID) throws { try inner.deleteCard(id: id) }
        func installments() throws -> [InstallmentItem] { try inner.installments() }
        func save(_ item: InstallmentItem) throws { try inner.save(item) }
        func deleteInstallment(id: InstallmentItem.ID) throws { try inner.deleteInstallment(id: id) }
        func subscriptions() throws -> [SubscriptionItem] { try inner.subscriptions() }
        func save(_ item: SubscriptionItem) throws { try inner.save(item) }
        func deleteSubscription(id: SubscriptionItem.ID) throws { try inner.deleteSubscription(id: id) }
        func oneTimePayments() throws -> [OneTimePaymentItem] { try inner.oneTimePayments() }
        func save(_ item: OneTimePaymentItem) throws { throw Failure() }
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws { try inner.deleteOneTimePayment(id: id) }
    }

    @Test("A failing statement payment removes the installments saved before it")
    func rollbackOnStatementPaymentFailure() throws {
        let repository = FailingStatementPayment()
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), summary: Self.summary(), repository: repository, todayMonth: Self.october,
            todayDay: 17, lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(!model.save())
        #expect(model.failureMessage != nil)
        #expect(try repository.installments().isEmpty)
        #expect(try repository.oneTimePayments().isEmpty)
    }

    private final class FailingSecondInstallment: PaymentRepository, @unchecked Sendable {
        struct Failure: Error {}
        let inner = InMemoryPaymentRepository()
        var saves = 0
        func cards() throws -> [Card] { try inner.cards() }
        func save(_ card: Card) throws { try inner.save(card) }
        func deleteCard(id: Card.ID) throws { try inner.deleteCard(id: id) }
        func installments() throws -> [InstallmentItem] { try inner.installments() }
        func save(_ item: InstallmentItem) throws {
            saves += 1
            if saves == 2 { throw Failure() }
            try inner.save(item)
        }
        func deleteInstallment(id: InstallmentItem.ID) throws { try inner.deleteInstallment(id: id) }
        func subscriptions() throws -> [SubscriptionItem] { try inner.subscriptions() }
        func save(_ item: SubscriptionItem) throws { try inner.save(item) }
        func deleteSubscription(id: SubscriptionItem.ID) throws { try inner.deleteSubscription(id: id) }
        func oneTimePayments() throws -> [OneTimePaymentItem] { try inner.oneTimePayments() }
        func save(_ item: OneTimePaymentItem) throws { try inner.save(item) }
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws { try inner.deleteOneTimePayment(id: id) }
    }

    @Test("A failing installment leaves no statement payment behind")
    func rollbackOnInstallmentFailure() throws {
        let repository = FailingSecondInstallment()
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), summary: Self.summary(), repository: repository, todayMonth: Self.october,
            todayDay: 17, lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
        #expect(try repository.oneTimePayments().isEmpty)
    }
}
