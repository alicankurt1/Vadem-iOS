import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("AddSubscriptionViewModel")
struct AddSubscriptionViewModelTests {
    private static let october = YearMonth(year: 2026, month: 10)!
    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")

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

    /// Kaydı reddeden, kartları okuyabilen depo.
    private struct SaveFailingRepository: PaymentRepository {
        struct Failure: Error {}
        func cards() throws -> [Card] { [] }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { [] }
        func save(_ item: InstallmentItem) throws {}
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { [] }
        func save(_ item: SubscriptionItem) throws { throw Failure() }
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
        func oneTimePayments() throws -> [OneTimePaymentItem] { [] }
        func save(_ item: OneTimePaymentItem) throws { throw Failure() }
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws {}
    }

    private static func card(_ name: String = "Bonus") -> Card {
        Card(id: UUID(), name: name, statementDay: 10, dueDay: 20)!
    }

    private static func makeModel(
        cards: [Card] = [card()], locale: Locale = turkish
    ) throws -> (AddSubscriptionViewModel, InMemoryPaymentRepository) {
        let repository = InMemoryPaymentRepository()
        for card in cards { try repository.save(card) }
        return (AddSubscriptionViewModel(repository: repository, initialMonth: october, locale: locale), repository)
    }

    private static func fillValid(_ model: AddSubscriptionViewModel) {
        model.title = "Müzik"
        model.amountText = "149,90"
    }

    // MARK: Başlangıç durumu

    @Test("Starts empty, invalid and without visible errors")
    func initialState() throws {
        let (model, _) = try Self.makeModel()
        #expect(model.title.isEmpty)
        #expect(model.cardID == nil)
        #expect(model.amountText.isEmpty)
        #expect(model.period == .monthly)
        #expect(model.firstMonth == Self.october)
        #expect(model.renewalDay == Subscription.supportedRenewalDays.lowerBound)
        #expect(!model.canSave)
        #expect(model.failureMessage == nil)
        for field in SubscriptionDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("Loads the cards of the repository, sorted")
    func loadsCards() throws {
        let a = Self.card("Axess"), b = Self.card("Bonus")
        let (model, _) = try Self.makeModel(cards: [b, a])
        #expect(model.cards == [a, b])
    }

    @Test("First month options contain the initial month, in order, without duplicates")
    func monthOptions() throws {
        let (model, _) = try Self.makeModel()
        #expect(model.firstMonthOptions.contains(Self.october))
        #expect(model.firstMonthOptions == model.firstMonthOptions.sorted())
        #expect(Set(model.firstMonthOptions).count == model.firstMonthOptions.count)
    }

    @Test("A card load failure sets the failure message")
    func cardsLoadFailure() {
        let model = AddSubscriptionViewModel(repository: FailingRepository(), initialMonth: Self.october, locale: Self.turkish)
        #expect(model.failureMessage == AddSubscriptionViewModel.cardsLoadErrorMessage)
        #expect(model.cards.isEmpty)
    }

    // MARK: Hatalar

    @Test("Errors show only for touched fields")
    func errorsAfterTouch() throws {
        let (model, _) = try Self.makeModel()
        model.title = "  "
        #expect(model.errorMessage(for: .title) == "Enter a title.")
        #expect(model.errorMessage(for: .amount) == nil)
        model.title = "Müzik"
        #expect(model.errorMessage(for: .title) == nil)
    }

    @Test("showAllErrors shows every invalid field and no valid one, and the card is never an error")
    func showAllErrors() throws {
        let (model, _) = try Self.makeModel()
        model.showAllErrors()
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .amount) != nil)
        #expect(model.errorMessage(for: .card) == nil)
        #expect(model.errorMessage(for: .period) == nil)
        #expect(model.errorMessage(for: .renewalDay) == nil)
        #expect(model.errorMessage(for: .firstMonth) == nil)
    }

    @Test("Amount messages differ by error kind", arguments: [
        ("", "Enter an amount."),
        ("abc", "Enter a number like 1499,90."),
        ("0", "Amount must be greater than zero."),
        ("-5", "Amount must be greater than zero."),
    ])
    func amountMessages(text: String, message: String) throws {
        let (model, _) = try Self.makeModel(locale: Self.turkish)
        model.amountText = text
        #expect(model.errorMessage(for: .amount) == message)
        #expect(!model.canSave)
    }

    @Test("Renewal day out of range has a message and blocks saving", arguments: [0, 32, -3])
    func renewalDayMessage(value: Int) throws {
        let (model, _) = try Self.makeModel()
        Self.fillValid(model)
        model.renewalDay = value
        #expect(model.errorMessage(for: .renewalDay) == "Choose a renewal day from 1 to 31.")
        #expect(!model.canSave)
    }

    @Test("Title longer than the limit has a message")
    func titleTooLong() throws {
        let (model, _) = try Self.makeModel()
        model.title = String(repeating: "x", count: SubscriptionItem.maxTitleLength + 1)
        #expect(model.errorMessage(for: .title) == "Use at most \(SubscriptionItem.maxTitleLength) characters.")
        #expect(!model.canSave)
    }

    @Test("Amount typed in Turkish becomes the exact decimal in the draft")
    func draftAmountIsExact() throws {
        let (model, _) = try Self.makeModel()
        model.amountText = "149,90"
        #expect(model.draft.amount == Decimal(string: "149.90"))
        let (english, _) = try Self.makeModel(locale: Self.english)
        english.amountText = "149.90"
        #expect(english.draft.amount == Decimal(string: "149.90"))
    }

    @Test("Period titles", arguments: [(Subscription.Period.monthly, "Monthly"), (.yearly, "Yearly")])
    func periodTitles(period: Subscription.Period, title: String) {
        #expect(AddSubscriptionViewModel.title(of: period) == title)
        #expect(AddSubscriptionViewModel.periods.contains(period))
    }

    // MARK: canSave ve save

    @Test("canSave is true with a title and an amount; the card is optional")
    func canSave() throws {
        let (model, _) = try Self.makeModel()
        model.title = "Müzik"
        #expect(!model.canSave)
        model.amountText = "149,90"
        #expect(model.canSave)
        model.title = "   "
        #expect(!model.canSave)
    }

    @Test("Saving without a card stores the subscription")
    func saveWithoutCard() throws {
        let (model, repository) = try Self.makeModel(cards: [])
        Self.fillValid(model)
        model.period = .yearly
        model.renewalDay = 31
        #expect(model.save())
        let stored = try #require(try repository.subscriptions().first)
        #expect(try repository.subscriptions().count == 1)
        #expect(stored.title == "Müzik")
        #expect(stored.cardID == nil)
        #expect(stored.subscription.amount == Money(Decimal(string: "149.90")!))
        #expect(stored.subscription.period == .yearly)
        #expect(stored.subscription.renewalDay == 31)
        #expect(stored.subscription.firstMonth == Self.october)
        #expect(model.failureMessage == nil)
    }

    @Test("Saving with a card stores the card id")
    func saveWithCard() throws {
        let (model, repository) = try Self.makeModel()
        Self.fillValid(model)
        model.cardID = model.cards.first?.id
        #expect(model.save())
        #expect(try repository.subscriptions().first?.cardID == model.cards.first?.id)
    }

    @Test("Saving an invalid form stores nothing, returns false and shows all errors")
    func saveInvalid() throws {
        let (model, repository) = try Self.makeModel()
        #expect(!model.save())
        #expect(try repository.subscriptions().isEmpty)
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .amount) != nil)
    }

    @Test("An unknown card is rejected by the repository: false, failure message, nothing stored")
    func saveUnknownCard() throws {
        let (model, repository) = try Self.makeModel(cards: [])
        Self.fillValid(model)
        model.cardID = UUID()
        #expect(model.canSave)
        #expect(!model.save())
        #expect(model.failureMessage == AddSubscriptionViewModel.saveErrorMessage)
        #expect(try repository.subscriptions().isEmpty)
    }

    @Test("A repository failure on save sets the failure message and returns false")
    func saveFailure() {
        let model = AddSubscriptionViewModel(repository: SaveFailingRepository(), initialMonth: Self.october, locale: Self.turkish)
        Self.fillValid(model)
        #expect(model.canSave)
        #expect(!model.save())
        #expect(model.failureMessage == AddSubscriptionViewModel.saveErrorMessage)
    }

    // MARK: Home ile bütünleşme

    @Test("Home makes a form at its selected month; a saved subscription shows after reload in every applicable month")
    func homeIntegration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let repository = InMemoryPaymentRepository()
        let home = HomeViewModel(repository: repository, today: today, calendar: calendar)
        #expect(home.total == .zero)

        home.showNextMonth()
        let form = home.makeAddSubscriptionModel(locale: Self.turkish)
        #expect(form.firstMonth == YearMonth(year: 2026, month: 11))

        form.title = "Müzik"
        form.amountText = "100"
        #expect(form.save())
        home.reload()
        #expect(home.month == YearMonth(year: 2026, month: 11))
        #expect(home.total == Money(100))
        #expect(home.rows.count == 1)
        home.showNextMonth()
        #expect(home.total == Money(100))
        home.showPreviousMonth()
        home.showPreviousMonth()
        // Başlangıç ayından önce ödeme yok.
        #expect(home.total == .zero)
    }
}
