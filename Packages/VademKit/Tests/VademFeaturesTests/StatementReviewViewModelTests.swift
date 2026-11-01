import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

@MainActor
@Suite("StatementReviewViewModel")
struct StatementReviewViewModelTests {
    private static let october = YearMonth(year: 2026, month: 10)!
    private static let english = Locale(identifier: "en_US")

    private struct SaveFailingRepository: PaymentRepository {
        struct Failure: Error {}
        func cards() throws -> [Card] { [] }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { [] }
        func save(_ item: InstallmentItem) throws { throw Failure() }
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { [] }
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
        func oneTimePayments() throws -> [OneTimePaymentItem] { [] }
        func save(_ item: OneTimePaymentItem) throws {}
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws {}
    }

    private struct LoadFailingRepository: PaymentRepository {
        struct Failure: Error {}
        let failCards: Bool
        let saved = SavedBox()
        final class SavedBox: @unchecked Sendable { var count = 0 }
        func cards() throws -> [Card] { if failCards { throw Failure() }; return [] }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { if !failCards { throw Failure() }; return [] }
        func save(_ item: InstallmentItem) throws { saved.count += 1 }
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { [] }
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
        func oneTimePayments() throws -> [OneTimePaymentItem] { [] }
        func save(_ item: OneTimePaymentItem) throws {}
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws {}
    }

    private static func store(lastUsed: Card.ID? = nil) -> LastUsedCardStore {
        let name = "vadem.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = LastUsedCardStore(defaults: defaults)
        store.cardID = lastUsed
        return store
    }

    private static func card(_ name: String) -> Card {
        Card(id: UUID(), name: name, statementDay: 5, dueDay: 15)!
    }

    private static func candidates() -> [InstallmentCandidate] {
        [
            InstallmentCandidate(merchant: "ORNEK ELEKTRONIK", installmentAmount: Decimal(string: "1234.56")!, currentInstallment: 3, totalInstallments: 6),
            InstallmentCandidate(merchant: "ORNEK GIYIM", installmentAmount: 450, currentInstallment: 2, totalInstallments: 4),
            InstallmentCandidate(merchant: "LAPTOP", installmentAmount: 400, currentInstallment: 4, totalInstallments: 12),
        ]
    }

    private static func makeModel(
        candidates: [InstallmentCandidate] = candidates(),
        cards: [Card] = [],
        lastUsed: Card.ID? = nil,
        saved: [InstallmentItem] = [],
        todayDay: Int = 17,
        repository: InMemoryPaymentRepository = InMemoryPaymentRepository()
    ) throws -> (StatementReviewViewModel, InMemoryPaymentRepository, LastUsedCardStore) {
        for card in cards { try repository.save(card) }
        for item in saved { try repository.save(item) }
        let lastUsedStore = store(lastUsed: lastUsed)
        let model = StatementReviewViewModel(
            candidates: candidates, repository: repository, todayMonth: october, todayDay: todayDay,
            lastUsedCard: lastUsedStore, locale: english
        )
        return (model, repository, lastUsedStore)
    }

    // MARK: Başlangıç durumu

    @Test("Rows start selected, in statement order, with cleaned values")
    func initialRows() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.rows.count == 3)
        #expect(model.rows.allSatisfy { $0.isSelected })
        #expect(model.rows.map(\.title) == ["ORNEK ELEKTRONIK", "ORNEK GIYIM", "LAPTOP"])
        #expect(model.rows[0].amountText == "1234.56")
        #expect(model.rows[1].amountText == "450")
        #expect(model.rows.map(\.currentInstallment) == [3, 2, 4])
        #expect(model.rows.map(\.totalInstallments) == [6, 4, 12])
        #expect(model.selectedCount == 3)
        #expect(model.canSave)
    }

    @Test("Statement month starts at today's month and is among the options")
    func statementMonthDefault() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.statementMonth == Self.october)
        #expect(model.statementMonthOptions.contains(Self.october))
        #expect(model.statementMonthOptions.first == Self.october.adding(months: -StatementReviewViewModel.monthsBefore))
        #expect(model.statementMonthOptions.last == Self.october.adding(months: StatementReviewViewModel.monthsAfter))
    }

    @Test("Card defaults to the last used card")
    func defaultCardLastUsed() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, _, _) = try Self.makeModel(cards: [a, b], lastUsed: b.id)
        #expect(model.cardID == b.id)
        #expect(model.cardTitle == "Bonus")
    }

    @Test("Card falls back to the first card when none was used or the last one is gone")
    func defaultCardFallback() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        #expect(try Self.makeModel(cards: [a, b]).0.cardID == a.id)
        #expect(try Self.makeModel(cards: [a, b], lastUsed: UUID()).0.cardID == a.id)
    }

    @Test("Without cards the installments are card-less")
    func noCards() throws {
        let (model, repository, _) = try Self.makeModel()
        #expect(model.cardID == nil)
        #expect(model.save())
        #expect(try repository.installments().allSatisfy { $0.cardID == nil })
    }

    // MARK: Olası tekrar

    @Test("Possible duplicates start unselected")
    func duplicatesUnselected() throws {
        let card = Self.card("Akbank")
        let existing = InstallmentItem(
            title: "Ornek Giyim", cardID: card.id,
            plan: InstallmentPlan(total: Money(1800), count: 4, firstMonth: YearMonth(year: 2026, month: 9)!)!
        )!
        let (model, _, _) = try Self.makeModel(cards: [card], saved: [existing])
        #expect(model.rows.map(\.isSelected) == [true, false, true])
        #expect(model.isPossibleDuplicate(model.rows[1]))
        #expect(!model.isPossibleDuplicate(model.rows[0]))
        #expect(model.selectedCount == 2)
    }

    @Test("A saved plan on another card is not a duplicate")
    func otherCardNotDuplicate() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let existing = InstallmentItem(
            title: "ORNEK GIYIM", cardID: b.id,
            plan: InstallmentPlan(total: Money(1800), count: 4, firstMonth: Self.october)!
        )!
        let (model, _, _) = try Self.makeModel(cards: [a, b], lastUsed: a.id, saved: [existing])
        #expect(model.rows.allSatisfy { $0.isSelected })
    }

    // MARK: Düzenleme ve sayaç

    @Test("Toggling a row changes the selected count and the Add title")
    func toggle() throws {
        let (model, _, _) = try Self.makeModel()
        model.toggleSelection(at: 1)
        #expect(!model.rows[1].isSelected)
        #expect(model.selectedCount == 2)
        #expect(model.saveTitle.contains("2"))
        model.toggleSelection(at: 1)
        #expect(model.selectedCount == 3)
        #expect(model.saveTitle.contains("3"))
        // Geçersiz indeks sessizce yok sayılır.
        model.toggleSelection(at: 99)
        model.toggleSelection(at: -1)
        #expect(model.selectedCount == 3)
    }

    @Test("Nothing selected cannot be saved")
    func noneSelected() throws {
        let (model, repository, _) = try Self.makeModel()
        for index in model.rows.indices { model.toggleSelection(at: index) }
        #expect(model.selectedCount == 0)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
    }

    @Test("Total is clamped to the supported counts and lowers the current installment")
    func totalClamped() throws {
        let (model, _, _) = try Self.makeModel()
        model.setTotalInstallments(2, at: 0) // 3/6 → 2/2
        #expect(model.rows[0].totalInstallments == 2)
        #expect(model.rows[0].currentInstallment == 2)
        model.setTotalInstallments(100, at: 0)
        #expect(model.rows[0].totalInstallments == InstallmentPlan.supportedCounts.upperBound)
        model.setTotalInstallments(-5, at: 0)
        #expect(model.rows[0].totalInstallments == InstallmentPlan.supportedCounts.lowerBound)
        #expect(model.rows[0].currentInstallment == 1)
    }

    @Test("Current installment is clamped to 1...total")
    func currentClamped() throws {
        let (model, _, _) = try Self.makeModel()
        model.setCurrentInstallment(0, at: 0)
        #expect(model.rows[0].currentInstallment == 1)
        model.setCurrentInstallment(99, at: 0)
        #expect(model.rows[0].currentInstallment == 6)
        model.setCurrentInstallment(4, at: 0)
        #expect(model.rows[0].currentInstallment == 4)
    }

    @Test("Remaining installments and end month follow the row and the statement month")
    func remainingAndEnd() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.remainingInstallments(of: model.rows[0]) == 4) // 3/6
        #expect(model.endMonth(of: model.rows[0]) == YearMonth(year: 2027, month: 1)!)
        model.statementMonth = YearMonth(year: 2026, month: 9)!
        #expect(model.endMonth(of: model.rows[0]) == YearMonth(year: 2026, month: 12)!)
        model.setCurrentInstallment(6, at: 0)
        #expect(model.remainingInstallments(of: model.rows[0]) == 1)
        #expect(model.endMonth(of: model.rows[0]) == YearMonth(year: 2026, month: 9)!)
    }

    // MARK: Kaydetme

    @Test("Save adds only the selected rows, with the plan math, and returns true")
    func saveSelectedOnly() throws {
        let card = Self.card("Akbank")
        let (model, repository, _) = try Self.makeModel(cards: [card])
        model.toggleSelection(at: 1)
        #expect(model.save())
        let saved = try repository.installments()
        #expect(saved.count == 2)
        #expect(Set(saved.map(\.title)) == ["ORNEK ELEKTRONIK", "LAPTOP"])
        #expect(!saved.contains { $0.title == "ORNEK GIYIM" })
        let elektronik = try #require(saved.first { $0.title == "ORNEK ELEKTRONIK" })
        #expect(elektronik.cardID == card.id)
        // 3/6, ekstre Ekim 2026: Ağustos 2026 – Ocak 2027, toplam 1234,56 × 6.
        #expect(elektronik.plan.firstMonth == YearMonth(year: 2026, month: 8)!)
        #expect(elektronik.plan.lastMonth == YearMonth(year: 2027, month: 1)!)
        #expect(elektronik.plan.total.amount == Decimal(string: "7407.36")!)
        #expect(elektronik.plan.amount(in: Self.october).amount == Decimal(string: "1234.56")!)
        let laptop = try #require(saved.first { $0.title == "LAPTOP" })
        // 4/12 → Temmuz 2026'da başlar.
        #expect(laptop.plan.firstMonth == YearMonth(year: 2026, month: 7)!)
        #expect(laptop.plan.total.amount == 4800)
    }

    @Test("Changing the statement month moves every plan")
    func statementMonthMovesPlans() throws {
        let (model, repository, _) = try Self.makeModel()
        model.statementMonth = YearMonth(year: 2026, month: 9)!
        #expect(model.save())
        let elektronik = try #require(try repository.installments().first { $0.title == "ORNEK ELEKTRONIK" })
        #expect(elektronik.plan.firstMonth == YearMonth(year: 2026, month: 7)!)
    }

    @Test("Edits are saved: title, amount, counts")
    func editsSaved() throws {
        let (model, repository, _) = try Self.makeModel()
        model.rows[2].title = "  Yeni   Laptop "
        model.rows[2].amountText = "500"
        model.setTotalInstallments(6, at: 2)
        model.setCurrentInstallment(1, at: 2)
        #expect(model.save())
        let item = try #require(try repository.installments().first { $0.title == "Yeni Laptop" })
        #expect(item.plan.count == 6)
        #expect(item.plan.total.amount == 3000)
        #expect(item.plan.firstMonth == Self.october)
    }

    @Test("Save remembers the chosen card")
    func rememberCard() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, _, store) = try Self.makeModel(cards: [a, b])
        model.cardID = b.id
        #expect(model.save())
        #expect(store.cardID == b.id)
    }

    @Test("Card-less rows use today's day as the payment day")
    func cardlessPaymentDay() throws {
        let (model, repository, _) = try Self.makeModel(todayDay: 23)
        #expect(model.save())
        #expect(try repository.installments().allSatisfy { $0.paymentDay == 23 })
    }

    @Test("An invalid selected row saves nothing", arguments: ["", "abc", "0"])
    func invalidRowSavesNothing(amount: String) throws {
        let (model, repository, store) = try Self.makeModel(cards: [Self.card("Akbank")])
        model.rows[1].amountText = amount
        #expect(!model.isValid(model.rows[1]))
        #expect(model.errorMessage(for: model.rows[1]) != nil)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
        #expect(store.cardID == nil)
    }

    @Test("An invalid row that is unselected does not block saving")
    func invalidUnselectedRowIgnored() throws {
        let (model, repository, _) = try Self.makeModel()
        model.rows[1].amountText = "abc"
        model.toggleSelection(at: 1)
        #expect(model.canSave)
        #expect(model.save())
        #expect(try repository.installments().count == 2)
    }

    @Test("Empty title is an error for the row")
    func emptyTitleInvalid() throws {
        let (model, repository, _) = try Self.makeModel()
        model.rows[0].title = "   "
        #expect(model.errorMessage(for: model.rows[0]) != nil)
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
    }

    @Test("A valid row has no error message")
    func validRowNoError() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.rows.allSatisfy { model.errorMessage(for: $0) == nil })
    }

    @Test("Nothing is saved before save() is called (cancel saves nothing)")
    func cancelSavesNothing() throws {
        let (model, repository, store) = try Self.makeModel(cards: [Self.card("Akbank")])
        model.toggleSelection(at: 0)
        model.rows[1].title = "Degisti"
        model.cardID = nil
        #expect(try repository.installments().isEmpty)
        #expect(store.cardID == nil)
    }

    @Test("A repository failure saves nothing and sets a failure message")
    func repositoryFailure() throws {
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), repository: SaveFailingRepository(), todayMonth: Self.october,
            todayDay: 17, lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(!model.save())
        #expect(model.failureMessage != nil)
    }

    @Test("A mid-way failure removes the installments saved so far")
    func rollback() throws {
        final class FailingSecond: PaymentRepository, @unchecked Sendable {
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
        let repository = FailingSecond()
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), repository: repository, todayMonth: Self.october,
            todayDay: 17, lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
        #expect(model.failureMessage != nil)
    }

    @Test("Turkish locale uses a decimal comma in the amount text and parses it back")
    func turkishAmount() throws {
        let repository = InMemoryPaymentRepository()
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), repository: repository, todayMonth: Self.october, todayDay: 17,
            lastUsedCard: Self.store(), locale: Locale(identifier: "tr_TR")
        )
        #expect(model.rows[0].amountText == "1234,56")
        #expect(model.save())
        let item = try #require(try repository.installments().first { $0.title == "ORNEK ELEKTRONIK" })
        #expect(item.plan.amount(in: Self.october).amount == Decimal(string: "1234.56")!)
    }

    // MARK: Kart değişimi ve yükleme hatası (#216 düzeltmeleri)

    private static func savedGiyim(on card: Card) -> InstallmentItem {
        InstallmentItem(
            title: "Ornek Giyim", cardID: card.id,
            plan: InstallmentPlan(total: Money(1800), count: 4, firstMonth: YearMonth(year: 2026, month: 9)!)!
        )!
    }

    @Test("Changing the card to one with a duplicate unselects that row")
    func cardChangeBecomesDuplicate() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        // Kayıtlı plan b kartında; varsayılan kart a olduğundan satır başta seçili.
        let (model, _, _) = try Self.makeModel(cards: [a, b], lastUsed: a.id, saved: [Self.savedGiyim(on: b)])
        #expect(model.rows.map(\.isSelected) == [true, true, true])
        model.cardID = b.id
        #expect(model.isPossibleDuplicate(model.rows[1]))
        #expect(model.rows.map(\.isSelected) == [true, false, true])
    }

    @Test("Changing the card away from a duplicate selects that row")
    func cardChangeStopsBeingDuplicate() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, _, _) = try Self.makeModel(cards: [a, b], lastUsed: b.id, saved: [Self.savedGiyim(on: b)])
        #expect(model.rows.map(\.isSelected) == [true, false, true])
        model.cardID = a.id
        #expect(!model.isPossibleDuplicate(model.rows[1]))
        #expect(model.rows.map(\.isSelected) == [true, true, true])
    }

    @Test("Rows whose duplicate status does not change keep the manual choice on a card change")
    func cardChangeKeepsManualChoice() throws {
        let a = Self.card("Akbank"), b = Self.card("Bonus")
        let (model, _, _) = try Self.makeModel(cards: [a, b], lastUsed: a.id, saved: [Self.savedGiyim(on: b)])
        // Duplicate olmayan satır elle kapatılır; duplicate olan satırı kullanıcı bilerek seçer.
        model.toggleSelection(at: 0)
        model.cardID = nil
        // a -> nil: hiçbir satırın durumu değişmez (kayıt b kartında).
        #expect(model.rows.map(\.isSelected) == [false, true, true])
        model.cardID = b.id
        // Yalnızca satır 1 duplicate olur; satır 0 ve 2 olduğu gibi kalır.
        #expect(model.rows.map(\.isSelected) == [false, false, true])
        model.toggleSelection(at: 1)
        #expect(model.rows[1].isSelected)
        // Duplicate durumu değişmeyen kart değişimi (b -> b) seçimi bozmaz.
        model.cardID = b.id
        #expect(model.rows.map(\.isSelected) == [false, true, true])
    }

    @Test("A failed cards load disables saving and saves nothing")
    func cardsLoadFailure() {
        let repository = LoadFailingRepository(failCards: true)
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), repository: repository, todayMonth: Self.october, todayDay: 17,
            lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(model.failureMessage != nil)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(repository.saved.count == 0)
    }

    @Test("A failed installments load disables saving and saves nothing")
    func installmentsLoadFailure() {
        let repository = LoadFailingRepository(failCards: false)
        let model = StatementReviewViewModel(
            candidates: Self.candidates(), repository: repository, todayMonth: Self.october, todayDay: 17,
            lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(model.failureMessage != nil)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(repository.saved.count == 0)
    }

    @Test("Sample candidate 2 is a possible duplicate of the sample data's Laptop and starts unselected")
    func sampleCandidatesDuplicateLaptop() throws {
        let model = StatementReviewViewModel(
            candidates: StatementReviewView.sampleCandidates, repository: HomeSampleData.makeRepository(),
            todayMonth: Self.october, todayDay: 12, lastUsedCard: Self.store(), locale: Self.english
        )
        #expect(model.rows.count == 4)
        #expect(model.isPossibleDuplicate(model.rows[2]))
        #expect(model.rows.map(\.isSelected) == [true, true, false, true])
        #expect(!model.isPossibleDuplicate(model.rows[0]))
        #expect(!model.isPossibleDuplicate(model.rows[1]))
        #expect(!model.isPossibleDuplicate(model.rows[3]))
        #expect(model.selectedCount == 3)
    }
}
