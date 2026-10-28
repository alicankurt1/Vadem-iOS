import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("AddCardViewModel")
struct AddCardViewModelTests {
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
        func oneTimePayments() throws -> [OneTimePaymentItem] { throw Failure() }
        func save(_ item: OneTimePaymentItem) throws { throw Failure() }
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws { throw Failure() }
    }

    private static func fill(_ model: AddCardViewModel, name: String = "Bonus", statement: String = "10", due: String = "20") {
        model.name = name
        model.statementDayText = statement
        model.dueDayText = due
    }

    @Test("Starts empty: Save disabled, no errors shown")
    func initialState() {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        #expect(!model.canSave)
        #expect(model.savedCard == nil)
        #expect(model.failureMessage == nil)
        for field in CardDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("Save is enabled once all fields are valid")
    func canSaveWhenValid() {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        Self.fill(model)
        #expect(model.canSave)
    }

    @Test("Save stays disabled for each invalid field", arguments: [
        ("", "10", "20"), ("   ", "10", "20"),
        ("Bonus", "0", "20"), ("Bonus", "32", "20"), ("Bonus", "abc", "20"), ("Bonus", "", "20"),
        ("Bonus", "10", "0"), ("Bonus", "10", "32"), ("Bonus", "10", ""),
        (String(repeating: "a", count: Card.maxNameLength + 1), "10", "20"),
    ])
    func cannotSaveInvalid(_ values: (String, String, String)) {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        Self.fill(model, name: values.0, statement: values.1, due: values.2)
        #expect(!model.canSave)
    }

    @Test("An error shows under a field only after it was changed")
    func errorsAppearAfterEditing() {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        model.name = " "
        #expect(model.errorMessage(for: .name) != nil)
        #expect(model.errorMessage(for: .statementDay) == nil)
        #expect(model.errorMessage(for: .dueDay) == nil)
        model.statementDayText = "40"
        #expect(model.errorMessage(for: .statementDay) != nil)
    }

    @Test("A valid field shows no message")
    func validFieldNoMessage() {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        Self.fill(model)
        for field in CardDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("showAllErrors reveals every invalid field")
    func showAllErrors() {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        model.showAllErrors()
        for field in CardDraft.Field.allCases {
            #expect(model.errorMessage(for: field) != nil)
        }
    }

    @Test("Name errors differ between empty and too long")
    func nameMessagesDiffer() {
        let model = AddCardViewModel(repository: InMemoryPaymentRepository())
        model.name = ""
        let empty = model.errorMessage(for: .name)
        model.name = String(repeating: "a", count: Card.maxNameLength + 1)
        let tooLong = model.errorMessage(for: .name)
        #expect(empty != nil && tooLong != nil && empty != tooLong)
    }

    @Test("Saving stores a trimmed card in the repository")
    func savesCard() throws {
        let repository = InMemoryPaymentRepository()
        let model = AddCardViewModel(repository: repository)
        Self.fill(model, name: "  Bonus ", statement: " 28 ", due: "8")
        #expect(model.save())
        let stored = try repository.cards()
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Bonus")
        #expect(stored.first?.statementDay == 28)
        #expect(stored.first?.dueDay == 8)
        #expect(model.savedCard == stored.first)
        #expect(model.failureMessage == nil)
    }

    @Test("Saving an invalid form stores nothing and shows all errors")
    func invalidSaveShowsErrors() throws {
        let repository = InMemoryPaymentRepository()
        let model = AddCardViewModel(repository: repository)
        #expect(!model.save())
        #expect(try repository.cards().isEmpty)
        #expect(model.savedCard == nil)
        for field in CardDraft.Field.allCases {
            #expect(model.errorMessage(for: field) != nil)
        }
    }

    @Test("A repository error sets the failure message and no saved card")
    func saveFailure() {
        let model = AddCardViewModel(repository: FailingRepository())
        Self.fill(model)
        #expect(!model.save())
        #expect(model.failureMessage == AddCardViewModel.saveErrorMessage)
        #expect(model.savedCard == nil)
    }

    @Test("parseDay accepts ASCII digits only", arguments: [
        ("28", 28), (" 8 ", 8), ("007", 7), ("0", 0), ("99", 99),
    ])
    func parseDayValid(_ pair: (String, Int)) {
        #expect(AddCardViewModel.parseDay(pair.0) == pair.1)
    }

    @Test("parseDay rejects non-numbers", arguments: [
        "", "  ", "abc", "-1", "+5", "1.5", "1 2", "٣", "99999999999999999999",
    ])
    func parseDayInvalid(_ text: String) {
        #expect(AddCardViewModel.parseDay(text) == nil)
    }

    // MARK: Entegrasyon: Home ve ekleme formu

    @Test("Installment form shows and selects a card added from its card list")
    func installmentFormSelectsAddedCard() throws {
        let repository = InMemoryPaymentRepository()
        let form = AddInstallmentViewModel(
            repository: repository, initialMonth: YearMonth(year: 2026, month: 10)!, locale: Locale(identifier: "en_US")
        )
        #expect(form.cards.isEmpty)
        let cardModel = form.makeAddCardModel()
        Self.fill(cardModel)
        #expect(cardModel.save())
        let saved = try #require(cardModel.savedCard)
        form.selectAddedCard(saved)
        #expect(form.cards == [saved])
        #expect(form.cardID == saved.id)
    }

    @Test("Home sees a new card after reload without relaunching")
    func homeSeesNewCard() throws {
        let repository = InMemoryPaymentRepository()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let home = HomeViewModel(repository: repository, today: today, calendar: calendar)
        home.reload()
        #expect(!home.hasCards)
        let cardModel = home.makeAddCardModel()
        Self.fill(cardModel)
        #expect(cardModel.save())
        home.reload()
        #expect(home.hasCards)
    }
}
