import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("EditOneTimePaymentViewModel")
struct EditOneTimePaymentViewModelTests {
    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")

    private static func month(_ year: Int, _ month: Int) -> YearMonth {
        YearMonth(year: year, month: month)!
    }

    private struct FailingRepository: PaymentRepository {
        struct Failure: Error {}
        var item: OneTimePaymentItem
        func cards() throws -> [Card] { [] }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { [] }
        func save(_ item: InstallmentItem) throws {}
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { [] }
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
        func oneTimePayments() throws -> [OneTimePaymentItem] { [item] }
        func save(_ item: OneTimePaymentItem) throws { throw Failure() }
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws { throw Failure() }
    }

    private static func saved(
        in repository: InMemoryPaymentRepository, card: Card? = nil,
        due: YearMonth = month(2026, 11), day: Int = 20, amount: Decimal = 1500
    ) throws -> OneTimePaymentItem {
        if let card { try repository.save(card) }
        let item = try #require(OneTimePaymentItem(
            title: "Dentist", cardID: card?.id, amount: Money(amount), dueMonth: due, dueDay: day
        ))
        try repository.save(item)
        return item
    }

    @Test("Starts with the saved values and shows no error")
    func prefilled() throws {
        let repository = InMemoryPaymentRepository()
        let card = Card(id: UUID(), name: "Travel", statementDay: 5, dueDay: 15)!
        let item = try Self.saved(in: repository, card: card)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.title == "Dentist")
        #expect(model.cardID == card.id)
        #expect(model.amountText == "1500")
        #expect(model.dueMonth == Self.month(2026, 11))
        #expect(model.dueDay == 20)
        #expect(model.editingID == item.id)
        #expect(model.cards.map(\.id) == [card.id])
        #expect(model.monthOptions.contains(Self.month(2026, 11)))
        #expect(model.canSave)
        for field in OneTimePaymentDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("Payment without a card starts without a card")
    func noCard() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        #expect(model.cardID == nil)
    }

    @Test("Save replaces the payment under the same id")
    func saveReplaces() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        model.title = "Dentist Plus"
        model.amountText = "99.5"
        model.dueDay = 3
        #expect(model.save())
        let all = try repository.oneTimePayments()
        #expect(all.count == 1)
        #expect(all.first?.id == item.id)
        #expect(all.first?.title == "Dentist Plus")
        #expect(all.first?.amount == Money(Decimal(string: "99.5")!))
        #expect(all.first?.dueDay == 3)
    }

    @Test("Changing the card is saved; clearing it saves no card")
    func changeCard() throws {
        let repository = InMemoryPaymentRepository()
        let card = Card(id: UUID(), name: "Travel", statementDay: 5, dueDay: 15)!
        try repository.save(card)
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        model.cardID = card.id
        #expect(model.save())
        #expect(try repository.oneTimePayments().first?.cardID == card.id)
        model.cardID = nil
        #expect(model.save())
        #expect(try repository.oneTimePayments().first?.cardID == nil)
    }

    @Test("Changing to a shorter month clamps the due day", arguments: [
        (2026, 1, 31, 2026, 2, 28),
        (2028, 1, 31, 2028, 2, 29),
        (2026, 3, 31, 2026, 4, 30),
        (2026, 1, 15, 2026, 2, 15),
    ])
    func clampsDay(y: Int, m: Int, d: Int, ey: Int, em: Int, ed: Int) throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository, due: Self.month(y, m), day: d)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        model.dueMonth = Self.month(ey, em)
        #expect(model.dueDay == ed)
        #expect(model.canSave)
    }

    @Test("Invalid input disables Save; a failed save shows every error")
    func invalidShowsErrors() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        model.title = "   "
        model.amountText = ""
        #expect(!model.canSave)
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .amount) != nil)
        #expect(!model.save())
        #expect(try repository.oneTimePayments().first?.title == "Dentist")
    }

    @Test("Zero amount is invalid", arguments: ["0", "0.00", "-5"])
    func zeroAmount(text: String) throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        model.amountText = text
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repository.oneTimePayments().first?.amount == Money(1500))
    }

    @Test("Title over the maximum is invalid")
    func longTitle() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        model.title = String(repeating: "a", count: OneTimePaymentItem.maxTitleLength + 1)
        #expect(!model.canSave)
    }

    @Test("Errors appear only after a field changed")
    func errorsAfterTouch() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        #expect(model.errorMessage(for: .title) == nil)
        model.title = ""
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .amount) == nil)
        model.amountText = ""
        model.showAllErrors()
        #expect(model.errorMessage(for: .amount) != nil)
    }

    @Test("Delete removes only that payment")
    func deleteRemoves() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.saved(in: repository)
        let other = try #require(OneTimePaymentItem(
            title: "Tax", cardID: nil, amount: Money(10), dueMonth: Self.month(2026, 12), dueDay: 1
        ))
        try repository.save(other)
        let model = EditOneTimePaymentViewModel(repository: repository, editing: item, locale: Self.english)
        #expect(model.delete())
        #expect(try repository.oneTimePayments().map(\.id) == [other.id])
    }

    @Test("Repository failures set messages and return false")
    func failures() throws {
        let item = try #require(OneTimePaymentItem(
            title: "Dentist", cardID: nil, amount: Money(1500), dueMonth: Self.month(2026, 11), dueDay: 20
        ))
        let model = EditOneTimePaymentViewModel(
            repository: FailingRepository(item: item), editing: item, locale: Self.english
        )
        #expect(!model.save())
        #expect(model.failureMessage == EditOneTimePaymentViewModel.saveErrorMessage)
        #expect(!model.delete())
        #expect(model.failureMessage == EditOneTimePaymentViewModel.deleteErrorMessage)
    }
}
