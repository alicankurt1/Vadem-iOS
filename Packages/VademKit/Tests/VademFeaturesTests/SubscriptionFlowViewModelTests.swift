import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("SubscriptionFlowViewModel")
struct SubscriptionFlowViewModelTests {
    private static let october = YearMonth(year: 2026, month: 10)!
    private static let english = Locale(identifier: "en_US")
    private static let turkish = Locale(identifier: "tr_TR")

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

    private static func card(_ name: String) -> Card {
        Card(id: UUID(), name: name, statementDay: 10, dueDay: 20)!
    }

    private static func make(
        cards: [Card] = [],
        lastUsed: Card.ID? = nil,
        start: SubscriptionFlowStep = .amount,
        amount: Decimal? = nil,
        renewalDay: Int = 17,
        locale: Locale = english,
        onSaved: @escaping (Card.ID?) -> Void = { _ in }
    ) throws -> (SubscriptionFlowViewModel, InMemoryPaymentRepository) {
        let repository = InMemoryPaymentRepository()
        for card in cards { try repository.save(card) }
        let form = AddSubscriptionViewModel(
            repository: repository, initialMonth: october, initialRenewalDay: renewalDay, locale: locale
        )
        let model = SubscriptionFlowViewModel(
            form: form, start: start, lastUsedCardID: lastUsed, amount: amount, locale: locale, onSaved: onSaved
        )
        return (model, repository)
    }

    private static func type(_ text: String, into model: SubscriptionFlowViewModel) {
        for character in text {
            if let digit = character.wholeNumberValue {
                model.keypad.press(.digit(digit))
            } else {
                model.keypad.press(.decimalSeparator)
            }
        }
    }

    // MARK: Adım sırası

    @Test("Steps are amount, period, card, title, summary in that order")
    func stepOrder() {
        #expect(SubscriptionFlowStep.allCases == [.amount, .period, .card, .title, .summary])
    }

    @Test("Launch arguments are -ui-add-subscription-flow-<step>", arguments: [
        (SubscriptionFlowStep.amount, "-ui-add-subscription-flow-amount"),
        (SubscriptionFlowStep.period, "-ui-add-subscription-flow-period"),
        (SubscriptionFlowStep.card, "-ui-add-subscription-flow-card"),
        (SubscriptionFlowStep.title, "-ui-add-subscription-flow-title"),
        (SubscriptionFlowStep.summary, "-ui-add-subscription-flow-summary"),
    ])
    func launchArguments(step: SubscriptionFlowStep, expected: String) {
        #expect(step.launchArgument == expected)
        #expect(SubscriptionFlowStep.step(in: ["-ui-sample-data", expected]) == step)
    }

    @Test("No flow argument gives no step")
    func noArgument() {
        #expect(SubscriptionFlowStep.step(in: []) == nil)
        #expect(SubscriptionFlowStep.step(in: ["-ui-sample-data", "-ui-add-sheet"]) == nil)
    }

    @Test("Flow starts on the amount step and walks through every step in order")
    func walksInOrder() throws {
        let (model, _) = try Self.make()
        #expect(model.step == .amount)
        Self.type("5", into: model)
        model.advance()
        #expect(model.step == .period)
        model.choose(period: .yearly)
        #expect(model.step == .card)
        model.choose(cardID: nil)
        #expect(model.step == .title)
        model.skipTitle()
        #expect(model.step == .summary)
    }

    @Test("Starts at the requested step")
    func startsAtStep() throws {
        let (model, _) = try Self.make(start: .card, amount: 10)
        #expect(model.step == .card)
        #expect(model.steps.number == 3)
        #expect(model.steps.count == 5)
    }

    // MARK: Tutar

    @Test("Amount step cannot continue without a positive amount", arguments: [
        "", "0", "0.0", "0.00",
    ])
    func amountRequired(text: String) throws {
        let (model, _) = try Self.make()
        Self.type(text, into: model)
        #expect(!model.canContinueAmount)
        model.advance()
        #expect(model.step == .amount)
    }

    @Test("A positive amount continues; the keypad text is written to the form")
    func amountContinues() throws {
        let (model, _) = try Self.make()
        Self.type("149.9", into: model)
        #expect(model.canContinueAmount)
        #expect(model.form.amountText == "149.9")
        model.advance()
        #expect(model.step == .period)
    }

    @Test("Starting amount fills the keypad and the form")
    func startingAmount() throws {
        let (model, _) = try Self.make(amount: Decimal(14990) / 100)
        #expect(model.canContinueAmount)
        #expect(model.keypad.amount == Decimal(string: "149.9"))
        #expect(model.form.draft.amount == Decimal(string: "149.9"))
    }

    @Test("Deleting the typed amount disables continue again")
    func deleteAmount() throws {
        let (model, _) = try Self.make()
        Self.type("7", into: model)
        #expect(model.canContinueAmount)
        model.keypad.press(.delete)
        #expect(!model.canContinueAmount)
        #expect(model.form.amountText.isEmpty)
    }

    @Test("Turkish locale keypad types the comma the form parses")
    func turkishSeparator() throws {
        let (model, repository) = try Self.make(locale: Self.turkish)
        Self.type("12,5", into: model)
        #expect(model.form.draft.amount == Decimal(string: "12.5"))
        #expect(model.save())
        #expect(try repository.subscriptions().first?.subscription.amount == Money(Decimal(string: "12.5")!))
    }

    // MARK: Dönem

    @Test("Period defaults to monthly; choosing stores it and advances", arguments: [
        Subscription.Period.monthly, .yearly,
    ])
    func choosePeriod(period: Subscription.Period) throws {
        let (model, _) = try Self.make(start: .period, amount: 10)
        #expect(model.form.period == .monthly)
        model.choose(period: period)
        #expect(model.form.period == period)
        #expect(model.step == .card)
    }

    // MARK: Kart

    @Test("Last used card is preselected")
    func preselectsLastUsed() throws {
        let first = Self.card("Bonus"), second = Self.card("World")
        let (model, _) = try Self.make(cards: [first, second], lastUsed: second.id)
        #expect(model.form.cardID == second.id)
        #expect(model.cardTitle == "World")
    }

    @Test("No last used card, or a deleted one, selects No card", arguments: [false, true])
    func noCardPreselected(deletedCard: Bool) throws {
        let first = Self.card("Bonus")
        let (model, _) = try Self.make(cards: [first], lastUsed: deletedCard ? UUID() : nil)
        #expect(model.form.cardID == nil)
        #expect(model.cardTitle != "Bonus")
        #expect(!model.cardTitle.isEmpty)
    }

    @Test("Choosing No card clears the preselected card and advances")
    func chooseNoCard() throws {
        let first = Self.card("Bonus")
        let (model, _) = try Self.make(cards: [first], lastUsed: first.id, start: .card, amount: 10)
        model.choose(cardID: nil)
        #expect(model.form.cardID == nil)
        #expect(model.step == .title)
    }

    @Test("Choosing a card stores it and advances")
    func chooseCard() throws {
        let first = Self.card("Bonus"), second = Self.card("World")
        let (model, _) = try Self.make(cards: [first, second], start: .card, amount: 10)
        model.choose(cardID: second.id)
        #expect(model.form.cardID == second.id)
        #expect(model.step == .title)
    }

    @Test("A new card is added to the list and selected; the step does not advance")
    func newCard() throws {
        let first = Self.card("Bonus")
        let added = Self.card("Fresh")
        let (model, _) = try Self.make(cards: [first], start: .card, amount: 10)
        model.didAddCard(added)
        #expect(model.cards.map(\.name) == ["Bonus", "Fresh"])
        #expect(model.form.cardID == added.id)
        #expect(model.step == .card)
        // Aynı kart ikinci kez eklenmez.
        model.didAddCard(added)
        #expect(model.cards.count == 2)
    }

    // MARK: Başlık

    @Test("Empty title is saved as the default title", arguments: ["", "   ", "\n"])
    func defaultTitle(raw: String) throws {
        let (model, repository) = try Self.make(amount: 10)
        model.form.title = raw
        #expect(model.effectiveTitle == SubscriptionFlowViewModel.defaultTitle)
        #expect(model.canSave)
        #expect(model.save())
        #expect(try repository.subscriptions().first?.title == SubscriptionFlowViewModel.defaultTitle)
    }

    @Test("Default title is not empty")
    func defaultTitleNotEmpty() {
        #expect(!SubscriptionFlowViewModel.defaultTitle.isEmpty)
    }

    @Test("Quick titles are six distinct, non-empty chips")
    func quickTitles() {
        let titles = SubscriptionFlowViewModel.quickTitles
        #expect(titles.count == 6)
        #expect(Set(titles).count == 6)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }

    @Test("Choosing a quick title stores it and advances to the summary")
    func chooseTitle() throws {
        let (model, repository) = try Self.make(start: .title, amount: 10)
        let chip = try #require(SubscriptionFlowViewModel.quickTitles.first)
        model.choose(title: chip)
        #expect(model.step == .summary)
        #expect(model.effectiveTitle == chip)
        #expect(model.save())
        #expect(try repository.subscriptions().first?.title == chip)
    }

    @Test("Skip clears a previous title, advances and saves the default title")
    func skip() throws {
        let (model, repository) = try Self.make(start: .title, amount: 10)
        model.form.title = "Old"
        model.skipTitle()
        #expect(model.form.title.isEmpty)
        #expect(model.step == .summary)
        #expect(model.save())
        #expect(try repository.subscriptions().first?.title == SubscriptionFlowViewModel.defaultTitle)
    }

    // MARK: Yenileme günü

    @Test("Renewal day starts at the form's initial value (today) and can change", arguments: [1, 17, 31])
    func renewalDay(day: Int) throws {
        let (model, repository) = try Self.make(amount: 10, renewalDay: day)
        #expect(model.form.renewalDay == day)
        #expect(!model.isChangingRenewalDay)
        model.isChangingRenewalDay = true
        model.form.renewalDay = 5
        #expect(model.save())
        #expect(try repository.subscriptions().first?.subscription.renewalDay == 5)
    }

    @Test("Unchanged renewal day is saved as today's day")
    func renewalDayDefaultSaved() throws {
        let (model, repository) = try Self.make(amount: 10, renewalDay: 23)
        #expect(model.save())
        #expect(try repository.subscriptions().first?.subscription.renewalDay == 23)
        #expect(try repository.subscriptions().first?.subscription.firstMonth == Self.october)
    }

    // MARK: Gezinme

    @Test("Back returns to the previous step and reports false on the first step")
    func goBack() throws {
        let (model, _) = try Self.make(start: .card, amount: 10)
        #expect(model.goBack())
        #expect(model.step == .period)
        #expect(model.goBack())
        #expect(model.step == .amount)
        #expect(!model.goBack())
        #expect(model.step == .amount)
    }

    @Test("Going back keeps earlier choices")
    func backKeepsChoices() throws {
        let (model, _) = try Self.make(start: .period, amount: 10)
        model.choose(period: .yearly)
        model.goBack()
        #expect(model.form.period == .yearly)
        #expect(model.form.amountText.isEmpty == false)
    }

    // MARK: Kayıt: formla aynı doğrulama ve sonuç

    @Test("Saved result equals what the existing form stores for the same inputs")
    func sameResultAsForm() throws {
        let bonus = Self.card("Bonus")
        let (model, flowRepository) = try Self.make(cards: [bonus], lastUsed: bonus.id)
        Self.type("149.9", into: model)
        model.advance()
        model.choose(period: .yearly)
        model.choose(cardID: bonus.id)
        model.choose(title: "Music")
        model.isChangingRenewalDay = true
        model.form.renewalDay = 9
        #expect(model.save())

        let formRepository = InMemoryPaymentRepository()
        try formRepository.save(bonus)
        let form = AddSubscriptionViewModel(
            repository: formRepository, initialMonth: Self.october, initialRenewalDay: 17, locale: Self.english
        )
        form.title = "Music"
        form.amountText = "149.9"
        form.period = .yearly
        form.cardID = bonus.id
        form.renewalDay = 9
        #expect(form.save())

        let flowItem = try #require(try flowRepository.subscriptions().first)
        let formItem = try #require(try formRepository.subscriptions().first)
        #expect(flowItem.title == formItem.title)
        #expect(flowItem.cardID == formItem.cardID)
        #expect(flowItem.subscription == formItem.subscription)
        // Elle hesaplanan beklenen değerler.
        #expect(flowItem.title == "Music")
        #expect(flowItem.cardID == bonus.id)
        #expect(flowItem.subscription.amount == Money(Decimal(string: "149.9")!))
        #expect(flowItem.subscription.period == .yearly)
        #expect(flowItem.subscription.renewalDay == 9)
        #expect(flowItem.subscription.firstMonth == Self.october)
    }

    @Test("Only the amount typed: save works with defaults (monthly, no card, default title)")
    func onlyAmount() throws {
        let (model, repository) = try Self.make(renewalDay: 12)
        Self.type("99", into: model)
        model.advance()
        model.advance()
        model.advance()
        model.advance()
        #expect(model.step == .summary)
        #expect(model.canSave)
        #expect(model.save())
        let stored = try #require(try repository.subscriptions().first)
        #expect(try repository.subscriptions().count == 1)
        #expect(stored.title == SubscriptionFlowViewModel.defaultTitle)
        #expect(stored.cardID == nil)
        #expect(stored.subscription.amount == Money(99))
        #expect(stored.subscription.period == .monthly)
        #expect(stored.subscription.renewalDay == 12)
    }

    @Test("Without an amount the draft is invalid, cannot save, and nothing is stored")
    func invalidWithoutAmount() throws {
        let (model, repository) = try Self.make()
        #expect(!model.canSave)
        #expect(!model.draft.isValid)
        #expect(!model.save())
        #expect(try repository.subscriptions().isEmpty)
    }

    @Test("Draft carries the effective title")
    func draftTitle() throws {
        let (model, _) = try Self.make(amount: 10)
        #expect(model.draft.title == SubscriptionFlowViewModel.defaultTitle)
        model.form.title = "  Gym  "
        #expect(model.draft.title == "Gym")
    }

    @Test("onSaved gets the chosen card after a successful save, and not after a failed one")
    func onSavedCallback() throws {
        let bonus = Self.card("Bonus")
        var reported: [Card.ID?] = []
        let (model, _) = try Self.make(cards: [bonus], lastUsed: bonus.id, amount: 10) { reported.append($0) }
        #expect(model.save())
        #expect(reported == [bonus.id])

        var failedReports = 0
        let form = AddSubscriptionViewModel(
            repository: InMemoryPaymentRepository(), initialMonth: Self.october, locale: Self.english
        )
        let invalid = SubscriptionFlowViewModel(form: form, lastUsedCardID: nil, locale: Self.english) { _ in failedReports += 1 }
        #expect(!invalid.save())
        #expect(failedReports == 0)
    }

    @Test("onSaved gets nil for No card")
    func onSavedNoCard() throws {
        var reported: [Card.ID?] = []
        let (model, _) = try Self.make(amount: 10) { reported.append($0) }
        #expect(model.save())
        #expect(reported.count == 1)
        #expect(reported.first == .some(nil))
    }

    @Test("A repository failure returns false, sets the form's failure message and does not call onSaved")
    func saveFailure() {
        var called = false
        let form = AddSubscriptionViewModel(
            repository: SaveFailingRepository(), initialMonth: Self.october, locale: Self.english
        )
        let model = SubscriptionFlowViewModel(form: form, lastUsedCardID: nil, amount: 10, locale: Self.english) { _ in called = true }
        #expect(model.canSave)
        #expect(!model.save())
        #expect(model.form.failureMessage == AddSubscriptionViewModel.saveErrorMessage)
        #expect(!called)
    }

    @Test("Home makes a flow on its repository with today's renewal day; saving updates the last used card")
    func homeIntegration() throws {
        let repository = InMemoryPaymentRepository()
        let bonus = Self.card("Bonus")
        try repository.save(bonus)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let home = HomeViewModel(repository: repository, today: today, calendar: calendar)
        let flow = home.makeSubscriptionFlowModel(amount: 10, locale: Self.english)
        #expect(flow.form.renewalDay == 14)
        #expect(flow.form.firstMonth == Self.october)
        flow.choose(cardID: bonus.id)
        #expect(flow.save())
        #expect(home.lastUsedCardID == bonus.id)
        // Sonraki akışta son kullanılan kart seçili gelir.
        let next = home.makeSubscriptionFlowModel(amount: 10, locale: Self.english)
        #expect(next.form.cardID == bonus.id)
    }
}
