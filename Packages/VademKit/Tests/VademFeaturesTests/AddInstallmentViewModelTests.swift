import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("AddInstallmentViewModel")
struct AddInstallmentViewModelTests {
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
        let card: Card
        func cards() throws -> [Card] { [card] }
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

    private static func card(_ name: String = "Bonus") -> Card {
        Card(id: UUID(), name: name, statementDay: 10, dueDay: 20)!
    }

    private static func makeModel(
        cards: [Card] = [card()], locale: Locale = turkish
    ) throws -> (AddInstallmentViewModel, InMemoryPaymentRepository) {
        let repository = InMemoryPaymentRepository()
        for card in cards { try repository.save(card) }
        return (AddInstallmentViewModel(repository: repository, initialMonth: october, locale: locale), repository)
    }

    private static func fillValid(_ model: AddInstallmentViewModel) {
        model.title = "Telefon"
        model.cardID = model.cards.first?.id
        model.amountText = "1200"
        model.count = 3
    }

    // MARK: Başlangıç durumu

    @Test("Starts empty, invalid and without visible errors")
    func initialState() throws {
        let (model, _) = try Self.makeModel()
        #expect(model.title.isEmpty)
        #expect(model.cardID == nil)
        #expect(model.amountText.isEmpty)
        #expect(model.firstMonth == Self.october)
        #expect(model.count == InstallmentPlan.supportedCounts.lowerBound)
        #expect(!model.canSave)
        #expect(model.failureMessage == nil)
        for field in InstallmentDraft.Field.allCases {
            #expect(model.errorMessage(for: field) == nil)
        }
    }

    @Test("Loads the cards of the repository")
    func loadsCards() throws {
        let a = Self.card("Axess"), b = Self.card("Bonus")
        let (model, _) = try Self.makeModel(cards: [b, a])
        #expect(model.cards == [a, b])
    }

    @Test("First month options contain the initial month, in order")
    func monthOptions() throws {
        let (model, _) = try Self.makeModel()
        #expect(model.firstMonthOptions.contains(Self.october))
        #expect(model.firstMonthOptions == model.firstMonthOptions.sorted())
        #expect(Set(model.firstMonthOptions).count == model.firstMonthOptions.count)
    }

    @Test("A card load failure sets the failure message")
    func cardsLoadFailure() {
        let model = AddInstallmentViewModel(repository: FailingRepository(), initialMonth: Self.october, locale: Self.turkish)
        #expect(model.failureMessage == AddInstallmentViewModel.cardsLoadErrorMessage)
        #expect(model.cards.isEmpty)
    }

    // MARK: Hatalar

    @Test("Errors show only for touched fields")
    func errorsAfterTouch() throws {
        let (model, _) = try Self.makeModel()
        model.title = "  "
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .amount) == nil)
        #expect(model.errorMessage(for: .card) == nil)
        model.title = "Telefon"
        #expect(model.errorMessage(for: .title) == nil)
    }

    @Test("showAllErrors shows every invalid field and no valid one")
    func showAllErrors() throws {
        let (model, _) = try Self.makeModel()
        model.showAllErrors()
        #expect(model.errorMessage(for: .title) != nil)
        // Kart artık isteğe bağlı: boş kart da, varsayılan ödeme günü de hata değildir.
        #expect(model.errorMessage(for: .card) == nil)
        #expect(model.errorMessage(for: .paymentDay) == nil)
        #expect(model.errorMessage(for: .amount) != nil)
        #expect(model.errorMessage(for: .count) == nil)
        #expect(model.errorMessage(for: .firstMonth) == nil)
    }

    @Test("Messages differ by error kind", arguments: [
        ("", "Enter an amount."),
        ("abc", "Enter a number like 1499,90."),
        ("0", "Amount must be greater than zero."),
        ("-5", "Amount must be greater than zero."),
    ])
    func amountMessages(text: String, message: String) throws {
        let (model, _) = try Self.makeModel(locale: Self.turkish)
        model.amountText = text
        #expect(model.errorMessage(for: .amount) == message)
    }

    @Test("Count out of range has a message", arguments: [0, 37])
    func countMessage(value: Int) throws {
        let (model, _) = try Self.makeModel()
        model.count = value
        #expect(model.errorMessage(for: .count) == "Choose 1 to 36 installments.")
        #expect(!model.canSave)
    }

    @Test("The card is optional: no card never shows a card error, with or without saved cards")
    func cardIsOptional() throws {
        for cards in [[Self.card()], []] {
            let (model, _) = try Self.makeModel(cards: cards)
            model.showAllErrors()
            #expect(model.cardID == nil)
            #expect(model.errorMessage(for: .card) == nil)
        }
    }

    @Test("A payment day outside 1 to 31 without a card has a message", arguments: [0, -1, 32, 100])
    func paymentDayMessage(day: Int) throws {
        let (model, _) = try Self.makeModel()
        model.paymentDay = day
        #expect(model.errorMessage(for: .paymentDay) == "Choose a payment day from 1 to 31.")
        #expect(!model.canSave)
    }

    @Test("An out-of-range payment day is ignored while a card is chosen")
    func paymentDayIgnoredWithCard() throws {
        let (model, repository) = try Self.makeModel()
        Self.fillValid(model)
        model.paymentDay = 99
        #expect(model.errorMessage(for: .paymentDay) == nil)
        #expect(model.canSave)
        #expect(model.save())
        #expect(try repository.installments().first?.paymentDay == nil)
    }

    @Test("A user with no cards can save an installment on a payment day")
    func saveWithoutAnyCard() throws {
        let (model, repository) = try Self.makeModel(cards: [])
        model.title = "Telefon"
        model.amountText = "1200"
        model.count = 3
        model.paymentDay = 17
        #expect(model.cards.isEmpty)
        #expect(model.canSave)
        #expect(model.save())
        let stored = try #require(try repository.installments().first)
        #expect(try repository.installments().count == 1)
        #expect(stored.cardID == nil)
        #expect(stored.paymentDay == 17)
    }

    @Test("The payment day starts at the given initial day")
    func initialPaymentDay() {
        let model = AddInstallmentViewModel(
            repository: InMemoryPaymentRepository(), initialMonth: Self.october, initialPaymentDay: 9, locale: Self.turkish
        )
        #expect(model.paymentDay == 9)
    }

    @Test("Editing a card-less installment loads its payment day and can move it to a card")
    func editCardless() throws {
        let (_, repository) = try Self.makeModel(cards: [])
        let plan = try #require(InstallmentPlan(total: Money(600), count: 3, firstMonth: Self.october))
        let item = try #require(InstallmentItem(title: "Okul", cardID: nil, paymentDay: 23, plan: plan))
        try repository.save(item)
        let model = AddInstallmentViewModel(repository: repository, editing: item, locale: Self.turkish)
        #expect(model.cardID == nil)
        #expect(model.paymentDay == 23)
        model.paymentDay = 30
        #expect(model.save())
        #expect(try repository.installments().first?.paymentDay == 30)
        #expect(try repository.installments().first?.id == item.id)
    }

    @Test("Title longer than the limit has a message")
    func titleTooLong() throws {
        let (model, _) = try Self.makeModel()
        model.title = String(repeating: "x", count: InstallmentItem.maxTitleLength + 1)
        #expect(model.errorMessage(for: .title) == "Use at most 60 characters.")
    }

    // MARK: Tutar ayrıştırma

    @Test("Parses amounts with the locale's decimal separator", arguments: [
        ("1499,90", "tr_TR", "1499.90" as String?),
        ("1499", "tr_TR", "1499"),
        (" 1499,5 ", "tr_TR", "1499.5"),
        (",5", "tr_TR", "0.5"),
        ("1499.90", "tr_TR", nil),
        ("1.499,90", "tr_TR", nil),
        ("1499.90", "en_US", "1499.90"),
        ("1499,90", "en_US", nil),
        ("1,499.90", "en_US", nil),
        ("0,0", "tr_TR", "0"),
        ("-12,5", "tr_TR", "-12.5"),
        ("", "tr_TR", nil),
        ("   ", "tr_TR", nil),
        (",", "tr_TR", nil),
        ("12,3,4", "tr_TR", nil),
        ("12a", "tr_TR", nil),
        ("1e5", "tr_TR", nil),
    ])
    func parseAmount(text: String, locale: String, expected: String?) {
        let result = AddInstallmentViewModel.parseAmount(text, locale: Locale(identifier: locale))
        #expect(result == expected.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
    }

    @Test("Integer part is limited to 12 digits, leading zeros counted", arguments: [
        ("999999999999", "tr_TR", "999999999999" as String?),
        ("999999999999,99", "tr_TR", "999999999999.99"),
        ("999999999999.99", "en_US", "999999999999.99"),
        ("000000000001", "tr_TR", "1"),
        ("-999999999999", "tr_TR", "-999999999999"),
        ("1000000000000", "tr_TR", nil),
        ("1000000000000,50", "tr_TR", nil),
        ("1000000000000.50", "en_US", nil),
        ("0000000000001", "tr_TR", nil),
        ("0000000000001,5", "tr_TR", nil),
        ("0000000000001.5", "en_US", nil),
        ("-1000000000000", "tr_TR", nil),
        (String(repeating: "9", count: 40), "tr_TR", nil),
    ])
    func parseAmountDigitLimit(text: String, locale: String, expected: String?) {
        #expect(AddInstallmentViewModel.maxIntegerDigits == 12)
        let result = AddInstallmentViewModel.parseAmount(text, locale: Locale(identifier: locale))
        #expect(result == expected.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
    }

    @Test("Fraction part is limited to 6 digits, trailing zeros counted", arguments: [
        ("1,123456", "tr_TR", "1.123456" as String?),
        ("1,1234567", "tr_TR", nil),
        ("1,1000000", "tr_TR", nil),
        ("1,100000", "tr_TR", "1.1"),
        ("10,005", "tr_TR", "10.005"),
        ("1.123456", "en_US", "1.123456"),
        ("1.1234567", "en_US", nil),
        ("1.0000000", "en_US", nil),
        ("10.005", "en_US", "10.005"),
    ])
    func parseAmountFractionLimit(text: String, locale: String, expected: String?) {
        #expect(AddInstallmentViewModel.maxFractionDigits == 6)
        let result = AddInstallmentViewModel.parseAmount(text, locale: Locale(identifier: locale))
        #expect(result == expected.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
    }

    @Test("Over-long amount shows the number error and blocks saving", arguments: [
        ("tr_TR", "1000000000000,50", "Enter a number like 1499,90."),
        ("en_US", "1000000000000.50", "Enter a number like 1499.90."),
        ("tr_TR", "0000000000001", "Enter a number like 1499,90."),
    ])
    func overLongAmountError(locale: String, text: String, message: String) throws {
        let (model, repository) = try Self.makeModel(locale: Locale(identifier: locale))
        Self.fillValid(model)
        model.amountText = text
        #expect(model.errorMessage(for: .amount) == message)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
    }

    @Test("Amount of 12 digits is accepted by the form")
    func twelveDigitAmountSaves() throws {
        let (model, _) = try Self.makeModel()
        Self.fillValid(model)
        model.amountText = "999999999999,99"
        #expect(model.errorMessage(for: .amount) == nil)
        #expect(model.canSave)
    }

    @Test("Amount typed in Turkish becomes the exact decimal in the draft")
    func draftAmountIsExact() throws {
        let (model, _) = try Self.makeModel()
        model.amountText = "1499,90"
        #expect(model.draft.total == Decimal(string: "1499.90"))
    }

    // MARK: canSave ve save

    @Test("canSave becomes true only when every field is valid")
    func canSave() throws {
        let (model, _) = try Self.makeModel()
        model.title = "Telefon"
        #expect(!model.canSave)
        model.cardID = model.cards.first?.id
        #expect(!model.canSave)
        model.amountText = "1200"
        #expect(model.canSave)
        model.title = "   "
        #expect(!model.canSave)
    }

    @Test("Saving a valid form stores the installment")
    func saveValid() throws {
        let (model, repository) = try Self.makeModel()
        Self.fillValid(model)
        model.count = 4
        #expect(model.save())
        let stored = try #require(try repository.installments().first)
        #expect(try repository.installments().count == 1)
        #expect(stored.title == "Telefon")
        #expect(stored.cardID == model.cards.first?.id)
        #expect(stored.plan.total == Money(1200))
        #expect(stored.plan.count == 4)
        #expect(stored.plan.firstMonth == Self.october)
        #expect(model.failureMessage == nil)
    }

    @Test("Saving an invalid form stores nothing, returns false and shows all errors")
    func saveInvalid() throws {
        let (model, repository) = try Self.makeModel()
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
        #expect(model.errorMessage(for: .title) != nil)
        #expect(model.errorMessage(for: .card) == nil)
        #expect(model.errorMessage(for: .amount) != nil)
    }

    @Test("A repository failure on save sets the failure message and returns false")
    func saveFailure() {
        let card = Self.card()
        let model = AddInstallmentViewModel(repository: SaveFailingRepository(card: card), initialMonth: Self.october, locale: Self.turkish)
        Self.fillValid(model)
        #expect(model.canSave)
        #expect(!model.save())
        #expect(model.failureMessage == AddInstallmentViewModel.saveErrorMessage)
    }

    // MARK: Home ile bütünleşme

    @Test("Home makes a form that starts at its selected month and shares the repository")
    func homeIntegration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let repository = InMemoryPaymentRepository()
        let card = Self.card()
        try repository.save(card)
        let home = HomeViewModel(repository: repository, today: today, calendar: calendar)
        #expect(home.total == .zero)

        home.showNextMonth()
        let form = home.makeAddInstallmentModel(locale: Self.turkish)
        #expect(form.firstMonth == YearMonth(year: 2026, month: 11))
        #expect(form.cards == [card])

        form.title = "Telefon"
        form.cardID = card.id
        form.amountText = "1200"
        form.count = 3
        #expect(form.save())
        home.reload()
        // 1200 / 3 = 400, ilk taksit gösterilen ayda.
        #expect(home.month == YearMonth(year: 2026, month: 11))
        #expect(home.total == Money(400))
        #expect(home.rows.count == 1)
        home.showNextMonth()
        #expect(home.total == Money(400))
        home.showPreviousMonth()
        home.showPreviousMonth()
        #expect(home.total == .zero)
    }
}
