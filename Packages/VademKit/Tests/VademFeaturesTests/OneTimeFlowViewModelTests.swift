import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("OneTimeFlowViewModel")
struct OneTimeFlowViewModelTests {
    private static let english = Locale(identifier: "en_US")

    private static func month(_ year: Int, _ month: Int) -> YearMonth {
        YearMonth(year: year, month: month)!
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
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
        func oneTimePayments() throws -> [OneTimePaymentItem] { [] }
        func save(_ item: OneTimePaymentItem) throws { throw Failure() }
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws {}
    }

    private static func freshStore() -> LastUsedCardStore {
        // Her test kendi temiz UserDefaults paketini kullanır.
        let name = "vadem.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return LastUsedCardStore(defaults: defaults)
    }

    private static func card(_ name: String) -> Card {
        Card(id: UUID(), name: name, statementDay: 10, dueDay: 20)!
    }

    private static func make(
        cards: [Card] = [],
        lastUsed: Card.ID? = nil,
        todayMonth: YearMonth = month(2026, 10),
        todayDay: Int = 12,
        start: OneTimeFlowStep = .amount,
        amount: Decimal? = nil,
        repository: (any PaymentRepository)? = nil,
        store: LastUsedCardStore = freshStore()
    ) throws -> (OneTimeFlowViewModel, any PaymentRepository, LastUsedCardStore) {
        let repo: any PaymentRepository = repository ?? InMemoryPaymentRepository()
        for card in cards { try repo.save(card) }
        let model = OneTimeFlowViewModel(
            repository: repo, todayMonth: todayMonth, todayDay: todayDay,
            lastUsedCardID: lastUsed, lastUsedCard: store,
            start: start, amount: amount, locale: english
        )
        return (model, repo, store)
    }

    private static func type(_ text: String, into model: OneTimeFlowViewModel) {
        for character in text {
            if let digit = character.wholeNumberValue {
                model.keypad.press(.digit(digit))
            } else {
                model.keypad.press(.decimalSeparator)
            }
        }
    }

    // MARK: Adım sırası

    @Test("Steps are amount, date, card, title, summary in that order")
    func stepOrder() {
        #expect(OneTimeFlowStep.allCases == [.amount, .date, .card, .title, .summary])
    }

    @Test("Launch arguments are -ui-add-onetime-flow-<step>", arguments: [
        (OneTimeFlowStep.amount, "-ui-add-onetime-flow-amount"),
        (OneTimeFlowStep.date, "-ui-add-onetime-flow-date"),
        (OneTimeFlowStep.card, "-ui-add-onetime-flow-card"),
        (OneTimeFlowStep.title, "-ui-add-onetime-flow-title"),
        (OneTimeFlowStep.summary, "-ui-add-onetime-flow-summary"),
    ])
    func launchArguments(step: OneTimeFlowStep, expected: String) {
        #expect(step.launchArgument == expected)
        #expect(OneTimeFlowStep.step(in: ["-ui-sample-data", expected]) == step)
    }

    @Test("No flow argument gives no step")
    func noArgument() {
        #expect(OneTimeFlowStep.step(in: []) == nil)
        #expect(OneTimeFlowStep.step(in: ["-ui-sample-data", "-ui-add-subscription-flow-amount"]) == nil)
    }

    @Test("Flow walks amount, date, card, title, summary and saves")
    func walksInOrder() throws {
        let (model, _, _) = try Self.make()
        #expect(model.step == .amount)
        Self.type("5", into: model)
        model.continueFromCurrentStep()
        #expect(model.step == .date)
        model.chooseDate(.today)
        #expect(model.step == .card)
        model.chooseCard(nil)
        #expect(model.step == .title)
        model.skipTitle()
        #expect(model.step == .summary)
        #expect(model.canSave)
    }

    @Test("Starts at the requested step")
    func startsAtStep() throws {
        let (model, _, _) = try Self.make(start: .card, amount: 10)
        #expect(model.step == .card)
        #expect(model.steps.number == 3)
        #expect(model.steps.count == 5)
    }

    @Test("Going back returns to the previous step and is refused on the first")
    func goBack() throws {
        let (model, _, _) = try Self.make(start: .date, amount: 10)
        #expect(model.goBack())
        #expect(model.step == .amount)
        #expect(!model.goBack())
        #expect(model.step == .amount)
    }

    // MARK: Tutar

    @Test("Amount step cannot continue without a positive amount", arguments: ["", "0", "0.0", "0.00"])
    func amountRequired(text: String) throws {
        let (model, _, _) = try Self.make()
        Self.type(text, into: model)
        #expect(!model.canContinue)
        model.continueFromCurrentStep()
        #expect(model.step == .amount)
    }

    @Test("A positive amount continues and becomes the draft amount")
    func amountContinues() throws {
        let (model, _, _) = try Self.make()
        Self.type("149.9", into: model)
        #expect(model.canContinue)
        #expect(model.draft.amount == Decimal(string: "149.9"))
        model.continueFromCurrentStep()
        #expect(model.step == .date)
    }

    @Test("Starting amount fills the keypad")
    func startingAmount() throws {
        let (model, _, _) = try Self.make(amount: Decimal(string: "149.9"))
        #expect(model.keypad.amount == Decimal(string: "149.9"))
        #expect(model.canContinue)
    }

    // MARK: Tarih

    @Test("Due date starts at today")
    func dueDateStartsToday() throws {
        let (model, _, _) = try Self.make(todayMonth: Self.month(2026, 10), todayDay: 12)
        #expect(model.dueMonth == Self.month(2026, 10))
        #expect(model.dueDay == 12)
        #expect(model.dateChoice == nil)
    }

    @Test("Today chip sets today and advances")
    func todayChip() throws {
        let (model, _, _) = try Self.make(start: .date, amount: 1)
        model.chooseDate(.today)
        #expect(model.dueMonth == Self.month(2026, 10))
        #expect(model.dueDay == 12)
        #expect(model.dateChoice == .today)
        #expect(model.step == .card)
    }

    @Test("Tomorrow chip handles month ends and leap years", arguments: [
        (2026, 10, 12, 2026, 10, 13),
        (2026, 10, 30, 2026, 10, 31),
        (2026, 10, 31, 2026, 11, 1),
        (2026, 12, 31, 2027, 1, 1),
        (2027, 2, 28, 2027, 3, 1),
        (2028, 2, 28, 2028, 2, 29),
        (2028, 2, 29, 2028, 3, 1),
    ])
    func tomorrowChip(y: Int, m: Int, d: Int, ey: Int, em: Int, ed: Int) throws {
        let (model, _, _) = try Self.make(todayMonth: Self.month(y, m), todayDay: d, start: .date, amount: 1)
        model.chooseDate(.tomorrow)
        #expect(model.dueMonth == Self.month(ey, em))
        #expect(model.dueDay == ed)
        #expect(model.step == .card)
    }

    @Test("Pick chip stays on the date step and shows Continue")
    func pickChip() throws {
        let (model, _, _) = try Self.make(start: .date, amount: 1)
        #expect(!model.showsContinue)
        model.chooseDate(.pick)
        #expect(model.step == .date)
        #expect(model.showsContinue)
        model.continueFromCurrentStep()
        #expect(model.step == .card)
    }

    @Test("Month stepper clamps the index and the day to the month's days")
    func pickClamps() throws {
        let (model, _, _) = try Self.make(todayMonth: Self.month(2027, 1), todayDay: 31, start: .date, amount: 1)
        model.chooseDate(.pick)
        let feb = try #require(model.monthOptions.firstIndex(of: Self.month(2027, 2)))
        model.setDueMonthIndex(feb)
        #expect(model.dueMonth == Self.month(2027, 2))
        #expect(model.dueDay == 28)
        model.setDueDay(40)
        #expect(model.dueDay == 28)
        model.setDueDay(0)
        #expect(model.dueDay == 1)
        model.setDueMonthIndex(-5)
        #expect(model.dueMonth == model.monthOptions.first)
        model.setDueMonthIndex(10_000)
        #expect(model.dueMonth == model.monthOptions.last)
    }

    @Test("Month options surround today's month")
    func monthOptions() throws {
        let (model, _, _) = try Self.make(todayMonth: Self.month(2026, 10))
        #expect(model.monthOptions.contains(Self.month(2026, 10)))
        #expect(model.monthOptions.first == Self.month(2025, 10))
        #expect(model.monthOptions.last == Self.month(2028, 10))
        #expect(model.monthOptions.count == 37)
    }

    // MARK: Kart

    @Test("Last used card is preselected")
    func lastUsedPreselected() throws {
        let a = Self.card("A"), b = Self.card("B")
        let (model, _, _) = try Self.make(cards: [a, b], lastUsed: b.id)
        #expect(model.cardID == b.id)
        #expect(model.cardTitle == "B")
    }

    @Test("Unknown last used card falls back to No card")
    func unknownLastUsed() throws {
        let (model, _, _) = try Self.make(cards: [Self.card("A")], lastUsed: UUID())
        #expect(model.cardID == nil)
    }

    @Test("Choosing a card or No card advances")
    func chooseCard() throws {
        let a = Self.card("A")
        let (model, _, _) = try Self.make(cards: [a], start: .card, amount: 1)
        model.chooseCard(a.id)
        #expect(model.cardID == a.id)
        #expect(model.step == .title)
        let (other, _, _) = try Self.make(cards: [a], lastUsed: a.id, start: .card, amount: 1)
        other.chooseCard(nil)
        #expect(other.cardID == nil)
        #expect(other.step == .title)
    }

    @Test("A newly added card is listed once, chosen and advances")
    func selectAddedCard() throws {
        let (model, _, _) = try Self.make(start: .card, amount: 1)
        let added = Self.card("New")
        model.selectAddedCard(added)
        model.goBack()
        model.selectAddedCard(added)
        #expect(model.cards.filter { $0.id == added.id }.count == 1)
        #expect(model.cardID == added.id)
    }

    // MARK: Başlık

    @Test("Skipped or blank title saves as the default title", arguments: ["", "   ", "\n"])
    func defaultTitle(typed: String) throws {
        let (model, repo, _) = try Self.make(start: .title, amount: 25)
        model.title = typed
        #expect(model.resolvedTitle == OneTimeFlowViewModel.defaultTitle)
        model.skipTitle()
        #expect(model.step == .summary)
        #expect(model.save())
        #expect(try repo.oneTimePayments().map(\.title) == [OneTimeFlowViewModel.defaultTitle])
    }

    @Test("Skip clears a typed title")
    func skipClears() throws {
        let (model, _, _) = try Self.make(start: .title, amount: 25)
        model.title = "Dentist"
        model.skipTitle()
        #expect(model.title.isEmpty)
    }

    @Test("Quick title chip sets the title and advances")
    func quickTitle() throws {
        let (model, _, _) = try Self.make(start: .title, amount: 25)
        let chip = try #require(OneTimeFlowViewModel.quickTitles.first)
        model.chooseTitle(chip)
        #expect(model.resolvedTitle == chip)
        #expect(model.step == .summary)
        #expect(!OneTimeFlowViewModel.quickTitles.isEmpty)
        #expect(Set(OneTimeFlowViewModel.quickTitles).count == OneTimeFlowViewModel.quickTitles.count)
    }

    @Test("Typed title is trimmed")
    func trimmed() throws {
        let (model, _, _) = try Self.make(start: .title, amount: 25)
        model.title = "  Dentist  "
        #expect(model.resolvedTitle == "Dentist")
    }

    @Test("Title longer than the maximum blocks Continue; the maximum is allowed")
    func titleLength() throws {
        let (model, _, _) = try Self.make(start: .title, amount: 25)
        model.title = String(repeating: "a", count: OneTimePaymentItem.maxTitleLength)
        #expect(!model.isTitleTooLong)
        #expect(model.canContinue)
        model.title = String(repeating: "a", count: OneTimePaymentItem.maxTitleLength + 1)
        #expect(model.isTitleTooLong)
        #expect(!model.canContinue)
        model.continueFromCurrentStep()
        #expect(model.step == .title)
    }

    @Test("Title step shows Continue; empty title can continue")
    func titleContinue() throws {
        let (model, _, _) = try Self.make(start: .title, amount: 25)
        #expect(model.showsContinue)
        #expect(model.canContinue)
    }

    // MARK: Kaydetme

    @Test("Save stores the payment with the chosen values and remembers the card")
    func saveStores() throws {
        let a = Self.card("A")
        let (model, repo, store) = try Self.make(cards: [a], todayDay: 31, amount: Decimal(string: "149.9"))
        model.chooseDate(.tomorrow)
        model.chooseCard(a.id)
        model.chooseTitle("Doctor")
        #expect(model.save())
        let saved = try #require(try repo.oneTimePayments().first)
        #expect(saved.title == "Doctor")
        #expect(saved.cardID == a.id)
        #expect(saved.amount == Money(Decimal(string: "149.9")!))
        #expect(saved.dueMonth == Self.month(2026, 11))
        #expect(saved.dueDay == 1)
        #expect(store.cardID == a.id)
    }

    @Test("Saving without a card clears the remembered card")
    func saveNoCardClears() throws {
        let a = Self.card("A")
        let store = Self.freshStore()
        store.cardID = a.id
        let (model, repo, _) = try Self.make(cards: [a], lastUsed: a.id, start: .card, amount: 5, store: store)
        model.chooseCard(nil)
        model.skipTitle()
        #expect(model.save())
        #expect(store.cardID == nil)
        #expect(try repo.oneTimePayments().first?.cardID == nil)
    }

    @Test("Save without an amount is refused and stores nothing")
    func saveWithoutAmount() throws {
        let (model, repo, store) = try Self.make(start: .summary)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repo.oneTimePayments().isEmpty)
        #expect(store.cardID == nil)
    }

    @Test("Repository failure sets the message, returns false and keeps the remembered card")
    func saveFailure() throws {
        let (model, _, store) = try Self.make(
            start: .summary, amount: 5, repository: SaveFailingRepository()
        )
        #expect(!model.save())
        #expect(model.failureMessage == EditOneTimePaymentViewModel.saveErrorMessage)
        #expect(store.cardID == nil)
    }

    @Test("Summary texts reflect the choices")
    func summaryTexts() throws {
        let (model, _, _) = try Self.make(todayDay: 12, start: .date, amount: 5)
        model.chooseDate(.today)
        #expect(model.cardID == nil)
        #expect(!model.cardTitle.isEmpty)
        #expect(model.dueDateText.hasSuffix("2026"))
        #expect(model.dueDateText.contains("12"))
    }
}

@MainActor
@Suite("HomeViewModel one-time payment factories")
struct HomeOneTimeFactoryTests {
    private static func home(_ repository: any PaymentRepository) -> HomeViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        return HomeViewModel(repository: repository, today: today, calendar: calendar)
    }

    @Test("Flow uses today's month and day; saving makes the payment show on Home after reload")
    func flowFromHome() throws {
        let repository = InMemoryPaymentRepository()
        let home = Self.home(repository)
        let flow = home.makeOneTimeFlowModel(amount: 10, locale: Locale(identifier: "en_US"))
        #expect(flow.dueMonth == YearMonth(year: 2026, month: 10))
        #expect(flow.dueDay == 14)
        #expect(flow.save())
        home.reload()
        #expect(try repository.oneTimePayments().count == 1)
        #expect(home.rows.contains { $0.title == OneTimeFlowViewModel.defaultTitle })
    }

    @Test("Edit factory returns a model for a saved payment and nil for unknown ids and other kinds")
    func editFactory() throws {
        let repository = InMemoryPaymentRepository()
        let item = try #require(OneTimePaymentItem(
            title: "Dentist", cardID: nil, amount: Money(1500), dueMonth: YearMonth(year: 2026, month: 11)!, dueDay: 20
        ))
        try repository.save(item)
        let home = Self.home(repository)
        let model = try #require(home.makeEditOneTimeModel(id: item.id, locale: Locale(identifier: "en_US")))
        #expect(model.editingID == item.id)
        #expect(model.title == "Dentist")
        #expect(home.makeEditOneTimeModel(id: UUID()) == nil)
    }
}
