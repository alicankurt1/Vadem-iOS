import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

// Düzenleme kipi (#67): ön doldurma, doğrulama, aynı id ile kayıt, silme ve hata yolları.
// SwiftUI yok; yalnızca görünüm modelleri ve bellek içi depo.
@MainActor
@Suite("Edit mode view models")
struct EditModeViewModelTests {
    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")

    /// Okumalar çalışır, yazma ve silme hep hata verir.
    private struct WriteFailingRepository: PaymentRepository {
        struct Failure: Error {}
        var storedCards: [Card] = []
        var storedInstallments: [InstallmentItem] = []
        var storedSubscriptions: [SubscriptionItem] = []
        func cards() throws -> [Card] { storedCards }
        func save(_ card: Card) throws { throw Failure() }
        func deleteCard(id: Card.ID) throws { throw Failure() }
        func installments() throws -> [InstallmentItem] { storedInstallments }
        func save(_ item: InstallmentItem) throws { throw Failure() }
        func deleteInstallment(id: InstallmentItem.ID) throws { throw Failure() }
        func subscriptions() throws -> [SubscriptionItem] { storedSubscriptions }
        func save(_ item: SubscriptionItem) throws { throw Failure() }
        func deleteSubscription(id: SubscriptionItem.ID) throws { throw Failure() }
    }

    /// Hiçbir okuma çalışmaz.
    private struct ReadFailingRepository: PaymentRepository {
        struct Failure: Error {}
        func cards() throws -> [Card] { throw Failure() }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { throw Failure() }
        func save(_ item: InstallmentItem) throws {}
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { throw Failure() }
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
    }

    // MARK: Taksit

    private static func savedInstallment(
        in repository: InMemoryPaymentRepository
    ) throws -> (InstallmentItem, Card) {
        let card = try Fixture.card("Bonus")
        try repository.save(card)
        let plan = try Fixture.plan(total: Decimal(string: "1499.90")!, count: 6, first: Fixture.month(2026, 7))
        let item = try Fixture.installment("Telefon", card: card.id, plan: plan)
        try repository.save(item)
        return (item, card)
    }

    @Test("Installment edit form starts with the saved values and no errors")
    func installmentPrefill() throws {
        let repository = InMemoryPaymentRepository()
        let (item, card) = try Self.savedInstallment(in: repository)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.isEditing)
        #expect(model.editingID == item.id)
        #expect(model.title == "Telefon")
        #expect(model.cardID == card.id)
        #expect(model.amountText == "1499,9")
        #expect(model.count == 6)
        #expect(model.firstMonth == (try Fixture.month(2026, 7)))
        #expect(model.firstMonthOptions.contains(model.firstMonth))
        #expect(model.cards == [card])
        #expect(model.canSave)
        #expect(model.failureMessage == nil)
        for field in InstallmentDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("New installment form is not in edit mode and delete does nothing")
    func installmentAddModeHasNoDelete() throws {
        let repository = InMemoryPaymentRepository()
        let (item, _) = try Self.savedInstallment(in: repository)
        let model = AddInstallmentViewModel(
            repository: repository, initialMonth: try Fixture.month(2026, 10), locale: Self.turkish
        )
        #expect(!model.isEditing)
        #expect(model.editingID == nil)
        #expect(!model.delete())
        #expect(try repository.installments() == [item])
    }

    @Test("Saving an edited installment replaces it under the same id")
    func installmentSaveSameID() throws {
        let repository = InMemoryPaymentRepository()
        let (item, card) = try Self.savedInstallment(in: repository)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.title = "Yeni telefon"
        model.amountText = "3000"
        model.count = 3
        #expect(model.save())
        let stored = try repository.installments()
        #expect(stored.count == 1)
        let saved = try #require(stored.first)
        #expect(saved.id == item.id)
        #expect(saved.title == "Yeni telefon")
        #expect(saved.cardID == card.id)
        #expect(saved.plan.total.amount == 3000)
        #expect(saved.plan.count == 3)
        #expect(saved.plan.firstMonth == item.plan.firstMonth)
        #expect(model.failureMessage == nil)
    }

    @Test("Saving an unchanged installment keeps it equal")
    func installmentSaveUnchanged() throws {
        let repository = InMemoryPaymentRepository()
        let (item, _) = try Self.savedInstallment(in: repository)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.save())
        #expect(try repository.installments() == [item])
    }

    @Test("Prefill round trips the amount in both locales")
    func installmentAmountRoundTrip() throws {
        for locale in [Self.turkish, Self.english] {
            let repository = InMemoryPaymentRepository()
            let (item, _) = try Self.savedInstallment(in: repository)
            let model = AddInstallmentViewModel(repository: repository, editing: item, locale: locale)
            #expect(model.draft.total == item.plan.total.amount)
            #expect(model.save())
            #expect(try repository.installments() == [item])
        }
    }

    @Test("Installment edit validates like the add form and does not save when invalid")
    func installmentValidation() throws {
        let repository = InMemoryPaymentRepository()
        let (item, _) = try Self.savedInstallment(in: repository)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.title = "   "
        #expect(!model.canSave)
        #expect(model.errorMessage(for: .title) == "Enter a title.")
        model.amountText = "0"
        #expect(model.errorMessage(for: .amount) == "Amount must be greater than zero.")
        #expect(!model.save())
        #expect(try repository.installments() == [item])
    }

    @Test("Installment edit shows other errors only after a failed save")
    func installmentErrorsAfterFailedSave() throws {
        let repository = InMemoryPaymentRepository()
        let (item, _) = try Self.savedInstallment(in: repository)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.amountText = ""
        #expect(model.errorMessage(for: .title) == nil)
        model.title = ""
        #expect(!model.save())
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .amount) != nil)
    }

    @Test("Deleting an installment removes it from the repository")
    func installmentDelete() throws {
        let repository = InMemoryPaymentRepository()
        let (item, card) = try Self.savedInstallment(in: repository)
        let other = try Fixture.installment("Diğer", card: card.id)
        try repository.save(other)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.delete())
        #expect(try repository.installments() == [other])
        #expect(model.failureMessage == nil)
    }

    @Test("A failing save or delete of an installment sets the failure message")
    func installmentWriteErrors() throws {
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id)
        let repository = WriteFailingRepository(storedCards: [card], storedInstallments: [item])
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(!model.save())
        #expect(model.failureMessage == AddInstallmentViewModel.saveErrorMessage)
        #expect(!model.delete())
        #expect(model.failureMessage == AddInstallmentViewModel.deleteErrorMessage)
    }

    @Test("Installment edit form reports a cards load error")
    func installmentCardsLoadError() throws {
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id)
        let model = AddInstallmentViewModel(repository: ReadFailingRepository(), editing: item, locale: Self.turkish)
        #expect(model.failureMessage == AddInstallmentViewModel.cardsLoadErrorMessage)
        #expect(model.title == item.title)
    }

    // MARK: Abonelik

    private static func savedSubscription(
        in repository: InMemoryPaymentRepository, lastMonth: YearMonth? = nil, card: Bool = true
    ) throws -> SubscriptionItem {
        var cardID: Card.ID?
        if card {
            let saved = try Fixture.card("Axess")
            try repository.save(saved)
            cardID = saved.id
        }
        let subscription = try #require(Subscription(
            amount: Money(Decimal(string: "149.90")!), period: .yearly, renewalDay: 17,
            firstMonth: Fixture.month(2026, 3), lastMonth: lastMonth
        ))
        let item = try Fixture.subscriptionItem("Müzik", card: cardID, subscription: subscription)
        try repository.save(item)
        return item
    }

    @Test("Subscription edit form starts with the saved values and no errors")
    func subscriptionPrefill() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.isEditing)
        #expect(model.editingID == item.id)
        #expect(model.title == "Müzik")
        #expect(model.cardID == item.cardID)
        #expect(model.amountText == "149,9")
        #expect(model.period == .yearly)
        #expect(model.renewalDay == 17)
        #expect(model.firstMonth == (try Fixture.month(2026, 3)))
        #expect(model.firstMonthOptions.contains(model.firstMonth))
        #expect(model.canSave)
        for field in SubscriptionDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("Subscription without a card is prefilled without a card")
    func subscriptionPrefillWithoutCard() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository, card: false)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.cardID == nil)
        #expect(model.canSave)
    }

    @Test("Saving an edited subscription replaces it under the same id")
    func subscriptionSaveSameID() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.title = "Film"
        model.amountText = "50"
        model.period = .monthly
        model.renewalDay = 5
        model.cardID = nil
        #expect(model.save())
        let stored = try repository.subscriptions()
        #expect(stored.count == 1)
        let saved = try #require(stored.first)
        #expect(saved.id == item.id)
        #expect(saved.title == "Film")
        #expect(saved.cardID == nil)
        #expect(saved.subscription.amount.amount == 50)
        #expect(saved.subscription.period == .monthly)
        #expect(saved.subscription.renewalDay == 5)
    }

    @Test("Saving an unchanged subscription keeps it equal")
    func subscriptionSaveUnchanged() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.english)
        #expect(model.save())
        #expect(try repository.subscriptions() == [item])
    }

    @Test("Last month is kept on save while it is not before the first month")
    func subscriptionKeepsLastMonth() throws {
        let repository = InMemoryPaymentRepository()
        let last = try Fixture.month(2027, 3)
        let item = try Self.savedSubscription(in: repository, lastMonth: last)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.title = "Yeni ad"
        #expect(model.save())
        #expect(try repository.subscriptions().first?.subscription.lastMonth == last)
    }

    @Test("Last month is dropped when the new first month would be after it")
    func subscriptionDropsInvalidLastMonth() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository, lastMonth: try Fixture.month(2026, 5))
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.firstMonth = try Fixture.month(2026, 8)
        #expect(model.save())
        let saved = try #require(try repository.subscriptions().first)
        #expect(saved.id == item.id)
        #expect(saved.subscription.firstMonth == (try Fixture.month(2026, 8)))
        #expect(saved.subscription.lastMonth == nil)
    }

    @Test("Subscription edit validates like the add form and does not save when invalid", arguments: ["", "0", "-5", "abc"])
    func subscriptionValidation(amount: String) throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.amountText = amount
        #expect(!model.canSave)
        #expect(model.errorMessage(for: .amount) != nil)
        #expect(!model.save())
        #expect(try repository.subscriptions() == [item])
    }

    @Test("Subscription edit rejects an empty title")
    func subscriptionEmptyTitle() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        model.title = ""
        #expect(model.errorMessage(for: .title) == "Enter a title.")
        #expect(!model.save())
    }

    @Test("Deleting a subscription removes it from the repository")
    func subscriptionDelete() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.delete())
        #expect(try repository.subscriptions().isEmpty)
        #expect(model.failureMessage == nil)
    }

    @Test("Subscription delete outside edit mode does nothing")
    func subscriptionAddModeHasNoDelete() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let model = AddSubscriptionViewModel(
            repository: repository, initialMonth: try Fixture.month(2026, 10), locale: Self.turkish
        )
        #expect(!model.isEditing)
        #expect(!model.delete())
        #expect(try repository.subscriptions() == [item])
    }

    @Test("A failing save or delete of a subscription sets the failure message")
    func subscriptionWriteErrors() throws {
        let item = try Fixture.subscriptionItem(card: nil)
        let repository = WriteFailingRepository(storedSubscriptions: [item])
        let model = AddSubscriptionViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(!model.save())
        #expect(model.failureMessage == AddSubscriptionViewModel.saveErrorMessage)
        #expect(!model.delete())
        #expect(model.failureMessage == AddSubscriptionViewModel.deleteErrorMessage)
    }

    // MARK: Kart

    @Test("Card edit form starts with the saved values and no errors")
    func cardPrefill() throws {
        let card = try #require(Card(id: UUID(), name: "Bonus", statementDay: 28, dueDay: 8))
        let model = AddCardViewModel(repository: InMemoryPaymentRepository(), editing: card)
        #expect(model.isEditing)
        #expect(model.editingID == card.id)
        #expect(model.name == "Bonus")
        #expect(model.statementDayText == "28")
        #expect(model.dueDayText == "8")
        #expect(model.canSave)
        for field in CardDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("New card form is not in edit mode and delete does nothing")
    func cardAddModeHasNoDelete() throws {
        let repository = InMemoryPaymentRepository()
        let card = try Fixture.card()
        try repository.save(card)
        let model = AddCardViewModel(repository: repository)
        #expect(!model.isEditing)
        #expect(!model.delete())
        #expect(try repository.cards() == [card])
    }

    @Test("Saving an edited card replaces it under the same id and keeps its payments")
    func cardSaveSameID() throws {
        let repository = InMemoryPaymentRepository()
        let (item, card) = try Self.savedInstallment(in: repository)
        let model = AddCardViewModel(repository: repository, editing: card)
        model.name = "Yeni ad"
        model.statementDayText = "3"
        model.dueDayText = "31"
        #expect(model.save())
        let stored = try repository.cards()
        #expect(stored.count == 1)
        #expect(stored.first?.id == card.id)
        #expect(stored.first?.name == "Yeni ad")
        #expect(stored.first?.statementDay == 3)
        #expect(stored.first?.dueDay == 31)
        #expect(model.savedCard == stored.first)
        #expect(try repository.installments() == [item])
    }

    @Test("Card edit validates like the add form", arguments: [
        ("", "10", "20"), ("Bonus", "0", "20"), ("Bonus", "32", "20"),
        ("Bonus", "10", "0"), ("Bonus", "10", "32"), ("Bonus", "x", "20"),
    ])
    func cardValidation(name: String, statement: String, due: String) throws {
        let repository = InMemoryPaymentRepository()
        let card = try Fixture.card()
        try repository.save(card)
        let model = AddCardViewModel(repository: repository, editing: card)
        model.name = name
        model.statementDayText = statement
        model.dueDayText = due
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(model.savedCard == nil)
        #expect(try repository.cards() == [card])
    }

    @Test("Deleting an unused card removes it")
    func cardDeleteUnused() throws {
        let repository = InMemoryPaymentRepository()
        let card = try Fixture.card()
        try repository.save(card)
        let model = AddCardViewModel(repository: repository, editing: card)
        #expect(model.delete())
        #expect(try repository.cards().isEmpty)
        #expect(model.failureMessage == nil)
    }

    @Test("Deleting a card used by an installment is refused with the in-use message")
    func cardDeleteInUseByInstallment() throws {
        let repository = InMemoryPaymentRepository()
        let (_, card) = try Self.savedInstallment(in: repository)
        let model = AddCardViewModel(repository: repository, editing: card)
        #expect(!model.delete())
        #expect(model.failureMessage == AddCardViewModel.cardInUseMessage)
        #expect(try repository.cards() == [card])
    }

    @Test("Deleting a card used by a subscription is refused with the in-use message")
    func cardDeleteInUseBySubscription() throws {
        let repository = InMemoryPaymentRepository()
        let item = try Self.savedSubscription(in: repository)
        let card = try #require(try repository.cards().first)
        #expect(item.cardID == card.id)
        let model = AddCardViewModel(repository: repository, editing: card)
        #expect(!model.delete())
        #expect(model.failureMessage == AddCardViewModel.cardInUseMessage)
        #expect(try repository.cards() == [card])
    }

    @Test("The in-use message differs from the generic delete error")
    func cardMessagesDiffer() {
        #expect(AddCardViewModel.cardInUseMessage != AddCardViewModel.deleteErrorMessage)
        #expect(!AddCardViewModel.cardInUseMessage.isEmpty)
    }

    @Test("A card can be deleted after its payments are gone, and the failure clears")
    func cardDeleteAfterRelease() throws {
        let repository = InMemoryPaymentRepository()
        let (item, card) = try Self.savedInstallment(in: repository)
        let model = AddCardViewModel(repository: repository, editing: card)
        #expect(!model.delete())
        try repository.deleteInstallment(id: item.id)
        #expect(model.delete())
        #expect(model.failureMessage == nil)
        #expect(try repository.cards().isEmpty)
    }

    @Test("Other repository errors on card save and delete use their own messages")
    func cardWriteErrors() throws {
        let card = try Fixture.card()
        let model = AddCardViewModel(repository: WriteFailingRepository(storedCards: [card]), editing: card)
        #expect(!model.save())
        #expect(model.failureMessage == AddCardViewModel.saveErrorMessage)
        #expect(!model.delete())
        #expect(model.failureMessage == AddCardViewModel.deleteErrorMessage)
    }

    // MARK: Home fabrikaları

    private static func homeModel(_ repository: any PaymentRepository) -> HomeViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        return HomeViewModel(repository: repository, today: today, calendar: calendar)
    }

    @Test("Home builds edit models for saved installments, subscriptions and cards")
    func homeEditFactories() throws {
        let repository = InMemoryPaymentRepository()
        let (installment, card) = try Self.savedInstallment(in: repository)
        let subscription = try Self.savedSubscription(in: repository, card: false)
        let home = Self.homeModel(repository)

        let installmentModel = try #require(home.makeEditInstallmentModel(id: installment.id, locale: Self.turkish))
        #expect(installmentModel.editingID == installment.id)
        #expect(installmentModel.title == "Telefon")

        let subscriptionModel = try #require(home.makeEditSubscriptionModel(id: subscription.id, locale: Self.turkish))
        #expect(subscriptionModel.editingID == subscription.id)
        #expect(subscriptionModel.title == "Müzik")

        let cardModel = try #require(home.makeEditCardModel(id: card.id))
        #expect(cardModel.editingID == card.id)
        #expect(cardModel.name == "Bonus")
    }

    @Test("Home edit factories return nil for unknown ids")
    func homeEditFactoriesUnknownID() throws {
        let repository = InMemoryPaymentRepository()
        _ = try Self.savedInstallment(in: repository)
        let home = Self.homeModel(repository)
        let unknown = UUID()
        #expect(home.makeEditInstallmentModel(id: unknown) == nil)
        #expect(home.makeEditSubscriptionModel(id: unknown) == nil)
        #expect(home.makeEditCardModel(id: unknown) == nil)
    }

    @Test("Home edit factories do not mix kinds")
    func homeEditFactoriesDoNotMixKinds() throws {
        let repository = InMemoryPaymentRepository()
        let (installment, card) = try Self.savedInstallment(in: repository)
        let home = Self.homeModel(repository)
        #expect(home.makeEditSubscriptionModel(id: installment.id) == nil)
        #expect(home.makeEditCardModel(id: installment.id) == nil)
        #expect(home.makeEditInstallmentModel(id: card.id) == nil)
    }

    @Test("Home edit factories return nil when the repository cannot be read")
    func homeEditFactoriesReadError() {
        let home = Self.homeModel(ReadFailingRepository())
        let id = UUID()
        #expect(home.makeEditInstallmentModel(id: id) == nil)
        #expect(home.makeEditSubscriptionModel(id: id) == nil)
        #expect(home.makeEditCardModel(id: id) == nil)
    }

    @Test("Home shows an edited and removes a deleted installment after reload")
    func homeReloadAfterEditAndDelete() throws {
        let repository = InMemoryPaymentRepository()
        let (item, _) = try Self.savedInstallment(in: repository)
        let home = Self.homeModel(repository)
        home.select(month: try Fixture.month(2026, 10))

        let edit = try #require(home.makeEditInstallmentModel(id: item.id, locale: Self.turkish))
        edit.title = "Tablet"
        #expect(edit.save())
        home.reload()
        #expect(home.rows.contains { $0.title == "Tablet" })
        #expect(!home.rows.contains { $0.title == "Telefon" })

        let again = try #require(home.makeEditInstallmentModel(id: item.id, locale: Self.turkish))
        #expect(again.delete())
        home.reload()
        #expect(home.rows.isEmpty)
        #expect(home.makeEditInstallmentModel(id: item.id) == nil)
    }
}
